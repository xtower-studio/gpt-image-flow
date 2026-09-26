import SwiftUI
import FlowCore

struct JobResponseView: View {
    let jobID: UUID
    @Environment(WorkspaceStore.self) private var store
    @Environment(GenerationEngine.self) private var engine
    @Environment(WebSession.self) private var session
    @State private var showAPIConnection = false
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
                        .font(StudioTypography.title).foregroundStyle(job.state == .failed || job.state == .needsReview || job.state == .needsLogin ? Color.orange : Color.primary)
                    Spacer()
                    if let url = job.conversationURL { Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help("ChatGPT 대화 열기") }
                }
                if job.imageToolVerifiedAt != nil { Label("이미지 생성 도구 적용 확인", systemImage: "checkmark.seal").font(StudioTypography.supporting).foregroundStyle(.secondary) }
                if job.apiOptions == nil, job.state.isRunning {
                    Button("실제 ChatGPT 작업 화면 보기") { engine.workers[job.id]?.host.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
                }
                DisclosureGroup("보낸 프롬프트") { Text(job.prompt).font(StudioTypography.body).textSelection(.enabled).padding(.top, 8) }.padding(14).panelSurface()
                if let options = job.apiOptions {
                    Text(ImageAPIModel.label(options.model) + " · OpenAI API").font(StudioTypography.control)
                    if let data = engine.apiPreviews[job.id], let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 180).accessibilityLabel("API 생성 중 미리보기") }
                    if let id = job.apiRequestID { Text(id).font(StudioTypography.code).textSelection(.enabled) }
                    if let usage = job.apiUsageJSON { DisclosureGroup("API 사용량") { Text(usage).font(StudioTypography.code).textSelection(.enabled) } }
                    Link("OpenAI 사용량 확인 ↗", destination: URL(string: "https://platform.openai.com/usage")!)
                    if job.state == .failed { Button("API 연결 관리…") { showAPIConnection = true } }
                }
                if !job.results.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) { ForEach(job.results) { asset in AssetThumbnail(url: store.vault.thumbnail(asset)).frame(height: 110) } }
                }
                if job.state.isRunning || job.state == .queued { GenerationActivityView(job: job) }
                if let response = job.responseText { Text(response).font(StudioTypography.body).lineSpacing(StudioTypography.lineSpacing).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                if let error = job.error { Text(error).font(StudioTypography.body).foregroundStyle(.secondary).textSelection(.enabled) }
                if job.state == .queued {
                    HStack {
                        Button("먼저 실행") { store.moveQueued(job.id, toFront: true) }
                        Button("대기 취소", role: .destructive) { store.cancelQueued(job.id) }
                    }
                }
                if job.state == .needsReview && job.apiOptions != nil {
                    Text("API는 완료 결과를 다시 조회할 수 없습니다. 받은 이미지는 보관했습니다. 사용량을 확인하고 새 요청 여부를 결정하세요.").font(StudioTypography.supporting)
                    Button("기록 닫기") { do { try store.updateJob(job.id) { $0.state = .cancelled } } catch { store.report(error) } }
                } else if job.state == .needsReview {
                    Text("전송됐을 수 있어 자동으로 다시 보내지 않았습니다. 다른 작업은 계속됩니다.").font(StudioTypography.supporting).foregroundStyle(.secondary)
                    if session.status != .ready { Button("ChatGPT 연결", action: session.connect) }
                    else if engine.activeCount >= (engine.eco ? 1 : 3) { Text("진행 중인 작업이 끝나면 기존 결과를 확인할 수 있습니다.").font(StudioTypography.body).foregroundStyle(.secondary) }
                    HStack {
                        Button("기존 결과 확인") { engine.recover(job) }.disabled(job.conversationID == nil || session.status != .ready || engine.activeCount >= (engine.eco ? 1 : 3))
                        Button("기록 닫기") { do { try store.updateJob(job.id) { $0.state = .cancelled } } catch { store.report(error) } }
                    }
                } else if job.conversationID != nil && !job.state.isRunning && job.state != .queued {
                    Divider()
                    PanelSectionHeading(title: "같은 대화에서 이어서 요청")
                    ZStack(alignment: .topLeading) {
                        if followup.isEmpty { Text("어떻게 이어갈까요?\n수정하거나 생성할 내용을 적어 주세요.").font(StudioTypography.body).foregroundStyle(.secondary).lineSpacing(StudioTypography.lineSpacing).padding(12).allowsHitTesting(false) }
                        DropTextEditor(text: $followup, onFiles: { _ in store.notice = "이미지를 첨부하려면 만들기 탭에서 참조를 추가해 주세요." }).frame(height: 112).padding(5)
                    }.panelSurface(editor: true)
                    VStack(alignment: .leading, spacing: 12) {
                        GenerationModeControl(selection: Binding(get: { store.selectedGenerationMode == .sunburstAPI ? .automatic : store.selectedGenerationMode }, set: { store.selectedGenerationMode = $0 }), allowsAPI: false)
                        Button {
                            do { try store.enqueueFollowup(to: job, text: followup, mode: store.selectedGenerationMode == .sunburstAPI ? .automatic : store.selectedGenerationMode); followup = ""; store.notice = "후속 요청을 대기열에 추가했습니다." }
                            catch { store.report(error) }
                        } label: {
                            Label("\(store.selectedGenerationMode == .sunburstAPI ? 4 : store.selectedGenerationMode.imagesPerRequest)개 이미지 요청", systemImage: "sparkles").font(StudioTypography.action).frame(maxWidth: .infinity).padding(.vertical, 3)
                        }.studioActionButton(prominent: true).buttonBorderShape(.capsule).controlSize(.large).keyboardShortcut(.return, modifiers: .command).disabled(followup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else if job.state == .failed || job.state == .needsLogin {
                    Button(job.apiOptions != nil ? "다시 요청 · API 유료" : "다시 준비") {
                        if job.apiOptions != nil && !store.apiConnection.ready { showAPIConnection = true }
                        else { if job.apiOptions == nil && session.status != .ready { session.connect() }; engine.retryBeforeSubmission(job) }
                    }
                }
            }.padding(16).sheet(isPresented: $showAPIConnection) { APIConnectionView() }
        }
    }
}
