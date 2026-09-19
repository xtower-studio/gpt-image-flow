import SwiftUI
import FlowCore

struct InspectorView: View {
    let asset: Asset?
    var edit: (Asset) -> Void
    var reuse: (Job) -> Void
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        ScrollView {
            if let asset {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        AssetThumbnail(url: store.vault.thumbnail(asset)).frame(height: 210).frame(maxWidth: .infinity)
                            .background(StudioPalette.stage, in: RoundedRectangle(cornerRadius: 8))
                        Text(asset.title).font(.system(size: 15, weight: .semibold))
                        HStack {
                            Text("\(asset.width) × \(asset.height)")
                            Spacer()
                            Text(URL(fileURLWithPath: asset.filename).pathExtension.uppercased())
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Button { edit(asset) } label: { Label("이 시안에서 이어 만들기", systemImage: "arrow.triangle.branch") }.buttonStyle(.borderedProminent).controlSize(.large)
                    if let job = store.jobs.first(where: { $0.id == asset.jobID }) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionCaption(title: "사용한 프롬프트")
                            Text(job.prompt).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                            Button { reuse(job) } label: { Label("생성 설정 다시 사용", systemImage: "arrow.counterclockwise") }.font(.system(size: 11)).buttonStyle(.link)
                        }
                        if !job.referenceIDs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionCaption(title: "참조 이미지", trailing: "\(job.referenceIDs.count)")
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66))]) {
                                    ForEach(job.referenceIDs.compactMap { store.asset($0) }) { reference in
                                        AssetThumbnail(url: store.vault.thumbnail(reference)).frame(height: 66).background(StudioPalette.stage, in: RoundedRectangle(cornerRadius: 5)).help(reference.title)
                                    }
                                }
                            }
                        }
                        VStack(spacing: 10) {
                            detail("모델", job.requestedModel.label)
                            detail("생성일", asset.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let url = job.conversationURL { Link(destination: url) { Label("ChatGPT 대화 열기", systemImage: "arrow.up.right") }.font(.system(size: 11)) }
                    }
                    if let parentID = asset.parentID, let parent = store.asset(parentID) {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionCaption(title: "수정 원본")
                            HStack(spacing: 10) { AssetThumbnail(url: store.vault.thumbnail(parent)).frame(width: 44, height: 44); Text(parent.title).font(.system(size: 11)) }
                        }
                    }
                    Divider()
                    HStack {
                        Button { store.toggleFavorite(asset) } label: { Label("후보", systemImage: store.asset(asset.id)?.isFavorite == true ? "star.fill" : "star") }
                        Spacer()
                        StudioIconButton(symbol: "square.and.arrow.up", label: "내보내기") { store.export([asset]) }
                        StudioIconButton(symbol: "folder", label: "Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([store.vault.original(asset)]) }
                    }.buttonStyle(.borderless).font(.system(size: 11))
                }.padding(20)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "cursorarrow.click").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(.tertiary)
                    Text("시안을 선택해 주세요").font(.system(size: 13, weight: .medium))
                    Text("프롬프트와 참조 이미지,\n생성 설정을 여기서 볼 수 있어요.").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                }.frame(maxWidth: .infinity).padding(.top, 100)
            }
        }
    }
    private func detail(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.system(size: 11))
    }
}
