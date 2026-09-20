import SwiftUI
import FlowCore

struct ComposerInputCard: View {
    @Binding var text: String
    let references: [Asset]
    let originalID: UUID?
    let focusRequest: Int
    var thumbnail: (Asset) -> URL
    var add: () -> Void
    var remove: (UUID) -> Void
    var importFiles: ([URL]) -> Void
    @State private var focused = false
    @State private var dropTarget = false
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(originalID == nil ? "어떤 이미지를 만들까요?\n피사체, 분위기, 빛과 색을 설명해 주세요." : "바꿀 부분과 유지할 부분을 설명해 주세요.")
                        .font(StudioTypography.body).lineSpacing(StudioTypography.lineSpacing).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.top, 16).allowsHitTesting(false)
                }
                DropTextEditor(text: $text, onFiles: importFiles, onFocusChanged: { focused = $0 }, focusRequest: focusRequest)
                    .frame(height: 96).padding(8).accessibilityLabel("이미지 프롬프트")
            }
            Divider().padding(.horizontal, 14)
            referenceStrip
        }.panelSurface(editor: true)
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(focused ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1.5).allowsHitTesting(false) }
    }
    private var referenceStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "paperclip").font(.system(size: 12))
                Text("참조 이미지").font(StudioTypography.control).foregroundStyle(.primary)
                Text(references.isEmpty ? "선택 사항" : "\(references.count)개").font(StudioTypography.metadata).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: add) { Image(systemName: "plus").font(.system(size: 12, weight: .medium)).frame(width: 24, height: 24).contentShape(Circle()) }
                    .buttonStyle(.plain).help("참조 이미지 추가 · ⌘O").accessibilityLabel("참조 이미지 추가")
            }.foregroundStyle(.secondary)
            if !references.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(references) { asset in
                            AssetThumbnail(url: thumbnail(asset)).frame(width: 54, height: 54)
                                .background(StudioPalette.stage, in: RoundedRectangle(cornerRadius: 10))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .help(originalID == asset.id ? "수정 원본: \(asset.title)" : asset.title)
                                .overlay(alignment: .topTrailing) {
                                    if originalID != asset.id {
                                        Button { remove(asset.id) } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.65)).font(.system(size: 15)) }
                                            .buttonStyle(.plain).padding(3).accessibilityLabel("\(asset.title) 참조 제거")
                                    }
                                }
                        }
                    }
                }
            } else {
                Button("이미지를 이 영역에 놓거나 추가하세요", action: add)
                    .font(StudioTypography.supporting).foregroundStyle(.secondary).buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .background(dropTarget ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay { if dropTarget { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 1.5).allowsHitTesting(false) } }
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }; importFiles(files); return true
            } isTargeted: { dropTarget = $0 }
            .accessibilityElement(children: .contain).accessibilityLabel("참조 이미지 영역").accessibilityIdentifier("reference-drop-region")
    }
}
