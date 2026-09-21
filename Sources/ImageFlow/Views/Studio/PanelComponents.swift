import SwiftUI

struct PanelSectionHeading: View {
    let title: String
    var note: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(StudioTypography.section).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let note { Text(note).font(StudioTypography.metadata).foregroundStyle(.secondary) }
        }
    }
}

private struct PanelSurface: ViewModifier {
    var radius: CGFloat
    var editor: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.studioPreviewIncreaseContrast) private var previewContrast
    func body(content: Content) -> some View {
        content.background(Color(nsColor: editor ? .textBackgroundColor : .controlBackgroundColor).opacity(editor ? 1 : 0.65), in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(contrast == .increased || previewContrast ? 0.35 : 0.055)) }
    }
}

extension View {
    func panelSurface(radius: CGFloat = 18, editor: Bool = false) -> some View {
        modifier(PanelSurface(radius: radius, editor: editor))
    }
    @ViewBuilder func panelScrollEdges() -> some View {
        if #available(macOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: [.top, .bottom]) }
        else { self }
    }
}

struct StudioPanelTabs: View {
    @Binding var selection: StudioPanelTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func tabLabel(_ tab: StudioPanelTab) -> some View {
        Label(tab.rawValue, systemImage: tab.symbol)
            .font(StudioTypography.control.weight(selection == tab ? .semibold : .medium))
            .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity).frame(height: 34).contentShape(Capsule())
    }
    var body: some View {
        StudioGlassGroup {
            HStack(spacing: 4) {
                ForEach(StudioPanelTab.allCases, id: \.self) { tab in
                    Button { selection = tab } label: {
                        if selection == tab { tabLabel(tab).studioGlass(cornerRadius: 18) }
                        else { tabLabel(tab) }
                    }.buttonStyle(.plain).accessibilityLabel(tab.rawValue)
                        .accessibilityValue(selection == tab ? "선택됨" : "")
                        .accessibilityIdentifier("studio-panel-\(tab.rawValue)")
                }
            }
        }.padding(.horizontal, PanelSpacing.inset).padding(.top, 12).padding(.bottom, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
    }
}
