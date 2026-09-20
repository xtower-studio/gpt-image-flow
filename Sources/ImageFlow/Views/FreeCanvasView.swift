import SwiftUI
import FlowCore

struct FreeCanvasView: View {
    let project: Project
    let assets: [Asset]
    let jobs: [Job]
    @Binding var selection: Set<UUID>
    var preview: (Asset) -> Void
    var edit: (Asset) -> Void
    var openJob: (Job) -> Void
    @Environment(WorkspaceStore.self) private var store
    @State private var viewport = CanvasViewport()
    @State private var panStart: CanvasViewport?
    @State private var zoomStart: Double?
    @State private var moving: [String: CanvasPoint] = [:]
    @State private var moveOrigins: [String: CanvasPoint] = [:]
    @State private var showHelp = false
    @AppStorage("canvasShowsConnections") private var showConnections = true
    @State private var viewportSave: Task<Void, Never>?
    private let width = 244.0, height = 342.0
    struct Node: Identifiable {
        let id: UUID
        var asset: Asset?
        var job: Job?
    }
    var nodes: [Node] {
        assets.map { Node(id: $0.id, asset: $0) } + jobs.filter { $0.state != .saved && $0.state != .cancelled && $0.results.isEmpty }.map { Node(id: $0.id, job: $0) }
    }
    func point(_ node: Node) -> CanvasPoint {
        if let value = moving[node.id.uuidString] { return value }
        if let value = project.layout?[node.id.uuidString] { return value }
        if let jobID = node.asset?.jobID, let value = project.layout?[jobID.uuidString] { return value }
        let index = nodes.firstIndex { $0.id == node.id } ?? 0
        return CanvasPoint(x: Double(index % 4) * (width + 60), y: Double(index / 4) * (height + 65))
    }
    func center(_ point: CanvasPoint) -> CGPoint {
        CGPoint(x: (point.x + width/2)*viewport.scale+viewport.x, y: (point.y+height/2)*viewport.scale+viewport.y)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                StudioPalette.stage.contentShape(Rectangle())
                    .onTapGesture { selection = [] }
                    .gesture(DragGesture().onChanged { value in
                        if panStart == nil { panStart = viewport }
                        viewport.x = (panStart?.x ?? 0) + value.translation.width
                        viewport.y = (panStart?.y ?? 0) + value.translation.height
                    }.onEnded { _ in panStart = nil; saveViewport() })
                Canvas { context, size in
                    let spacing = max(14, 24 * viewport.scale)
                    let offsetX = viewport.x.truncatingRemainder(dividingBy: spacing)
                    let offsetY = viewport.y.truncatingRemainder(dividingBy: spacing)
                    for x in stride(from: offsetX, through: size.width, by: spacing) {
                        for y in stride(from: offsetY, through: size.height, by: spacing) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.secondary.opacity(0.16)))
                        }
                    }
                    for node in nodes where showConnections {
                        let job = node.job ?? jobs.first { $0.id == node.asset?.jobID }
                        let sources = Set((job?.referenceIDs ?? []) + (node.asset?.parentID.map { [$0] } ?? []) + (job?.continuationOf.map { [$0] } ?? []))
                        for id in sources {
                            guard let source = nodes.first(where: { $0.id == id }), source.id != node.id else { continue }
                            let a = center(point(source)), b = center(point(node))
                            var path = Path(); path.move(to: CGPoint(x: a.x+width*viewport.scale/2, y: a.y))
                            path.addCurve(to: CGPoint(x: b.x-width*viewport.scale/2, y: b.y),
                                control1: CGPoint(x: a.x+(width/2+65)*viewport.scale, y: a.y),
                                control2: CGPoint(x: b.x-(width/2+65)*viewport.scale, y: b.y))
                            context.stroke(path, with: .color(.accentColor.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5))
                        }
                    }
                }.allowsHitTesting(false)
                ForEach(nodes) { node in
                    let c = center(point(node))
                    if c.x > -width*viewport.scale && c.x < geometry.size.width+width*viewport.scale && c.y > -height*viewport.scale && c.y < geometry.size.height+height*viewport.scale {
                        nodeView(node).frame(width: width, height: height).scaleEffect(viewport.scale)
                            .position(c).zIndex(selection.contains(node.id) ? 2 : 1)
                    }
                }
                if nodes.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.dashed").font(.largeTitle)
                        Text("아이디어를 자유롭게 펼쳐 보세요").font(.headline)
                        Text("오른쪽 참조 영역에 이미지를 놓고 첫 시안을 생성하세요.").font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                }
            }.background {
                CanvasScrollBridge(pan: { x, y in viewport.x += x; viewport.y += y; scheduleViewportSave() }, zoom: { factor in zoom(factor, size: geometry.size, save: false); scheduleViewportSave() })
            }.clipped().overlay(alignment: .bottomLeading) {
                HStack(spacing: 12) {
                    Button { zoom(0.8, size: geometry.size) } label: { Image(systemName: "minus.magnifyingglass") }.help("축소")
                    Text("\(Int(viewport.scale*100))%").monospacedDigit().font(.caption).frame(width: 40)
                    Button { zoom(1.25, size: geometry.size) } label: { Image(systemName: "plus.magnifyingglass") }.help("확대")
                    Divider().frame(height: 15)
                    Button("전체 보기") { fit(geometry.size) }.help("모든 카드를 화면에 맞추기")
                        .contextMenu {
                            Button("선택한 카드에 맞추기") { fit(geometry.size, positions: nodes.filter { selection.contains($0.id) }.map(point)) }.disabled(selection.isEmpty)
                            Button("100% 보기") { zoom(1 / viewport.scale, size: geometry.size) }
                        }
                    Button("정렬") { let positions = arrange(); fit(geometry.size, positions: positions) }.help("카드를 격자로 정렬 · ⌘Z로 되돌리기")
                    Toggle(isOn: $showConnections) { Image(systemName: "point.3.connected.trianglepath.dotted") }.toggleStyle(.button).help("참조 연결선 표시")
                    StudioIconButton(symbol: "questionmark.circle", label: "캔버스 조작 안내") { showHelp.toggle() }
                        .popover(isPresented: $showHelp) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("캔버스 조작").font(.headline)
                                Text("이동     두 손가락 스크롤 또는 빈 곳 드래그")
                                Text("배치     카드 상단 드래그 · ⌘클릭으로 여러 개 선택")
                                Text("확대     트랙패드 핀치 또는 ⌘ + 스크롤")
                                Text("첨부     이미지를 오른쪽 참조 영역으로 드래그")
                            }.font(.system(size: 13)).padding(20)
                        }
                }.buttonStyle(.borderless).padding(.horizontal, 14).padding(.vertical, 8).studioGlass(cornerRadius: 24).padding(16)
            }
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                if zoomStart == nil { zoomStart = viewport.scale }
                let newScale = min(2, max(0.01, (zoomStart ?? 1)*value))
                zoom(newScale/viewport.scale, size: geometry.size, save: false)
            }.onEnded { _ in zoomStart = nil; saveViewport() })
            .onDisappear { viewportSave?.cancel(); saveViewport() }
            .onAppear { viewport = project.viewport ?? CanvasViewport(scale: 0.8) }
            .onChange(of: project.viewport) { _, value in if let value, value != viewport { viewport = value } }
        }
    }
    func nodeView(_ node: Node) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "circle.grid.2x2.fill").foregroundStyle(.tertiary)
                Text(node.asset?.isReference == true ? "참조 이미지" : node.job != nil ? "생성 작업" : "이미지").font(.caption)
                Spacer()
                if let asset = node.asset, !asset.isReference {
                    Text(asset.actualModelLabel).font(.caption2).foregroundStyle(.secondary)
                } else if let job = node.job {
                    Text("\(job.requestModeLabel) · \(job.expectedImageCount)장").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 12).frame(height: 30).background(.quaternary.opacity(0.2)).contentShape(Rectangle())
                .gesture(moveGesture(node))
            if let asset = node.asset {
                AssetTile(asset: asset, selected: selection.contains(asset.id), preview: { preview(asset) }, edit: { edit(asset) }, attach: { store.attach(asset, to: project.id) }, compact: true)
                    .padding(10).onTapGesture(count: 2) { preview(asset) }.onTapGesture { select(node.id) }
            } else if let job = node.job {
                VStack(alignment: .leading, spacing: 12) {
                    Label(job.state.label, systemImage: job.state.isRunning ? "sparkles" : job.state == .responded ? "text.bubble" : job.state.needsAttention ? "exclamationmark.triangle" : "clock")
                        .font(.headline).foregroundStyle(job.state == .failed || job.state == .needsReview ? Color.orange : Color.primary)
                    if job.state.isRunning { ProgressView().controlSize(.small) }
                    Text(job.responseText ?? job.error ?? job.prompt).font(.callout).lineLimit(8).textSelection(.enabled)
                    Spacer(minLength: 0)
                    if job.state.needsAttention { Button(job.state == .responded ? "답변 보기 · 이어서 요청" : "상태 보기") { openJob(job) }.buttonStyle(.bordered) }
                    else { Text(job.label).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Spacer(minLength: 0)
        }.background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(selection.contains(node.id) ? Color.accentColor : Color.primary.opacity(0.13), lineWidth: selection.contains(node.id) ? 2 : 1) }
            .clipShape(RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
    func moveGesture(_ node: Node) -> some Gesture {
        DragGesture(minimumDistance: 2).onChanged { value in
            if moveOrigins.isEmpty {
                if !selection.contains(node.id) { selection = [node.id] }
                for item in nodes where selection.contains(item.id) { moveOrigins[item.id.uuidString] = point(item) }
            }
            for (key, origin) in moveOrigins {
                moving[key] = CanvasPoint(x: origin.x + value.translation.width/viewport.scale, y: origin.y + value.translation.height/viewport.scale)
            }
        }.onEnded { _ in store.setCanvasPositions(moving, projectID: project.id, undoable: true); moving = [:]; moveOrigins = [:] }
    }
    func select(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else { selection = [id] }
    }
    func zoom(_ factor: Double, size: CGSize, save: Bool = true) {
        let center = viewport.world(x: size.width/2, y: size.height/2)
        viewport.scale = min(2, max(0.01, viewport.scale*factor))
        viewport.x = size.width/2-center.x*viewport.scale; viewport.y = size.height/2-center.y*viewport.scale
        if save { saveViewport() }
    }
    func scheduleViewportSave() {
        viewportSave?.cancel()
        viewportSave = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(300)); saveViewport() } catch { }
        }
    }
    func saveViewport() { store.setViewport(viewport, projectID: project.id) }
    func arrange() -> [CanvasPoint] {
        var positions: [String: CanvasPoint] = [:]
        for (index,node) in nodes.enumerated() { positions[node.id.uuidString] = CanvasPoint(x: Double(index%4)*(width+60), y: Double(index/4)*(height+65)) }
        store.setCanvasPositions(positions, projectID: project.id, undoable: true)
        return Array(positions.values)
    }
    func fit(_ size: CGSize, positions: [CanvasPoint]? = nil) {
        guard !nodes.isEmpty else { viewport = CanvasViewport(); saveViewport(); return }
        let points = positions ?? nodes.map(point)
        guard !points.isEmpty else { return }
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!+width
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!+height
        viewport.scale = max(0.01, min(1.1, min((size.width-80)/(maxX-minX), (size.height-100)/(maxY-minY))))
        viewport.x = (size.width-(maxX-minX)*viewport.scale)/2-minX*viewport.scale
        viewport.y = 25-minY*viewport.scale; saveViewport()
    }
}
