import Foundation
import Darwin
import PreflightCore

// A true CLI tool used by crash_test.py. Only touches the supplied test directory.
let args = CommandLine.arguments
guard args.count == 5, let id = UUID(uuidString: args[3]) else { exit(2) }
let journal = try JobJournal(directory: URL(fileURLWithPath: args[2]))
if args[1] == "read" {
    print(try journal.recover(id).rawValue)
} else {
    var entry = JournalEntry(id: id, state: JobState(rawValue: args[4]) ?? .queued)
    if [.submitted, .generating, .collecting, .saved].contains(entry.state) {
        entry.conversationID = "local-fixture-conversation"
    }
    try journal.write(entry)
    if entry.state == .collecting || entry.state == .saved {
        try journal.stageResult(Data("local-result".utf8), entry: &entry)
        if args[4] == "saved" { entry.state = .saved; try journal.write(entry) }
    }
    // Terminate without cleanup, after the specified persistent boundary.
    kill(getpid(), SIGKILL)
}
