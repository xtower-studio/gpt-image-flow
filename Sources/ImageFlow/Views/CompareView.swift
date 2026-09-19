import SwiftUI
import FlowCore

struct CompareView: View {
    let assets: [Asset]
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var zoom = 1.0
    @State private var actualSize = false
    @State private var showPrompts = false
    private var columns: Int { assets.count == 1 ? 1 : 2 }
    private var rows: Int { (assets.count + columns - 1) / columns }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(assets.count == 1 ? assets[0].title : "\(assets.count)개 이미지 비교").font(.headline).lineLimit(1)
                Spacer()
                Button { actualSize = false; zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass") }.disabled(!actualSize && zoom == 1).help("축소")
                Menu(actualSize ? "100%" : zoom == 1 ? "맞춤" : "맞춤 × \(zoom.formatted())") {
                    Button("화면에 맞춤") { actualSize = false; zoom = 1 }
                    Button("실제 크기 · 100%") { actualSize = true }
                }.frame(width: 110)
                Button { actualSize = false; zoom = min(4, zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass") }.disabled(zoom == 4 && !actualSize).help("확대")
                Divider().frame(height: 18)
                Toggle(isOn: $showPrompts) { Image(systemName: "text.alignleft") }.toggleStyle(.button).help("프롬프트 표시")
                Button("완료") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }.buttonStyle(.borderless).padding(16)
            Divider()
            GeometryReader { geometry in
                let gap: CGFloat = 16
                let width = (geometry.size.width - 32 - gap * CGFloat(columns - 1)) / CGFloat(columns)
                let height = (geometry.size.height - 32 - gap * CGFloat(rows - 1)) / CGFloat(rows)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: gap), count: columns), spacing: gap) {
                    ForEach(assets) { asset in
                        VStack(spacing: 10) {
                            GeometryReader { canvas in
                                let ratio = min(canvas.size.width / CGFloat(max(1, asset.width)), canvas.size.height / CGFloat(max(1, asset.height)))
                                let scale = actualSize ? 1 / displayScale : ratio * zoom
                                ScrollView([.horizontal, .vertical]) {
                                    AssetThumbnail(url: store.vault.original(asset))
                                        .frame(width: CGFloat(asset.width) * scale, height: CGFloat(asset.height) * scale)
                                        .frame(minWidth: canvas.size.width, minHeight: canvas.size.height)
                                }
                            }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6)).clipShape(RoundedRectangle(cornerRadius: 6))
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(asset.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text("\(asset.width) × \(asset.height)").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { store.toggleFavorite(asset) } label: { Image(systemName: store.asset(asset.id)?.isFavorite == true ? "star.fill" : "star") }.help("후보 표시")
                                Button { store.export([asset]) } label: { Image(systemName: "square.and.arrow.up") }.help("내보내기")
                            }.buttonStyle(.borderless)
                            if showPrompts, let job = store.jobs.first(where: { $0.id == asset.jobID }) {
                                ScrollView { Text(job.prompt).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: rows == 1 ? 76 : 46)
                            }
                        }.frame(width: width, height: height)
                    }
                }.padding(16)
            }.background(StudioPalette.stage)
        }.frame(minWidth: 820, idealWidth: 1040, minHeight: 600, idealHeight: 760).background(.background)
    }
}
