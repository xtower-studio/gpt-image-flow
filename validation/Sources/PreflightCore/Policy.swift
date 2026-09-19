import Foundation

public struct GenerationPolicy: Decodable, Sendable {
    public let defaultConcurrency: Int
    public let maximumConcurrency: Int
    public let ecoConcurrency: Int
    public let batchSizeLimit: Int
    public let submissionSpacingMinimumSeconds: Double
    public let submissionSpacingMaximumSeconds: Double
    public let generationObservationTimeoutSeconds: Double
    public let jobWatchdogSeconds: Double
    public let automaticResubmission: Bool

    public static func load(_ url: URL) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.ecoConcurrency >= 1,
              value.defaultConcurrency <= value.maximumConcurrency,
              value.ecoConcurrency <= value.defaultConcurrency,
              value.maximumConcurrency <= 3,
              value.batchSizeLimit > 0, value.batchSizeLimit <= 50,
              value.submissionSpacingMinimumSeconds >= 30,
              value.submissionSpacingMaximumSeconds >= value.submissionSpacingMinimumSeconds,
              value.jobWatchdogSeconds > value.generationObservationTimeoutSeconds,
              !value.automaticResubmission else { throw PolicyError.invalidPolicy }
        return value
    }
}

public enum PolicyError: Error { case invalidPolicy, invalidBatch }

public struct GateSnapshot: Codable, Sendable {
    let active: [UUID: UUID]
    let usedJobs: Set<UUID>
    let nextSubmission: Double
    let paused: Bool
    let concurrency: Int
}

/// Virtual-time scheduling specification. No web requests or real-time sleeps.
public actor SubmissionGate {
    let policy: GenerationPolicy
    var active: [UUID: UUID] = [:]
    var usedJobs: Set<UUID> = []
    var nextSubmission: Double = 0
    var paused = false
    var concurrency: Int

    public init(policy: GenerationPolicy, eco: Bool = false) {
        self.policy = policy
        concurrency = eco ? policy.ecoConcurrency : policy.defaultConcurrency
    }

    public init(policy: GenerationPolicy, restoring snapshot: GateSnapshot) {
        self.policy = policy
        active = snapshot.active
        usedJobs = snapshot.usedJobs
        nextSubmission = snapshot.nextSubmission
        concurrency = max(policy.ecoConcurrency, min(policy.maximumConcurrency, snapshot.concurrency))
        // Reconcile remote jobs before admitting more work after a restart.
        paused = snapshot.paused || !snapshot.active.isEmpty
    }
    public func snapshot() -> GateSnapshot {
        GateSnapshot(active: active, usedJobs: usedJobs, nextSubmission: nextSubmission,
                     paused: paused, concurrency: concurrency)
    }

    public func validateBatch(_ count: Int) throws {
        guard count > 0 && count <= policy.batchSizeLimit else { throw PolicyError.invalidBatch }
    }

    public func claim(job: UUID, now: Double, delay: Double) -> UUID? {
        guard !paused, now >= nextSubmission, active.count < concurrency,
              !usedJobs.contains(job) else { return nil }
        let token = UUID()
        active[job] = token
        usedJobs.insert(job)
        nextSubmission = now + min(policy.submissionSpacingMaximumSeconds,
                                  max(policy.submissionSpacingMinimumSeconds, delay))
        return token
    }

    public func finish(job: UUID, token: UUID) {
        guard active[job] == token else { return }
        active.removeValue(forKey: job)
    }

    // An ambiguous timeout keeps its slot occupied until remote state is resolved.
    public func pauseForUncertainRemoteState() { paused = true }
    public func resumeExplicitly() { paused = false }
    public func setEco(_ enabled: Bool) {
        concurrency = enabled ? policy.ecoConcurrency : policy.defaultConcurrency
    }
    public func activeCount() -> Int { active.count }
}
