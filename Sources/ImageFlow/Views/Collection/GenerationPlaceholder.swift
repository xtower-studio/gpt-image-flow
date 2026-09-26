import SwiftUI
import FlowCore

struct GenerationPlaceholder: View {
    let job: Job
    let ordinal: Int
    var compact = false
    var body: some View {
        VStack(spacing: compact ? 4 : 10) {
            if job.state.needsAttention {
                Image(systemName: "exclamationmark.circle").font(.title2).foregroundStyle(.orange)
            } else {
                FlowGenerationMark(active: job.state.isRunning).frame(width: compact ? 40 : 76, height: compact ? 40 : 76)
            }
            Text(job.state.label).font(compact ? StudioTypography.metadata : StudioTypography.control)
            Text("\(ordinal) / \(job.expectedImageCount)").font(StudioTypography.metadata).monospacedDigit().foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.accentColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 5])) }
            .accessibilityLabel("\(job.label), 이미지 \(ordinal)/\(job.expectedImageCount), \(job.state.label)")
    }
}

final class GenerationCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("GenerationCell")
    private var host: NSHostingView<AnyView>?
    override func loadView() { view = NSView() }
    func render(job: Job, ordinal: Int, phase: ScenePhase, open: @escaping () -> Void) {
        let content = AnyView(Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                GenerationPlaceholder(job: job, ordinal: ordinal).aspectRatio(1, contentMode: .fit)
                Text("\(job.label) · \(ordinal)").font(StudioTypography.item).lineLimit(1)
                Text(job.inputPrompt ?? job.prompt).font(StudioTypography.metadata).foregroundStyle(.secondary).lineLimit(1)
            }.padding(3).contentShape(Rectangle())
        }.buttonStyle(.plain).help("작업 상태와 응답 보기").environment(\.scenePhase, phase))
        if let host { host.rootView = content }
        else {
            let host = NSHostingView(rootView: content); host.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host)
            NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.trailingAnchor.constraint(equalTo: view.trailingAnchor), host.topAnchor.constraint(equalTo: view.topAnchor), host.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
            self.host = host
        }
    }
}
