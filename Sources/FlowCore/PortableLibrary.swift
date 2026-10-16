import Foundation

/// Open, versioned recovery document. Contains no API keys or browser credentials.
public struct PortableLibrary: Codable, Sendable {
    public var format = "ImageFlow Library"
    public var version = 3
    public var savedAt = Date()
    public var library: Library
    public var journal: QueueJournal
    public init(library: Library, journal: QueueJournal) { self.library = library; self.journal = journal }
    public static let filename = ".imageflow/ImageFlow.library.json"
    public static let journalFilename = ".imageflow/Jobs.json"
    public static func manifestURL(in root: URL) -> URL {
        let current = root.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: current.path) ? current : root.appendingPathComponent("ImageFlow.library.json")
    }
    public struct ImageRecord: Codable {
        public let asset: Asset
        public let original: String
        public let project: Project?
        public let generation: Job?
        public let references: [Asset]
    }
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return encoder
    }
    public static func load(from root: URL) throws -> Self {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(Self.self, from: Data(contentsOf: manifestURL(in: root)))
        guard value.format == "ImageFlow Library", (1...3).contains(value.version), value.library.schemaVersion == 1, value.journal.schemaVersion == 1 else { throw FlowError.message("지원하지 않는 보관함 형식입니다.") }
        guard Set(value.library.assets.map(\.id)).count == value.library.assets.count else { throw FlowError.message("보관함의 이미지 식별자가 중복됩니다.") }
        for asset in value.library.assets { _ = try original(asset, in: root) }
        return value
    }
    public static func original(_ asset: Asset, in root: URL) throws -> URL {
        try AssetPaths.original(asset, in: root)
    }
    public func verifyFiles(in root: URL) throws {
        for asset in library.assets {
            let path = try Self.original(asset, in: root)
            guard let bytes = try? Data(contentsOf: path, options: .mappedIfSafe), AssetVault.hash(bytes) == asset.digest else {
                throw FlowError.message("원본이 없거나 손상되었습니다: \(asset.title). 현재 보관함은 그대로 유지됩니다.")
            }
        }
    }
    public func save(to root: URL, sidecars: Bool = true) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent(".imageflow"), withIntermediateDirectories: true)
        try Self.encoder.encode(self).write(to: root.appendingPathComponent(Self.filename), options: .atomic)
        guard sidecars else { return }
        let jobs = Dictionary(journal.jobs.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let projects = Dictionary(library.projects.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let assets = Dictionary(library.assets.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for asset in library.assets {
            let job = asset.jobID.flatMap { jobs[$0] }
            let record = ImageRecord(asset: asset, original: AssetPaths.relativePath(asset), project: projects[asset.projectID],
                generation: job, references: (job?.referenceIDs ?? []).compactMap { assets[$0] })
            let data = try Self.encoder.encode(record), url = try AssetPaths.metadata(asset, in: root)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
        }
        for project in library.projects {
            guard let name = project.storageFolder else { continue }
            let directory = root.appendingPathComponent(AssetPaths.component(name) + "/.imageflow")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(project), url = directory.appendingPathComponent("project.json")
            if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
        }
        let help = """
        Image Flow — 복구 가능한 보관함

        프로젝트 폴더/ : 생성 이미지와 첨부 원본. 썸네일은 만들지 않습니다.
        프로젝트 폴더/.imageflow/ : 이미지별 생성 정보 JSON과 project.json.
        .imageflow/ImageFlow.library.json : 전체 보관함 복구 정보.
        .imageflow/Jobs.json : 작업 기록. .imageflow/Receipts : 저장 복구 기록.
        .imageflow/Library.store* : 앱 캐시.
        Finder에서 숨김 파일 보기: Command + Shift + 마침표.

        앱을 다시 설치한 후 온보딩 또는 설정 → 저장 공간 → 기존 보관함 열기에서 이 폴더를 선택하세요.
        폴더 전체를 함께 보관하면 생성 원본·참조·작업 흐름을 복원할 수 있습니다.
        API 키와 ChatGPT 로그인 정보는 포함하지 않습니다. 프롬프트와 참조에는 개인 작업 내용이 포함될 수 있습니다.
        """
        let readme = root.appendingPathComponent(".imageflow/보관함 안내.txt")
        if (try? String(contentsOf: readme, encoding: .utf8)) != help { try help.write(to: readme, atomically: true, encoding: .utf8) }
    }
    /// Copy and verify first. Never delete or overwrite the source library.
    public func copy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let a = source.standardizedFileURL.resolvingSymlinksInPath(), b = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard a != b, !b.path.hasPrefix(a.path + "/"), !a.path.hasPrefix(b.path + "/") else { throw FlowError.message("현재 보관함과 겹치지 않는 폴더를 선택하세요.") }
        if fm.fileExists(atPath: b.path), !(try fm.contentsOfDirectory(at: b, includingPropertiesForKeys: nil, options: [])).filter({ $0.lastPathComponent != ".DS_Store" }).isEmpty {
            throw FlowError.message("빈 폴더를 선택하세요. 기존 보관함은 ‘기존 보관함 열기’로 복원할 수 있습니다.")
        }
        try verifyFiles(in: a)
        for folder in [".imageflow/Receipts"] { try fm.createDirectory(at: b.appendingPathComponent(folder), withIntermediateDirectories: true) }
        for asset in library.assets {
            let target = try Self.original(asset, in: b)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: Self.original(asset, in: a), to: target)
            try JSONEncoder().encode(asset).write(to: b.appendingPathComponent(".imageflow/Receipts/\(asset.id).json"), options: .atomic)
        }
        try verifyFiles(in: b)
        try journal.save(b.appendingPathComponent(Self.journalFilename))
        try save(to: b)
    }
}
