import AppKit
import WebKit

@main enum ProbeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ProbeApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class ProbeApp: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var workers: [WebFixture] = []
    var recorder: Recorder!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--output"), arguments.count > index + 1 else {
            NSApp.terminate(nil); return
        }
        recorder = Recorder(output: URL(fileURLWithPath: arguments[index + 1]))
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 780, height: 260),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Image Flow — 구현 전 로컬 검증"
        let store = WKWebsiteDataStore.nonPersistent()
        workers = (0..<3).map { WebFixture(slot: $0, store: store) }
        workers.forEach { window.contentView?.addSubview($0.view) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task {
            do { try await run() }
            catch { recorder.record("probe-completed", false, String(describing: error)) }
            do { try recorder.finish() }
            catch { FileHandle.standardError.write(Data("Could not save probe report: \(error)\n".utf8)) }
            NSApp.terminate(nil)
        }
    }

    func run() async throws {
        let scratch = recorder.output.deletingLastPathComponent().appendingPathComponent("fixtures-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let png = scratch.appendingPathComponent("참조 이미지 1.png")
        let jpeg = scratch.appendingPathComponent("제품 reference 2.jpg")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<8 { for y in 0..<8 { bitmap.setColor(.systemBlue, atX: x, y: y) } }
        try bitmap.representation(using: .png, properties: [:])!.write(to: png)
        try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!.write(to: jpeg)
        for worker in workers {
            try await waitUntil("fixture ready") {
                try await worker.view.evaluateJavaScript("typeof window.readFiles === 'function'") as? Bool == true
            }
        }
        let worker = workers[0]
        let contract = Bundle.module.url(forResource: "result-contract", withExtension: "js", subdirectory: "Fixtures")!
        let contractResults = try await worker.view.evaluateJavaScript(String(contentsOf: contract, encoding: .utf8))
        guard let checks = contractResults as? [[String: Any]], checks.count == 8 else { throw ProbeError.invalidResult }
        for check in checks {
            recorder.record(check["name"] as? String ?? "unnamed", check["passed"] as? Bool == true,
                            check["detail"] as? String ?? "")
        }
        try await worker.choose([png])
        recorder.record("single-png-unicode-filename", try await worker.filesMatch([png]))
        try await worker.choose([png, jpeg])
        recorder.record("multiple-png-jpeg-exact-bytes", try await worker.filesMatch([png, jpeg]))
        try await worker.choose([png, jpeg])
        recorder.record("same-references-reused", try await worker.filesMatch([png, jpeg]))

        try await workers[1].choose([jpeg])
        try await workers[2].choose([png])
        let isolation = try await workers[0].filesMatch([png, jpeg])
        let isolation1 = try await workers[1].filesMatch([jpeg])
        let isolation2 = try await workers[2].filesMatch([png])
        recorder.record("three-webviews-independent-attachments", isolation && isolation1 && isolation2)

        try await worker.choose([scratch.appendingPathComponent("missing.png")])
        recorder.record("missing-file-fails-closed", try await worker.filesMatch([]))
        worker.cancelled = true
        let before = worker.panelCalls
        try await worker.view.evaluateJavaScript("document.querySelector('#upload').click();")
        try await waitUntil("cancel callback") { worker.panelCalls > before }
        recorder.record("cancelled-file-selection-empty", try await worker.filesMatch([]))
        worker.cancelled = false

        window.miniaturize(nil)
        try await Task.sleep(for: .milliseconds(500))
        try await worker.choose([png])
        recorder.record("minimized-file-attachment", try await worker.filesMatch([png]))
        window.deminiaturize(nil)
        window.orderOut(nil)
        try await worker.choose([jpeg])
        recorder.record("hidden-file-attachment", try await worker.filesMatch([jpeg]))
        let beforeTicks = try await worker.view.evaluateJavaScript("window.ticks") as? Int ?? 0
        try await Task.sleep(for: .seconds(10))
        let afterTicks = try await worker.view.evaluateJavaScript("window.ticks") as? Int ?? 0
        recorder.record("hidden-timer-10-seconds", afterTicks > beforeTicks,
                        "ticks=\(afterTicks - beforeTicks); only local short-duration evidence")

        let output = scratch.appendingPathComponent("downloaded.png")
        worker.downloadDestination = output
        let bytes = try Data(contentsOf: png)
        _ = try await worker.javaScript("""
          const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
          const url = URL.createObjectURL(new Blob([bytes], {type:'image/png'}));
          const a = document.createElement('a'); a.href = url; a.download = 'fixture.png';
          document.body.append(a); a.click(); return true;
        """, arguments: ["base64": bytes.base64EncodedString()])
        try await waitUntil("WKDownload completed", timeout: 8) {
            worker.downloadFinished || worker.downloadError != nil
        }
        let same = (try? Data(contentsOf: output)) == bytes
        recorder.record("wkdownload-blob-original-bytes", worker.downloadFinished && same,
                        worker.downloadError ?? "local Blob download, not authenticated ChatGPT download")
        recorder.record("probe-completed", true)
    }
}
