import AppKit
import Observation
import FlowCore

@MainActor @Observable final class WorkspaceStore {
    var library = Library()
    var journal = QueueJournal()
    var errorMessage: String?
    var storageReady = false
    var restoringAssets = true
    var importing = false
    var changingStorage = false
    var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingCompletedV11")
    @ObservationIgnored var storageAccess: URL?
    var notice: String?
    var lastHiddenAssets: [UUID] = []
    var requestedJobID: UUID?
    var requestedProjectID: UUID?
    var requestedComparison: [UUID] = []
    var requestedInspectorAsset: UUID?
    var root: URL
    @ObservationIgnored var vault: AssetVault
    @ObservationIgnored var persistence: LibraryPersistence?
    @ObservationIgnored var draftSave: Task<Void, Never>?
    let apiConnection = APIConnection()
    var selectedGenerationMode: GenerationMode {
        get { (library.preferredGenerationMode ?? .migrated(from: library.preferredModel)).selectable }
        set { library.preferredGenerationMode = newValue; flush() }
    }
    func dismissAttention(_ ids: Set<UUID>) {
        for index in journal.jobs.indices where ids.contains(journal.jobs[index].id) {
            journal.jobs[index].dismissedAttentionState = journal.jobs[index].state
        }
        flush()
    }
    var jobs: [Job] { journal.jobs }
    var journalURL: URL { root.appendingPathComponent("Jobs.json") }

    init() {
        let args = CommandLine.arguments
        let initialRoot: URL
        if let index = args.firstIndex(of: "--data-directory"), args.count > index + 1 { initialRoot = URL(fileURLWithPath: args[index + 1]) }
        else { initialRoot = Self.initialStorageLocation() }
        root = initialRoot; vault = AssetVault(root: initialRoot)
        do {
            if let bookmark = UserDefaults.standard.data(forKey: "libraryFolderBookmark"), !args.contains("--data-directory") {
                var stale = false
                if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale), resolved.startAccessingSecurityScopedResource() {
                    storageAccess = resolved; root = resolved; vault = AssetVault(root: root)
                }
            }
            if UserDefaults.standard.string(forKey: "libraryFolderPath") != nil, !args.contains("--data-directory"), !FileManager.default.fileExists(atPath: root.path) {
                throw FlowError.message("선택한 저장 폴더를 찾을 수 없습니다. 드라이브를 연결하거나 설정에서 보관함을 다시 열어 주세요.")
            }
            let archive = FileManager.default.fileExists(atPath: root.appendingPathComponent(PortableLibrary.filename).path) ? try PortableLibrary.load(from: root) : nil
            let persistence = try LibraryPersistence(root: root)
            self.persistence = persistence; library = try archive?.library ?? persistence.load()
            journal = FileManager.default.fileExists(atPath: journalURL.path) ? try QueueJournal.load(journalURL) : archive?.journal ?? QueueJournal()
            journal.jobs = journal.jobs.map(JobRules.recovered)
            for index in (journal.workflowRuns ?? []).indices where journal.workflowRuns?[index].state == .running {
                journal.workflowRuns?[index].state = .paused
            }
            // A single interrupted request does not block unrelated queued work.
            if journal.paused && journal.pauseReason == nil { journal.pauseReason = "이전 버전에서 일시정지한 작업입니다. 계속을 누르면 대기 작업을 실행합니다." }
            if library.projects.isEmpty { library.projects = [Project(name: "첫 프로젝트")] }
            library.restoreMissingAssets(journal.jobs.flatMap(\.results))
            storageReady = true
            try persist()
            Task {
                defer { restoringAssets = false }
                do {
                    for asset in try await vault.receipts() {
                        library.restoreMissingAssets([asset])
                        guard let id = asset.jobID, let index = journal.jobs.firstIndex(where: { $0.id == id }) else { continue }
                        library.restoreMissingAssets([asset])
                        if !journal.jobs[index].results.contains(where: { $0.id == asset.id }) { journal.jobs[index].results.append(asset) }
                    }
                    try await vault.rebuildMissingThumbnails(library.assets)
                    try persist()
                } catch { report(error) }
            }
        } catch { restoringAssets = false; storageReady = false; errorMessage = "저장 공간을 열 수 없습니다. 원본 데이터를 보존했습니다.\n" + error.localizedDescription }
    }
    func persist() throws {
        guard storageReady, let persistence else { throw FlowError.message("저장 공간을 확인해 주세요.") }
        do {
            try journal.save(journalURL)
            try PortableLibrary(library: library, journal: journal).save(to: root)
            try persistence.save(library)
        } catch { storageReady = false; journal.paused = true; throw error }
    }
    func flush() { draftSave?.cancel(); do { try persist() } catch { report(error) } }
    func report(_ error: Error) { errorMessage = error.localizedDescription }
    func project(_ id: UUID?) -> Project? { library.projects.first { $0.id == id } }
    func asset(_ id: UUID) -> Asset? { library.assets.first { $0.id == id } }
    func upsert(_ asset: Asset) {
        if let index = library.assets.firstIndex(where: { $0.id == asset.id }) { library.assets[index] = asset }
        else { library.assets.append(asset) }
    }
    func addProject() -> UUID {
        let project = Project(name: "새 프로젝트 \(library.projects.count + 1)")
        library.projects.append(project); flush(); return project.id
    }
    func updateProject(_ project: Project) {
        guard !changingStorage else { return }
        guard let index = library.projects.firstIndex(where: { $0.id == project.id }) else { return }
        library.projects[index] = project
        draftSave?.cancel()
        draftSave = Task { try? await Task.sleep(for: .milliseconds(350)); if !Task.isCancelled { flush() } }
    }
    func enqueue(project: Project, parentID: UUID? = nil) throws {
        guard storageReady else { throw FlowError.message("저장 공간을 확인해 주세요.") }
        if project.generationMode == .sunburstAPI, !apiConnection.ready { throw FlowError.message("OpenAI API를 먼저 연결하세요.") }
        let jobs = try JobRules.makeBatch(project: project, parentID: parentID)
        for id in project.referenceIDs { guard let asset = asset(id), FileManager.default.fileExists(atPath: vault.original(asset).path) else { throw FlowError.message("참조 원본을 찾을 수 없습니다. 다시 추가해 주세요.") } }
        reserveCanvasPositions(for: jobs)
        journal.jobs.append(contentsOf: jobs)
        try persist()
    }
    func updateJob(_ id: UUID, _ body: (inout Job) -> Void) throws {
        guard let index = journal.jobs.firstIndex(where: { $0.id == id }) else { throw FlowError.message("작업을 찾을 수 없습니다.") }
        let previous = journal.jobs[index].state
        body(&journal.jobs[index])
        if journal.jobs[index].state != previous { journal.jobs[index].dismissedAttentionState = nil }
        try persist()
    }
    func toggleFavorite(_ asset: Asset) {
        guard let index = library.assets.firstIndex(where: { $0.id == asset.id }) else { return }
        library.assets[index].isFavorite.toggle(); flush()
    }
    func importImages(_ urls: [URL], projectID: UUID) {
        guard storageReady, !urls.isEmpty else { return }
        importing = true
        Task {
            defer { importing = false }
            do {
                for url in urls where url.isFileURL {
                    if let existing = library.assets.first(where: { vault.original($0).standardizedFileURL == url.standardizedFileURL }) {
                        attach(existing, to: projectID); continue
                    }
                    let asset = try await vault.ingest(url: url, projectID: projectID)
                    upsert(asset)
                    if let index = library.projects.firstIndex(where: { $0.id == projectID }) { library.projects[index].referenceIDs.append(asset.id) }
                    try persist()
                }
            } catch { report(error) }
        }
    }
    func selectImages(projectID: UUID) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.message = "프로젝트에서 함께 사용할 참조 이미지를 선택하세요."
        if panel.runModal() == .OK { importImages(panel.urls, projectID: projectID) }
    }
    func export(_ assets: [Asset]) {
        guard !assets.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.prompt = "여기에 내보내기"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task {
            do {
                let folder = try await vault.export(assets, jobs: journal.jobs, to: directory)
                notice = "\(assets.count)개 이미지를 내보냈습니다."
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch { report(error) }
        }
    }
    func cancelQueued(_ id: UUID) {
        do { try updateJob(id) { if [.queued, .needsLogin, .failed].contains($0.state) { $0.state = .cancelled } } }
        catch { report(error) }
    }
    func moveQueued(_ id: UUID, toFront: Bool) {
        guard let index = journal.jobs.firstIndex(where: { $0.id == id && $0.state == .queued }) else { return }
        let job = journal.jobs.remove(at: index)
        if toFront { journal.jobs.insert(job, at: 0) } else { journal.jobs.append(job) }
        flush()
    }
}
