import Foundation
import FlowCore

extension FlowAppDelegate {
    struct ComposerPreparationProof: Codable, Sendable {
        let slot: Int
        let appliedReasoning: Int?
        let references: Int
        let error: String?
    }

    // Explicit, no-submit compatibility check. Uses only the known QA reference.
    func verifyComposerConcurrency(directory: URL) async throws {
        guard let session, let store, engine?.workers.isEmpty == true else { return }
        let reference = store.library.assets.first { $0.id == UUID(uuidString: "D1A84191-D395-43FD-9D34-7AA9763AE45D") }
        let files = reference.map { [store.vault.original($0)] } ?? []
        let tasks = (0..<3).map { slot in
            Task { @MainActor in
                let attachments = slot == 0 ? files : []
                do {
                    let worker = try WebWorker(slot: slot, session: session)
                    defer { worker.close() }
                    var project = Project(name: "Concurrent composer verification")
                    project.prompt = "A small cobalt blue ceramic teapot on an ivory background, product photograph, no lettering."
                    project.generationMode = slot == 0 ? .automatic : .instant
                    let job = try JobRules.makeBatch(project: project)[0]
                    _ = try await worker.prepare(job: job, files: attachments)
                    return ComposerPreparationProof(slot: slot, appliedReasoning: worker.appliedReasoning, references: attachments.count, error: nil)
                } catch {
                    return ComposerPreparationProof(slot: slot, appliedReasoning: nil, references: attachments.count, error: String(describing: error))
                }
            }
        }
        var proof: [ComposerPreparationProof] = []
        for task in tasks { proof.append(await task.value) }
        try JSONEncoder().encode(proof).write(to: directory.appendingPathComponent("composer-concurrency.json"))
    }
}
