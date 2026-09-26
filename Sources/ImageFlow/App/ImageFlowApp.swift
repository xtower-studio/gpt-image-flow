import SwiftUI

@main struct ImageFlowApp: App {
    @NSApplicationDelegateAdaptor(FlowAppDelegate.self) var appDelegate
    @State private var session = WebSession()
    @State private var store = WorkspaceStore()
    @State private var engine: GenerationEngine?
    var body: some Scene {
        WindowGroup("Image Flow") {
            Group {
                if let engine { WorkspaceView().environment(engine) }
                else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.environment(session).environment(store)
                .modifier(DevelopmentAppearance())
                .disabled(store.changingStorage)
                .sheet(isPresented: $store.showOnboarding) { OnboardingView().environment(store).environment(session) }
                .frame(minWidth: 1000, minHeight: 680)
                .task {
                    appDelegate.session = session
                    appDelegate.store = store
                    if engine == nil { let engine = GenerationEngine(store: store, session: session); self.engine = engine; appDelegate.engine = engine; engine.start() }
                    if CommandLine.arguments.contains("--connect") { session.connect() }
                    else { session.restore() }
                }
        }
        .defaultSize(width: 1280, height: 840)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands { StudioCommands() }
        Settings {
            if let engine { SettingsView().environment(session).environment(store).environment(engine) }
        }
    }
}

@MainActor final class FlowAppDelegate: NSObject, NSApplicationDelegate {
    var session: WebSession?
    var store: WorkspaceStore?
    var engine: GenerationEngine?
    var statusTask: Task<Void, Never>?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let index = CommandLine.arguments.firstIndex(of: "--dev-directory"), CommandLine.arguments.count > index + 1 else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                if let session = self?.session {
                    var status: [String: Any] = ["connection": session.status.rawValue,
                        "url": session.browser?.url?.absoluteString ?? "", "title": session.browser?.title ?? ""]
                    if let store = self?.store {
                        status["jobs"] = store.jobs.map { ["id": $0.id.uuidString, "state": $0.state.rawValue, "conversation": $0.conversationID ?? "", "error": $0.error ?? "", "results": String($0.results.count), "reasoning": String($0.reasoning?.rawValue ?? -1), "appliedReasoning": String($0.appliedReasoning ?? -1), "response": $0.responseText ?? "", "continuationOf": $0.continuationOf?.uuidString ?? ""] }
                        status["assets"] = store.library.assets.count
                        status["favorites"] = store.library.assets.filter(\.isFavorite).count
                        status["paused"] = store.journal.paused
                        status["error"] = store.errorMessage ?? ""
                        status["notice"] = store.notice ?? ""
                        status["storageReady"] = store.storageReady
                        status["restoringAssets"] = store.restoringAssets
                    }
                    status["workers"] = self?.engine?.workers.count ?? 0
                    status["connectionBrowserLoaded"] = session.browser != nil
                    if let data = try? JSONSerialization.data(withJSONObject: status, options: .prettyPrinted) {
                        try? data.write(to: directory.appendingPathComponent("status.json"), options: .atomic)
                    }
                }
                if let self { await self.processCommand(directory) }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { store?.flush(); return .terminateNow }
}
