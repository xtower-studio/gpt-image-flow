import SwiftUI

struct SettingsView: View {
    @Environment(WebSession.self) private var session
    @Environment(WorkspaceStore.self) private var store
    @Environment(GenerationEngine.self) private var engine
    @State private var showAPIConnection = false
    var body: some View {
        Form {
            Section("ChatGPT") { LabeledContent("연결 상태", value: session.status.rawValue); Button("계정 연결 창 열기", action: session.connect) }
            Section("고급 · OpenAI API") {
                LabeledContent("연결", value: store.apiConnection.ready ? "키 저장됨" : "연결 안 됨")
                Button("API 연결 및 키 관리…") { showAPIConnection = true }
                APIBillingNotice()
            }
            Section("생성") {
                Toggle("절전 모드", isOn: Binding(get: { engine.eco }, set: { engine.eco = $0 }))
                Text("절전 모드에서는 한 번에 하나씩 생성합니다. 기본 모드는 최대 3개를 실행합니다.").font(StudioTypography.supporting).foregroundStyle(.secondary)
            }
            Section("저장 공간") {
                Text(store.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(StudioTypography.supporting).textSelection(.enabled)
                HStack {
                    Button("저장 폴더 변경…") { store.selectStorageFolder(openExisting: false) }
                    Button("기존 보관함 열기…") { store.selectStorageFolder(openExisting: true) }
                }.disabled(!store.canChangeStorage)
                if store.changingStorage { ProgressView("원본과 작업 기록 복사 중…") }
                Text("원본·첨부·생성 정보와 프로젝트를 함께 보관합니다. 권장 위치: ~/Pictures/Image Flow").font(StudioTypography.supporting).foregroundStyle(.secondary)
            }
            Section("내 작업") {
                Button("숨긴 이미지 모두 복원", action: store.restoreAllHidden).disabled((store.library.hiddenAssetIDs ?? []).isEmpty)
                Button("시작 안내 다시 보기") { store.showOnboarding = true }
                Button("저장 폴더 열기") { NSWorkspace.shared.open(store.root) }
                Text("요청과 참조는 생성할 때 선택한 ChatGPT 또는 OpenAI API로 전송됩니다. 원본과 작업 이력은 이 Mac에 저장됩니다.").font(StudioTypography.supporting).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 480, height: 710).sheet(isPresented: $showAPIConnection) { APIConnectionView() }
    }
}
