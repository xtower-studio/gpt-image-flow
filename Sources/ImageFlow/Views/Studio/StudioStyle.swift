import SwiftUI

/// Content uses system colors. Navigation and floating controls own the glass layer.
enum StudioPalette {
    static let stage = Color(nsColor: .underPageBackgroundColor)
    static let panel = Color(nsColor: .windowBackgroundColor)
    static let field = Color(nsColor: .textBackgroundColor)
    static let line = Color(nsColor: .separatorColor)
}

enum StudioGeometry {
    static let contentRadius: CGFloat = 20
    static let fieldRadius: CGFloat = 16
    static let inset: CGFloat = 8
    static let icon: CGFloat = 16
    static let target: CGFloat = 32
}

struct StudioIconButton: View {
    let symbol: String
    let label: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: StudioGeometry.icon, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .frame(width: StudioGeometry.target, height: StudioGeometry.target)
                .contentShape(Rectangle())
        }.buttonStyle(.borderless).tint(active ? .accentColor : .primary)
            .help(label).accessibilityLabel(label)
    }
}

struct SectionCaption: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(StudioTypography.section).foregroundStyle(.primary)
            Spacer()
            if let trailing { Text(trailing).font(StudioTypography.metadata).monospacedDigit().foregroundStyle(.secondary) }
        }
    }
}
