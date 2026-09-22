import AppKit
import FlowCore

extension WorkspaceStore {
    func changeWorkflow(_ projectID: UUID, undoable: Bool = false, _ change: (inout WorkflowGraph) -> Void) {
        guard var project = project(projectID) else { return }
        let previous = project.workflow
        if undoable, let undo = NSApp.keyWindow?.undoManager {
            undo.registerUndo(withTarget: self) { [weak undo] target in target.restoreWorkflow(previous, projectID: projectID, undo: undo) }
            undo.setActionName("워크플로 편집")
        }
        var graph = previous ?? WorkflowGraph(); change(&graph); project.workflow = graph; updateProject(project)
    }
    private func restoreWorkflow(_ graph: WorkflowGraph?, projectID: UUID, undo: UndoManager?) {
        guard var project = project(projectID), !workflowBusy(projectID) else { return }
        let previous = project.workflow
        undo?.registerUndo(withTarget: self) { [weak undo] target in target.restoreWorkflow(previous, projectID: projectID, undo: undo) }
        project.workflow = graph; updateProject(project)
    }
    func workflowBusy(_ projectID: UUID) -> Bool {
        (journal.workflowRuns ?? []).contains { run in run.projectID == projectID && (run.state == .running || run.state == .paused || run.steps.contains { step in jobs.contains { $0.id == step.jobID && $0.state.isRunning } }) }
    }
    func latestWorkflowRun(_ projectID: UUID) -> WorkflowRun? { journal.workflowRuns?.last { $0.projectID == projectID } }
    func workflowAllows(_ job: Job) -> Bool {
        guard let run = journal.workflowRuns?.last(where: { $0.steps.contains { $0.jobID == job.id } }) else { return true }
        return run.state == .running
    }
    func startWorkflow(_ projectID: UUID, only nodeID: UUID? = nil) throws {
        guard !importing else { throw FlowError.message("참조 이미지를 가져온 뒤 실행하세요.") }
        guard storageReady, !restoringAssets, let graph = project(projectID)?.workflow else { throw FlowError.message("워크플로를 먼저 만드세요.") }
        guard !workflowBusy(projectID) else { throw FlowError.message("현재 실행을 마치거나 중단한 뒤 다시 실행하세요.") }
        let ids = try graph.orderedIDs().filter { graph.node($0)?.kind == .generation && (nodeID == nil || $0 == nodeID) }
        let run = WorkflowRun(projectID: projectID, graph: graph, nodeIDs: ids)
        try WorkflowRules.preflight(run)
        for node in graph.nodes where node.kind == .reference && graph.edges.contains(where: { $0.source == node.id && ids.contains($0.target) }) {
            guard let id = node.assetID, let asset = asset(id), FileManager.default.fileExists(atPath: vault.original(asset).path) else { throw FlowError.message("‘\(node.title)’에 사용할 참조 원본을 확인하세요.") }
        }
        if ids.contains(where: { graph.node($0)?.settings.mode == .sunburstAPI }), !apiConnection.ready { throw FlowError.message("고급 단계 실행에 필요한 OpenAI API를 먼저 연결하세요.") }
        if nodeID != nil { _ = try WorkflowRules.references(nodeID: nodeID!, run: run, jobs: jobs) }
        if journal.workflowRuns == nil { journal.workflowRuns = [] }
        journal.workflowRuns?.append(run)
        // Persist the plan before any queued request can reach the generation engine.
        try persist(); advanceWorkflows()
        notice = "\(ids.count)개 단계 실행을 시작했습니다. 여러 결과가 나오면 다음 단계에 사용할 이미지를 선택하세요."
    }
    func advanceWorkflows() {
        guard storageReady, !restoringAssets, !journal.paused else { return }
        for runIndex in (journal.workflowRuns ?? []).indices {
            guard var run = journal.workflowRuns?[runIndex], run.state == .running else { continue }
            let before = run
            for i in run.steps.indices where run.steps[i].jobID == nil && run.steps[i].error == nil {
                let id = run.steps[i].nodeID
                do {
                    // Propagate validation failures too, even when no upstream job was created.
                    if let failed = run.graph.imageSources(for: id).first(where: { source in run.steps.contains { $0.nodeID == source.id && $0.error != nil } }) {
                        throw FlowError.message("‘\(failed.title)’에서 실행이 중단되어 기다리고 있습니다.")
                    }
                    guard let references = try WorkflowRules.references(nodeID: id, run: run, jobs: jobs) else { continue }
                    for reference in references {
                        guard let asset = asset(reference), FileManager.default.fileExists(atPath: vault.original(asset).path) else { throw FlowError.message("참조 이미지 원본을 찾을 수 없습니다.") }
                    }
                    let job = try WorkflowRules.request(nodeID: id, graph: run.graph, projectID: run.projectID, references: references)
                    guard job.apiOptions == nil || apiConnection.ready else { throw FlowError.message("API 연결을 확인한 뒤 이 단계를 다시 실행하세요.") }
                    run.steps[i].jobID = job.id
                    journal.jobs.append(job)
                    changeWorkflow(run.projectID) { graph in
                        if let n = graph.nodes.firstIndex(where: { $0.id == id }) { graph.nodes[n].lastJobID = job.id; graph.nodes[n].selectedAssetID = nil }
                    }
                } catch { run.steps[i].error = error.localizedDescription }
            }
            if WorkflowRules.isComplete(run, jobs: jobs) { run.state = .completed }
            else if run.steps.allSatisfy({ step in
                step.error != nil || jobs.contains { $0.id == step.jobID && $0.state != .queued && !$0.state.isRunning }
            }) { run.state = .stopped }
            if run != before {
                journal.workflowRuns?[runIndex] = run
                do { try persist() } catch { report(error); return }
            }
        }
    }
    func chooseWorkflowResult(projectID: UUID, nodeID: UUID, assetID: UUID) {
        guard let node = project(projectID)?.workflow?.node(nodeID), let job = jobs.first(where: { $0.id == node.lastJobID }),
              job.state == .saved, job.results.contains(where: { $0.id == assetID }) else { return }
        if let run = journal.workflowRuns?.last(where: { $0.projectID == projectID && ($0.state == .running || $0.state == .paused) }),
           run.graph.edges.contains(where: { edge in edge.source == nodeID && run.steps.contains { $0.nodeID == edge.target && $0.jobID != nil } }) {
            notice = "다음 단계에 전달한 이미지는 실행 중 바꿀 수 없습니다. 완료 후 다른 후보를 선택해 다시 실행하세요."
            return
        }
        changeWorkflow(projectID) { graph in
            if let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) { graph.nodes[index].selectedAssetID = assetID }
        }
        if let index = journal.workflowRuns?.lastIndex(where: { $0.projectID == projectID && ($0.state == .running || $0.state == .paused) }),
           let step = journal.workflowRuns?[index].steps.firstIndex(where: { $0.nodeID == nodeID && $0.jobID == job.id }) {
            journal.workflowRuns?[index].steps[step].selectedAssetID = assetID
        }
        flush(); advanceWorkflows()
    }
    func stopWorkflow(_ projectID: UUID) {
        guard let index = journal.workflowRuns?.lastIndex(where: { $0.projectID == projectID && ($0.state == .running || $0.state == .paused) }),
              let run = journal.workflowRuns?[index] else { return }
        journal.workflowRuns?[index].state = .stopped
        let ids = Set(run.steps.compactMap(\.jobID))
        for i in journal.jobs.indices where ids.contains(journal.jobs[i].id) && journal.jobs[i].state == .queued { journal.jobs[i].state = .cancelled }
        flush(); notice = "후속 실행을 중단했습니다. 이미 전송한 생성은 결과를 보존합니다."
    }
    func resumeWorkflow(_ projectID: UUID) {
        guard let index = journal.workflowRuns?.lastIndex(where: { $0.projectID == projectID && $0.state == .paused }) else { return }
        journal.workflowRuns?[index].state = .running; flush(); advanceWorkflows()
    }
    func importWorkflowReference(_ urls: [URL], projectID: UUID, position: CanvasPoint) {
        guard !workflowBusy(projectID), !importing else { notice = "진행 중인 작업을 마친 후 참조를 추가하세요."; return }
        importing = true
        Task {
            defer { importing = false }
            do {
                for (index, url) in urls.filter(\.isFileURL).enumerated() {
                    let reference: Asset
                    if let existing = library.assets.first(where: { vault.original($0).standardizedFileURL == url.standardizedFileURL }) { reference = existing }
                    else { reference = try await vault.ingest(url: url, projectID: projectID); upsert(reference) }
                    var node = WorkflowNode(kind: .reference, title: reference.title, position: CanvasPoint(x: position.x, y: position.y + Double(index) * 310))
                    node.assetID = reference.id
                    changeWorkflow(projectID, undoable: true) { $0.nodes.append(node) }
                }
                flush()
            } catch { report(error) }
        }
    }
}
