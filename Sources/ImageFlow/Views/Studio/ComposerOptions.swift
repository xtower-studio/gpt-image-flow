import SwiftUI
import FlowCore

struct ComposerOptions: View {
    @Binding var aspect: String
    @Binding var background: BackgroundOption
    @Binding var count: Int
    let countLocked: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSectionHeading(title: "출력 설정")
            HStack(spacing: 10) {
                OptionTile(title: "화면 비율", symbol: "aspectratio") {
                    Menu {
                        Picker("화면 비율", selection: $aspect) {
                            ForEach(["자유", "1:1", "3:2", "2:3", "16:9"], id: \.self) { Text($0 == "자유" ? "자동" : $0).tag($0) }
                        }
                    } label: { Text(aspect == "자유" || aspect == "자동" ? "자동" : aspect) }
                    .accessibilityLabel("화면 비율").accessibilityValue(aspect).accessibilityIdentifier("composer-aspect")
                }
                OptionTile(title: "배경", symbol: "square.on.square") {
                    Menu {
                        Picker("배경", selection: $background) { ForEach(BackgroundOption.allCases, id: \.self) { Text($0.label).tag($0) } }
                    } label: { Text(background.label) }
                    .accessibilityLabel("배경").accessibilityValue(background.label).accessibilityIdentifier("composer-background")
                }
            }
            HStack {
                Text("요청 횟수").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 2) {
                    Button { count = max(1, count - 1) } label: { Image(systemName: "minus").frame(width: 28, height: 30).contentShape(Rectangle()) }.disabled(count <= 1).accessibilityLabel("요청 횟수 줄이기")
                    TextField("요청 횟수", value: $count, format: .number.grouping(.never))
                        .textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 32).monospacedDigit().accessibilityLabel("요청 횟수 입력")
                    Button { count = min(50, count + 1) } label: { Image(systemName: "plus").frame(width: 28, height: 30).contentShape(Rectangle()) }.disabled(count >= 50).accessibilityLabel("요청 횟수 늘리기")
                }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).panelSurface(radius: 12).disabled(countLocked)
            }.padding(.top, 2)
        }
    }
}

private struct OptionTile<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            content().menuStyle(.borderlessButton).menuIndicator(.visible)
                .font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).panelSurface(radius: 16)
    }
}
