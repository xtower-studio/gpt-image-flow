import Foundation

public struct GenerationPolicy: Codable, Sendable {
    public let defaultConcurrency: Int
    public let maximumConcurrency: Int
    public let ecoConcurrency: Int
    public let batchSizeLimit: Int
    public let submissionSpacingMinimumSeconds: Double
    public let submissionSpacingMaximumSeconds: Double
    public let generationObservationTimeoutSeconds: Double
    public let jobWatchdogSeconds: Double
    public let automaticResubmission: Bool
    public static func load(_ data: Data) throws -> Self {
        let policy = try JSONDecoder().decode(Self.self, from: data)
        guard policy.defaultConcurrency == 3, policy.maximumConcurrency == 3,
              policy.ecoConcurrency == 1, policy.batchSizeLimit == 50,
              policy.submissionSpacingMinimumSeconds >= 30,
              policy.submissionSpacingMaximumSeconds >= policy.submissionSpacingMinimumSeconds,
              !policy.automaticResubmission else { throw FlowError.message("생성 정책을 확인할 수 없습니다.") }
        return policy
    }
}

public enum JobRules {
    public static func makeBatch(project: Project, parentID: UUID? = nil, maximum: Int = 50) throws -> [Job] {
        let prompt = project.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw FlowError.message("만들고 싶은 이미지를 적어 주세요.") }
        let variations = project.variations.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let count = variations.isEmpty ? project.copies : variations.count
        guard (1...maximum).contains(count) else { throw FlowError.message("요청 횟수는 1~\(maximum)회로 설정해 주세요.") }
        let batchID = UUID()
        let mode = project.generationMode ?? GenerationMode.migrated(from: project.imageModel)
        let api = mode == .sunburstAPI ? (project.apiOptions ?? ImageAPIOptions()) : nil
        if let api { try api.validate(prompt: prompt, referenceCount: project.referenceIDs.count) }
        return try (0..<count).map { index in
            let variation = variations.isEmpty ? "" : variations[index]
            let size = ["자유", "자동"].contains(project.aspect) ? nil : "size:\(project.aspect)"
            let full = [prompt, variation.isEmpty ? nil : variation, size, project.background?.promptOption, "n=\(mode.imagesPerRequest)"]
                .compactMap { $0 }.joined(separator: "\n")
            var job = Job(batchID: batchID, projectID: project.id, prompt: full,
                       label: variation.isEmpty ? "요청 \(index + 1)" : variation,
                       referenceIDs: project.referenceIDs, parentID: parentID)
            job.generationMode = mode; job.apiOptions = api; job.requestedImageCount = api?.count ?? mode.imagesPerRequest
            job.reasoning = api == nil ? mode.reasoning : nil
            job.inputPrompt = [prompt, variation.isEmpty ? nil : variation].compactMap { $0 }.joined(separator: "\n")
            if let api { job.prompt = job.inputPrompt!; try api.validate(prompt: job.prompt, referenceCount: job.referenceIDs.count) }
            job.requestedAspect = project.aspect; job.requestedBackground = project.background
            return job
        }
    }
    public static func finishing(_ job: Job) -> Job {
        var job = job
        let count = job.results.count
        job.state = count >= job.expectedImageCount ? .saved : .needsReview
        job.error = count >= job.expectedImageCount ? nil : "요청한 \(job.expectedImageCount)장 중 \(count)장을 저장했습니다. 기존 대화에서 나머지 결과를 확인할 수 있습니다."
        job.finishedAt = Date()
        return job
    }
    public static func recovered(_ job: Job) -> Job {
        var job = job
        if job.state == .preparing || job.state == .uploading { job.state = .queued }
        else if job.state.isRunning {
            job.state = .needsReview
            job.error = job.conversationID == nil ? "전송 여부를 확인한 뒤 다시 시작하세요." : "기존 대화의 결과를 확인할 수 있습니다."
        }
        return job
    }
}

public struct QueueJournal: Codable, Sendable {
    public var schemaVersion = 1
    public var jobs: [Job] = []
    public var workflowRuns: [WorkflowRun]?
    public var paused = false
    public var nextSubmissionAt = Date.distantPast
    public var workerAvailableAt: [String: Date]?
    public var pauseReason: String?
    public init() {}
    public static func load(_ url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let journal = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard journal.schemaVersion == 1 else { throw FlowError.message("지원하지 않는 작업 기록 버전입니다.") }
        return journal
    }
    public func save(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
