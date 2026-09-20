import SwiftUI
import FlowCore

struct TaskHistoryView: View {
    let project: Project
    @Binding var selectedJobID: UUID?
    @Environment(WorkspaceStore.self) private var store
    @Environment(GenerationEngine.self) private var engine
    private var jobs: [Job] { store.jobs.filter { $0.projectID == project.id && $0.state != .cancelled }.reversed() }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if selectedJobID != nil { Button { selectedJobID = nil } label: { Label("모든 작업", systemImage: "chevron.left") }.buttonStyle(.borderless) }
                else { Text("작업 기록").font(.system(size: 15, weight: .semibold)) }
                Spacer()
                Button(action: engine.pauseOrResume) { Image(systemName: store.journal.paused ? "play" : "pause") }.help(store.journal.paused ? "대기열 계속" : "대기열 일시정지").studioActionButton().buttonBorderShape(.circle)
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            if store.journal.paused {
                Label(store.journal.pauseReason ?? "대기열이 일시정지되었습니다", systemImage: "pause.circle").font(.callout).foregroundStyle(.orange).padding(.horizontal, 16).padding(.bottom, 12)
            }
            if let selectedJobID { ScrollView { JobResponseView(jobID: selectedJobID).id(selectedJobID) }.panelScrollEdges() }
            else if jobs.isEmpty {
                ContentUnavailableView("아직 작업이 없습니다", systemImage: "clock", description: Text("생성한 이미지와 답변을 여기에서 확인할 수 있습니다."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(jobs) { job in
                            Button { selectedJobID = job.id } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    if let asset = job.results.first { AssetThumbnail(url: store.vault.thumbnail(asset), fit: false).frame(width: 46, height: 46).clipped().clipShape(RoundedRectangle(cornerRadius: 12)) }
                                    else { Image(systemName: symbol(job)).font(.system(size: 19)).foregroundStyle(job.state.needsAttention && job.state != .responded ? Color.orange : .secondary).frame(width: 46, height: 46).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12)) }
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack { Text(job.label).fontWeight(.medium); Spacer(); Text(job.createdAt, style: .time).font(.caption).foregroundStyle(.secondary) }
                                        Text("\(job.state.label) · \(job.results.count)/\(job.expectedImageCount)장").font(.caption).foregroundStyle(job.state == .failed ? Color.orange : .secondary)
                                        Text(job.responseText ?? job.error ?? job.inputPrompt ?? job.prompt).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                                    }
                                }.contentShape(Rectangle()).padding(12).panelSurface(radius: 16)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 16)
                }.panelScrollEdges()
            }
        }
    }
    private func symbol(_ job: Job) -> String { job.state == .responded ? "text.bubble" : job.state.isRunning ? "sparkles" : job.state == .queued ? "clock" : "exclamationmark.triangle" }
}
