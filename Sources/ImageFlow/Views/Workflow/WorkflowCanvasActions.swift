import SwiftUI
import FlowCore

extension WorkflowCanvasView {
    func point(_ node: WorkflowNode) -> CanvasPoint { moving[node.id] ?? node.position }
    func screen(_ point: CanvasPoint) -> CGPoint { CGPoint(x: point.x * viewport.scale + viewport.x, y: point.y * viewport.scale + viewport.y) }
    func outputPoint(_ node: WorkflowNode) -> CGPoint {
        let p = point(node); return screen(CanvasPoint(x: p.x + WorkflowNodeCard.width, y: p.y + 54))
    }
    func inputPoint(_ node: WorkflowNode, port: WorkflowPort) -> CGPoint {
        let p = point(node); return screen(CanvasPoint(x: p.x, y: p.y + (port == .prompt ? 55 : 81)))
    }
    func portColor(_ port: WorkflowPort) -> Color { port == .prompt ? .purple : .accentColor }
    func curve(_ a: CGPoint, _ b: CGPoint) -> Path {
        let offset = max(60, abs(b.x - a.x) * 0.45)
        var path = Path(); path.move(to: a)
        path.addCurve(to: b, control1: CGPoint(x: a.x + offset, y: a.y), control2: CGPoint(x: b.x - offset, y: b.y)); return path
    }
    func connect(_ source: UUID, to target: UUID, port: WorkflowPort? = nil) {
        guard !busy else { return }
        if let port, graph.node(source)?.outputPort != port { store.notice = "프롬프트는 공통 지시 입력에, 이미지는 참조 입력에 연결하세요."; return }
        var draft = graph
        do {
            try draft.connect(source: source, target: target)
            store.changeWorkflow(project.id, undoable: true) { $0.edges = draft.edges }
            connecting = nil; connectionPoint = nil
        } catch { store.report(error) }
    }
    func move(_ node: WorkflowNode, delta: CGSize, ended: Bool) {
        if moveOrigins[node.id] == nil { moveOrigins[node.id] = node.position; selectedNode = node.id }
        guard let origin = moveOrigins[node.id] else { return }
        moving[node.id] = CanvasPoint(x: origin.x + delta.width / viewport.scale, y: origin.y + delta.height / viewport.scale)
        if ended {
            let position = moving[node.id]!
            store.changeWorkflow(project.id, undoable: true) { graph in if let index = graph.nodes.firstIndex(where: { $0.id == node.id }) { graph.nodes[index].position = position } }
            moving.removeValue(forKey: node.id); moveOrigins.removeValue(forKey: node.id)
        }
    }
    func insertionPoint(_ size: CGSize) -> CanvasPoint {
        let p = viewport.world(x: size.width / 2, y: size.height / 2)
        return CanvasPoint(x: p.x - 140 + Double(graph.nodes.count % 4) * 24, y: p.y - 130 + Double(graph.nodes.count % 4) * 24)
    }
    func add(_ kind: WorkflowNodeKind, size: CGSize) {
        var node = WorkflowNode(kind: kind, title: kind == .prompt ? "공통 프롬프트" : "생성 \(graph.nodes.filter { $0.kind == .generation }.count + 1)", position: insertionPoint(size))
        node.settings = initialSettings()
        store.changeWorkflow(project.id, undoable: true) { $0.nodes.append(node) }; selectedNode = node.id
    }
    func initialSettings() -> WorkflowSettings {
        var settings = WorkflowSettings()
        let current = store.project(project.id) ?? project
        settings.mode = store.selectedGenerationMode; settings.aspect = current.aspect == "자유" ? "자동" : current.aspect
        settings.background = current.background ?? .automatic; settings.api = current.apiOptions ?? ImageAPIOptions()
        return settings
    }
    func branch(_ source: WorkflowNode) {
        guard !busy else { return }
        var node = WorkflowNode(kind: .generation, title: "\(source.title) · 변형", position: CanvasPoint(x: source.position.x + 360, y: source.position.y))
        while graph.nodes.contains(where: { abs($0.position.x - node.position.x) < 100 && abs($0.position.y - node.position.y) < 350 }) { node.position.y += 570 }
        node.settings = source.settings
        store.changeWorkflow(project.id, undoable: true) { graph in graph.nodes.append(node); try? graph.connect(source: source.id, target: node.id) }
        selectedNode = node.id; store.notice = "변형 단계를 만들었습니다. 이 단계에서 바꿀 내용을 적어 주세요."
    }
    func duplicate(_ source: WorkflowNode) {
        guard !busy else { return }
        var node = source; node.id = UUID(); node.title += " 복사"; node.lastJobID = nil; node.selectedAssetID = nil
        node.position.y += WorkflowNodeCard.height(node.kind) + 50
        let inputs = graph.edges.filter { $0.target == source.id }
        store.changeWorkflow(project.id, undoable: true) { graph in
            graph.nodes.append(node)
            for edge in inputs { try? graph.connect(source: edge.source, target: node.id) }
        }
        selectedNode = node.id
    }
    func seed(branching: Bool) {
        guard graph.nodes.isEmpty else { return }
        let current = store.project(project.id) ?? project
        var prompt = WorkflowNode(kind: .prompt, title: "공통 프롬프트", position: CanvasPoint(x: 0, y: 0)); prompt.text = current.prompt
        var generate = WorkflowNode(kind: .generation, title: "기본 이미지", position: CanvasPoint(x: 360, y: 0)); generate.settings = initialSettings()
        store.changeWorkflow(project.id, undoable: true) { graph in
            graph.nodes = [prompt, generate]; try? graph.connect(source: prompt.id, target: generate.id)
            for (index, id) in current.referenceIDs.enumerated() {
                guard let asset = store.asset(id) else { continue }
                var reference = WorkflowNode(kind: .reference, title: asset.title, position: CanvasPoint(x: 0, y: 290 + Double(index) * 350)); reference.assetID = id
                graph.nodes.append(reference); try? graph.connect(source: reference.id, target: generate.id)
            }
            if branching {
                for (index, pair) in [("빛의 변형", "피사체와 구도를 유지하고 따뜻한 저녁빛으로 바꿔 주세요."), ("배경의 변형", "피사체를 유지하고 배경을 밝은 미니멀 스튜디오로 바꿔 주세요.")].enumerated() {
                    var variant = WorkflowNode(kind: .generation, title: pair.0, position: CanvasPoint(x: 720, y: Double(index) * 570))
                    variant.text = pair.1; variant.settings = generate.settings; graph.nodes.append(variant)
                    try? graph.connect(source: generate.id, target: variant.id)
                }
            }
        }
    }
    func importReference(size: CGSize) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { store.importWorkflowReference(panel.urls, projectID: project.id, position: insertionPoint(size)) }
    }
    func copyWorkflow() {
        var copy = Project(name: project.name + " · 워크플로 복사")
        var draft = graph
        for i in draft.nodes.indices { draft.nodes[i].lastJobID = nil; draft.nodes[i].selectedAssetID = nil }
        copy.workflow = draft
        store.library.projects.append(copy); store.flush(); store.requestedProjectID = copy.id
        store.notice = "워크플로와 참조 연결을 복제했습니다. 생성 결과는 원래 프로젝트에 보존됩니다."
    }
    func zoom(_ factor: Double, size: CGSize) {
        let center = viewport.world(x: size.width / 2, y: size.height / 2)
        viewport.scale = min(1.5, max(0.15, viewport.scale * factor))
        viewport.x = size.width / 2 - center.x * viewport.scale; viewport.y = size.height / 2 - center.y * viewport.scale
    }
    func fit(_ size: CGSize) {
        let nodes = graph.nodes; guard !nodes.isEmpty else { return }
        let minX = nodes.map { $0.position.x }.min()!, minY = nodes.map { $0.position.y }.min()!
        let maxX = nodes.map { $0.position.x + WorkflowNodeCard.width }.max()!, maxY = nodes.map { $0.position.y + WorkflowNodeCard.height($0.kind) }.max()!
        viewport.scale = min(1, max(0.15, min((size.width - 110) / (maxX - minX), (size.height - 150) / (maxY - minY))))
        viewport.x = (size.width - (maxX - minX) * viewport.scale) / 2 - minX * viewport.scale
        viewport.y = 90 - minY * viewport.scale; saveViewport()
    }
    func scheduleSave() {
        saveTask?.cancel(); saveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(300)); saveViewport() } catch { }
        }
    }
    func saveViewport() {
        guard !graph.nodes.isEmpty else { return }
        store.changeWorkflow(project.id) { $0.viewport = viewport }
    }
}
