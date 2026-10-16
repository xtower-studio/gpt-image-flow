import Foundation
import FlowCore

extension WorkspaceStore {
    func renameImage(_ original: Asset, to text: String) {
        let name = AssetPaths.component(text)
        guard name != original.title, !changingStorage, !restoringAssets else { return }
        Task {
            do {
                let updated = try await vault.copyRenamed(original, title: name, folder: project(original.projectID)?.storageFolder ?? original.projectID.uuidString)
                upsert(updated)
                for i in journal.jobs.indices {
                    if let j = journal.jobs[i].results.firstIndex(where: { $0.id == updated.id }) { journal.jobs[i].results[j] = updated }
                }
                try persist()
                try await vault.updateReceipt(updated)
                try await vault.removeSupersededFile(original, replacement: updated)
            } catch { report(error) }
        }
    }
}
