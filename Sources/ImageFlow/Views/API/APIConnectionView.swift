import SwiftUI

struct APIConnectionView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var organization = ""
    @State private var project = ""
    @State private var acceptsBilling = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("OpenAI API 연결", systemImage: "slider.horizontal.3").font(StudioTypography.title)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("API 연결 닫기")
            }
            APIBillingNotice()
            Text("ChatGPT 구독과 API 사용료는 별도입니다.").font(StudioTypography.supporting).foregroundStyle(.secondary)
            if store.apiConnection.ready {
                Label("API 키가 이 Mac에 저장되어 있습니다", systemImage: "checkmark.shield").foregroundStyle(.green)
                Text("키는 프로젝트·내보내기 파일에 포함되지 않습니다. 새 키를 연결하면 기존 키를 교체합니다.").font(StudioTypography.supporting).foregroundStyle(.secondary)
            }
            if store.apiConnection.savedKeyNeedsPermission {
                Button("저장한 키 사용…") { Task { await store.apiConnection.restoreSavedConnection(interactive: true) } }
                    .accessibilityIdentifier("api-restore-key")
                    .disabled(store.apiConnection.checking)
            }
            VStack(alignment: .leading, spacing: 16) {
                step("1", title: "OpenAI 계정과 API 결제 준비", text: "계정을 만들거나 로그인한 뒤 API 결제·사용 한도를 확인하세요.")
                HStack { Link("계정 및 결제 열기 ↗", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!); Link("요금표 ↗", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!); Link("사용량 ↗", destination: URL(string: "https://platform.openai.com/usage")!) }
                step("2", title: "API 키 만들기", text: "프로젝트에서 새 Secret key를 만든 뒤 아래에 붙여 넣으세요. 권한을 제한할 때는 모델 조회와 이미지 생성·수정을 허용하세요. 키는 생성할 때 한 번만 표시됩니다.")
                Link("API 키 발급 페이지 ↗", destination: URL(string: "https://platform.openai.com/api-keys")!)
                step("3", title: "키를 붙여 넣고 연결 확인", text: "API 키와 모델 목록 접근을 확인합니다. 이 단계에서는 이미지를 생성하지 않습니다.")
                SecureField("API 키", text: $key).textFieldStyle(.roundedBorder).accessibilityIdentifier("api-key-input")
                DisclosureGroup("조직·프로젝트 직접 지정 (선택)") {
                    TextField("Organization ID", text: $organization).textFieldStyle(.roundedBorder)
                    TextField("Project ID", text: $project).textFieldStyle(.roundedBorder)
                    Text("대부분의 프로젝트 키는 비워 두면 됩니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                }
                Toggle("OpenAI가 API 사용료를 직접 청구함을 확인했습니다", isOn: $acceptsBilling).font(StudioTypography.supporting)
            }.font(StudioTypography.supporting)
            if let message = store.apiConnection.message { Text(message).font(StudioTypography.supporting).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("api-connection-message") }
            HStack {
                if store.apiConnection.ready { Button("연결 해제", role: .destructive) { Task { await store.apiConnection.disconnect() } }.disabled(store.apiConnection.checking) }
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(store.apiConnection.checking ? "연결 확인 중…" : "연결 확인 및 저장") {
                    Task {
                        await store.apiConnection.connect(key: key, organization: organization, project: project)
                        key = ""
                    }
                }.studioActionButton(prominent: true).disabled(key.isEmpty || !acceptsBilling || store.apiConnection.checking)
            }
        }.padding(24).frame(width: 540).onDisappear { key = "" }
    }
    private func step(_ number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(StudioTypography.control).frame(width: 26, height: 26).background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 5) { Text(title).font(StudioTypography.item); Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
