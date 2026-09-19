import Foundation
import CryptoKit

public enum JobState: String, Codable, Sendable {
    case queued, uploading, submitting, submitted, generating, collecting, saved
}
public enum RecoveryAction: String, Sendable {
    case prepare, needsReview, collectExisting, useSaved
}
public struct JournalEntry: Codable, Sendable {
    public let id: UUID
    public var state: JobState
    public var conversationID: String?
    public var digest: String?
    public init(id: UUID, state: JobState, conversationID: String? = nil) {
        self.id = id; self.state = state; self.conversationID = conversationID
    }
}

/// A preflight journal, deliberately separate from the future project metadata DB.
/// Proves process-crash ordering, not power-loss durability or production migration.
public struct JobJournal {
    public let directory: URL
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public func entryURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id).json") }
    public func assetURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id).asset") }
    public func write(_ entry: JournalEntry) throws {
        try JSONEncoder().encode(entry).write(to: entryURL(entry.id), options: .atomic)
    }
    public func read(_ id: UUID) throws -> JournalEntry {
        try JSONDecoder().decode(JournalEntry.self, from: Data(contentsOf: entryURL(id)))
    }
    public func stageResult(_ bytes: Data, entry: inout JournalEntry) throws {
        entry.digest = Self.hash(bytes)
        entry.state = .collecting
        try write(entry)
        try bytes.write(to: assetURL(entry.id), options: .atomic)
    }
    public func recover(_ id: UUID) throws -> RecoveryAction {
        var entry = try read(id)
        if let digest = entry.digest,
           let bytes = try? Data(contentsOf: assetURL(id)), Self.hash(bytes) == digest {
            entry.state = .saved
            try write(entry)
            return .useSaved
        }
        if entry.state == .queued || entry.state == .uploading { return .prepare }
        if entry.conversationID != nil { return .collectExisting }
        return .needsReview
    }
    public static func hash(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
