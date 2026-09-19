import SwiftUI
import AppKit

/// Reject file drags here: only the reference region accepts attachments.
/// Explicit paste and native text editing, IME and undo remain available.
struct DropTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.isEnabled) private var enabled
    var onFiles: ([URL]) -> Void
    var onFocusChanged: (Bool) -> Void = { _ in }
    var focusRequest = 0
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        let view = FileTextView()
        view.allowsUndo = true
        view.isAutomaticTextCompletionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isRichText = false; view.drawsBackground = false; view.font = .systemFont(ofSize: 13)
        view.textColor = .labelColor; view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 4, height: 7)
        view.delegate = context.coordinator; view.onFiles = onFiles; view.onFocusChanged = onFocusChanged
        view.registerForDraggedTypes([.fileURL]); view.string = text
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? FileTextView else { return }
        view.onFiles = onFiles; view.onFocusChanged = onFocusChanged
        view.isEditable = enabled; view.isSelectable = enabled
        if !enabled, scroll.window?.firstResponder === view { scroll.window?.makeFirstResponder(nil) }
        if !view.hasMarkedText(), view.string != text { view.string = text }
        if enabled, focusRequest > 0, context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            Task { @MainActor [weak view] in
                try? await Task.sleep(for: .milliseconds(80))
                guard let view, view.isEditable else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DropTextEditor
        var lastFocusRequest = 0
        init(_ parent: DropTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
}
final class FileTextView: NSTextView {
    var onFiles: (([URL]) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); if result { Task { @MainActor [weak self] in self?.onFocusChanged?(true) } }; return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); if result { Task { @MainActor [weak self] in self?.onFocusChanged?(false) } }; return result }
    func files(_ pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        files(sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : []
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        files(sender.draggingPasteboard).isEmpty ? super.draggingUpdated(sender) : []
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = files(sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        return false
    }
    override func paste(_ sender: Any?) {
        let urls = files(.general)
        if !urls.isEmpty { onFiles?(urls) } else { super.paste(sender) }
    }
}
