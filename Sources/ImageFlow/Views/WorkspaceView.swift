import SwiftUI
import FlowCore

struct WorkspaceView: View {
    @Environment(WorkspaceStore.self) private var store
    @SceneStorage("selectedProject") private var selectedProject = ""
    @AppStorage("lastSelectedProject") private var lastSelectedProject = ""
    @AppStorage("studioBoardMode") private var boardMode = "grid"
    @SceneStorage("studioPanelVisible") private var panelVisible = true
    @State private var selection = Set<UUID>()
    @State private var query = ""
    @State private var searchPresented = false
    @State private var favoritesOnly = false
    @State private var comparison: [Asset]?
    @State private var editing: Asset?
    @SceneStorage("studioEditDrafts") private var editDraftData = Data()
    private var editPrompt: Binding<String> {
        let key = editing?.id.uuidString ?? ""
        return Binding(get: { (try? JSONDecoder().decode([String: String].self, from: editDraftData))?[key] ?? "" }, set: { value in
            var drafts = (try? JSONDecoder().decode([String: String].self, from: editDraftData)) ?? [:]
            if value.isEmpty { drafts.removeValue(forKey: key) } else { drafts[key] = value }
            editDraftData = (try? JSONEncoder().encode(drafts)) ?? Data()
        })
    }
    @AppStorage("studioCardSize") private var cardSize = 225.0
    @State private var panel = StudioPanelTab.create
    @State private var responseJobID: UUID?
    @State private var focusRequest = 0
    @State private var showHelp = false
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    private enum RenameTarget { case project(Project), asset(Asset) }
    var project: Project? { store.project(UUID(uuidString: selectedProject)) ?? store.library.projects.first }
    var selectedAssets: [Asset] { assets.filter { selection.contains($0.id) } }
    var allAssets: [Asset] {
        let order = Dictionary(uniqueKeysWithValues: store.jobs.enumerated().map { ($0.element.id, $0.offset) })
        return store.library.assets.filter { $0.projectID == project?.id && !$0.isReference && !(store.library.hiddenAssetIDs ?? []).contains($0.id) }.sorted {
            let a = $0.jobID.flatMap { order[$0] } ?? Int.max, b = $1.jobID.flatMap { order[$0] } ?? Int.max
            return a == b ? $0.createdAt < $1.createdAt : a < b
        }
    }
    var assets: [Asset] { allAssets.filter(matches) }
    var projectJobs: [Job] { store.jobs.filter { $0.projectID == project?.id && $0.state != .cancelled } }
    var body: some View {
        NavigationSplitView {
            WorkspaceSidebar(selectedProject: $selectedProject, currentID: project?.id, onSelect: resetSelection, rename: { renameText = $0.name; renameTarget = .project($0) }, addProject: newProject)
                .navigationSplitViewColumnWidth(min: 175, ideal: 200, max: 280)
        } detail: {
            StudioGlassGroup {
                VStack(spacing: 0) {
                    if let project {
                        activityStrip
                        board(project)
                        footer
                    } else { ContentUnavailableView("저장 공간을 확인해 주세요", systemImage: "externaldrive.badge.exclamationmark", description: Text(store.errorMessage ?? "")) }
                }
                .background(StudioPalette.stage)
                .overlay(alignment: .bottom) { notice }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .navigationTitle(project?.name ?? "프로젝트")
            .navigationSubtitle("\(allAssets.count)개 이미지")
            .searchable(text: $query, isPresented: $searchPresented, placement: .toolbar, prompt: "이미지 검색")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("보기 방식", selection: $boardMode) {
                        Label("컬렉션", systemImage: "square.grid.2x2").tag("grid")
                        Label("캔버스", systemImage: "square.dashed").tag("canvas")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 76).help("컬렉션 ⌘1 · 캔버스 ⌘2")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { favoritesOnly.toggle() } label: { Label("후보만 보기", systemImage: favoritesOnly ? "star.fill" : "star") }.help("후보만 보기").tint(favoritesOnly ? .accentColor : nil)
                }
                if #available(macOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: startCreate) { Label("만들기", systemImage: "square.and.pencil") }.help("새 이미지 만들기 · ⇧⌘N")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { panelVisible.toggle() } label: { Label("작업 패널", systemImage: "sidebar.right") }.help("작업 패널 표시 / 가리기 · ⌥⌘I")
                }
            }
            .inspector(isPresented: $panelVisible) {
                if let project {
                    StudioPanel(project: project, tab: $panel, editing: $editing, editPrompt: editPrompt, selectedAssets: selectedAssets, responseJobID: $responseJobID, focusRequest: focusRequest, edit: beginEdit, reuse: reuse)
                        .id(project.id).inspectorColumnWidth(min: 300, ideal: 340, max: 430)
                }
            }
        }
        .focusedSceneValue(\.studioActions, actions)
        .sheet(isPresented: Binding(get: { comparison != nil }, set: { if !$0 { comparison = nil } })) {
            if let comparison { CompareView(assets: comparison).environment(store) }
        }
        .sheet(isPresented: $showHelp) { StudioHelpView() }
        .alert("이름 변경", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("이름", text: $renameText)
            Button("저장", action: commitRename).disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("취소", role: .cancel) { renameTarget = nil }
        } message: { Text("이름을 입력해 주세요.") }
        .alert("작업을 완료하지 못했습니다", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("확인") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .task(id: store.notice) {
            guard let value = store.notice, store.lastHiddenAssets.isEmpty else { return }
            do { try await Task.sleep(for: .seconds(5)); if store.notice == value { store.notice = nil } } catch { }
        }
        .onAppear { if selectedProject.isEmpty { selectedProject = lastSelectedProject } }
        .onChange(of: selectedProject) { _, value in lastSelectedProject = value; resetSelection() }
        .onChange(of: query) { _, _ in selection.formIntersection(Set(assets.map(\.id))) }
        .onChange(of: favoritesOnly) { _, _ in selection.formIntersection(Set(assets.map(\.id))) }
        .onChange(of: store.requestedProjectID) { _, value in if let value { selectedProject = value.uuidString; store.requestedProjectID = nil } }
        .onChange(of: store.requestedJobID) { _, value in if let value, let job = store.jobs.first(where: { $0.id == value }) { openJob(job); store.requestedJobID = nil } }
        .onChange(of: store.requestedComparison) { _, value in if !value.isEmpty { comparison = value.compactMap { store.asset($0) }; store.requestedComparison = [] } }
        .onChange(of: store.requestedInspectorAsset) { _, value in
            guard let value, let asset = store.asset(value) else { return }
            selectedProject = asset.projectID.uuidString; store.requestedInspectorAsset = nil
            Task { @MainActor in await Task.yield(); selection = [value]; panel = .details; panelVisible = true }
        }
    }
    @ViewBuilder private func board(_ project: Project) -> some View {
        Group {
            if boardMode == "canvas" {
                FreeCanvasView(project: project, assets: canvasAssets(project), jobs: projectJobs, selection: $selection, preview: { comparison = [$0] }, edit: beginEdit, openJob: openJob).id(project.id)
            } else if assets.isEmpty {
                EmptyStudioView(filtered: favoritesOnly || !query.isEmpty, running: projectJobs.contains { $0.state.isRunning || $0.state == .queued }, create: startCreate, importImages: { store.selectImages(projectID: project.id) }, clear: { query = ""; favoritesOnly = false })
            } else {
                NativeImageCollection(assets: assets, store: store, cardSize: cardSize, selection: $selection, preview: { comparison = Array($0.prefix(4)) }, edit: beginEdit, inspect: { panel = .details; panelVisible = true }, attach: { store.attach($0, to: project.id); panel = .create; panelVisible = true }, rename: renameAsset, hide: hideAssets)
            }
        }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity).background(StudioPalette.stage)
    }
    @ViewBuilder private var activityStrip: some View {
        let active = projectJobs.filter { $0.state.isRunning || $0.state == .queued }
        let attention = projectJobs.filter { job in job.showsAttention && !store.jobs.contains { $0.continuationOf == job.id && $0.state != .cancelled } }
        if !active.isEmpty || !attention.isEmpty || favoritesOnly {
            HStack(spacing: 8) {
                if !active.isEmpty { ProgressView().controlSize(.small); Text("\(active.count)개 작업 진행 중").fontWeight(.medium) }
                else if favoritesOnly { Label("후보 \(assets.count)개", systemImage: "star.fill") }
                else {
                    let failures = attention.filter { $0.state != .responded }.count
                    Label(failures > 0 ? "확인 필요 \(failures)개" + (attention.count > failures ? " · 새 답변 \(attention.count - failures)개" : "") : "새 답변 \(attention.count)개", systemImage: failures > 0 ? "exclamationmark.circle" : "text.bubble")
                        .foregroundStyle(failures > 0 ? Color.orange : .secondary)
                }
                Spacer()
                if let job = attention.last {
                    Button(attention.count > 1 ? "작업 보기" : job.state == .responded ? "답변 보기" : "상태 확인") {
                        if attention.count == 1 { openJob(job) } else { responseJobID = nil; panel = .reply; panelVisible = true }
                    }.buttonStyle(.borderless)
                }
                Button { responseJobID = nil; panel = .reply; panelVisible = true } label: { Image(systemName: "clock.arrow.circlepath") }.buttonStyle(.borderless).help("전체 작업 기록")
                if !attention.isEmpty {
                    Button { store.dismissAttention(Set(attention.map(\.id))) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("확인 알림 닫기 · 작업 기록은 유지됩니다").accessibilityLabel("확인 알림 닫기")
                }
            }.font(StudioTypography.supporting).padding(.horizontal, 20).frame(height: 36).background(.bar)
            Divider()
        }
    }
    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 14) {
                Text(selection.isEmpty ? "\(assets.count)개 이미지" : "\(selectedAssets.count)개 선택")
                    .foregroundStyle(.secondary).monospacedDigit()
                if selectedAssets.count == 1 { Button("수정") { if let first = selectedAssets.first { beginEdit(first) } }.help("선택한 이미지 수정 · ⌘E") }
                if (2...4).contains(selectedAssets.count) { Button("비교") { comparison = selectedAssets }.help("나란히 비교 · ⇧⌘C") }
                if !selectedAssets.isEmpty {
                    Divider().frame(height: 16)
                    Button { panel = .details; panelVisible = true } label: { Image(systemName: "info.circle") }.help("선택 정보")
                    Button { store.export(selectedAssets) } label: { Image(systemName: "square.and.arrow.up") }.help("내보내기 · ⇧⌘E")
                }
            }.padding(.horizontal, 16).frame(height: 36).studioGlass()
            Spacer(minLength: 0)
            if boardMode == "grid" {
                HStack(spacing: 10) {
                    Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: $cardSize, in: 170...320).frame(width: 80).controlSize(.small).accessibilityLabel("이미지 크기")
                    Image(systemName: "photo").font(.system(size: 15)).foregroundStyle(.secondary)
                }.padding(.horizontal, 14).frame(height: 36).studioGlass()
            }
        }.buttonStyle(.borderless).font(StudioTypography.supporting).padding(.horizontal, 16).padding(.vertical, 10)
    }
    @ViewBuilder private var notice: some View {
        if let text = store.notice {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text(text).font(StudioTypography.supporting).lineLimit(3)
                if !store.lastHiddenAssets.isEmpty { Button("되돌리기", action: store.undoHide) }
                Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("알림 닫기")
            }.padding(.horizontal, 16).padding(.vertical, 12).studioGlass(cornerRadius: 20).frame(maxWidth: 480).padding(.bottom, 66).padding(.horizontal, 20)
        }
    }
    private var actions: StudioActions {
        StudioActions(selectedCount: selectedAssets.count, search: { searchPresented = true }, inspect: { panel = .details; panelVisible = true }, newProject: newProject, importImages: { if let project { store.selectImages(projectID: project.id) } }, preview: { if !selectedAssets.isEmpty { comparison = Array(selectedAssets.prefix(4)) } }, compare: { comparison = selectedAssets }, edit: { if let first = selectedAssets.first { beginEdit(first) } }, export: { store.export(selectedAssets) }, favorite: { for asset in selectedAssets { store.toggleFavorite(asset) } }, hide: { hideAssets(selectedAssets) }, rename: { if let asset = selectedAssets.first { renameAsset(asset) } }, showGrid: { boardMode = "grid" }, showCanvas: { boardMode = "canvas" }, toggleInspector: { panelVisible.toggle() }, create: startCreate, showHelp: { showHelp = true })
    }
    private func matches(_ asset: Asset) -> Bool { (!favoritesOnly || asset.isFavorite) && (query.isEmpty || asset.title.localizedCaseInsensitiveContains(query) || store.jobs.first(where: { $0.id == asset.jobID })?.prompt.localizedCaseInsensitiveContains(query) == true) }
    private func canvasAssets(_ project: Project) -> [Asset] { store.library.assets.filter { ($0.projectID == project.id || project.referenceIDs.contains($0.id)) && !(store.library.hiddenAssetIDs ?? []).contains($0.id) && matches($0) } }
    private func resetSelection() { selection = []; editing = nil; responseJobID = nil; panel = .create; query = ""; favoritesOnly = false }
    private func showComposer() { panel = .create; panelVisible = true; focusRequest += 1 }
    private func startCreate() { editing = nil; showComposer() }
    private func beginEdit(_ asset: Asset) { editing = asset; showComposer() }
    private func newProject() { selectedProject = store.addProject().uuidString; if let project = store.project(UUID(uuidString: selectedProject)) { renameText = ""; renameTarget = .project(project) } }
    private func renameAsset(_ asset: Asset) { renameText = asset.title; renameTarget = .asset(asset) }
    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let target = renameTarget else { return }
        switch target { case .project(var project): project.name = name; store.updateProject(project)
        case .asset(var asset): asset.title = name; store.upsert(asset); store.flush() }
        renameTarget = nil
    }
    private func hideAssets(_ assets: [Asset]) {
        guard !assets.isEmpty else { return }
        store.hideAssets(assets.map(\.id)); selection = []
    }
    private func openJob(_ job: Job) { selectedProject = job.projectID.uuidString; Task { @MainActor in await Task.yield(); responseJobID = job.id; panel = .reply; panelVisible = true } }
    private func reuse(_ job: Job) {
        guard var project else { return }
        project.prompt = job.prompt; project.variations = ""; project.copies = 1; project.referenceIDs = job.referenceIDs; project.reasoning = job.reasoning
        project.prompt = job.inputPrompt ?? job.prompt
        project.aspect = job.requestedAspect ?? "자유"; project.background = job.requestedBackground
        if let mode = job.generationMode { store.selectedGenerationMode = mode }
        store.updateProject(project); editing = nil; startCreate()
    }
}
