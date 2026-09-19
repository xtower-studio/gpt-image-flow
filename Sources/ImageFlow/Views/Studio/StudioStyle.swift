import SwiftUI

// Quiet, adaptive surfaces keep artwork—not application chrome—in the foreground.
enum StudioPalette {
    static let stage = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.105, green: 0.11, blue: 0.12, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.965, alpha: 1)
    })
    static let panel = Color(nsColor: .windowBackgroundColor)
    static let field = Color.primary.opacity(0.035)
    static let line = Color.primary.opacity(0.09)
}
struct StudioIconButton: View {
    let symbol: String
    let label: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 28, height: 28) }
            .buttonStyle(QuietButtonStyle(active: active)).help(label).accessibilityLabel(label)
    }
}
struct QuietButtonStyle: ButtonStyle {
    var active = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(content: configuration.label, active: active, pressed: configuration.isPressed)
            .opacity(enabled ? 1 : 0.3)
    }
    private struct HoverLabel<Content: View>: View {
        let content: Content
        let active: Bool
        let pressed: Bool
        @State private var hovered = false
        var body: some View {
            content.foregroundStyle(active ? Color.accentColor : Color.primary.opacity(0.75))
                .background(active ? Color.accentColor.opacity(0.1) : Color.primary.opacity(pressed ? 0.1 : hovered ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle()).onHover { hovered = $0 }
        }
    }
}
struct SectionCaption: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack { Text(title).font(.system(size: 13, weight: .semibold)); Spacer(); if let trailing { Text(trailing).font(.system(size: 10)).monospacedDigit() } }.foregroundStyle(.secondary)
    }
}
