import Foundation
import SwiftData
import FlowCore

@Model final class LibraryRecord {
    @Attribute(.unique) var key: String
    var payload: Data
    init(payload: Data) { key = "library-v1"; self.payload = payload }
}

/// Project metadata is a versioned value snapshot; the job journal is authoritative
/// for remote side effects and is saved before every submission boundary.
@MainActor final class LibraryPersistence {
    let container: ModelContainer
    let context: ModelContext
    init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container = try ModelContainer(for: LibraryRecord.self,
            configurations: ModelConfiguration(url: root.appendingPathComponent("Library.store")))
        context = ModelContext(container); context.autosaveEnabled = false
    }
    func load() throws -> Library {
        guard let record = try context.fetch(FetchDescriptor<LibraryRecord>()).first else { return Library() }
        let library = try JSONDecoder().decode(Library.self, from: record.payload)
        guard library.schemaVersion == 1 else { throw FlowError.message("지원하지 않는 라이브러리 버전입니다.") }
        return library
    }
    func save(_ library: Library) throws {
        let data = try JSONEncoder().encode(library)
        if let record = try context.fetch(FetchDescriptor<LibraryRecord>()).first { record.payload = data }
        else { context.insert(LibraryRecord(payload: data)) }
        try context.save()
    }
}
