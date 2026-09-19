import SwiftUI
import FlowCore

struct WorkspaceSidebar: View {
    @Binding var selectedProject: String
    let currentID: UUID?
    var onSelect: () -> Void
    var rename: (Project) -> Void
    var addProject: () -> Void
    @Environment(WorkspaceStore.self) private var store
    @Environment(WebSession.self) private var session
    @Environment(GenerationEngine.self) private var engine
    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding<UUID?>(get: { currentID }, set: { id in if let id { selectedProject = id.uuidString; onSelect() } })) {
                Section("프로젝트") {
                    ForEach(store.library.projects) { project in
                        HStack(spacing: 9) {
                            projectCover(project)
                            Text(project.name).lineLimit(1)
                            Spacer(minLength: 2)
                            let count = store.library.assets.filter { $0.projectID == project.id && !$0.isReference && !(store.library.hiddenAssetIDs ?? []).contains($0.id) }.count
                            Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(project.id)
                            .help(project.name)
                            .contextMenu { Button("이름 변경…") { rename(project) }; Button("새 프로젝트…", action: addProject) }
                    }
                }
            }.listStyle(.sidebar)
            VStack(spacing: 14) {
                Button(action: addProject) { Label("새 프로젝트", systemImage: "plus").frame(maxWidth: .infinity) }.controlSize(.regular).help("새 프로젝트 · ⌘N")
                Divider()
                HStack(spacing: 8) {
                    Circle().fill(session.status == .ready ? Color.green : Color.orange).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ChatGPT").font(.system(size: 12, weight: .medium))
                        Text(engine.activeCount > 0 ? "\(engine.activeCount)개 생성 중" : session.status == .ready ? "연결됨" : "로그인 필요").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("ChatGPT 연결 창 열기", action: session.connect)
                        SettingsLink { Text("설정…") }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("계정 및 설정")
                }
            }.padding(16)
        }
    }
    @ViewBuilder private func projectCover(_ project: Project) -> some View {
        if let asset = store.library.assets.last(where: { $0.projectID == project.id && !$0.isReference && !(store.library.hiddenAssetIDs ?? []).contains($0.id) }) {
            AssetThumbnail(url: store.vault.thumbnail(asset), fit: false).frame(width: 28, height: 28).clipped().clipShape(RoundedRectangle(cornerRadius: 5)).accessibilityHidden(true)
        } else { Image(systemName: "folder").font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 28, height: 28) }
    }
}
