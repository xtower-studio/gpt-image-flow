import AppKit
import FlowCore

extension WorkspaceStore {
    static var recommendedStorage: URL { FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Image Flow", isDirectory: true) }
    static var legacyStorage: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ImageFlow", isDirectory: true) }
    static func initialStorageLocation() -> URL {
        if let path = UserDefaults.standard.string(forKey: "libraryFolderPath") { return URL(fileURLWithPath: path, isDirectory: true) }
        if FileManager.default.fileExists(atPath: legacyStorage.appendingPathComponent("Library.store").path) { return legacyStorage }
        return recommendedStorage
    }
    var canChangeStorage: Bool { !changingStorage && !importing && !restoringAssets && !jobs.contains { $0.state.isRunning } }
    func selectStorageFolder(openExisting: Bool) {
        guard canChangeStorage else { notice = "현재 생성과 파일 저장이 끝나면 저장 폴더를 변경할 수 있습니다."; return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = !openExisting
        panel.directoryURL = root.deletingLastPathComponent()
        panel.prompt = openExisting ? "보관함 열기" : "이 폴더로 이동"
        panel.message = openExisting ? "ImageFlow.library.json이 들어 있는 보관함 폴더를 선택하세요." : "비어 있는 폴더를 선택하세요. 원본·첨부·작업 기록을 복사하고 기존 폴더는 보존합니다."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { do { try await changeStorage(to: url, openExisting: openExisting) } catch { report(error) } }
    }
    func changeStorage(to destination: URL, openExisting: Bool = false) async throws {
        guard canChangeStorage else { throw FlowError.message("생성 또는 파일 작업이 끝나면 저장 폴더를 변경해 주세요.") }
        if destination.standardizedFileURL == root.standardizedFileURL, storageReady { return }
        if storageReady { try persist() }
        draftSave?.cancel()
        let previousReady = storageReady, source = root
        let snapshot = PortableLibrary(library: library, journal: journal)
        changingStorage = true; storageReady = false
        let access = destination.startAccessingSecurityScopedResource()
        var adopted = false
        defer { changingStorage = false; if access && !adopted { destination.stopAccessingSecurityScopedResource() } }
        do {
            var restored = try await Task.detached(priority: .userInitiated) {
                if openExisting {
                    let archive = try PortableLibrary.load(from: destination)
                    try archive.verifyFiles(in: destination)
                    return archive
                }
                try snapshot.copy(from: source, to: destination)
                return snapshot
            }.value
            if openExisting {
                restored.journal.jobs = restored.journal.jobs.map(JobRules.recovered)
                restored.journal.paused = true; restored.journal.pauseReason = "복원한 보관함입니다. 대기 작업을 확인한 후 계속할 수 있습니다."
                for i in (restored.journal.workflowRuns ?? []).indices where restored.journal.workflowRuns?[i].state == .running { restored.journal.workflowRuns?[i].state = .paused }
            }
            try await AssetVault(root: destination).rebuildMissingThumbnails(restored.library.assets)
            let next = try LibraryPersistence(root: destination)
            try next.save(restored.library)
            try restored.journal.save(destination.appendingPathComponent("Jobs.json"))
            try restored.save(to: destination)
            storageAccess?.stopAccessingSecurityScopedResource(); storageAccess = access ? destination : nil; adopted = true
            root = destination; vault = AssetVault(root: destination); persistence = next
            library = restored.library; journal = restored.journal; storageReady = true
            UserDefaults.standard.set(destination.path, forKey: "libraryFolderPath")
            if let bookmark = try? destination.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(bookmark, forKey: "libraryFolderBookmark") }
            else { UserDefaults.standard.removeObject(forKey: "libraryFolderBookmark") }
            requestedProjectID = library.projects.first?.id
            notice = openExisting ? "이미지·첨부·프로젝트·작업 기록을 복원했습니다." : "저장 폴더를 변경했습니다. 기존 폴더는 보존했습니다."
        } catch { storageReady = previousReady; throw error }
    }
}
