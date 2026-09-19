import SwiftUI
import FlowCore

struct JobResponseView: View {
    let jobID: UUID
    @Environment(WorkspaceStore.self) private var store
    @Environment(GenerationEngine.self) private var engine
    @Environment(WebSession.self) private var session
    @SceneStorage private var followup: String
    init(jobID: UUID) {
        self.jobID = jobID
        _followup = SceneStorage(wrappedValue: "", "followup-\(jobID.uuidString)")
    }
    var job: Job? { store.jobs.first { $0.id == jobID } }
    var body: some View {
        if let job {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(job.state.label, systemImage: job.state == .responded ? "text.bubble" : job.state.isRunning ? "sparkles" : job.state == .queued ? "clock" : job.state == .saved ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(job.state == .failed || job.state == .needsReview || job.state == .needsLogin ? Color.orange : Color.primary)
                    Spacer()
                    if let url = job.conversationURL { Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help("ChatGPT 대화 열기") }
                }
                DisclosureGroup("보낸 프롬프트") { Text(job.prompt).font(.callout).textSelection(.enabled).padding(.top, 8) }
                if !job.results.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) { ForEach(job.results) { asset in AssetThumbnail(url: store.vault.thumbnail(asset)).frame(height: 110) } }
                }
                if job.state.isRunning || job.state == .queued { Text("응답을 기다리고 있습니다. 이 화면에서 계속 확인할 수 있어요.").font(.callout).foregroundStyle(.secondary) }
                if let response = job.responseText { Text(response).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                if let error = job.error { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                if job.state == .queued {
                    HStack {
                        Button("먼저 실행") { store.moveQueued(job.id, toFront: true) }
                        Button("대기 취소", role: .destructive) { store.cancelQueued(job.id) }
                    }
                }
                if job.state == .needsReview {
                    Text("전송됐을 수 있어 자동으로 다시 보내지 않았습니다. 다른 작업은 계속됩니다.").font(.caption).foregroundStyle(.secondary)
                    if session.status != .ready { Button("ChatGPT 연결", action: session.connect) }
                    else if engine.activeCount >= (engine.eco ? 1 : 3) { Text("진행 중인 작업이 끝나면 기존 결과를 확인할 수 있습니다.").font(.callout).foregroundStyle(.secondary) }
                    HStack {
                        Button("기존 결과 확인") { engine.recover(job) }.disabled(job.conversationID == nil || session.status != .ready || engine.activeCount >= (engine.eco ? 1 : 3))
                        Button("기록 닫기") { do { try store.updateJob(job.id) { $0.state = .cancelled } } catch { store.report(error) } }
                    }
                } else if job.conversationID != nil && !job.state.isRunning && job.state != .queued {
                    Divider()
                    Text("같은 대화에서 이어서 요청").font(.caption).foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        if followup.isEmpty { Text("어떻게 이어갈까요?\n수정하거나 생성할 내용을 적어 주세요.").font(.system(size: 12)).foregroundStyle(.tertiary).lineSpacing(4).padding(12).allowsHitTesting(false) }
                        DropTextEditor(text: $followup, onFiles: { _ in store.notice = "이미지를 첨부하려면 만들기 탭에서 참조를 추가해 주세요." }).frame(height: 112).padding(5)
                    }.background(StudioPalette.field, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(StudioPalette.line) }
                    VStack(alignment: .leading, spacing: 12) {
                        ImageModelControl(selection: Binding(get: { store.selectedImageModel }, set: { store.selectedImageModel = $0 }))
                        Button("후속 요청 보내기") {
                            do { try store.enqueueFollowup(to: job, text: followup, model: store.selectedImageModel); followup = ""; store.notice = "후속 요청을 대기열에 추가했습니다." }
                            catch { store.report(error) }
                        }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command).disabled(followup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else if job.state == .failed || job.state == .needsLogin {
                    Button("다시 준비") { if session.status != .ready { session.connect() }; engine.retryBeforeSubmission(job) }
                }
            }.padding(20)
        }
    }
}
