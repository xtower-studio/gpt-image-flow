import SwiftUI
import FlowCore

struct WorkflowCanvasView: View {
    let project: Project
    let assets: [Asset]
    let jobs: [Job]
    @Binding var selection: Set<UUID>
    var preview: (Asset) -> Void
    var edit: (Asset) -> Void
    var openJob: (Job) -> Void
    @Environment(WorkspaceStore.self) var store
    @Environment(WebSession.self) var session
    @State var viewport = CanvasViewport(scale: 0.8)
    @State var panOrigin: CanvasViewport?
    @State var moving: [UUID: CanvasPoint] = [:]
    @State var moveOrigins: [UUID: CanvasPoint] = [:]
    @State var selectedNode: UUID?
    @State var connecting: UUID?
    @State var connectionPoint: CGPoint?
    @State var showAssets = false
    @State var showRun = false
    @State var showAPIConnection = false
    @State var runOnly: UUID?
    @State var legacy = false
    @State var zoomStart: Double?
    @State var saveTask: Task<Void, Never>?
    var graph: WorkflowGraph { store.project(project.id)?.workflow ?? WorkflowGraph() }
    var busy: Bool { store.workflowBusy(project.id) }
    var latestRun: WorkflowRun? { store.latestWorkflowRun(project.id) }
    var body: some View {
        if legacy {
            FreeCanvasView(project: project, assets: assets, jobs: jobs, selection: $selection, preview: preview, edit: edit, openJob: openJob)
                .overlay(alignment: .topLeading) { Button("노드 워크플로로 돌아가기") { legacy = false }.buttonStyle(.bordered).padding(16) }
        } else {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    StudioPalette.stage.contentShape(Rectangle()).onTapGesture { selectedNode = nil; connecting = nil }
                        .gesture(DragGesture().onChanged { value in
                            if panOrigin == nil { panOrigin = viewport }
                            viewport.x = (panOrigin?.x ?? 0) + value.translation.width
                            viewport.y = (panOrigin?.y ?? 0) + value.translation.height
                        }.onEnded { _ in panOrigin = nil; saveViewport() })
                    connections
                    ForEach(graph.nodes) { node in
                        let p = screen(point(node)), h = WorkflowNodeCard.height(node.kind)
                        if p.x + WorkflowNodeCard.width * viewport.scale > -50 && p.x < geometry.size.width + 50 && p.y + h * viewport.scale > -50 && p.y < geometry.size.height + 50 {
                            card(node).frame(width: WorkflowNodeCard.width, height: h)
                                .scaleEffect(viewport.scale, anchor: .topLeading)
                                .offset(x: p.x, y: p.y).zIndex(selectedNode == node.id ? 2 : 1)
                        }
                    }
                    if graph.nodes.isEmpty { welcome(size: geometry.size) }
                }.coordinateSpace(name: "workflow").clipped()
                    .background {
                        CanvasScrollBridge(pan: { x, y in viewport.x += x; viewport.y += y; scheduleSave() }, zoom: { factor in zoom(factor, size: geometry.size); scheduleSave() }, ignoresPanAt: { location in
                            graph.nodes.contains { node in
                                let origin = screen(point(node))
                                return CGRect(x: origin.x, y: origin.y, width: WorkflowNodeCard.width * viewport.scale, height: WorkflowNodeCard.height(node.kind) * viewport.scale).contains(location)
                            }
                        })
                    }
                    .dropDestination(for: URL.self) { urls, location in
                        let files = urls.filter(\.isFileURL); guard !files.isEmpty else { return false }
                        store.importWorkflowReference(files, projectID: project.id, position: viewport.world(x: location.x, y: location.y)); return true
                    }
                    .overlay(alignment: .topLeading) { toolbar(size: geometry.size).padding(16) }
                    .overlay(alignment: .bottomLeading) { navigation(size: geometry.size).padding(16) }
                    .simultaneousGesture(MagnificationGesture().onChanged { value in
                        if zoomStart == nil { zoomStart = viewport.scale }
                        zoom(min(1.5, max(0.2, (zoomStart ?? 1) * value)) / viewport.scale, size: geometry.size)
                    }.onEnded { _ in zoomStart = nil; saveViewport() })
                    .onAppear { viewport = graph.viewport }
                    .onDisappear { saveTask?.cancel(); if !graph.nodes.isEmpty { saveViewport() } }
                    .sheet(isPresented: $showRun) { runReview }
            }
        }
    }
    func card(_ node: WorkflowNode) -> some View {
        WorkflowNodeCard(projectID: project.id, node: node, graph: graph, busy: busy, selected: selectedNode == node.id,
            move: { delta, ended in move(node, delta: delta, ended: ended) }, select: { selectedNode = node.id },
            run: { runOnly = node.id; showRun = true }, branch: { branch(node) }, duplicate: { duplicate(node) },
            remove: { store.changeWorkflow(project.id, undoable: true) { $0.remove(node.id) } }, preview: preview, openJob: openJob)
            .overlay(alignment: .topLeading) {
                if node.kind == .generation {
                    VStack(alignment: .leading, spacing: 2) {
                        input(node, port: .prompt)
                        input(node, port: .image)
                    }.offset(x: -7, y: 43)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 5) {
                    Text(node.outputPort == .prompt ? "프롬프트" : "이미지").font(.system(size: 10)).foregroundStyle(.secondary)
                    Button { connecting = connecting == node.id ? nil : node.id; connectionPoint = nil } label: {
                        Circle().fill(portColor(node.outputPort)).frame(width: 14, height: 14)
                            .overlay { Circle().stroke(.background, lineWidth: 2) }
                    }.buttonStyle(.plain).help("드래그하거나 클릭한 뒤 다음 단계의 입력을 클릭하세요")
                        .accessibilityLabel("\(node.title) 출력 연결").accessibilityIdentifier("workflow-output-\(node.id)")
                        .simultaneousGesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("workflow")).onChanged { value in
                            guard !busy else { return }; connecting = node.id; connectionPoint = value.location
                        }.onEnded { value in
                            guard !busy else { return }
                            let candidates = graph.nodes.filter { $0.kind == .generation && $0.id != node.id }
                            if let target = candidates.first(where: { target in
                                let p = inputPoint(target, port: node.outputPort)
                                return hypot(p.x - value.location.x, p.y - value.location.y) < max(24, 30 * viewport.scale)
                            }) { connect(node.id, to: target.id) }
                            connecting = nil; connectionPoint = nil
                        })
                        .disabled(busy)
                }.offset(x: 7, y: 47)
            }
    }
    func input(_ node: WorkflowNode, port: WorkflowPort) -> some View {
        HStack(spacing: 5) {
            Button {
                if let connecting { connect(connecting, to: node.id, port: port) }
            } label: { Circle().strokeBorder(portColor(port), lineWidth: 2).background(Circle().fill(.background)).frame(width: 14, height: 14) }
                .buttonStyle(.plain).disabled(busy).help("출력 점을 클릭한 뒤 여기를 클릭해 연결")
                .accessibilityLabel("\(node.title) \(port == .prompt ? "프롬프트" : "이미지") 입력").accessibilityIdentifier("workflow-input-\(port.rawValue)-\(node.id)")
            Menu {
                let sources = graph.nodes.filter { $0.id != node.id && $0.outputPort == port }
                if sources.isEmpty { Text(port == .prompt ? "공통 프롬프트 노드를 추가하세요" : "참조 또는 생성 노드를 추가하세요") }
                ForEach(sources) { source in
                    if let edge = graph.edges.first(where: { $0.source == source.id && $0.target == node.id }) {
                        Button("연결 해제 · " + source.title) { store.changeWorkflow(project.id, undoable: true) { $0.edges.removeAll { $0.id == edge.id } } }
                    } else { Button(source.title) { connect(source.id, to: node.id) } }
                }
            } label: {
                let count = graph.edges.filter { $0.target == node.id && $0.port == port }.count
                Text((port == .prompt ? "공통 지시" : "참조") + (count == 0 ? " +" : " \(count)"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(busy)
        }.frame(height: 24)
    }
    var connections: some View {
        Canvas { context, size in
            let spacing = max(14, 24 * viewport.scale)
            for x in stride(from: viewport.x.truncatingRemainder(dividingBy: spacing), through: size.width, by: spacing) {
                for y in stride(from: viewport.y.truncatingRemainder(dividingBy: spacing), through: size.height, by: spacing) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.3, height: 1.3)), with: .color(.secondary.opacity(0.16)))
                }
            }
            for edge in graph.edges {
                guard let source = graph.node(edge.source), let target = graph.node(edge.target) else { continue }
                context.stroke(curve(outputPoint(source), inputPoint(target, port: edge.port)), with: .color(portColor(edge.port).opacity(0.65)), style: StrokeStyle(lineWidth: 2))
            }
            if let connecting, let source = graph.node(connecting), let connectionPoint {
                context.stroke(curve(outputPoint(source), connectionPoint), with: .color(portColor(source.outputPort)), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }.allowsHitTesting(false)
    }
    func toolbar(size: CGSize) -> some View {
        HStack(spacing: 12) {
            Menu {
                Button("공통 프롬프트") { add(.prompt, size: size) }
                Button("생성 단계") { add(.generation, size: size) }
                Button("참조 이미지 가져오기…") { importReference(size: size) }
                Button("프로젝트 이미지에서 선택…") { showAssets = true }
            } label: { Label("노드 추가", systemImage: "plus") }.disabled(busy).accessibilityIdentifier("workflow-add")
            Divider().frame(height: 18)
            if latestRun?.state == .paused {
                Button("실행 계속") { store.resumeWorkflow(project.id); if session.status != .ready { session.connect() } }
            } else {
                Button { runOnly = nil; showRun = true } label: { Label("흐름 실행", systemImage: "play.fill") }
                    .disabled(busy || !graph.nodes.contains { $0.kind == .generation }).accessibilityIdentifier("workflow-run-all")
            }
            if latestRun?.state == .running || latestRun?.state == .paused { Button("후속 중단") { store.stopWorkflow(project.id) } }
            Menu {
                Button("흐름 정렬") { store.changeWorkflow(project.id, undoable: true) { try? $0.arrange() }; fit(size) }.disabled(graph.nodes.isEmpty)
                Button("프로젝트로 복제") { copyWorkflow() }.disabled(graph.nodes.isEmpty)
                Divider()
                Button("이전 이미지 배치 보기") { legacy = true }
            } label: { Image(systemName: "ellipsis") }.menuIndicator(.hidden).fixedSize()
        }.font(StudioTypography.control).buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10).studioGlass(cornerRadius: 20)
            .popover(isPresented: $showAssets) { assetPicker(size: size) }
    }
    func navigation(size: CGSize) -> some View {
        HStack(spacing: 10) {
            Button { zoom(0.8, size: size); saveViewport() } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int(viewport.scale * 100))%").monospacedDigit().frame(width: 40)
            Button { zoom(1.25, size: size); saveViewport() } label: { Image(systemName: "plus.magnifyingglass") }
            Divider().frame(height: 16)
            Button("전체 보기") { fit(size) }.accessibilityIdentifier("workflow-fit")
            if connecting != nil { Text("연결할 입력을 클릭하세요").foregroundStyle(Color.accentColor); Button("취소") { connecting = nil } }
            else if busy { Text(latestRun?.state == .paused ? "재시작 후 일시정지" : latestRun?.state == .stopped ? "후속 중단됨 · 전송한 작업 완료 대기" : "실행 중 · 결과 선택 시 다음 단계 진행").foregroundStyle(.secondary).lineLimit(1) }
            else if let run = latestRun {
                Text(run.state == .completed ? "\(run.steps.count)개 단계 완료" : "실행 기록 보존됨").foregroundStyle(.secondary)
            }
        }.font(StudioTypography.metadata).buttonStyle(.borderless).padding(.horizontal, 14).padding(.vertical, 10).studioGlass(cornerRadius: 20)
    }
    func welcome(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 30)).foregroundStyle(Color.accentColor)
            Text("좋은 결과를, 다음 작업의 출발점으로").font(StudioTypography.title)
            Text("공통 지시와 참조를 연결하고, 결과를 골라 새 방향으로 분기하세요. 각 단계의 설정과 생성 기록은 이곳에 남습니다.")
                .font(StudioTypography.body).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("현재 설정으로 시작") { seed(branching: false); fit(size) }.buttonStyle(.borderedProminent).accessibilityIdentifier("workflow-seed")
                Button("분기 워크플로 만들기") { seed(branching: true); fit(size) }.buttonStyle(.bordered)
            }
            Text("이미지 파일을 캔버스에 놓으면 참조 노드가 됩니다.\n출력 점을 입력 점으로 드래그하거나 순서대로 클릭해 연결합니다.")
                .font(StudioTypography.supporting).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(28).frame(width: 460).panelSurface()
            .position(x: size.width / 2, y: size.height / 2)
    }
    func assetPicker(size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("참조로 사용할 이미지").font(StudioTypography.section)
            if assets.isEmpty { Text("프로젝트에 이미지가 없습니다. 파일을 캔버스에 놓아 주세요.").font(StudioTypography.supporting) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                    ForEach(assets) { asset in
                        Button {
                            var node = WorkflowNode(kind: .reference, title: asset.title, position: insertionPoint(size))
                            node.assetID = asset.id; store.changeWorkflow(project.id, undoable: true) { $0.nodes.append(node) }; showAssets = false
                        } label: { AssetThumbnail(url: store.vault.thumbnail(asset)).frame(height: 88).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).help(asset.title)
                    }
                }
            }
        }.padding(20).frame(width: 350, height: 320)
    }
    var runReview: some View {
        let nodes = graph.nodes.filter { $0.kind == .generation && (runOnly == nil || $0.id == runOnly) }
        let paid = nodes.filter { $0.settings.mode == .sunburstAPI }
        return VStack(alignment: .leading, spacing: 16) {
            Text(runOnly == nil ? "워크플로 실행" : "선택한 단계 실행").font(StudioTypography.title)
            Text("\(nodes.count)개 단계 · 최대 \(nodes.reduce(0) { $0 + $1.settings.imageCount })장").font(StudioTypography.section)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(nodes) { node in HStack { Text(node.title); Spacer(); Text("\(node.settings.mode.label) · \(node.settings.imageCount)장").foregroundStyle(.secondary) } }
                }.font(StudioTypography.supporting)
            }.frame(maxHeight: 180)
            Text(runOnly == nil ? "각 단계를 한 번씩 새로 실행합니다. 여러 결과가 나오면 사용할 이미지를 선택할 때까지 연결된 단계가 기다립니다. 실행 중 설정은 고정됩니다." : "앞 단계에서 선택한 결과를 재사용합니다. 다른 단계는 실행하지 않습니다.")
                .font(StudioTypography.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !paid.isEmpty {
                APIBillingNotice()
                if !store.apiConnection.ready { Button("OpenAI API 연결…") { showAPIConnection = true } }
            }
            HStack {
                Button("취소") { showRun = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(paid.isEmpty ? "실행 시작" : "API 유료 생성 포함 · 실행") {
                    do {
                        try store.startWorkflow(project.id, only: runOnly); showRun = false
                        if nodes.contains(where: { $0.settings.mode != .sunburstAPI }), session.status != .ready { session.connect() }
                    } catch { showRun = false; store.report(error) }
                }.buttonStyle(.borderedProminent).disabled(nodes.isEmpty || busy || (!paid.isEmpty && !store.apiConnection.ready)).accessibilityIdentifier("workflow-confirm-run")
            }
        }.padding(24).frame(width: 430)
            .sheet(isPresented: $showAPIConnection) { APIConnectionView() }
    }
}
