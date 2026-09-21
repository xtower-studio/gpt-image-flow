import SwiftUI
import FlowCore

struct GenerationModeControl: View {
    @Binding var selection: GenerationMode
    var allowsAPI = true
    var body: some View {
        VStack(alignment: .leading, spacing: PanelSpacing.heading) {
            PanelSectionHeading(title: "생성 방식")
            VStack(spacing: 0) {
                ForEach(GenerationMode.allCases, id: \.self) { mode in
                    Button { selection = mode } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selection == mode ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 14)).foregroundStyle(selection == mode ? Color.accentColor : .secondary)
                                .frame(width: 16, height: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(mode.label).font(StudioTypography.control)
                                    Text(mode == .sunburstAPI ? "API" : "\(mode.imagesPerRequest)장").font(StudioTypography.metadata).foregroundStyle(.secondary)

                                    Spacer(minLength: 0)

                                }
                                Text(description(mode)).font(StudioTypography.supporting).foregroundStyle(.secondary).lineSpacing(0).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selection == mode ? Color.accentColor.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).disabled(mode == .sunburstAPI && !allowsAPI).accessibilityLabel(mode.label).accessibilityValue(selection == mode ? "선택됨" : "")
                        .accessibilityHint(mode.explanation).accessibilityIdentifier("generation-mode-\(mode.rawValue)")
                }
            }.padding(4).frame(maxWidth: .infinity).panelSurface(radius: 12)
        }
    }
    private func description(_ mode: GenerationMode) -> String {
        switch mode {
        case .automatic: "가장 적절한 모델을 자동으로 선택"
        case .sunburstExperimental: "이전 실험 방식"
        case .sunburstAPI: "모델과 세부 설정을 직접 선택"
        case .instant: "가장 빠르고 저렴한 모델"
        }
    }
}
