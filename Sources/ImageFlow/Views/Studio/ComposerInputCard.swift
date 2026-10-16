import SwiftUI
import FlowCore

struct ComposerInputCard: View {
    @Binding var text: String
    let references: [Asset]
    let originalID: UUID?
    let focusRequest: Int
    var imageURL: (Asset) -> URL
    var add: () -> Void
    var remove: (UUID) -> Void
    var importFiles: ([URL]) -> Void
    @State private var focused = false
    @State private var dropTarget = false
    @State private var editorDropTarget = false
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(originalID == nil ? "어떤 이미지를 만들까요?\n피사체, 분위기, 빛과 색을 설명해 주세요." : "바꿀 부분과 유지할 부분을 설명해 주세요.")
                        .font(StudioTypography.body).lineSpacing(StudioTypography.lineSpacing).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.top, 16).allowsHitTesting(false)
                }
                DropTextEditor(text: $text, onFiles: importFiles, onFocusChanged: { focused = $0 }, acceptsFileDrops: true, onFileDragChanged: { editorDropTarget = $0 }, focusRequest: focusRequest)
                    .frame(height: 112).padding(8).accessibilityLabel("이미지 프롬프트")
            }
            Divider().padding(.horizontal, 14)
            referenceStrip
        }.panelSurface(editor: true)
            .contentShape(RoundedRectangle(cornerRadius: StudioGeometry.fieldRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: StudioGeometry.fieldRadius, style: .continuous).strokeBorder(dropTarget || editorDropTarget ? Color.accentColor : focused ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1.5).allowsHitTesting(false) }
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }; importFiles(files); return true
            } isTargeted: { dropTarget = $0 }
    }
    private var referenceStrip: some View {
        VStack(alignment: .leading, spacing: PanelSpacing.related) {
            HStack(spacing: 8) {
                Image(systemName: "paperclip").font(.system(size: 14))
                Text("참조").font(StudioTypography.control).foregroundStyle(.primary)
                if !references.isEmpty { Text("\(references.count)개").font(StudioTypography.metadata).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Button(action: add) { Image(systemName: "plus").font(.system(size: 14, weight: .medium)).frame(width: 32, height: 32).contentShape(Circle()) }
                    .buttonStyle(.borderless).help("참조 이미지 추가 · ⌘O").accessibilityLabel("참조 이미지 추가")
            }.foregroundStyle(.secondary)
            if !references.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(references) { asset in
                            AssetPreview(url: imageURL(asset)).frame(width: 54, height: 54)
                                .background(StudioPalette.stage, in: RoundedRectangle(cornerRadius: 10))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .help(originalID == asset.id ? "수정 원본: \(asset.title)" : asset.title)
                                .overlay(alignment: .topTrailing) {
                                    if originalID != asset.id {
                                        Button { remove(asset.id) } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.65)).font(.system(size: 16)).frame(width: 28, height: 28).contentShape(Rectangle()) }
                                            .buttonStyle(.plain).padding(3).accessibilityLabel("\(asset.title) 참조 제거")
                                    }
                                }
                        }
                    }
                }
            } else {
                Button("이미지를 놓거나 추가하세요", action: add)
                    .font(StudioTypography.supporting).foregroundStyle(.secondary).buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.horizontal, PanelSpacing.card).padding(.top, 10).padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .accessibilityElement(children: .contain).accessibilityLabel("참조 이미지 영역").accessibilityIdentifier("reference-drop-region")
    }
}
