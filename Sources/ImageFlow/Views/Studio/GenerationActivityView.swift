import SwiftUI
import FlowCore

/// Four image planes gather into a frame. No simulated percentage or completion promise.
struct FlowGenerationMark: View {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active || reduceMotion || scenePhase != .active)) { timeline in
            let time = reduceMotion || !active ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let unit = min(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<4 {
                    let phase = time * 0.7 + Double(i) * 0.9
                    let spread = 0.5 + 0.5 * sin(phase)
                    var layer = context
                    layer.translateBy(x: center.x + sin(phase) * unit * 0.07, y: center.y + Double(i-2) * unit * 0.06)
                    layer.rotate(by: .degrees(Double(i-2) * 9 + sin(phase) * 4))
                    let side = unit * (0.45 + Double(i) * 0.035)
                    let rect = CGRect(x: -side/2, y: -side/2, width: side, height: side * 0.82)
                    let path = Path(roundedRect: rect, cornerRadius: unit * 0.055)
                    layer.fill(path, with: .color(Color.accentColor.opacity(0.025 + Double(i)*0.015)))
                    layer.stroke(path, with: .linearGradient(Gradient(colors: [.accentColor.opacity(0.2 + spread*0.6), .cyan.opacity(0.65), .accentColor.opacity(0.15)]), startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)), lineWidth: max(1, unit*0.009))
                }
                for i in 0..<6 {
                    let angle = time*0.24 + Double(i)*Double.pi/3
                    let radius = unit * 0.42
                    let p = CGPoint(x: center.x+cos(angle)*radius, y: center.y+sin(angle)*radius*0.72)
                    context.fill(Path(ellipseIn: CGRect(x: p.x-1.5, y: p.y-1.5, width: 3, height: 3)), with: .color(Color.accentColor.opacity(0.3)))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct GenerationActivityView: View {
    let job: Job
    var compact = false
    var showMark = true
    var body: some View {
        HStack(spacing: compact ? 10 : 18) {
            if showMark { FlowGenerationMark(active: job.state.isRunning).frame(width: compact ? 48 : 82, height: compact ? 48 : 82) }
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(job.state.label).font(StudioTypography.control); Spacer()
                    if let date = job.startedAt { Text(date, style: .timer).font(StudioTypography.metadata).monospacedDigit().foregroundStyle(.secondary) }
                }
                Text(job.inputPrompt ?? job.prompt).font(StudioTypography.supporting).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2)
                if !compact {
                    HStack(spacing: 5) {
                        ForEach(0..<4) { index in Capsule().fill(index <= stage ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.15)).frame(height: 3) }
                    }.padding(.top, 3).accessibilityHidden(true)
                    Text("\(job.requestModeLabel) · \(job.expectedImageCount)장 요청" + (job.imageToolVerifiedAt != nil ? " · 이미지 도구 확인됨" : ""))
                        .font(StudioTypography.metadata).foregroundStyle(.secondary)
                }
            }
        }.padding(compact ? 10 : 16).frame(maxWidth: .infinity, alignment: .leading).panelSurface(radius: 14)
        .accessibilityElement(children: .combine)
    }
    private var stage: Int {
        switch job.state { case .queued: -1; case .preparing, .uploading: 0; case .submitting: 1; case .generating: 2; case .collecting, .saved: 3; default: 0 }
    }
}
