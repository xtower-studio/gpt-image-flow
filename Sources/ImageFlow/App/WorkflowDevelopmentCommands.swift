import AppKit
import FlowCore

extension FlowAppDelegate {
    func workflowCommand(_ operation: String, directory: URL) throws {
        guard let store, let session else { return }
        let name = "노드 워크플로 검증"
        if operation == "workflowSeedQA" {
            guard !store.library.projects.contains(where: { $0.name == name }),
                  let reference = store.library.assets.first(where: { $0.id.uuidString == "D1A84191-D395-43FD-9D34-7AA9763AE45D" }) else { throw FlowError.message("워크플로 검증 프로젝트가 이미 있거나 검증용 원본이 없습니다.") }
            var project = Project(name: name)
            var graph = WorkflowGraph()
            var prompt = WorkflowNode(kind: .prompt, title: "제품 촬영 지시", position: .init(x: 0, y: 0))
            prompt.text = "Generate an editorial product photo of this ceramic teapot on a pale ivory background. Preserve its silhouette. No text."
            var image = WorkflowNode(kind: .reference, title: "제품 참조", position: .init(x: 0, y: 290)); image.assetID = reference.id
            var first = WorkflowNode(kind: .generation, title: "제품 원본", position: .init(x: 360, y: 0)); first.settings.mode = .instant
            var next = WorkflowNode(kind: .generation, title: "따뜻한 빛", position: .init(x: 720, y: 0)); next.settings.mode = .instant; next.text = "Keep this teapot and composition. Change the lighting to warm sunset light. Generate one image."
            var branch = next; branch.id = UUID(); branch.title = "푸른 배경"; branch.position.y = 570; branch.text = "Keep this teapot and composition. Change only the background to pale sky blue. Generate one image."
            graph.nodes = [prompt, image, first, next, branch]
            try graph.connect(source: prompt.id, target: first.id); try graph.connect(source: image.id, target: first.id)
            try graph.connect(source: first.id, target: next.id); try graph.connect(source: first.id, target: branch.id)
            graph.viewport = CanvasViewport(x: 50, y: 95, scale: 0.65)
            project.workflow = graph; store.library.projects.append(project); store.flush(); store.requestedProjectID = project.id
            UserDefaults.standard.set("canvas", forKey: "studioBoardMode")
        } else if operation == "workflowRunQA" {
            guard let project = store.library.projects.first(where: { $0.name == name }),
                  !(store.journal.workflowRuns ?? []).contains(where: { $0.projectID == project.id }),
                  project.workflow?.nodes.filter({ $0.kind == .generation }).allSatisfy({ $0.settings.mode == .instant }) == true else { throw FlowError.message("검증은 한 번만, ChatGPT 빠르게 모드에서 실행합니다.") }
            try store.startWorkflow(project.id)
            if session.status != .ready { session.connect() }
        } else if operation == "workflowStatus" {
            let projects = store.library.projects.filter { $0.workflow != nil }.map { project in
                ["id": project.id.uuidString, "name": project.name,
                 "graph": String(data: (try? JSONEncoder().encode(project.workflow)) ?? Data(), encoding: .utf8) ?? "",
                 "run": String(data: (try? JSONEncoder().encode(store.latestWorkflowRun(project.id))) ?? Data(), encoding: .utf8) ?? "",
                 "jobs": store.jobs.filter { $0.projectID == project.id }.map { ["id": $0.id.uuidString, "state": $0.state.rawValue, "results": $0.results.map { $0.id.uuidString }, "refs": $0.referenceIDs.map { $0.uuidString }, "error": $0.error ?? ""] as [String: Any] }] as [String: Any]
            }
            try JSONSerialization.data(withJSONObject: projects, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("workflow-status.json"))
        }
    }
}
