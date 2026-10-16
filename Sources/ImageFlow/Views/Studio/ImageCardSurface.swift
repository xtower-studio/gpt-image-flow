import SwiftUI
import FlowCore

/// Shared card chrome. Original pixels stay unobscured except for readable edge overlays.
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
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.48), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 64).allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    if asset.isReference {
                        Image(systemName: "paperclip").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 32, height: 32).padding(6).help("참조 이미지").allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        Button { store.toggleFavorite(asset) } label: {
                            Image(systemName: asset.isFavorite ? "star.fill" : "star").frame(width: 32, height: 32).contentShape(Rectangle())
                        }.help("즐겨찾기 · F").accessibilityLabel(asset.isFavorite ? "즐겨찾기 해제" : "즐겨찾기")
                        Menu {
                            if let preview { Button("크게 보기", action: preview) }
                            if let attach { Button("참조에 추가", action: attach) }
                            if let edit { Button("이 이미지 수정…", action: edit) }
                            Button("이름 변경…") { beginRename() }
                            Divider()
                            Button("이미지 복사") { store.copyImage(asset) }
                            Button("내보내기…") { store.export([asset]) }
                            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([store.vault.original(asset)]) }
                            Divider()
                            Button("보관함에서 숨기기") { store.hideAssets([asset.id]) }
                        } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 32, height: 32).contentShape(Rectangle()) }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("이미지 설정").accessibilityLabel("이미지 설정")
                    }.buttonStyle(.plain).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 9)).padding(6)
                }
                .overlay(alignment: .bottom) {
                    Button { beginRename() } label: {
                        HStack { Text(asset.title).font(StudioTypography.item).lineLimit(1); Spacer(minLength: 0) }
                            .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 36)
                            .background(LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).help("파일 이름 변경").accessibilityLabel("파일 이름 변경: \(asset.title)")
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 0.5).allowsHitTesting(false) }
        }
        .alert("파일 이름 변경", isPresented: $renaming) {
            TextField("이름", text: $name)
            Button("저장") { store.renameImage(asset, to: name) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("취소", role: .cancel) { }
        }
    }
    private func beginRename() {
        if let rename { rename() }
        else { name = asset.title; renaming = true }
    }

}
