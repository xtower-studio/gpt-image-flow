import SwiftUI
import FlowCore

struct CompareView: View {
    let assets: [Asset]
    var navigationAssets: [Asset] = []
    @State private var offset = 0
    private var candidates: [Asset] { navigationAssets.isEmpty ? assets : navigationAssets }
    private var initialIndex: Int { candidates.firstIndex(where: { $0.id == assets.first?.id }) ?? 0 }
    private var index: Int { min(max(0, initialIndex + offset), max(0, candidates.count - 1)) }
    private var displayed: [Asset] { assets.count == 1 && !candidates.isEmpty ? [candidates[index]] : assets }
    private func move(_ delta: Int) {
        guard assets.count == 1, candidates.indices.contains(index + delta) else { return }
        offset = index + delta - initialIndex; zoom = 1; actualSize = false
    }
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var zoom = 1.0
    @State private var actualSize = false
    @State private var showPrompts = false
    private var columns: Int { assets.count == 1 ? 1 : 2 }
    private var rows: Int { (assets.count + columns - 1) / columns }
    var body: some View {
        StudioGlassGroup {
            VStack(spacing: 0) {
                header
                GeometryReader { geometry in
                    let gap: CGFloat = 16
                    let width = (geometry.size.width - 32 - gap * CGFloat(columns - 1)) / CGFloat(columns)
                    let height = (geometry.size.height - 32 - gap * CGFloat(rows - 1)) / CGFloat(rows)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: gap), count: columns), spacing: gap) {
                        ForEach(displayed) { asset in
                            VStack(spacing: 12) {
                                GeometryReader { canvas in
                                    let ratio = min(canvas.size.width / CGFloat(max(1, asset.width)), canvas.size.height / CGFloat(max(1, asset.height)))
                                    let scale = actualSize ? 1 / displayScale : ratio * zoom
                                    ScrollView([.horizontal, .vertical]) {
                                        AssetPreview(url: store.vault.original(asset))
                                            .frame(width: CGFloat(asset.width) * scale, height: CGFloat(asset.height) * scale)
                                            .frame(minWidth: canvas.size.width, minHeight: canvas.size.height)
                                    }
                                }.studioContainer()
                                if showPrompts, let job = store.jobs.first(where: { $0.id == asset.jobID }) {
                                    ScrollView { Text(job.inputPrompt ?? job.prompt).font(StudioTypography.body).lineSpacing(StudioTypography.lineSpacing).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                        .frame(height: rows == 1 ? 76 : 46)
                                }
                            }.frame(width: width, height: height)
                                .overlay(alignment: .bottomTrailing) { imageActions(asset).padding(12).padding(.bottom, showPrompts ? (rows == 1 ? 88 : 58) : 0) }
                        }
                    }.padding(16)
                }.background(StudioPalette.stage)
            }
        }
        .background { PreviewKeyHandler(previous: { move(-1) }, next: { move(1) }, close: { dismiss() }).frame(width: 0, height: 0) }
        .frame(minWidth: 820, idealWidth: 1040, minHeight: 600, idealHeight: 760)
    }
    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(assets.count == 1 ? displayed[0].title : "\(assets.count)개 이미지 비교").font(StudioTypography.title).lineLimit(1)
                if assets.count == 1 { Text("\(index + 1) / \(candidates.count)").font(StudioTypography.metadata).monospacedDigit().foregroundStyle(.secondary) }
            }.frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
            if assets.count == 1 {
                HStack(spacing: 0) {
                    StudioIconButton(symbol: "chevron.left", label: "이전 이미지 · ←") { move(-1) }.disabled(index == 0)
                    StudioIconButton(symbol: "chevron.right", label: "다음 이미지 · →") { move(1) }.disabled(index + 1 >= candidates.count)
                }.padding(4).studioGlass()
            }
            HStack(spacing: 0) {
                StudioIconButton(symbol: "minus.magnifyingglass", label: "축소") { actualSize = false; zoom = max(1, zoom - 0.5) }.disabled(!actualSize && zoom == 1)
                Menu(actualSize ? "100%" : zoom == 1 ? "맞춤" : "맞춤 × \(zoom.formatted())") {
                    Button("화면에 맞춤") { actualSize = false; zoom = 1 }
                    Button("실제 크기 · 100%") { actualSize = true }
                }.menuStyle(.borderlessButton).frame(width: 88)
                StudioIconButton(symbol: "plus.magnifyingglass", label: "확대") { actualSize = false; zoom = min(4, zoom + 0.5) }.disabled(zoom == 4 && !actualSize)
            }.padding(4).studioGlass()
            StudioIconButton(symbol: "text.alignleft", label: "프롬프트 표시", active: showPrompts) { showPrompts.toggle() }
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                .studioActionButton().buttonBorderShape(.circle).controlSize(.large)
                .keyboardShortcut(.escape, modifiers: []).help("닫기 · Space / Esc").accessibilityLabel("미리보기 닫기")
        }.padding(.horizontal, 20).padding(.vertical, 14)
    }
    private func imageActions(_ asset: Asset) -> some View {
        HStack(spacing: 4) {
            if assets.count > 1 { Text(asset.title).font(StudioTypography.item).lineLimit(1).padding(.leading, 8) }
            StudioIconButton(symbol: store.asset(asset.id)?.isFavorite == true ? "star.fill" : "star", label: "즐겨찾기", active: store.asset(asset.id)?.isFavorite == true) { store.toggleFavorite(asset) }
            StudioIconButton(symbol: "square.and.arrow.up", label: "내보내기") { store.export([asset]) }
        }.padding(4).studioGlass()
    }
}
