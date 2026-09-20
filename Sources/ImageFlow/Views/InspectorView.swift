import SwiftUI
import FlowCore

struct InspectorView: View {
    let asset: Asset?
    var edit: (Asset) -> Void
    var reuse: (Job) -> Void
    @Environment(WorkspaceStore.self) private var store
    @Environment(GenerationEngine.self) private var engine
    @State private var checkingMetadata = false
    var body: some View {
        ScrollView {
            if let asset {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        AssetThumbnail(url: store.vault.thumbnail(asset)).frame(height: 180).frame(maxWidth: .infinity)
                            .background(StudioPalette.stage, in: RoundedRectangle(cornerRadius: 18)).clipShape(RoundedRectangle(cornerRadius: 18))
                        Text(asset.title).font(StudioTypography.title).textSelection(.enabled)
                        HStack {
                            Text("\(asset.width) × \(asset.height)")
                            Spacer()
                            Text(URL(fileURLWithPath: asset.filename).pathExtension.uppercased())
                        }.font(StudioTypography.metadata).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Button { edit(asset) } label: { Label("이 이미지에서 이어 만들기", systemImage: "arrow.triangle.branch").font(StudioTypography.action).frame(maxWidth: .infinity).padding(.vertical, 3) }
                        .studioActionButton(prominent: true).buttonBorderShape(.capsule).controlSize(.large)
                    if let job = store.jobs.first(where: { $0.id == asset.jobID }) {
                        VStack(alignment: .leading, spacing: 10) {
                            PanelSectionHeading(title: "프롬프트")
                            VStack(alignment: .leading, spacing: 14) {
                                Text(job.inputPrompt ?? job.prompt).font(StudioTypography.body).lineSpacing(StudioTypography.lineSpacing).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                Button { reuse(job) } label: { Label("이 설정 다시 사용", systemImage: "arrow.counterclockwise") }.font(StudioTypography.control).buttonStyle(.borderless)
                            }.padding(14).panelSurface()
                        }
                        if !job.referenceIDs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                PanelSectionHeading(title: "참조 이미지", note: "\(job.referenceIDs.count)개")
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 62))], spacing: 8) {
                                    ForEach(job.referenceIDs.compactMap { store.asset($0) }) { reference in
                                        AssetThumbnail(url: store.vault.thumbnail(reference)).frame(height: 62).background(StudioPalette.stage, in: RoundedRectangle(cornerRadius: 12)).help(reference.title)
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            PanelSectionHeading(title: "생성 정보")
                            VStack(spacing: 12) {
                                detail("실제 모델", asset.actualModelLabel)
                                detail("생성 방식", job.requestModeLabel)
                                detail("생성일", asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                                if let size = asset.generationMetadata?.genSize {
                                    DisclosureGroup("식별 근거") { Text("gen_size: \(size)").font(StudioTypography.code).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 8) }.font(StudioTypography.metadata).foregroundStyle(.secondary)
                                }
                                if asset.generationMetadata?.model == nil {
                                    Button(checkingMetadata ? "모델 정보 확인 중…" : "모델 정보 확인") {
                                        checkingMetadata = true
                                        Task { @MainActor in
                                            defer { checkingMetadata = false }
                                            do { try await engine.refreshMetadata(for: asset) } catch { store.report(error) }
                                        }
                                    }.buttonStyle(.borderless).disabled(checkingMetadata).font(StudioTypography.supporting)
                                }
                            }.padding(14).panelSurface()
                        }
                        if let url = job.conversationURL { Link(destination: url) { Label("ChatGPT 대화 열기", systemImage: "arrow.up.right") }.font(StudioTypography.control) }
                    }
                    if let parentID = asset.parentID, let parent = store.asset(parentID) {
                        VStack(alignment: .leading, spacing: 10) {
                            PanelSectionHeading(title: "수정 원본")
                            HStack(spacing: 10) { AssetThumbnail(url: store.vault.thumbnail(parent)).frame(width: 44, height: 44); Text(parent.title).font(StudioTypography.supporting) }
                        }
                    }
                    HStack(spacing: 18) {
                        Button { store.toggleFavorite(asset) } label: { Label("후보", systemImage: store.asset(asset.id)?.isFavorite == true ? "star.fill" : "star") }
                        Spacer(minLength: 0)
                        Button { store.export([asset]) } label: { Image(systemName: "square.and.arrow.up") }.help("내보내기").accessibilityLabel("내보내기")
                        Button { NSWorkspace.shared.activateFileViewerSelecting([store.vault.original(asset)]) } label: { Image(systemName: "folder") }.help("Finder에서 보기").accessibilityLabel("Finder에서 보기")
                    }.buttonStyle(.borderless).font(StudioTypography.supporting).padding(14).panelSurface()
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
            } else {
                ContentUnavailableView("이미지를 선택하세요", systemImage: "photo", description: Text("프롬프트와 생성 정보를 확인하고\n다음 이미지로 이어갈 수 있습니다."))
                    .padding(.top, 50)
            }
        }.panelScrollEdges()
    }
    private func detail(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(name).foregroundStyle(.secondary); Spacer(minLength: 12); Text(value).multilineTextAlignment(.trailing) }.font(StudioTypography.supporting)
    }
}
