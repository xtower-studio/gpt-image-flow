import Foundation
import Observation
import FlowCore

@MainActor @Observable final class GenerationEngine {
    var activeCount = 0
    var apiPreviews: [UUID: Data] = [:]
    var eco: Bool { didSet { UserDefaults.standard.set(eco, forKey: "ecoMode") } }
    var nextStart: Date?
    @ObservationIgnored let store: WorkspaceStore
    @ObservationIgnored let session: WebSession
    @ObservationIgnored let policy: GenerationPolicy
    @ObservationIgnored var running: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var workers: [UUID: WebWorker] = [:]
    @ObservationIgnored var loop: Task<Void, Never>?
    @ObservationIgnored var slots: [UUID: Int] = [:]
    @ObservationIgnored var watchdogs: [UUID: Task<Void, Never>] = [:]

    init(store: WorkspaceStore, session: WebSession) {
        self.store = store; self.session = session
        eco = UserDefaults.standard.bool(forKey: "ecoMode")
        policy = try! GenerationPolicy.load(Data(contentsOf: Bundle.module.url(forResource: "generation-policy", withExtension: "json", subdirectory: "Resources")!))
    }
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func tick() {
        activeCount = running.count
        let cooldowns = store.journal.workerAvailableAt ?? [:]
        nextStart = cooldowns.values.filter { $0 > Date() }.min()
        guard store.storageReady, !store.restoringAssets, !store.journal.paused else { return }
        let available = QueueAdmission.slots(limit: eco ? policy.ecoConcurrency : policy.defaultConcurrency,
            occupied: Set(slots.values), availableAt: [:], now: Date())
        for slot in available {
            let executing = store.jobs.filter { running[$0.id] != nil }
            guard let job = store.jobs.first(where: { $0.state == .queued && ($0.apiOptions != nil || (session.status == .ready && (cooldowns[String(slot)] ?? .distantPast) <= Date())) && running[$0.id] == nil && QueueAdmission.canStart($0, alongside: executing) }) else { continue }
            launch(job, recovery: false, slot: slot)
        }
    }
    func launch(_ job: Job, recovery: Bool, slot: Int) {
        guard running[job.id] == nil else { return }
        slots[job.id] = slot
        running[job.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                apiPreviews.removeValue(forKey: job.id)
                workers[job.id]?.close(); workers.removeValue(forKey: job.id)
                running.removeValue(forKey: job.id)
                slots.removeValue(forKey: job.id)
                if !recovery && job.apiOptions == nil {
                    if store.journal.workerAvailableAt == nil { store.journal.workerAvailableAt = [:] }
                    store.journal.workerAvailableAt?[String(slot)] = Date().addingTimeInterval(Double.random(in: policy.submissionSpacingMinimumSeconds...policy.submissionSpacingMaximumSeconds))
                    store.flush()
                }
                activeCount = running.count
                watchdogs.removeValue(forKey: job.id)?.cancel()
            }
            do {
                if job.apiOptions != nil { try await executeAPI(job) }
                else { try await execute(job, recovery: recovery, slot: slot) }
            } catch {
                if job.apiOptions != nil { handleAPI(error, job: job) }
                else { handle(error, job: job.id) }
            }
        }
        watchdogs[job.id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(policy.jobWatchdogSeconds))
            guard !Task.isCancelled else { return }
            running[job.id]?.cancel()
        }
        activeCount = running.count
    }
    func pauseOrResume() {
        store.journal.paused.toggle()
        store.journal.pauseReason = store.journal.paused ? "사용자가 일시정지했습니다. 진행 중인 생성은 계속됩니다." : nil
        store.flush()
    }
    func recover(_ job: Job) {
        guard store.storageReady, !store.restoringAssets, job.conversationID != nil, session.status == .ready,
              !store.jobs.contains(where: { $0.id != job.id && $0.conversationID == job.conversationID && running[$0.id] != nil }),
              let slot = (0..<(eco ? 1 : 3)).first(where: { !slots.values.contains($0) }) else { return }
        launch(job, recovery: true, slot: slot)
    }
    func execute(_ job: Job, recovery: Bool, slot: Int) async throws {
        let worker = try WebWorker(slot: slot, session: session); workers[job.id] = worker
        let baseline: WebSnapshot
        var expectedConversation = job.conversationID
        var excluded = Set(job.excludedFileIDs ?? [])
        if recovery {
            guard let conversation = job.conversationID else { throw WorkerError.uncertain("원래 대화를 찾을 수 없습니다.") }
            try store.updateJob(job.id) { $0.state = .collecting; $0.error = nil }
            try await worker.load(conversation)
            baseline = try await worker.snapshot()
        } else {
            try store.updateJob(job.id) { $0.state = job.referenceIDs.isEmpty ? .preparing : .uploading; $0.startedAt = Date(); $0.error = nil }
            let files = try job.referenceIDs.map { id -> URL in
                guard let asset = store.asset(id) else { throw WorkerError.attachment }; return store.vault.original(asset)
            }
            baseline = try await worker.prepare(job: job, files: files)
            excluded = Set(baseline.images.map(\.fileID))
            if job.continuationOf != nil, let metadata = try? await worker.generationMetadata() {
                excluded.formUnion(metadata.map(\.fileID))
            }
            if store.journal.paused {
                try store.updateJob(job.id) { $0.state = .queued }
                return
            }
            // Freeze the response boundary before the remote side effect.
            try store.updateJob(job.id) {
                $0.state = .submitting; $0.submittedAt = Date()
                $0.excludedFileIDs = Array(excluded); $0.baselineAssistantCount = baseline.assistantCount
                $0.appliedReasoning = worker.appliedReasoning
            }
            try await worker.submit()

        }
        let deadline = Date().addingTimeInterval(recovery ? 120 : policy.generationObservationTimeoutSeconds)
        var stableKey = "", stableSince = Date(), sentConfirmed = recovery
        var replySince: Date?
        var lastReply = ""
        var progressKey = ""
        var progressAt = Date()
        while Date() < deadline {
            try await worker.wait(1.5)
            let state = try await worker.snapshot()
            if state.login { throw WorkerError.login }
            if state.limitation { throw WorkerError.limited }
            if let message = state.serviceError, !message.isEmpty { throw WorkerError.generationFailed(message) }
            if let conversation = state.conversationID {
                if let expectedConversation, conversation != expectedConversation { throw WorkerError.uncertain("작업 중 대화가 바뀌었습니다. 원래 대화를 확인해 주세요.") }
                if expectedConversation == nil {
                    expectedConversation = conversation
                    try store.updateJob(job.id) { $0.conversationID = conversation; $0.state = .generating }
                }
            }
            if !recovery, state.userCount > baseline.userCount, state.composerEmpty { sentConfirmed = true }
            guard sentConfirmed, expectedConversation != nil else { continue }
            if store.jobs.first(where: { $0.id == job.id })?.state == .submitting { try store.updateJob(job.id) { $0.state = .generating } }
            let newImages = state.images.filter { !excluded.contains($0.fileID) }
            let candidates = newImages.filter { $0.complete && $0.width > 0 && $0.height > 0 }
            let key = candidates.map(\.url).joined(separator: "|")
            if key != stableKey || state.generating || candidates.count != newImages.count { stableKey = key; stableSince = Date() }
            if !candidates.isEmpty, candidates.count == newImages.count, !state.generating, Date().timeIntervalSince(stableSince) >= (candidates.count >= job.expectedImageCount ? 5 : 25) {
                try store.updateJob(job.id) { $0.state = .collecting; $0.responseID = candidates.last?.responseID }
                let metadata = (try? await worker.generationMetadata()) ?? []
                let byFile = Dictionary(uniqueKeysWithValues: metadata.map { ($0.fileID, $0) })
                for (index, image) in candidates.enumerated() {
                    let existing = store.jobs.first(where: { $0.id == job.id })?.results ?? []
                    if existing.contains(where: { $0.generationMetadata?.fileID == image.fileID }) { continue }
                    let bytes = try await worker.bytes(for: image)
                    let digest = AssetVault.hash(bytes)
                    if existing.contains(where: { $0.generationMetadata == nil && $0.digest == digest }) { continue }
                    let title = job.expectedImageCount > 1 || candidates.count > 1 ? "\(job.label) · \(index + 1)" : job.label
                    let evidence = byFile[image.fileID] ?? ImageGenerationMetadata(fileID: image.fileID, messageID: image.responseID, genSize: nil, genSizeV2: nil)
                    let asset = try await store.vault.store(bytes, projectID: job.projectID, title: title,
                        isReference: false, jobID: job.id, parentID: job.parentID, generationMetadata: evidence)
                    store.upsert(asset)
                    store.placeResult(asset, job: job, index: index)
                    try store.updateJob(job.id) { $0.results.append(asset) }
                }
                try store.updateJob(job.id) { $0 = JobRules.finishing($0) }
                return
            }
            if !state.generating, candidates.isEmpty, state.assistantCount > (recovery ? (job.baselineAssistantCount ?? 0) : baseline.assistantCount), !state.reply.isEmpty {
                if replySince == nil || lastReply != state.reply { replySince = Date(); lastReply = state.reply }
                if Date().timeIntervalSince(replySince!) > 8 {
                    try store.updateJob(job.id) { $0.state = .responded; $0.responseText = state.reply; $0.error = nil; $0.finishedAt = Date() }
                    store.notice = "이미지 대신 답변이 도착했습니다. 작업 카드에서 이어서 요청할 수 있습니다."
                    return
                }
            } else { replySince = nil }
            let progress = "\(state.assistantCount)|\(state.generating)|\(key)|\(state.reply)"
            if progress != progressKey { progressKey = progress; progressAt = Date() }
            if Date().timeIntervalSince(progressAt) >= 45, let conversation = expectedConversation {
                // Hidden WebKit pages can stop rendering a text stream. Reload only
                // the known conversation; never resubmit the original prompt.
                try await worker.load(conversation)
                progressAt = Date(); stableKey = ""; stableSince = Date(); replySince = nil
            }

        }
        throw WorkerError.uncertain("대기 시간이 길어졌습니다. 새로 생성하지 않고 기존 대화를 확인합니다.")
    }
    func handle(_ error: Error, job id: UUID) {
        let current = store.jobs.first { $0.id == id }
        let mightHaveSubmitted = (current?.conversationID != nil && current?.continuationOf == nil) || [.submitting, .generating, .collecting].contains(current?.state ?? .queued)
        var state: JobState = mightHaveSubmitted ? .needsReview : .failed
        if case WorkerError.generationFailed = error { state = .failed }
        if case WorkerError.login = error { state = mightHaveSubmitted ? .needsReview : .needsLogin; session.status = .disconnected }
        if case WorkerError.limited = error {
            store.journal.paused = true; store.journal.pauseReason = error.localizedDescription
        }
        if case WorkerError.login = error {
            store.journal.paused = true; store.journal.pauseReason = error.localizedDescription
        }
        store.notice = "\(current?.label ?? "작업"): \(state == .needsReview ? "완료 여부 확인 필요" : "생성 실패") — \(error.localizedDescription)"
        do { try store.updateJob(id) { $0.state = state; $0.error = error.localizedDescription } }
        catch { store.report(error) }
    }
    func retryBeforeSubmission(_ job: Job) {
        guard [.needsLogin, .failed].contains(job.state), (job.conversationID == nil || job.continuationOf != nil) else { return }
        do { try store.updateJob(job.id) { $0.state = .queued; $0.error = nil; if $0.apiOptions != nil { $0.submittedAt = nil; $0.apiRequestID = nil } } }
        catch { store.report(error) }
    }
}
