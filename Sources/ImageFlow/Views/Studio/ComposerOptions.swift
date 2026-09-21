import SwiftUI
import FlowCore

struct ComposerOptions: View {
    @Binding var aspect: String
    @Binding var background: BackgroundOption
    @Binding var count: Int
    let countLocked: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: PanelSpacing.heading) {
            PanelSectionHeading(title: "출력 설정")
            VStack(spacing: 0) {
                OutputMenuRow(title: "화면 비율", value: aspect == "자유" || aspect == "자동" ? "자동" : aspect) {
                    ForEach(["자유", "1:1", "3:2", "2:3", "16:9"], id: \.self) { value in
                        Button { aspect = value } label: {
                            if aspect == value || (aspect == "자동" && value == "자유") { Label(value == "자유" ? "자동" : value, systemImage: "checkmark") }
                            else { Text(value == "자유" ? "자동" : value) }
                        }
                    }
                }.accessibilityIdentifier("composer-aspect")
                OutputDivider()
                OutputMenuRow(title: "배경", value: background.label) {
                    ForEach(BackgroundOption.allCases, id: \.self) { value in
                        Button { background = value } label: {
                            if background == value { Label(value.label, systemImage: "checkmark") }
                            else { Text(value.label) }
                        }
                    }
                }.accessibilityIdentifier("composer-background")
                OutputDivider()
                OutputQuantityRow(title: "요청 횟수", value: $count, maximum: 50, locked: countLocked)
            }.padding(.vertical, 4).frame(maxWidth: .infinity).panelSurface(radius: 12)
        }
    }
}
