import Foundation

/// Open, versioned recovery document. Contains no API keys or browser credentials.
public struct PortableLibrary: Codable, Sendable {
    public var format = "ImageFlow Library"
    public var version = 1
    public var savedAt = Date()
    public var library: Library
    public var journal: QueueJournal
    public init(library: Library, journal: QueueJournal) { self.library = library; self.journal = journal }
    public static let filename = "ImageFlow.library.json"
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
        let value = try decoder.decode(Self.self, from: Data(contentsOf: root.appendingPathComponent(filename)))
        guard value.format == "ImageFlow Library", value.version == 1, value.library.schemaVersion == 1, value.journal.schemaVersion == 1 else { throw FlowError.message("지원하지 않는 보관함 형식입니다.") }
        guard Set(value.library.assets.map(\.id)).count == value.library.assets.count else { throw FlowError.message("보관함의 이미지 식별자가 중복됩니다.") }
        for asset in value.library.assets { _ = try original(asset, in: root) }
        return value
    }
    public static func original(_ asset: Asset, in root: URL) throws -> URL {
        guard !asset.filename.isEmpty, asset.filename == URL(fileURLWithPath: asset.filename).lastPathComponent,
              !asset.filename.contains("\\"), asset.filename != ".", asset.filename != ".." else { throw FlowError.message("이미지 파일 경로가 올바르지 않습니다.") }
        let folder = root.appendingPathComponent("Originals").standardizedFileURL.resolvingSymlinksInPath()
        let file = folder.appendingPathComponent(asset.filename).resolvingSymlinksInPath()
        guard file.deletingLastPathComponent() == folder else { throw FlowError.message("보관함 밖의 이미지 경로는 사용할 수 없습니다.") }
        return file
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
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encoder.encode(self).write(to: root.appendingPathComponent(Self.filename), options: .atomic)
        guard sidecars else { return }
        let folder = root.appendingPathComponent("Metadata")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let jobs = Dictionary(journal.jobs.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let projects = Dictionary(library.projects.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        let assets = Dictionary(library.assets.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for asset in library.assets {
            let job = asset.jobID.flatMap { jobs[$0] }
            let record = ImageRecord(asset: asset, original: "Originals/\(asset.filename)", project: projects[asset.projectID],
                generation: job, references: (job?.referenceIDs ?? []).compactMap { assets[$0] })
            let data = try Self.encoder.encode(record), url = folder.appendingPathComponent("\(asset.id).json")
            if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
        }
        let help = """
        Image Flow — 복구 가능한 보관함

        Originals/ : 생성 원본과 첨부 이미지. 파일명은 고유 ID입니다.
        Metadata/ : 이미지별 프롬프트, 참조, 생성 설정, 대화/요청 ID, API 사용량, 프로젝트 정보 (JSON).
        ImageFlow.library.json : 프로젝트, 캔버스 연결, 레시피, 이미지 목록, 전체 작업 기록 (UTF-8 JSON, ISO 8601 날짜).
        Jobs.json : 전송 및 복구용 작업 저널.
        Thumbnails/ : 다시 만들 수 있는 미리보기.
        Receipts/ : 저장 직후의 이미지 복구 기록.
        Library.store* : 앱 캐시. 복구에 필수적이지 않습니다.

        앱을 다시 설치한 후 온보딩 또는 설정 → 저장 공간 → 기존 보관함 열기에서 이 폴더를 선택하세요.
        폴더 전체를 함께 보관하면 생성 원본·참조·작업 흐름을 복원할 수 있습니다.
        API 키와 ChatGPT 로그인 정보는 포함하지 않습니다. 프롬프트와 참조에는 개인 작업 내용이 포함될 수 있습니다.
        """
        let readme = root.appendingPathComponent("보관함 안내.txt")
        if (try? String(contentsOf: readme, encoding: .utf8)) != help { try help.write(to: readme, atomically: true, encoding: .utf8) }
    }
    /// Copy and verify first. Never delete or overwrite the source library.
    public func copy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let a = source.standardizedFileURL.resolvingSymlinksInPath(), b = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard a != b, !b.path.hasPrefix(a.path + "/"), !a.path.hasPrefix(b.path + "/") else { throw FlowError.message("현재 보관함과 겹치지 않는 폴더를 선택하세요.") }
        if fm.fileExists(atPath: b.path), !(try fm.contentsOfDirectory(at: b, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)).isEmpty {
            throw FlowError.message("빈 폴더를 선택하세요. 기존 보관함은 ‘기존 보관함 열기’로 복원할 수 있습니다.")
        }
        try verifyFiles(in: a)
        for folder in ["Originals", "Thumbnails", "Receipts"] { try fm.createDirectory(at: b.appendingPathComponent(folder), withIntermediateDirectories: true) }
        for asset in library.assets {
            try fm.copyItem(at: Self.original(asset, in: a), to: Self.original(asset, in: b))
            let thumb = a.appendingPathComponent("Thumbnails/\(asset.id).png")
            if fm.fileExists(atPath: thumb.path) { try fm.copyItem(at: thumb, to: b.appendingPathComponent("Thumbnails/\(asset.id).png")) }
            try JSONEncoder().encode(asset).write(to: b.appendingPathComponent("Receipts/\(asset.id).json"), options: .atomic)
        }
        try verifyFiles(in: b)
        try journal.save(b.appendingPathComponent("Jobs.json"))
        try save(to: b)
    }
}
