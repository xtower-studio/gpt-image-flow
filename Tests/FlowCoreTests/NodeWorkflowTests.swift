import XCTest
@testable import FlowCore

final class NodeWorkflowTests: XCTestCase {
    func fixture() throws -> (WorkflowGraph, WorkflowNode, WorkflowNode, WorkflowNode) {
        var graph = WorkflowGraph()
        var prompt = WorkflowNode(kind: .prompt, title: "공통", position: .init(x: 0, y: 0)); prompt.text = "ceramic teapot"
        var first = WorkflowNode(kind: .generation, title: "원본", position: .init(x: 360, y: 0)); first.settings.mode = .instant
        var next = WorkflowNode(kind: .generation, title: "변형", position: .init(x: 720, y: 0)); next.text = "change color to orange"
        graph.nodes = [prompt, first, next]
        try graph.connect(source: prompt.id, target: first.id); try graph.connect(source: first.id, target: next.id)
        return (graph, prompt, first, next)
    }
    func result(_ projectID: UUID) -> Asset { Asset(projectID: projectID, filename: "test.png", title: "result", width: 1024, height: 1024, digest: "test", isReference: false) }
    func testTypedConnectionsCycleProtectionAndDelete() throws {
        var (graph, prompt, first, next) = try fixture()
        XCTAssertThrowsError(try graph.connect(source: next.id, target: first.id))
        XCTAssertEqual(graph.edges.count, 2)
        XCTAssertThrowsError(try graph.connect(source: first.id, target: prompt.id))
        try graph.connect(source: first.id, target: next.id)
        XCTAssertEqual(graph.edges.count, 2)
        XCTAssertEqual(try graph.orderedIDs(), [prompt.id, first.id, next.id])
        graph.remove(first.id); XCTAssertTrue(graph.edges.isEmpty)
    }
    func testNewRunWaitsAndNeverUsesPreviousOutput() throws {
        var (graph, _, first, next) = try fixture()
        let projectID = UUID(), oldResult = result(UUID())
        var old = Job(batchID: UUID(), projectID: projectID, prompt: "old", label: "old", referenceIDs: [])
        old.state = .saved; old.results = [oldResult]
        let index = graph.nodes.firstIndex { $0.id == first.id }!
        graph.nodes[index].lastJobID = old.id; graph.nodes[index].selectedAssetID = oldResult.id
        let run = WorkflowRun(projectID: projectID, graph: graph, nodeIDs: [first.id, next.id])
        XCTAssertNil(try WorkflowRules.references(nodeID: next.id, run: run, jobs: [old]))
        let partial = WorkflowRun(projectID: projectID, graph: graph, nodeIDs: [next.id])
        XCTAssertEqual(try WorkflowRules.references(nodeID: next.id, run: partial, jobs: [old]), [oldResult.id])
    }
    func testCandidateSelectionGatesDownstreamAndSingleResultFlows() throws {
        let (graph, _, first, next) = try fixture(), projectID = UUID()
        var run = WorkflowRun(projectID: projectID, graph: graph, nodeIDs: [first.id, next.id])
        var job = try WorkflowRules.request(nodeID: first.id, graph: graph, projectID: projectID, references: [])
        run.steps[0].jobID = job.id
        XCTAssertNil(try WorkflowRules.references(nodeID: next.id, run: run, jobs: [job]))
        job.state = .saved; job.results = [result(projectID), result(projectID)]
        XCTAssertNil(try WorkflowRules.references(nodeID: next.id, run: run, jobs: [job]))
        run.steps[0].selectedAssetID = UUID()
        XCTAssertNil(try WorkflowRules.references(nodeID: next.id, run: run, jobs: [job]))
        run.steps[0].selectedAssetID = job.results[1].id
        XCTAssertEqual(try WorkflowRules.references(nodeID: next.id, run: run, jobs: [job]), [job.results[1].id])
        job.results.removeLast(); run.steps[0].selectedAssetID = nil
        XCTAssertEqual(try WorkflowRules.references(nodeID: next.id, run: run, jobs: [job]), [job.results[0].id])
    }
    func testFailedTextAndPartialResultsNeverTriggerChildren() throws {
        let (graph, _, first, next) = try fixture(), projectID = UUID()
        var run = WorkflowRun(projectID: projectID, graph: graph, nodeIDs: [first.id, next.id])
        var job = try WorkflowRules.request(nodeID: first.id, graph: graph, projectID: projectID, references: [])
        run.steps[0].jobID = job.id; job.results = [result(projectID)]
        for state in [JobState.failed, .responded, .needsReview, .needsLogin, .cancelled] {
            job.state = state
            XCTAssertThrowsError(try WorkflowRules.references(nodeID: next.id, run: run, jobs: [job]), state.rawValue)
        }
    }
    func testBranchesShareChosenReferenceAndSnapshotSurvivesEdits() throws {
        var (graph, prompt, first, next) = try fixture(), projectID = UUID()
        var branch = next; branch.id = UUID(); branch.text = "change lighting"
        graph.nodes.append(branch); try graph.connect(source: first.id, target: branch.id)
        var run = WorkflowRun(projectID: projectID, graph: graph, nodeIDs: [first.id, next.id, branch.id])
        graph.nodes[graph.nodes.firstIndex { $0.id == prompt.id }!].text = "changed later"
        var job = try WorkflowRules.request(nodeID: first.id, graph: run.graph, projectID: projectID, references: [])
        XCTAssertEqual(job.inputPrompt, "ceramic teapot")
        job.state = .saved; job.results = [result(projectID)]
        run.steps[0].jobID = job.id
        for id in [next.id, branch.id] {
            let refs = try XCTUnwrap(WorkflowRules.references(nodeID: id, run: run, jobs: [job]))
            XCTAssertEqual(refs, [job.results[0].id])
            let request = try WorkflowRules.request(nodeID: id, graph: run.graph, projectID: projectID, references: refs)
            XCTAssertEqual(request.parentID, job.results[0].id)
        }
        let decoded = try JSONDecoder().decode(WorkflowRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(decoded, run)
    }
    func testChangedSettingsAndUpstreamSelectionMarkOldResults() throws {
        var (graph, _, first, next) = try fixture(), projectID = UUID()
        var source = try WorkflowRules.request(nodeID: first.id, graph: graph, projectID: projectID, references: [])
        source.state = .saved; source.results = [result(projectID), result(projectID)]
        let index = graph.nodes.firstIndex { $0.id == first.id }!
        graph.nodes[index].lastJobID = source.id; graph.nodes[index].selectedAssetID = source.results[0].id
        let job = try WorkflowRules.request(nodeID: next.id, graph: graph, projectID: projectID, references: [source.results[0].id])
        XCTAssertTrue(WorkflowRules.usesCurrentInputs(job, nodeID: next.id, graph: graph, jobs: [source]))
        graph.nodes[index].selectedAssetID = source.results[1].id
        XCTAssertFalse(WorkflowRules.usesCurrentInputs(job, nodeID: next.id, graph: graph, jobs: [source]))
        graph.nodes[index].selectedAssetID = source.results[0].id
        graph.nodes[graph.nodes.firstIndex { $0.id == next.id }!].settings.background = .transparent
        XCTAssertFalse(WorkflowRules.usesCurrentInputs(job, nodeID: next.id, graph: graph, jobs: [source]))
    }
    func testPreflightCatchesBlankAndInvalidAPIAndSupportsLegacyFiles() throws {
        var (graph, _, first, next) = try fixture()
        try WorkflowRules.preflight(.init(projectID: UUID(), graph: graph, nodeIDs: [first.id, next.id]))
        let index = graph.nodes.firstIndex { $0.id == next.id }!
        graph.nodes[index].text = " "
        XCTAssertThrowsError(try WorkflowRules.preflight(.init(projectID: UUID(), graph: graph, nodeIDs: [next.id])))
        graph.nodes[index].text = "edit"; graph.nodes[index].settings.mode = .sunburstAPI; graph.nodes[index].settings.api.count = 11
        XCTAssertThrowsError(try WorkflowRules.preflight(.init(projectID: UUID(), graph: graph, nodeIDs: [next.id])))
        var project = Project(name: "old")
        XCTAssertNil(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project)).workflow)
        project.workflow = graph
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project)).workflow, graph)
        XCTAssertNil(try JSONDecoder().decode(QueueJournal.self, from: JSONEncoder().encode(QueueJournal())).workflowRuns)
    }
}
