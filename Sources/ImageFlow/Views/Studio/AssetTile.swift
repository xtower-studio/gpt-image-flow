import SwiftUI
import FlowCore

struct AssetTile: View {
    let asset: Asset
    let selected: Bool
    var preview: (() -> Void)?
    var edit: (() -> Void)?
    var attach: (() -> Void)?
    var compact = false
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        ImageCardSurface(asset: asset, store: store, selected: selected, preview: preview, edit: edit, attach: attach)
            .aspectRatio(1, contentMode: .fit)
            .onDrag { NSItemProvider(object: store.vault.original(asset) as NSURL) }
            .accessibilityElement(children: .contain).accessibilityLabel(asset.title)
    }
}
