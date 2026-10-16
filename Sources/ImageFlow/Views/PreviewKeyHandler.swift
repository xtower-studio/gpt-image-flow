import SwiftUI
import AppKit

/// Scope Quick Look keys to this sheet's window, regardless of which toolbar
/// button currently has focus. Other windows and text editors keep their keys.
struct PreviewKeyHandler: NSViewRepresentable {
    var previous: () -> Void
    var next: () -> Void
    var close: () -> Void
    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) { view.previous = previous; view.next = next; view.close = close }
    static func dismantleNSView(_ view: KeyView, coordinator: ()) { view.stop() }
    final class KeyView: NSView {
        var previous: (() -> Void)?
        var next: (() -> Void)?
        var close: (() -> Void)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                if let editor = window.firstResponder as? NSTextView, editor.isEditable { return event }
                switch event.keyCode {
                case 49, 53: if !event.isARepeat { self.close?() }; return nil
                case 123: self.previous?(); return nil
                case 124: self.next?(); return nil
                default: return event
                }
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}
