import SwiftUI
import AppKit

/// SwiftUI's magnification gesture handles pinch, but exposes no desktop wheel deltas.
/// A local event monitor forwards only events inside this canvas; no global hooks.
struct CanvasScrollBridge: NSViewRepresentable {
    var pan: (Double, Double) -> Void
    var zoom: (Double) -> Void
    var ignoresPanAt: ((CGPoint) -> Bool)? = nil
    func makeNSView(context: Context) -> WheelRegion { let view = WheelRegion(); view.pan = pan; view.zoom = zoom; view.ignoresPanAt = ignoresPanAt; return view }
    func updateNSView(_ view: WheelRegion, context: Context) { view.pan = pan; view.zoom = zoom; view.ignoresPanAt = ignoresPanAt }
    static func dismantleNSView(_ view: WheelRegion, coordinator: ()) { view.removeMonitor() }
    final class WheelRegion: NSView {
        var pan: ((Double, Double) -> Void)?
        var zoom: ((Double) -> Void)?
        var ignoresPanAt: ((CGPoint) -> Bool)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, let window = self.window, event.window === window,
                          !self.isHiddenOrHasHiddenAncestor, self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return false }
                    if event.modifierFlags.contains(.command) { self.zoom?(exp(event.scrollingDeltaY * 0.01)) }
                    else {
                        let point = self.convert(event.locationInWindow, from: nil)
                        if self.ignoresPanAt?(CGPoint(x: point.x, y: self.bounds.height - point.y)) == true { return false }
                        let multiplier = event.hasPreciseScrollingDeltas ? 1.0 : 16.0
                        self.pan?(event.scrollingDeltaX * multiplier, event.scrollingDeltaY * multiplier)
                    }
                    return true
                }
                return consumed ? nil : event
            }
        }
        func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}
