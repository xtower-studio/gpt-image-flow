import SwiftUI
import FlowCore

struct GenerationModeControl: View {
    @Binding var selection: GenerationMode
    var allowsAPI = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSectionHeading(title: "생성 방식", note: "요청당 이미지 수")
            VStack(spacing: 3) {
                ForEach(GenerationMode.allCases, id: \.self) { mode in
                    Button { selection = mode } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol(mode)).font(.system(size: 14, weight: .medium))
                                .foregroundStyle(selection == mode ? Color.accentColor : .secondary)
                                .frame(width: 30, height: 30)
                                .background(selection == mode ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(mode.label).font(StudioTypography.item)
                                    Text(mode == .sunburstAPI ? "API" : "\(mode.imagesPerRequest)장").font(StudioTypography.metadata).foregroundStyle(.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2).background(.primary.opacity(0.045), in: Capsule())
                                    Spacer(minLength: 0)
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).opacity(selection == mode ? 1 : 0)
                                }
                                Text(description(mode)).font(StudioTypography.supporting).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
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
        case .automatic: "매우 높은 추론으로 4장 동시 생성"
        case .sunburstExperimental: "이전 실험 방식"
        case .sunburstAPI: "API 키로 연결 · 별도 사용 요금"
        case .instant: "가장 빠르고 저렴한 모델"
        }
    }
}
