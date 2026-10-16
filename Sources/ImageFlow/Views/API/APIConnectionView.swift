import SwiftUI

struct APIConnectionView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var organization = ""
    @State private var project = ""
    @State private var acceptsBilling = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenAI API 연결").font(.title2.weight(.semibold))
                    Text("고급 생성에 사용할 계정을 연결하세요.").font(StudioTypography.supporting).foregroundStyle(.secondary)
                }
                Spacer()
                StudioIconButton(symbol: "xmark", label: "API 연결 닫기") { dismiss() }
            }.padding(24)
            Form {
                if store.apiConnection.ready {
                    Section {
                        Label("API 키가 이 Mac에 저장되어 있습니다", systemImage: "checkmark.shield").foregroundStyle(.green)
                        Text("새 키를 연결하면 기존 키를 교체합니다. 키는 프로젝트에 포함되지 않습니다.").font(StudioTypography.supporting).foregroundStyle(.secondary)
                    }
                }
                if store.apiConnection.savedKeyNeedsPermission {
                    Section {
                        Button("저장한 키 사용…") { Task { await store.apiConnection.restoreSavedConnection(interactive: true) } }
                            .accessibilityIdentifier("api-restore-key").disabled(store.apiConnection.checking)
                    }
                }
                Section("1. OpenAI 계정 준비") {
                    Text("계정에 로그인한 뒤 API 결제와 사용 한도를 설정하세요.").font(StudioTypography.supporting)
                    Link("계정 및 결제 열기", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                    HStack {
                        Link("요금표", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
                        Spacer()
                        Link("사용량", destination: URL(string: "https://platform.openai.com/usage")!)
                    }
                }
                Section("2. API 키 발급") {
                    Text("새 Secret key를 만든 뒤 아래에 붙여 넣으세요. 키는 발급할 때 한 번만 표시됩니다.").font(StudioTypography.supporting)
                    Link("API 키 발급 페이지 열기", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    SecureField("API 키", text: $key).textFieldStyle(.roundedBorder).accessibilityIdentifier("api-key-input")
                    DisclosureGroup("조직·프로젝트 직접 지정") {
                        TextField("Organization ID", text: $organization).textFieldStyle(.roundedBorder)
                        TextField("Project ID", text: $project).textFieldStyle(.roundedBorder)
                        Text("대부분은 비워 두면 됩니다. 키 권한을 제한할 경우 모델 조회와 이미지 생성·수정을 허용하세요.").font(StudioTypography.supporting).foregroundStyle(.secondary)
                    }
                }
                Section("3. 연결 확인") {
                    Text("키와 모델 접근 권한만 확인합니다. 연결 과정에서 이미지를 생성하지 않습니다.").font(StudioTypography.supporting)
                    Toggle("OpenAI가 API 사용료를 직접 청구함을 확인했습니다", isOn: $acceptsBilling).font(StudioTypography.supporting)
                }
                if let message = store.apiConnection.message {
                    Section { Text(message).font(StudioTypography.supporting).textSelection(.enabled).accessibilityIdentifier("api-connection-message") }
                }
            }.formStyle(.grouped)
            VStack(alignment: .leading, spacing: 16) {
                APIBillingNotice()
                Text("ChatGPT 구독과 API 요금은 별도입니다.").font(StudioTypography.supporting).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                if store.apiConnection.ready {
                    Button("연결 해제", role: .destructive) { Task { await store.apiConnection.disconnect() } }.disabled(store.apiConnection.checking)
                }
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(store.apiConnection.checking ? "연결 확인 중…" : "연결 및 저장") {
                    Task {
                        await store.apiConnection.connect(key: key, organization: organization, project: project)
                        key = ""
                    }
                }.studioActionButton(prominent: true).controlSize(.large)
                    .disabled(key.isEmpty || !acceptsBilling || store.apiConnection.checking)
                }
            }.padding(20)
        }.frame(width: 540, height: 740).onDisappear { key = "" }
    }
}
