import AppKit
import FlowCore

extension WorkspaceStore {
    func attach(_ asset: Asset, to projectID: UUID) {
        guard var project = project(projectID) else { return }
        if !project.referenceIDs.contains(asset.id) { project.referenceIDs.append(asset.id); updateProject(project) }
        notice = "참조에 추가했습니다."
    }
    func enqueueFollowup(to original: Job, text: String, mode: GenerationMode) throws {
        guard mode != .sunburstAPI else { throw FlowError.message("Sunburst API는 만들기 탭에서 새 요청으로 시작하세요. 기존 이미지를 참조로 추가할 수 있습니다.") }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, original.conversationID != nil else { throw FlowError.message("대화를 확인하고 후속 요청을 입력해 주세요.") }
        guard !jobs.contains(where: { $0.conversationID == original.conversationID && ($0.state.isRunning || $0.state == .queued) }) else {
            throw FlowError.message("이 대화의 이전 요청이 끝나면 이어서 보낼 수 있습니다.")
        }
        var job = Job(batchID: UUID(), projectID: original.projectID, prompt: text + "\nn=\(mode.imagesPerRequest)", label: "후속 요청", referenceIDs: [])
        job.conversationID = original.conversationID; job.continuationOf = original.id; job.generationMode = mode; job.reasoning = mode.reasoning
        job.requestedImageCount = mode.imagesPerRequest; job.inputPrompt = text
        reserveCanvasPositions(for: [job]); journal.jobs.append(job); try persist()
    }
    func saveRecipe(project: Project, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if library.recipes == nil { library.recipes = [] }
        var settings = project; settings.generationMode = selectedGenerationMode
        library.recipes?.append(Recipe(name: name, settings: settings)); flush()
        notice = "레시피를 저장했습니다."
    }
    func applyRecipe(_ recipe: Recipe, to id: UUID) {
        guard var project = project(id) else { return }
        let settings = recipe.settings
        project.prompt = settings.prompt; project.variations = settings.variations
        project.copies = settings.copies; project.aspect = settings.aspect; project.reasoning = settings.reasoning
        project.background = settings.background; project.imageModel = settings.imageModel
        project.generationMode = settings.generationMode; project.apiOptions = settings.apiOptions
        selectedGenerationMode = settings.generationMode ?? .migrated(from: settings.imageModel)
        project.referenceIDs = settings.referenceIDs.filter { asset($0) != nil }
        updateProject(project); notice = "\(recipe.name) 레시피를 적용했습니다."
    }
    func hideAssets(_ ids: [UUID]) {
        let undo = NSApp.keyWindow?.undoManager
        undo?.registerUndo(withTarget: self) { [weak undo] target in target.restoreHidden(ids, undoManager: undo) }
        undo?.setActionName("이미지 숨기기")
        lastHiddenAssets = ids
        library.hiddenAssetIDs = Array(Set((library.hiddenAssetIDs ?? []) + ids)); flush()
        notice = "\(ids.count)개 이미지를 보관함에서 숨겼습니다. 원본은 유지됩니다."
    }
    func restoreHidden(_ ids: [UUID], undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { target in target.hideAssets(ids) }
        library.hiddenAssetIDs?.removeAll { ids.contains($0) }; lastHiddenAssets = []; flush()
        notice = "이미지를 복원했습니다."
    }
    func undoHide() {
        if let undo = NSApp.keyWindow?.undoManager, undo.canUndo, undo.undoActionName == "이미지 숨기기" { undo.undo() }
        else { restoreHidden(lastHiddenAssets, undoManager: nil) }
    }
    func restoreAllHidden() { library.hiddenAssetIDs = []; lastHiddenAssets = []; flush() }
    func copyImage(_ asset: Asset) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([storeURL(asset) as NSURL])
        notice = "이미지를 복사했습니다."
    }
    private func storeURL(_ asset: Asset) -> URL { vault.original(asset) }
    func reserveCanvasPositions(for newJobs: [Job]) {
        for job in newJobs {
            guard var project = project(job.projectID) else { continue }
            var positions = project.layout ?? [:]
            let existingAssets = library.assets.filter { $0.projectID == project.id }
            for (index, asset) in existingAssets.enumerated() where positions[asset.id.uuidString] == nil {
                positions[asset.id.uuidString] = asset.jobID.flatMap { positions[$0.uuidString] } ?? CanvasPoint(x: Double(index%4)*304, y: Double(index/4)*407)
            }
            let bottom = positions.values.map(\.y).max() ?? -407
            positions[job.id.uuidString] = CanvasPoint(x: 0, y: bottom + 407)
            project.layout = positions; updateProject(project)
        }
    }
    func placeResult(_ asset: Asset, job: Job, index: Int) {
        guard let project = project(job.projectID), project.layout?[asset.id.uuidString] == nil else { return }
        let origin = project.layout?[job.id.uuidString] ?? CanvasPoint(x: 0, y: 0)
        setCanvasPositions([asset.id.uuidString: CanvasPoint(x: origin.x + Double(index % 4) * 304, y: origin.y + Double(index / 4) * 407)], projectID: job.projectID)
    }
    func setCanvasPositions(_ positions: [String: CanvasPoint], projectID: UUID, undoable: Bool = false) {
        guard var project = project(projectID) else { return }
        if undoable, let undo = NSApp.keyWindow?.undoManager {
            let previous = project.layout
            undo.registerUndo(withTarget: self) { [weak undo] target in target.restoreCanvasLayout(previous, projectID: projectID, undo: undo) }
            undo.setActionName("캔버스 배치")
        }
        if project.layout == nil { project.layout = [:] }
        project.layout?.merge(positions) { _, new in new }; updateProject(project)
    }
    private func restoreCanvasLayout(_ layout: [String: CanvasPoint]?, projectID: UUID, undo: UndoManager?) {
        guard var project = project(projectID) else { return }
        let current = project.layout
        undo?.registerUndo(withTarget: self) { [weak undo] target in target.restoreCanvasLayout(current, projectID: projectID, undo: undo) }
        undo?.setActionName("캔버스 배치")
        project.layout = layout; updateProject(project)
    }
    func setViewport(_ viewport: CanvasViewport, projectID: UUID) {
        guard var project = project(projectID) else { return }
        project.viewport = viewport; updateProject(project)
    }
}
