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
    @State private var hovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 11) {
            GeometryReader { geometry in
                AssetThumbnail(url: store.vault.thumbnail(asset))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.primary.opacity(0.025))
            }.aspectRatio(compact ? 1 : 0.92, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14))
                .overlay { RoundedRectangle(cornerRadius: compact ? 10 : 14).strokeBorder(selected ? Color.accentColor : StudioPalette.line, lineWidth: selected ? 2 : 0.5) }
                .overlay(alignment: .topLeading) {
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Color.accentColor, in: Circle()).padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if asset.isFavorite {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.primary)
                            .frame(width: 24, height: 24).background(.regularMaterial, in: Circle()).padding(10)
                    }
                }
                .onDrag { NSItemProvider(object: store.vault.original(asset) as NSURL) }
            HStack(alignment: .firstTextBaseline) {
                Text(asset.title).font(StudioTypography.item).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(asset.width) × \(asset.height)").font(StudioTypography.metadata).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                StudioIconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "크게 보기 · Space", action: { preview?() })
                StudioIconButton(symbol: "paperclip", label: "참조에 추가", action: { attach?() })
                StudioIconButton(symbol: "slider.horizontal.3", label: "이 시안 수정", action: { edit?() })
                Spacer(minLength: 0)
                StudioIconButton(symbol: asset.isFavorite ? "star.fill" : "star", label: "후보 표시", active: asset.isFavorite) { store.toggleFavorite(asset) }
                Menu {
                    Button("이미지 복사") { store.copyImage(asset) }
                    Button("내보내기") { store.export([asset]) }
                    Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([store.vault.original(asset)]) }
                    Divider()
                    Button("보관함에서 숨기기") { store.hideAssets([asset.id]) }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("이미지 작업").accessibilityLabel("이미지 작업")
            }.foregroundStyle(.secondary).opacity(hovered || selected ? 1 : 0.65)
        }.contentShape(Rectangle()).onHover { hovered = $0 }
            .accessibilityElement(children: .contain).accessibilityLabel(asset.title)
    }
}
