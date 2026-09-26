import Foundation

/// A request keeps one stable collection position per expected result.
public struct ProjectImageSlot: Identifiable, Equatable, Sendable {
    public let id: String
    public let asset: Asset?
    public let job: Job?
    public let ordinal: Int
    public static func make(assets: [Asset], jobs: [Job]) -> [Self] {
        let jobIDs = Set(jobs.map(\.id)), visible = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var slots = assets.filter { $0.jobID.map { !jobIDs.contains($0) } ?? true }.map {
            Self(id: $0.id.uuidString, asset: $0, job: nil, ordinal: 0)
        }
        for job in jobs {
            let waiting = job.state.isRunning || job.state == .queued || job.showsAttention
            let count = waiting ? max(job.expectedImageCount, job.results.count) : job.results.count
            for index in 0..<count {
                let asset = job.results.indices.contains(index) ? job.results[index] : nil
                if let asset, visible[asset.id] == nil { continue }
                slots.append(Self(id: "\(job.id)-\(index)", asset: asset.flatMap { result in visible[result.id] }, job: job, ordinal: index + 1))
            }
        }
        return slots
    }
}
