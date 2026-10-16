import Foundation

public enum AssetNaming {
    /// Allocate on persistence, before workers start. Cancellation never recycles numbers.
    public static func number(_ jobs: inout [Job]) {
        var maxima: [UUID: Int] = [:]
        for job in jobs { maxima[job.projectID] = max(maxima[job.projectID] ?? 0, job.requestNumber ?? 0) }
        for i in jobs.indices.sorted(by: { jobs[$0].createdAt == jobs[$1].createdAt ? $0 < $1 : jobs[$0].createdAt < jobs[$1].createdAt }) where jobs[i].requestNumber == nil {
            let next = (maxima[jobs[i].projectID] ?? 0) + 1
            jobs[i].requestNumber = next; maxima[jobs[i].projectID] = next
        }
    }
    public static func migrate(library: inout Library, jobs: inout [Job]) {
        number(&jobs)
        for job in jobs {
            let ids = job.results.map(\.id)
            let generated = library.assets.filter { !$0.isReference && $0.jobID == job.id }.sorted {
                let a = ids.firstIndex(of: $0.id) ?? Int.max, b = ids.firstIndex(of: $1.id) ?? Int.max
                return a == b ? $0.createdAt < $1.createdAt : a < b
            }
            for (ordinal, asset) in generated.enumerated() {
                guard let index = library.assets.firstIndex(where: { $0.id == asset.id }), asset.sequenceName == nil else { continue }
                let name = job.imageTitle(ordinal)
                if asset.title == job.label || asset.title.hasPrefix(job.label + " · ") { library.assets[index].title = name }
                library.assets[index].sequenceName = name
            }
        }
    }
}
extension Job {
    public func imageTitle(_ index: Int) -> String { "\(requestNumber ?? 1)-\(index + 1)" }
}
