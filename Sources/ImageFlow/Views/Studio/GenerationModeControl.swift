import SwiftUI
import FlowCore

struct GenerationModeControl: View {
    @Binding var selection: GenerationMode
    var allowsAPI = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var modes: [GenerationMode] { GenerationMode.allCases.filter { allowsAPI || $0 != .sunburstAPI } }
    var body: some View {
        VStack(alignment: .leading, spacing: PanelSpacing.heading) {
            PanelSectionHeading(title: "생성 방식")
            HStack(spacing: 8) {
                ForEach(modes, id: \.self) { mode in
                    Button { selection = mode } label: {
                        VStack(spacing: 8) {
                            Image(systemName: symbol(mode)).font(.system(size: 19, weight: .medium))
                                .symbolRenderingMode(.monochrome)
                            Text(mode.label).font(StudioTypography.control)
                        }.frame(maxWidth: .infinity).frame(height: 66)
                            .foregroundStyle(selection == mode ? Color.accentColor : .primary)
                            .background(selection == mode ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.035))
                            .studioContainer(radius: 14)
                            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selection == mode ? Color.accentColor : .clear, lineWidth: 1.5) }
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(mode.label).accessibilityValue(selection == mode ? "선택됨" : "")
                        .accessibilityAddTraits(selection == mode ? .isSelected : [])
                        .help(mode.explanation).accessibilityIdentifier("generation-mode-\(mode.rawValue)")
                }
            }
            Text(description(selection)).font(StudioTypography.supporting).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 32, alignment: .topLeading)
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selection)
    }
    private func symbol(_ mode: GenerationMode) -> String {
        switch mode { case .automatic: "sparkles"; case .sunburstAPI: "slider.horizontal.3"; case .instant: "bolt"; case .sunburstExperimental: "sun.max" }
    }
    private func description(_ mode: GenerationMode) -> String {
        switch mode {
        case .automatic: "가장 적절한 모델을 자동으로 선택합니다. 요청마다 4장을 만듭니다."
        case .sunburstAPI: "OpenAI API로 모델과 세부 설정을 직접 선택합니다."
        case .instant: "가장 빠르고 저렴한 모델로 1장을 만듭니다."
        case .sunburstExperimental: "이전 실험 방식"
        }
    }
}
