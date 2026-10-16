import SwiftUI
import AppKit

/// Shared reading hierarchy for SwiftUI chrome and the native prompt editor.
/// macOS HIG recommends 13 pt body text. Use 14 pt for reading and at least 13 pt for supporting copy.
enum StudioTypography {
    static let title = Font.system(size: 17, weight: .semibold)
    static let section = Font.system(size: 15, weight: .semibold)
    static let item = Font.system(size: 14, weight: .medium)
    static let body = Font.system(size: 14)
    static let action = Font.system(size: 14, weight: .semibold)
    static let control = Font.system(size: 14, weight: .medium)
    static let supporting = Font.system(size: 13)
    static let metadata = Font.system(size: 13)
    static let code = Font.system(size: 13, design: .monospaced)
    static let bodySize: CGFloat = 14
    static let lineSpacing: CGFloat = 4
}
