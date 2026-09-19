import SwiftUI
import FlowCore

struct GenerationModeControl: View {
    @Binding var selection: GenerationMode
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("생성 방식").fontWeight(.medium)
            ForEach(GenerationMode.allCases, id: \.self) { mode in
                Button { selection = mode } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selection == mode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selection == mode ? Color.accentColor : .secondary).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(mode.label).fontWeight(.semibold)
                                Spacer(minLength: 4)
                                Text("요청당 \(mode.imagesPerRequest)장").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(mode.explanation).font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                        }
                    }.font(.system(size: 12)).padding(11).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selection == mode ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
                        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(selection == mode ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selection == mode ? 1.5 : 1) }
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).accessibilityLabel(mode.label).accessibilityValue(selection == mode ? "선택됨" : "")
                    .accessibilityHint(mode.explanation).accessibilityIdentifier("generation-mode-\(mode.rawValue)")
            }
        }
    }
}
