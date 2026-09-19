import SwiftUI

struct SettingsView: View {
    @Environment(WebSession.self) private var session
    @Environment(WorkspaceStore.self) private var store
    @Environment(GenerationEngine.self) private var engine
    var body: some View {
        Form {
            Section("ChatGPT") { LabeledContent("연결 상태", value: session.status.rawValue); Button("계정 연결 창 열기", action: session.connect) }
            Section("생성") {
                Toggle("절전 모드", isOn: Binding(get: { engine.eco }, set: { engine.eco = $0 }))
                Text("절전 모드에서는 한 번에 하나씩 생성합니다. 기본 모드는 최대 3개를 실행합니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section("내 작업") {
                Button("숨긴 이미지 모두 복원", action: store.restoreAllHidden).disabled((store.library.hiddenAssetIDs ?? []).isEmpty)
                Button("저장 폴더 열기") { NSWorkspace.shared.open(store.root) }
                Text("요청과 참조는 생성할 때 ChatGPT로 전송됩니다. 원본과 작업 이력은 이 Mac에 저장됩니다.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 480, height: 360)
    }
}
