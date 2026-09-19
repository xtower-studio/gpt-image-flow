import SwiftUI
import FlowCore

@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()
    let cache = NSCache<NSString, NSImage>()
    init() { cache.totalCostLimit = 64 * 1024 * 1024; cache.countLimit = 180 }
    func image(_ url: URL) async -> NSImage? {
        if let image = cache.object(forKey: url.path as NSString) { return image }
        let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        guard !Task.isCancelled, let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url.path as NSString, cost: Int(image.size.width * image.size.height) * 4)
        return image
    }
}
struct AssetThumbnail: View {
    let url: URL
    var fit = true
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill) }
            else { Rectangle().fill(.quaternary.opacity(0.35)).overlay { Image(systemName: "photo").foregroundStyle(.tertiary) } }
        }.task(id: url) { image = await ThumbnailCache.shared.image(url) }
    }
}
