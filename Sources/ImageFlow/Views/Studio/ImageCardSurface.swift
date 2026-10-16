import SwiftUI
import FlowCore

/// One floating control surface per image; the original remains the content layer.
struct ImageCardSurface: View {
    let asset: Asset
    let store: WorkspaceStore
    let selected: Bool
    var preview: (() -> Void)?
    var edit: (() -> Void)?
    var attach: (() -> Void)?
    var rename: (() -> Void)?
    @State private var renaming = false
    @State private var name = ""
    var body: some View {
        GeometryReader { geometry in
            AssetPreview(url: store.vault.original(asset), fit: false)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(StudioPalette.field)
                .overlay(alignment: .bottom) {
                    HStack(spacing: 0) {
                        Button(action: beginRename) {
                            HStack(spacing: 6) {
                                if asset.isReference { Image(systemName: "paperclip").accessibilityHidden(true) }
                                Text(asset.title).font(StudioTypography.item).lineLimit(1)
                                Spacer(minLength: 0)
                            }.padding(.leading, 12).frame(maxWidth: .infinity).frame(height: 36).contentShape(Rectangle())
                        }.help("파일 이름 변경").accessibilityLabel("파일 이름 변경: \(asset.title)")
                        Button { store.toggleFavorite(asset) } label: {
                            Image(systemName: asset.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(asset.isFavorite ? Color.accentColor : .primary)
                                .frame(width: 32, height: 36).contentShape(Rectangle())
                        }.help("즐겨찾기 · F").accessibilityLabel(asset.isFavorite ? "즐겨찾기 해제" : "즐겨찾기")
                        Menu { imageActions } label: {
                            Image(systemName: "ellipsis").frame(width: 32, height: 36).contentShape(Rectangle())
                        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            .help("이미지 설정").accessibilityLabel("이미지 설정")
                    }.font(.system(size: 16, weight: .medium)).symbolRenderingMode(.monochrome)
                        .buttonStyle(.plain).padding(.trailing, 4)
                        .studioGlass(cornerRadius: 12).padding(StudioGeometry.inset)
                }
                .studioContainer()
                .overlay {
                    RoundedRectangle(cornerRadius: StudioGeometry.contentRadius, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 0.5)
                        .allowsHitTesting(false)
                }
        }
        .alert("파일 이름 변경", isPresented: $renaming) {
            TextField("이름", text: $name)
            Button("저장") { store.renameImage(asset, to: name) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("취소", role: .cancel) { }
        }
    }
    @ViewBuilder private var imageActions: some View {
        if let preview { Button(action: preview) { Label("크게 보기", systemImage: "arrow.up.left.and.arrow.down.right") } }
        if let attach { Button(action: attach) { Label("참조에 추가", systemImage: "paperclip") } }
        if let edit { Button(action: edit) { Label("이 이미지 수정…", systemImage: "square.and.pencil") } }
        Button(action: beginRename) { Label("이름 변경…", systemImage: "pencil") }
        Divider()
        Button { store.copyImage(asset) } label: { Label("이미지 복사", systemImage: "doc.on.doc") }
        Button { store.export([asset]) } label: { Label("내보내기…", systemImage: "square.and.arrow.up") }
        Button { NSWorkspace.shared.activateFileViewerSelecting([store.vault.original(asset)]) } label: { Label("Finder에서 보기", systemImage: "folder") }
        Divider()
        Button { store.hideAssets([asset.id]) } label: { Label("보관함에서 숨기기", systemImage: "eye.slash") }
    }
    private func beginRename() {
        if let rename { rename() } else { name = asset.title; renaming = true }
    }
}
