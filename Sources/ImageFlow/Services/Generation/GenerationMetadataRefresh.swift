import Foundation
import FlowCore

extension GenerationEngine {
    /// An explicit inspection action for historical files. Never derive identity from their request.
    func refreshMetadata(for asset: Asset) async throws {
        guard session.status == .ready else { throw FlowError.message("ChatGPT에 연결한 뒤 다시 확인해 주세요.") }
        guard let slot = (0..<(eco ? 1 : 3)).first(where: { !slots.values.contains($0) }) else {
            throw FlowError.message("진행 중인 요청이 끝나면 모델 정보를 확인할 수 있습니다.")
        }
        guard let job = store.jobs.first(where: { $0.id == asset.jobID }), let conversation = job.conversationID else {
            throw FlowError.message("원래 대화가 없어 실제 모델을 확인할 수 없습니다.")
        }
        let reservation = UUID()
        slots[reservation] = slot
        defer { slots.removeValue(forKey: reservation) }
        let worker = try WebWorker(slot: slot, session: session)
        defer { worker.close() }
        try await worker.load(conversation)
        let records = try await worker.generationMetadata()
        var matched = asset.generationMetadata.flatMap { prior in records.first { $0.fileID == prior.fileID } }
        if matched == nil {
            // Legacy records lack file IDs. Require exact original-byte equality, never image dimensions/order.
            let deadline = Date().addingTimeInterval(15)
            var checked = Set<String>()
            repeat {
                // Composer readiness does not mean old image cards have loaded.
                let snapshot = try await worker.snapshot()
                for image in snapshot.images where image.complete && image.width > 0 && !checked.contains(image.fileID) {
                    guard let record = records.first(where: { $0.fileID == image.fileID }) else { continue }
                    let bytes = try await worker.bytes(for: image)
                    checked.insert(image.fileID)
                    if AssetVault.hash(bytes) == asset.digest { matched = record; break }
                }
                if matched != nil { break }
                try await worker.wait(0.5)
            } while Date() < deadline

        }
        guard let matched else { throw FlowError.message("이 파일과 일치하는 모델 정보를 찾지 못했습니다. 확인되지 않음으로 유지합니다.") }
        var updated = store.asset(asset.id) ?? asset
        updated.generationMetadata = matched
        try await store.vault.updateReceipt(updated)
        store.upsert(updated)
        try store.updateJob(job.id) { job in
            if let index = job.results.firstIndex(where: { $0.id == updated.id }) { job.results[index].generationMetadata = matched }
        }
        store.notice = matched.model == nil ? "메타데이터가 없거나 불일치하여 모델을 확정하지 않았습니다." : "이미지의 실제 모델 정보를 확인했습니다."
    }
}
