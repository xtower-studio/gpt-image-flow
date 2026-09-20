import SwiftUI

/// App-local previews leave the user's system accessibility preferences intact.
struct DevelopmentAppearance: ViewModifier {
    @AppStorage("devPreviewReduceTransparency") private var transparency = false
    @AppStorage("devPreviewIncreaseContrast") private var contrast = false
    func body(content: Content) -> some View {
        if CommandLine.arguments.contains("--dev-directory") {
            content
                .environment(\.studioPreviewReduceTransparency, transparency)
                .environment(\.studioPreviewIncreaseContrast, contrast)
        } else {
            content
        }
    }
}
