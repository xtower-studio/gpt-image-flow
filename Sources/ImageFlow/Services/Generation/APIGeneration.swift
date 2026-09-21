import Foundation
import FlowCore

extension GenerationEngine {
    func executeAPI(_ job: Job) async throws {
        guard let options = job.apiOptions else { throw FlowError.message("API 설정을 찾을 수 없습니다.") }
        try store.updateJob(job.id) { $0.state = .preparing; $0.startedAt = Date(); $0.error = nil }
        let credentials = try store.apiConnection.credentials()
        let references = try job.referenceIDs.map { id -> URL in
            guard let asset = store.asset(id) else { throw FlowError.message("참조 이미지를 찾을 수 없습니다.") }
            return store.vault.original(asset)
        }
        let mask: URL?
        if let id = options.maskAssetID {
            guard let asset = store.asset(id) else { throw FlowError.message("마스크 파일을 찾을 수 없습니다.") }
            mask = store.vault.original(asset)
        } else { mask = nil }
        try options.validate(prompt: job.prompt, referenceCount: references.count)
        // Snapshot is persisted before the billed operation. Never retry automatically.
        let result = try await ImageAPIClient().generate(prompt: job.prompt, options: options, references: references, mask: mask, credentials: credentials, preview: { [weak self] data in
            await self?.showAPIPreview(data, jobID: job.id)
        }, willSend: { [weak self] in
            try await self?.markAPISubmission(job.id)
        }, completedImage: { [weak self] data, index in
            try await self?.saveAPIImage(data, job: job, index: index, model: options.model)
        })
        try store.updateJob(job.id) { $0.state = .collecting; $0.apiRequestID = result.requestID; $0.apiUsageJSON = result.usageJSON }
        for (index, data) in result.images.enumerated() {
            try await saveAPIImage(data, job: job, index: index, model: options.model)
        }
        try store.updateJob(job.id) {
            $0 = JobRules.finishing($0)
            if $0.state == .needsReview { $0.error = "API에서 요청한 \($0.expectedImageCount)장 중 \($0.results.count)장을 받았습니다. 사용량을 확인하세요. 자동으로 재요청하지 않습니다." }
        }
    }
    private func saveAPIImage(_ data: Data, job: Job, index: Int, model: String) async throws {
        guard (store.jobs.first(where: { $0.id == job.id })?.results.count ?? 0) <= index else { return }
        let asset = try await store.vault.store(data, projectID: job.projectID, title: "\(job.label) · \(index + 1)", isReference: false,
            jobID: job.id, parentID: job.parentID, apiModel: model)
        store.upsert(asset); store.placeResult(asset, job: job, index: index)
        try store.updateJob(job.id) { $0.results.append(asset) }
    }
    private func markAPISubmission(_ id: UUID) throws {
        try store.updateJob(id) { $0.state = .generating; $0.submittedAt = Date() }
    }
    private func showAPIPreview(_ data: Data, jobID: UUID) {
        apiPreviews[jobID] = data
        try? store.updateJob(jobID) { $0.state = .generating }
    }
    func handleAPI(_ error: Error, job: Job) {
        let status = (error as? ImageAPIError)?.status
        let sent = store.jobs.first(where: { $0.id == job.id })?.submittedAt != nil
        let uncertain = sent && (status == nil || (status ?? 0) >= 500)
        let message = APIConnection.safeMessage(error) + (uncertain ? "\n요청이 처리됐을 수 있습니다. OpenAI 사용량을 확인하세요. 자동 재전송하지 않았습니다." : "")
        try? store.updateJob(job.id) { $0.state = uncertain ? .needsReview : .failed; $0.error = message; $0.apiRequestID = (error as? ImageAPIError)?.requestID }
        store.notice = "Sunburst API: " + message
    }
}
