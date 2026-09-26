import SwiftUI
import FlowCore

struct OnboardingView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(WebSession.self) private var session
    @State private var step = 0
    @State private var folder = WorkspaceStore.recommendedStorage
    @State private var connection = false
    @State private var error: String?
    private let labels = ["내 작업의 위치", "생성 방식 연결", "첫 워크플로"]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                Label("Image Flow", systemImage: "square.stack.3d.up").font(.title2.weight(.semibold))
                Text("아이디어에서\n다음 시안까지.").font(.system(size: 29, weight: .semibold)).lineSpacing(5)
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(0..<3) { index in
                        HStack(spacing: 10) {
                            Image(systemName: index < step ? "checkmark.circle.fill" : "\(index + 1).circle\(index == step ? ".fill" : "")").font(.title3)
                            Text(labels[index]).font(.system(size: 14, weight: index == step ? .semibold : .regular))
                        }.foregroundStyle(index == step ? Color.accentColor : .secondary)
                    }
                }
                Spacer()
                Text("당신의 이미지와 작업 기록은\n당신의 폴더에 남습니다.").font(StudioTypography.supporting).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(30).frame(width: 265).background(.quaternary.opacity(0.35))
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text("시작하기 · \(step + 1) / 3").font(StudioTypography.metadata).foregroundStyle(.secondary); Spacer()
                    Button { store.showOnboarding = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("나중에 설정에서 다시 열기").disabled(store.changingStorage)
                }
                if step == 0 { storage }
                else if step == 1 { connections }
                else { workflow }
                Spacer(minLength: 8)
                if let error { Text(error).font(StudioTypography.supporting).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    if step > 0 { Button("이전") { step -= 1 } }
                    Spacer()
                    if store.changingStorage { ProgressView().controlSize(.small); Text("원본과 기록을 안전하게 복사하는 중…").font(StudioTypography.metadata) }
                    Button(step == 2 ? "작업 시작하기" : step == 0 ? "이 폴더 사용" : "계속") { advance() }
                        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                        .disabled(store.changingStorage || store.restoringAssets || (step == 0 && !store.canChangeStorage))
                        .accessibilityIdentifier("onboarding-continue")
                }
            }.padding(32).frame(width: 490)
        }.frame(height: 550).interactiveDismissDisabled(store.changingStorage)
        .sheet(isPresented: $connection) { APIConnectionView() }
        .onAppear { if store.root != WorkspaceStore.legacyStorage { folder = store.root } }
        .onChange(of: store.root) { _, value in folder = value }
    }
    private var storage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("작업을 보관할 곳을 정하세요").font(.title2.weight(.semibold))
            Text("이미지뿐 아니라 프롬프트, 참조 이미지, 캔버스와 생성 기록까지 함께 저장합니다. 앱을 지워도 이 폴더로 다시 시작할 수 있습니다.")
                .font(StudioTypography.body).foregroundStyle(.secondary).lineSpacing(4)
            VStack(alignment: .leading, spacing: 14) {
                Label(folder.lastPathComponent, systemImage: "folder.fill").font(.headline).foregroundStyle(Color.accentColor)
                Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(StudioTypography.supporting).foregroundStyle(.secondary).textSelection(.enabled)
                HStack { Text(folder == WorkspaceStore.recommendedStorage ? "Pictures 폴더 · 권장" : "사용자 지정 폴더").font(StudioTypography.metadata).foregroundStyle(.secondary); Spacer(); Button("변경…", action: chooseFolder) }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).panelSurface(radius: 14)
            if store.root == WorkspaceStore.legacyStorage {
                Label("기존 작업 \(store.library.assets.count)개를 복사합니다. 이전 폴더는 유지됩니다.", systemImage: "arrow.right.doc.on.clipboard").font(StudioTypography.supporting).foregroundStyle(.secondary)
            }
            Button("이미 보관함이 있나요? 기존 폴더 열기…") { store.selectStorageFolder(openExisting: true) }.buttonStyle(.link)
        }
    }
    private var connections: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("원하는 방식으로 연결하세요").font(.title2.weight(.semibold))
            Text("하나만 연결해도 시작할 수 있습니다. 나중에 설정에서 변경할 수 있습니다.").font(StudioTypography.body).foregroundStyle(.secondary)
            connectionRow("ChatGPT", subtitle: "자동 · 빠르게 / 구독 계정으로 생성", ready: session.status == .ready, action: session.connect)
            connectionRow("OpenAI API", subtitle: "고급 / 모델과 출력 옵션 직접 선택", ready: store.apiConnection.ready) { connection = true }
            APIBillingNotice()
        }
    }
    private func connectionRow(_ title: String, subtitle: String, ready: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(subtitle).font(StudioTypography.supporting).foregroundStyle(.secondary) }
            Spacer()
            Button(ready ? "연결됨 ✓" : "연결", action: action).controlSize(.large)
        }.padding(16).panelSurface(radius: 14)
    }
    private var workflow: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("한 번의 생성에서 끝내지 마세요").font(.title2.weight(.semibold))
            tip("text.alignleft", "프롬프트와 참조", "이미지를 프롬프트 영역으로 끌어놓고, 자주 쓰는 구성을 레시피로 저장하세요.")
            tip("point.3.connected.trianglepath.dotted", "연결해서 만드는 캔버스", "원본에서 배경·조명·색상을 나눠 실험하고, 선택한 결과를 다음 생성으로 연결하세요.")
            tip("square.and.arrow.down", "폴더 하나로 복원", "설정 → 저장 공간에서 보관함을 바꾸거나 기존 폴더를 다시 열 수 있습니다.")
            Text("⌘↵ 생성     Space 크게 보기     ⌘Z 되돌리기").font(StudioTypography.supporting).foregroundStyle(.secondary)
        }
    }
    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) { Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(StudioTypography.supporting).foregroundStyle(.secondary).lineSpacing(3) }
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.directoryURL = folder.deletingLastPathComponent(); panel.prompt = "이 폴더 선택"
        if panel.runModal() == .OK, let url = panel.url { folder = url }
    }
    private func advance() {
        error = nil
        if step == 0 {
            Task { do { if folder != store.root { try await store.changeStorage(to: folder) }; step = 1 } catch { self.error = error.localizedDescription } }
        } else if step == 1 { step = 2 }
        else { UserDefaults.standard.set(true, forKey: "onboardingCompletedV11"); store.showOnboarding = false }
    }
}
