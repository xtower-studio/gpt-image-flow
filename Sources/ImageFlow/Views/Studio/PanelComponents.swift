import SwiftUI

struct PanelSectionHeading: View {
    let title: String
    var note: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(StudioTypography.section)
            Spacer(minLength: 8)
            if let note { Text(note).font(StudioTypography.metadata).foregroundStyle(.secondary) }
        }
    }
}

/// Ordinary materials belong to content; glass is reserved for navigation and controls.
private struct PanelSurface: ViewModifier {
    var radius: CGFloat
    var editor: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.studioPreviewIncreaseContrast) private var previewContrast
    func body(content: Content) -> some View {
        content
            .background(editor ? StudioPalette.field : Color.primary.opacity(0.035))
            .studioContainer(radius: radius)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased || previewContrast ? 0.45 : editor ? 0.12 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func panelSurface(radius: CGFloat = StudioGeometry.fieldRadius, editor: Bool = false) -> some View {
        modifier(PanelSurface(radius: radius, editor: editor))
    }
    @ViewBuilder func panelScrollEdges() -> some View {
        if #available(macOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: [.top, .bottom]) }
        else { self }
    }
    /// Propagate a container's geometry to inset controls instead of inventing inner radii.
    @ViewBuilder func studioContainer(radius: CGFloat = StudioGeometry.contentRadius) -> some View {
        if #available(macOS 26.0, *) {
            clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(radius))))
                .containerShape(.rect(cornerRadius: radius))
        } else { clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)) }
    }
}

struct StudioPanelTabs: View {
    @Binding var selection: StudioPanelTab
    var body: some View {
        Picker("작업 패널", selection: $selection) {
            ForEach(StudioPanelTab.allCases, id: \.self) { tab in
                Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
            }
        }.pickerStyle(.segmented).labelsHidden().controlSize(.large)
            .padding(.horizontal, PanelSpacing.inset).padding(.top, 12).padding(.bottom, 16)
            .accessibilityIdentifier("studio-panel-tabs")
    }
}
