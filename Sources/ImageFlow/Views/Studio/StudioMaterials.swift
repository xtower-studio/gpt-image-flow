import SwiftUI

/// One sampling container for neighboring custom controls. Artwork stays on the
/// neutral stage; only the floating control layer receives glass.
struct StudioGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12, content: content)
        } else {
            content()
        }
    }
}

extension EnvironmentValues {
    @Entry var studioPreviewReduceTransparency = false
    @Entry var studioPreviewIncreaseContrast = false
}

private struct StudioGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.studioPreviewReduceTransparency) private var previewTransparency
    @Environment(\.studioPreviewIncreaseContrast) private var previewContrast
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency || previewTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay { shape.strokeBorder(.primary.opacity(contrast == .increased || previewContrast ? 0.5 : 0.18)) }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(.primary.opacity(0.12)) }
        }
    }
}

extension View {
    func studioGlass(cornerRadius: CGFloat = 22, interactive: Bool = true) -> some View {
        modifier(StudioGlassSurface(cornerRadius: cornerRadius, interactive: interactive))
    }
    @ViewBuilder func studioActionButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
    }
}
