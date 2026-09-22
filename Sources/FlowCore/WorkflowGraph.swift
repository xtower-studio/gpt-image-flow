import Foundation

public enum WorkflowNodeKind: String, Codable, Sendable { case prompt, reference, generation }
public enum WorkflowPort: String, Codable, Sendable { case prompt, image }
public struct WorkflowSettings: Codable, Equatable, Sendable {
    public var mode: GenerationMode = .automatic
    public var aspect = "자동"
    public var background: BackgroundOption = .automatic
    public var api = ImageAPIOptions()
    public init() {}
    public var imageCount: Int { mode == .sunburstAPI ? api.count : mode.imagesPerRequest }
}
public struct WorkflowNode: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: WorkflowNodeKind
    public var title: String
    public var position: CanvasPoint
    public var text = ""
    public var assetID: UUID?
    public var settings = WorkflowSettings()
    public var lastJobID: UUID?
    public var selectedAssetID: UUID?
    public init(kind: WorkflowNodeKind, title: String, position: CanvasPoint) {
        self.kind = kind; self.title = title; self.position = position
    }
    public var outputPort: WorkflowPort { kind == .prompt ? .prompt : .image }
}
public struct WorkflowEdge: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var source: UUID
    public var target: UUID
    public var port: WorkflowPort
    public init(source: UUID, target: UUID, port: WorkflowPort) { self.source = source; self.target = target; self.port = port }
}
public struct WorkflowGraph: Codable, Equatable, Sendable {
    public var nodes: [WorkflowNode] = []
    public var edges: [WorkflowEdge] = []
    public var viewport = CanvasViewport(scale: 0.8)
    public init() {}
    public func node(_ id: UUID) -> WorkflowNode? { nodes.first { $0.id == id } }
    public mutating func connect(source: UUID, target: UUID) throws {
        guard let from = node(source), node(target)?.kind == .generation, source != target else { throw FlowError.message("프롬프트 또는 이미지를 생성 단계의 입력에 연결하세요.") }
        guard !edges.contains(where: { $0.source == source && $0.target == target }) else { return }
        let edge = WorkflowEdge(source: source, target: target, port: from.outputPort)
        edges.append(edge)
        do { try validate() } catch { edges.removeAll { $0.id == edge.id }; throw error }
    }
    public func validate() throws {
        guard Set(nodes.map(\.id)).count == nodes.count, Set(edges.map(\.id)).count == edges.count else { throw FlowError.message("중복된 노드 또는 연결이 있습니다.") }
        for edge in edges {
            guard let from = node(edge.source), let to = node(edge.target), to.kind == .generation,
                  from.outputPort == edge.port, from.id != to.id else { throw FlowError.message("올바르지 않은 연결입니다.") }
        }
        _ = try orderedIDs()
    }
    public func orderedIDs() throws -> [UUID] {
        var result: [UUID] = [], remaining = nodes.map(\.id)
        while !remaining.isEmpty {
            guard let next = remaining.first(where: { id in edges.filter { $0.target == id }.allSatisfy { result.contains($0.source) } }) else {
                throw FlowError.message("순환 연결은 만들 수 없습니다. 결과에서 새 단계를 분기하세요.")
            }
            result.append(next); remaining.removeAll { $0 == next }
        }
        return result
    }
    public func prompt(for id: UUID) -> String {
        let shared = edges.filter { $0.target == id && $0.port == .prompt }.compactMap { node($0.source)?.text }
        return (shared + [node(id)?.text ?? ""]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    public func imageSources(for id: UUID) -> [WorkflowNode] { edges.filter { $0.target == id && $0.port == .image }.compactMap { node($0.source) } }
    public mutating func remove(_ id: UUID) { nodes.removeAll { $0.id == id }; edges.removeAll { $0.source == id || $0.target == id } }
    public mutating func arrange() throws {
        let order = try orderedIDs()
        var levels: [UUID: Int] = [:], rows: [Int: Int] = [:]
        for id in order {
            let level = (edges.filter { $0.target == id }.compactMap { levels[$0.source] }.max().map { $0 + 1 }) ?? 0
            let row = rows[level, default: 0]; rows[level] = row + 1; levels[id] = level
            if let i = nodes.firstIndex(where: { $0.id == id }) { nodes[i].position = CanvasPoint(x: Double(level) * 360, y: Double(row) * 510) }
        }
    }
}

public enum WorkflowRunState: String, Codable, Sendable { case running, paused, stopped, completed }
public struct WorkflowStep: Codable, Equatable, Sendable {
    public var nodeID: UUID
    public var jobID: UUID?
    public var selectedAssetID: UUID?
    public var error: String?
    public init(nodeID: UUID) { self.nodeID = nodeID }
}
public struct WorkflowRun: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var projectID: UUID
    public var graph: WorkflowGraph
    public var steps: [WorkflowStep]
    public var state: WorkflowRunState = .running
    public var createdAt = Date()
    public init(projectID: UUID, graph: WorkflowGraph, nodeIDs: [UUID]) {
        self.projectID = projectID; self.graph = graph; steps = nodeIDs.map { WorkflowStep(nodeID: $0) }
    }
}

public enum WorkflowRules {
    /// Resolve only successful, explicitly chosen upstream results. Never fall back to a stale run.
    public static func references(nodeID: UUID, run: WorkflowRun, jobs: [Job]) throws -> [UUID]? {
        var references: [UUID] = []
        for source in run.graph.imageSources(for: nodeID) {
            if source.kind == .reference {
                guard let id = source.assetID else { throw FlowError.message("‘\(source.title)’에 참조 이미지를 넣어 주세요.") }
                references.append(id); continue
            }
            let step = run.steps.first { $0.nodeID == source.id }
            let jobID = step == nil ? source.lastJobID : step?.jobID
            guard let jobID, let job = jobs.first(where: { $0.id == jobID }) else {
                if step != nil { return nil }
                throw FlowError.message("‘\(source.title)’을 먼저 실행하고 사용할 결과를 선택하세요.")
            }
            guard job.state == .saved else {
                if job.state == .queued || job.state.isRunning { return nil }
                throw FlowError.message("‘\(source.title)’의 \(job.state.label)을 확인하세요. 후속 단계는 실행하지 않았습니다.")
            }
            let chosen = step == nil ? source.selectedAssetID : step?.selectedAssetID
            if let chosen, job.results.contains(where: { $0.id == chosen }) { references.append(chosen) }
            else if job.results.count == 1 { references.append(job.results[0].id) }
            else if step != nil { return nil }
            else { throw FlowError.message("‘\(source.title)’에서 다음 단계에 사용할 이미지를 선택하세요.") }
        }
        var seen = Set<UUID>()
        return references.filter { seen.insert($0).inserted }
    }
    public static func request(nodeID: UUID, graph: WorkflowGraph, projectID: UUID, references: [UUID]) throws -> Job {
        guard let node = graph.node(nodeID), node.kind == .generation else { throw FlowError.message("생성 단계를 선택하세요.") }
        var project = Project(name: node.title); project.id = projectID; project.prompt = graph.prompt(for: nodeID)
        project.referenceIDs = references; project.generationMode = node.settings.mode
        project.aspect = node.settings.aspect; project.background = node.settings.background; project.apiOptions = node.settings.api
        var job = try JobRules.makeBatch(project: project, parentID: references.first)[0]
        job.label = node.title
        return job
    }
    public static func preflight(_ run: WorkflowRun) throws {
        try run.graph.validate()
        guard !run.steps.isEmpty, run.steps.count <= 50 else { throw FlowError.message("생성 단계는 1~50개까지 실행할 수 있습니다.") }
        for step in run.steps {
            let sources = run.graph.imageSources(for: step.nodeID)
            _ = try request(nodeID: step.nodeID, graph: run.graph, projectID: run.projectID, references: sources.map { $0.assetID ?? $0.id })
        }
    }
    public static func usesCurrentInputs(_ job: Job, nodeID: UUID, graph: WorkflowGraph, jobs: [Job]) -> Bool {
        let reuse = WorkflowRun(projectID: job.projectID, graph: graph, nodeIDs: [nodeID])
        guard let references = try? references(nodeID: nodeID, run: reuse, jobs: jobs),
              let expected = try? request(nodeID: nodeID, graph: graph, projectID: job.projectID, references: references) else { return false }
        return job.inputPrompt == expected.inputPrompt && job.generationMode == expected.generationMode
            && job.apiOptions == expected.apiOptions && job.referenceIDs == expected.referenceIDs
            && job.requestedAspect == expected.requestedAspect && job.requestedBackground == expected.requestedBackground
    }
    public static func isComplete(_ run: WorkflowRun, jobs: [Job]) -> Bool {
        run.steps.allSatisfy { step in jobs.contains { $0.id == step.jobID && $0.state == .saved } }
    }
}
