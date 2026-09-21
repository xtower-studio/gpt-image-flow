import SwiftUI
import FlowCore

struct GenerationModeControl: View {
    @Binding var selection: GenerationMode
    var allowsAPI = true
    var body: some View {
        VStack(alignment: .leading, spacing: PanelSpacing.heading) {
            PanelSectionHeading(title: "생성 방식", note: "요청당 이미지 수")
            VStack(spacing: 4) {
                ForEach(GenerationMode.allCases, id: \.self) { mode in
                    Button { selection = mode } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol(mode)).font(.system(size: 14, weight: .medium))
                                .foregroundStyle(selection == mode ? Color.accentColor : .secondary)
                                .frame(width: 30, height: 30)
                                .background(selection == mode ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(mode.label).font(StudioTypography.item)
                                    Text(mode == .sunburstAPI ? "API" : "\(mode.imagesPerRequest)장").font(StudioTypography.metadata).foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2).background(.primary.opacity(0.045), in: Capsule())
                                    Spacer(minLength: 0)
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).opacity(selection == mode ? 1 : 0)
                                }
                                Text(description(mode)).font(StudioTypography.supporting).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.horizontal, 10).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selection == mode ? Color.accentColor.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 14))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).disabled(mode == .sunburstAPI && !allowsAPI).accessibilityLabel(mode.label).accessibilityValue(selection == mode ? "선택됨" : "")
                        .accessibilityHint(mode.explanation).accessibilityIdentifier("generation-mode-\(mode.rawValue)")
                }
            }.padding(4).panelSurface()
        }
    }
    private func symbol(_ mode: GenerationMode) -> String {
        switch mode { case .automatic: "sparkles"; case .sunburstExperimental, .sunburstAPI: "sun.max"; case .instant: "bolt" }
    }
    private func description(_ mode: GenerationMode) -> String {
        switch mode {
        case .automatic: "가장 적절한 모델을 자동으로 선택"
        case .sunburstExperimental: "이전 실험 방식"
        case .sunburstAPI: "모델과 생성 옵션을 직접 선택 · API"
        case .instant: "가장 빠르고 저렴한 모델"
        }
    }
}
