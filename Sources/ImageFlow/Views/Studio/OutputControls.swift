import SwiftUI

/// One full-width click target; the label and value belong to the same menu.
struct OutputMenuRow<Choices: View>: View {
    let title: String
    let value: String
    var horizontalInset: CGFloat = 12
    @ViewBuilder var choices: () -> Choices
    var body: some View {
        Menu(content: choices) {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(.primary).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }.font(StudioTypography.supporting)
                .padding(.horizontal, horizontalInset).frame(minHeight: 36).contentShape(Rectangle())
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .frame(maxWidth: .infinity).accessibilityLabel(title).accessibilityValue(value)
    }
}

struct OutputDivider: View {
    var body: some View { Divider().padding(.horizontal, 12) }
}

struct OutputQuantityRow: View {
    let title: String
    @Binding var value: Int
    let maximum: Int
    var locked = false
    var body: some View {
        HStack {
            Text(title).font(StudioTypography.supporting)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                Button { value = max(1, value - 1) } label: { Image(systemName: "minus").frame(width: 26, height: 28).contentShape(Rectangle()) }
                    .disabled(value <= 1).accessibilityLabel(title + " 줄이기")
                TextField(title, value: $value, format: .number.grouping(.never))
                    .textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 28).monospacedDigit()
                    .accessibilityLabel(title + " 입력")
                    .onChange(of: value) { _, number in value = min(maximum, max(1, number)) }
                Button { value = min(maximum, value + 1) } label: { Image(systemName: "plus").frame(width: 26, height: 28).contentShape(Rectangle()) }
                    .disabled(value >= maximum).accessibilityLabel(title + " 늘리기")
            }.buttonStyle(.plain).font(StudioTypography.supporting).disabled(locked)
        }.padding(.horizontal, 12).frame(minHeight: 36)
    }
}
