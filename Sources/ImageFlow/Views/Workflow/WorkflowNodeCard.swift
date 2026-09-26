import SwiftUI
import FlowCore

struct WorkflowNodeCard: View {
    let projectID: UUID
    let node: WorkflowNode
    let graph: WorkflowGraph
    let busy: Bool
    let selected: Bool
    var move: (CGSize, Bool) -> Void
    var select: () -> Void
    var run: () -> Void
    var branch: () -> Void
    var duplicate: () -> Void
    var remove: () -> Void
    var preview: (Asset) -> Void
    var openJob: (Job) -> Void
    @Environment(WorkspaceStore.self) private var store
    @State private var settings = false
    static let width = 280.0
    static func height(_ kind: WorkflowNodeKind) -> Double { switch kind { case .prompt: 240; case .reference: 300; case .generation: 510 } }
    private var job: Job? {
        if let step, let run = store.latestWorkflowRun(projectID), run.state == .running || run.state == .paused || step.error != nil {
            return store.jobs.first { $0.id == step.jobID }
        }
        return store.jobs.first { $0.id == node.lastJobID }
    }
    private var step: WorkflowStep? { store.latestWorkflowRun(projectID)?.steps.first { $0.nodeID == node.id } }
    private var text: Binding<String> { Binding(get: { store.project(projectID)?.workflow?.node(node.id)?.text ?? node.text }, set: { value in update { $0.text = value } }) }
    private func update(_ change: (inout WorkflowNode) -> Void) {
        store.changeWorkflow(projectID) { graph in if let index = graph.nodes.firstIndex(where: { $0.id == node.id }) { change(&graph.nodes[index]) } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "circle.grid.2x2.fill").foregroundStyle(.secondary)
                Text(node.title).font(StudioTypography.control).lineLimit(1)
                Spacer(minLength: 0)
                Menu {
                    Button("복제", action: duplicate).disabled(busy)
                    if node.kind == .generation { Button("결과에서 분기", action: branch).disabled(busy) }
                    Button("노드 삭제", role: .destructive, action: remove).disabled(busy)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }.padding(.horizontal, 14).frame(height: 38).background(.primary.opacity(0.035))
                .contentShape(Rectangle()).onTapGesture(perform: select)
                .gesture(DragGesture(minimumDistance: 3).onChanged { move($0.translation, false) }.onEnded { move($0.translation, true) })
            if node.kind == .generation { Color.clear.frame(height: 52) }
            else { Color.clear.frame(height: 26) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch node.kind {
                    case .prompt:
                        Text("연결된 단계에 공통으로 적용됩니다").font(StudioTypography.metadata).foregroundStyle(.secondary)
                        TextEditor(text: text).font(StudioTypography.body).scrollContentBackground(.hidden)
                            .frame(height: 112).padding(8).panelSurface(radius: 8, editor: true).disabled(busy)
                            .accessibilityIdentifier("workflow-prompt-\(node.id)")
                    case .reference:
                        if let id = node.assetID, let asset = store.asset(id) {
                            AssetThumbnail(url: store.vault.thumbnail(asset)).frame(height: 172).frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8)).onTapGesture(count: 2) { preview(asset) }
                            Text(asset.displayDetails).font(StudioTypography.metadata).foregroundStyle(.secondary)
                        } else { Label("참조 원본이 없습니다", systemImage: "photo.badge.exclamationmark").foregroundStyle(.orange) }
                    case .generation:
                        generationContent
                    }
                }.padding(.horizontal, 14).padding(.bottom, 12)
            }
            if node.kind == .generation {
                Divider()
                HStack {
                    Button(action: run) { Label(node.settings.mode == .sunburstAPI ? "이 단계 실행 · API 유료" : "이 단계 실행", systemImage: "play.fill") }
                        .disabled(busy).accessibilityIdentifier("workflow-run-\(node.id)")
                    Spacer(minLength: 4)
                    Button(action: branch) { Image(systemName: "arrow.triangle.branch") }.disabled(busy).help("결과를 참조로 사용하는 새 단계 만들기")
                }.font(StudioTypography.control).buttonStyle(.borderless).padding(12)
            }
        }.frame(width: Self.width, height: Self.height(node.kind))
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .primary.opacity(0.14), lineWidth: selected ? 2 : 1) }
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .sheet(isPresented: $settings) {
                WorkflowNodeSettings(projectID: projectID, nodeID: node.id).environment(store)
            }
    }
    private var generationContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("이 단계의 지시").font(StudioTypography.metadata).foregroundStyle(.secondary)
                Spacer()
                if !graph.edges.contains(where: { $0.target == node.id && $0.port == .prompt }) { Text("필수").font(StudioTypography.metadata).foregroundStyle(.secondary) }
            }
            TextEditor(text: text).font(StudioTypography.supporting).scrollContentBackground(.hidden)
                .frame(height: 54).padding(6).panelSurface(radius: 8, editor: true).disabled(busy)
                .accessibilityIdentifier("workflow-instruction-\(node.id)")
            HStack {
                Text("\(node.settings.mode == .sunburstAPI ? ImageAPIModel.label(node.settings.api.model) : node.settings.mode.label) · \(node.settings.imageCount)장")
                    .font(StudioTypography.control).lineLimit(1)
                Spacer()
                Button("설정…") { settings = true }.buttonStyle(.borderless).disabled(busy)
            }
            Divider()
            if let error = step?.error, store.latestWorkflowRun(projectID)?.state != .completed {
                Label(error, systemImage: "exclamationmark.circle").font(StudioTypography.supporting).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let job {
                resultContent(job)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 24)).foregroundStyle(.secondary)
                    Text(busy ? "앞 단계의 결과를 기다립니다" : "실행하면 결과가 여기에 쌓입니다")
                        .font(StudioTypography.supporting).foregroundStyle(.secondary)
                    if graph.imageSources(for: node.id).contains(where: { $0.kind == .generation }) {
                        Text("앞 단계에서 고른 이미지로 이어 만듭니다").font(StudioTypography.metadata).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity).frame(height: 135)
            }
        }
    }
    @ViewBuilder private func resultContent(_ job: Job) -> some View {
        if job.state.isRunning || job.state == .queued {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ProjectImageSlot.make(assets: job.results, jobs: [job])) { slot in
                    if let asset = slot.asset { AssetThumbnail(url: store.vault.thumbnail(asset)).frame(height: 100) }
                    else { Button { openJob(job) } label: { GenerationPlaceholder(job: job, ordinal: slot.ordinal, compact: true).frame(height: 100) }.buttonStyle(.plain) }
                }
            }
        }
        HStack {
            Text(job.state.label).font(StudioTypography.control).foregroundStyle(job.state.needsAttention ? Color.orange : .secondary)
            Spacer()
            Button { openJob(job) } label: { Image(systemName: "clock.arrow.circlepath") }.buttonStyle(.borderless).help("이 실행의 기록 보기")
        }
        if !busy && !WorkflowRules.usesCurrentInputs(job, nodeID: node.id, graph: graph, jobs: store.jobs) {
            Text("입력·설정 변경됨 · 이전 실행 결과").font(StudioTypography.metadata).foregroundStyle(.orange)
        }
        if let response = job.responseText ?? job.error, job.state.needsAttention {
            Text(response).font(StudioTypography.supporting).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        if !job.results.isEmpty && !job.state.isRunning && job.state != .queued {
            let chosen = job.results.first { $0.id == node.selectedAssetID } ?? job.results.first!
            AssetThumbnail(url: store.vault.thumbnail(chosen)).frame(height: 112).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8)).onTapGesture(count: 2) { preview(chosen) }
                .contextMenu { Button("크게 보기") { preview(chosen) }; Button("내보내기") { store.export([chosen]) } }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(job.results) { asset in
                        Button { store.chooseWorkflowResult(projectID: projectID, nodeID: node.id, assetID: asset.id) } label: {
                            AssetThumbnail(url: store.vault.thumbnail(asset)).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(node.selectedAssetID == asset.id || job.results.count == 1 ? Color.accentColor : .clear, lineWidth: 2) }
                        }.buttonStyle(.plain).disabled(job.state != .saved)
                            .accessibilityLabel("다음 단계에 이미지 \((job.results.firstIndex(of: asset) ?? 0) + 1) 사용")
                            .accessibilityIdentifier("workflow-result-\(asset.id)")
                    }
                }.padding(2)
            }
            Text(job.results.count > 1 && node.selectedAssetID == nil ? "아래 후보를 클릭해 다음 단계에 사용할 이미지를 고르세요" : "선택한 이미지를 연결된 단계에 전달합니다")
                .font(StudioTypography.metadata).foregroundStyle(node.selectedAssetID == nil && job.results.count > 1 ? Color.accentColor : .secondary)
        }
    }
}

struct WorkflowNodeSettings: View {
    let projectID: UUID
    let nodeID: UUID
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var advanced = false
    @State private var connection = false
    private var settings: Binding<WorkflowSettings> {
        Binding(get: { store.project(projectID)?.workflow?.node(nodeID)?.settings ?? WorkflowSettings() }, set: { value in
            store.changeWorkflow(projectID) { graph in if let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) { graph.nodes[index].settings = value } }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("생성 단계 설정").font(StudioTypography.title); Spacer(); Button("완료") { dismiss() }.keyboardShortcut(.cancelAction) }
            TextField("단계 이름", text: Binding(get: { store.project(projectID)?.workflow?.node(nodeID)?.title ?? "" }, set: { value in
                store.changeWorkflow(projectID) { graph in if let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) { graph.nodes[index].title = value } }
            }))
            Picker("생성 방식", selection: settings.mode) { ForEach(GenerationMode.allCases, id: \.self) { Text($0.label).tag($0) } }.accessibilityIdentifier("workflow-settings-mode")
            if settings.wrappedValue.mode == .sunburstAPI {
                APIModelPicker(options: settings.api)
                APISizeControls(options: settings.api)
                Picker("품질", selection: settings.api.quality) { ForEach(settings.wrappedValue.api.modelInfo?.qualities ?? ImageAPIOptions.qualities, id: \.self) { Text(APIOptionsView.qualityName($0)).tag($0) } }
                Stepper("이미지 \(settings.wrappedValue.api.count)장", value: settings.api.count, in: 1...10)
                Button("모든 API 옵션…") { advanced = true }
                Button(store.apiConnection.ready ? "API 연결 관리…" : "OpenAI API 연결…") { connection = true }
                APICostView(options: settings.wrappedValue.api)
                APIBillingNotice()
            } else {
                Picker("화면 비율", selection: settings.aspect) { ForEach(["자동", "1:1", "3:2", "2:3", "16:9", "9:16"], id: \.self) { Text($0).tag($0) } }
                Picker("배경", selection: settings.background) { ForEach(BackgroundOption.allCases, id: \.self) { Text($0.label).tag($0) } }
                Text("이 단계에서 \(settings.wrappedValue.imageCount)장을 생성합니다.").font(StudioTypography.supporting).foregroundStyle(.secondary)
            }
        }.padding(24).frame(width: 420)
            .sheet(isPresented: $connection) { APIConnectionView() }
            .sheet(isPresented: $advanced) {
                APIAdvancedView(options: settings.api, projectID: projectID, references: referenceAssets)
            }
    }
    private var referenceAssets: [Asset] {
        guard let graph = store.project(projectID)?.workflow else { return [] }
        return graph.imageSources(for: nodeID).compactMap { node in
            if let id = node.assetID ?? node.selectedAssetID { return store.asset(id) }
            return store.jobs.first { $0.id == node.lastJobID }?.results.first
        }
    }
}
