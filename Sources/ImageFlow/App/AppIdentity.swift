import AppKit

@MainActor enum AppIdentity {
    static let bundleID = "studio.xtower.imageflow"
    static let legacyID = "app.imageflow.mac"
    private static var prepared = false
    static var migrationWarning: String?

    /// Run before constructing WebKit or any preferences-backed application state.
    static func prepare() {
        guard !prepared else { return }; prepared = true
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "identityMigratedV12") {
            let old = defaults.persistentDomain(forName: legacyID) ?? [:]
            for key in ["libraryFolderPath", "libraryFolderBookmark", "onboardingCompletedV11", "ecoMode", "lastSelectedProject", "studioBoardMode", "studioCardSize", "canvasShowsConnections"] {
                if defaults.object(forKey: key) == nil, let value = old[key] { defaults.set(value, forKey: key) }
            }
            let fm = FileManager.default, library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
            do {
                for suffix in ["WebKit/", "HTTPStorages/"] {
                    let source = library.appendingPathComponent(suffix + legacyID)
                    let destination = library.appendingPathComponent(suffix + bundleID)
                    try copyIfNeeded(source, to: destination)
                }
                try copyIfNeeded(library.appendingPathComponent("HTTPStorages/\(legacyID).binarycookies"), to: library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"))
                defaults.set(true, forKey: "identityMigratedV12")
            } catch { migrationWarning = "기존 ChatGPT 연결 정보를 옮기지 못했습니다. 연결 창에서 다시 로그인해 주세요. 작업 보관함은 유지됩니다." }
        }
    }
    private static func copyIfNeeded(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: destination.path) else { return }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".imageflow-migration-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: temporary)
        try fm.moveItem(at: temporary, to: destination)
    }
}
