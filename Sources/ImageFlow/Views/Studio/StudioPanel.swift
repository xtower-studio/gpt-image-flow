import SwiftUI
import FlowCore

enum StudioPanelTab: String, CaseIterable { case create = "만들기", details = "정보", reply = "작업" }

struct StudioPanel: View {
    let project: Project
    @Binding var tab: StudioPanelTab
    @Binding var editing: Asset?
    @Binding var editPrompt: String
    let selectedAssets: [Asset]
    @Binding var responseJobID: UUID?
    let focusRequest: Int
    var edit: (Asset) -> Void
    var reuse: (Job) -> Void
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        VStack(spacing: 0) {
            Picker("작업 패널", selection: $tab) { ForEach(StudioPanelTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().padding(16)
            ZStack(alignment: .top) {
                ComposerView(project: project, editing: $editing, editPrompt: $editPrompt, focusRequest: focusRequest)
                    .opacity(tab == .create ? 1 : 0).allowsHitTesting(tab == .create).disabled(tab != .create).accessibilityHidden(tab != .create)
                if tab == .details {
                    if selectedAssets.count > 1 { multipleSelection }
                    else { InspectorView(asset: selectedAssets.first, edit: edit, reuse: reuse) }
                }
                TaskHistoryView(project: project, selectedJobID: $responseJobID)
                    .opacity(tab == .reply ? 1 : 0).allowsHitTesting(tab == .reply).disabled(tab != .reply).accessibilityHidden(tab != .reply)
            }.frame(maxHeight: .infinity)
        }
    }
    private var multipleSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(selectedAssets.count)개 이미지").font(.title3.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))]) {
                    ForEach(selectedAssets) { asset in AssetThumbnail(url: store.vault.thumbnail(asset)).frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 5)) }
                }
                Button("선택한 이미지 내보내기…") { store.export(selectedAssets) }.frame(maxWidth: .infinity)
                Button("모두 참조에 추가") { for asset in selectedAssets { store.attach(asset, to: project.id) }; tab = .create }
                Text("한 장을 선택하면 프롬프트와 생성 설정을 볼 수 있습니다.").font(.callout).foregroundStyle(.secondary)
            }.padding(20)
        }
    }
}
