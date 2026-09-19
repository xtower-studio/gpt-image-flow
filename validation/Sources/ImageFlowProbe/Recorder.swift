import Foundation

struct Check: Codable {
    let name: String
    let passed: Bool
    let detail: String
}

@MainActor final class Recorder {
    let output: URL
    var checks: [Check] = []
    init(output: URL) { self.output = output }
    func record(_ name: String, _ passed: Bool, _ detail: String = "") {
        checks.append(Check(name: name, passed: passed, detail: detail))
    }
    func finish() throws {
        struct Report: Codable {
            let scope: String
            let os: String
            let checkedAt: String
            let passed: Bool
            let checks: [Check]
        }
        let report = Report(scope: "offline-local-WebKit-fixture; no ChatGPT requests",
                            os: ProcessInfo.processInfo.operatingSystemVersionString,
                            checkedAt: ISO8601DateFormatter().string(from: Date()),
                            passed: checks.allSatisfy(\.passed), checks: checks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: output, options: .atomic)
    }
}

enum ProbeError: Error { case timeout(String), invalidResult }

@MainActor func waitUntil(_ name: String, timeout: Double = 5,
                          _ condition: () async throws -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw ProbeError.timeout(name)
}
