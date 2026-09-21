import SwiftUI
import AppKit

/// File drops become references without inserting file paths into the prompt.
/// Text selection, IME and undo continue through NSTextView.
struct DropTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.isEnabled) private var enabled
    var onFiles: ([URL]) -> Void
    var onFocusChanged: (Bool) -> Void = { _ in }
    var acceptsFileDrops = false
    var onFileDragChanged: (Bool) -> Void = { _ in }
    var focusRequest = 0
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        let view = FileTextView()
        view.allowsUndo = true
        view.isAutomaticTextCompletionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isRichText = false; view.drawsBackground = false; view.font = .systemFont(ofSize: StudioTypography.bodySize)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = StudioTypography.lineSpacing
        view.defaultParagraphStyle = paragraph
        view.textColor = .labelColor; view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 4, height: 7)
        view.delegate = context.coordinator; view.onFiles = onFiles; view.onFocusChanged = onFocusChanged
        view.acceptsFileDrops = acceptsFileDrops; view.onFileDragChanged = onFileDragChanged
        view.registerForDraggedTypes([.fileURL]); view.string = text
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? FileTextView else { return }
        view.onFiles = onFiles; view.onFocusChanged = onFocusChanged
        view.acceptsFileDrops = acceptsFileDrops; view.onFileDragChanged = onFileDragChanged
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
    var acceptsFileDrops = false
    var onFileDragChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); if result { Task { @MainActor [weak self] in self?.onFocusChanged?(true) } }; return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); if result { Task { @MainActor [weak self] in self?.onFocusChanged?(false) } }; return result }
    func files(_ pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !files(sender.draggingPasteboard).isEmpty else { return super.draggingEntered(sender) }
        let accepted = acceptsFileDrops && isEditable
        onFileDragChanged?(accepted)
        return accepted ? .copy : []
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !files(sender.draggingPasteboard).isEmpty else { return super.draggingUpdated(sender) }
        return acceptsFileDrops && isEditable ? .copy : []
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onFileDragChanged?(false); super.draggingExited(sender)
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard !files(sender.draggingPasteboard).isEmpty else { return super.prepareForDragOperation(sender) }
        return acceptsFileDrops && isEditable && bounds.contains(convert(sender.draggingLocation, from: nil))
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = files(sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onFileDragChanged?(false)
        guard acceptsFileDrops && isEditable, bounds.contains(convert(sender.draggingLocation, from: nil)) else { return false }
        onFiles?(urls); return true
    }
    override func paste(_ sender: Any?) {
        let urls = files(.general)
        if !urls.isEmpty { onFiles?(urls) } else { super.paste(sender) }
    }
}
