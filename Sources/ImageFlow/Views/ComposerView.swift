import SwiftUI
import FlowCore

struct ComposerView: View {
    let project: Project
    @Binding var editing: Asset?
    @Binding var editPrompt: String
    let focusRequest: Int
    @Environment(WorkspaceStore.self) private var store
    @Environment(WebSession.self) private var session
    @Environment(GenerationEngine.self) private var engine
    @State private var showVariations = false
    @State private var recipeName = ""
    @State private var savingRecipe = false
    private var current: Project { store.project(project.id) ?? project }
    private var references: [Asset] {
        var ids = current.referenceIDs
        if let editing { ids.removeAll { $0 == editing.id }; ids.insert(editing.id, at: 0) }
        return ids.compactMap { store.asset($0) }
    }
    private var count: Int {
        if editing != nil { return 1 }
        let lines = current.variations.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.isEmpty ? current.copies : lines.count
    }
    private var totalImages: Int { count * store.selectedGenerationMode.imagesPerRequest }
    private var prompt: Binding<String> { editing == nil ? binding(\.prompt) : $editPrompt }
    private var canGenerate: Bool { store.storageReady && !store.importing && !prompt.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && count <= 50 }
    private func binding<Value>(_ path: WritableKeyPath<Project, Value>) -> Binding<Value> {
        Binding(get: { current[keyPath: path] }, set: { value in var copy = current; copy[keyPath: path] = value; store.updateProject(copy) })
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            PanelSectionHeading(title: editing == nil ? "프롬프트" : "수정할 내용")
                            if editing != nil {
                                Button { editing = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)) }.buttonStyle(.borderless).help("수정 모드 닫기")
                            } else { recipes }
                        }
                        ComposerInputCard(text: prompt, references: references, originalID: editing?.id, focusRequest: focusRequest,
                            thumbnail: store.vault.thumbnail, add: { store.selectImages(projectID: project.id) },
                            remove: { id in var copy = current; copy.referenceIDs.removeAll { $0 == id }; store.updateProject(copy) },
                            importFiles: { store.importImages($0, projectID: project.id) })
                    }
                    GenerationModeControl(selection: Binding(get: { store.selectedGenerationMode }, set: { store.selectedGenerationMode = $0 }))
                    ComposerOptions(aspect: binding(\.aspect),
                        background: Binding(get: { current.background ?? .automatic }, set: { var copy = current; copy.background = $0; store.updateProject(copy) }),
                        count: Binding(get: { count }, set: { value in var copy = current; copy.copies = min(50, max(1, value)); store.updateProject(copy) }),
                        countLocked: editing != nil || !current.variations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    DisclosureGroup(isExpanded: $showVariations) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("한 줄마다 별도 요청으로 보냅니다. 공통 프롬프트에 더할 내용을 적으세요.").font(StudioTypography.supporting).foregroundStyle(.secondary)
                            TextEditor(text: binding(\.variations)).font(StudioTypography.body).scrollContentBackground(.hidden)
                                .frame(height: 90).padding(10).panelSurface(radius: 14, editor: true).accessibilityLabel("요청별 변형 입력")
                        }.padding(.top, 12)
                    } label: { Text("요청별 변형").font(StudioTypography.control) }
                    .disabled(editing != nil)
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 18)
            }.panelScrollEdges()
            VStack(spacing: 10) {
                HStack {
                    Text("총 \(totalImages)장").font(StudioTypography.section)
                    Spacer()
                    Text("\(count)회 요청 × \(store.selectedGenerationMode.imagesPerRequest)장").font(StudioTypography.metadata).foregroundStyle(.secondary)
                }.monospacedDigit().accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(count)회 요청 × \(store.selectedGenerationMode.imagesPerRequest)장 = 총 \(totalImages)장").accessibilityIdentifier("generation-total")
                Button(action: generate) {
                    HStack { Image(systemName: "sparkles"); Text(editing == nil ? "\(totalImages)개 이미지 생성" : "\(totalImages)개 수정본 생성").font(StudioTypography.action); Spacer(); Text("⌘↵").font(StudioTypography.metadata).opacity(0.65) }.frame(maxWidth: .infinity).padding(.vertical, 5)
                }.studioActionButton(prominent: true).buttonBorderShape(.capsule).controlSize(.large).keyboardShortcut(.return, modifiers: .command).disabled(!canGenerate)
                HStack(spacing: 5) {
                    if store.importing { ProgressView().controlSize(.mini); Text("참조 이미지 가져오는 중…") }
                    else if store.journal.paused { Image(systemName: "pause.circle"); Text("대기열 일시정지 · 작업 탭에서 계속") }
                    else { Image(systemName: engine.eco ? "leaf" : "square.stack.3d.up"); Text(engine.eco ? "절전 모드 · 요청 1개씩 실행" : "최대 3개 요청 동시 실행") }
                }.font(StudioTypography.metadata).foregroundStyle(.secondary)
            }.padding(16)
        }
        .alert("레시피 저장", isPresented: $savingRecipe) {
            TextField("레시피 이름", text: $recipeName)
            Button("저장") { store.saveRecipe(project: current, name: recipeName) }.disabled(recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("취소", role: .cancel) {}
        } message: { Text("프롬프트, 참조와 생성 설정을 함께 저장합니다.") }
        .onAppear { showVariations = !current.variations.isEmpty }
    }
    private var recipes: some View {
        Menu {
            Button("현재 설정 저장…") { recipeName = current.name; savingRecipe = true }
            Divider()
            if (store.library.recipes ?? []).isEmpty { Text("저장한 레시피 없음") }
            ForEach(store.library.recipes ?? []) { recipe in
                Menu(recipe.name) {
                    Button("적용") { store.applyRecipe(recipe, to: project.id) }
                    Button("삭제") { store.library.recipes?.removeAll { $0.id == recipe.id }; store.flush() }
                }
            }
        } label: { Image(systemName: "bookmark") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("레시피 저장 및 불러오기")
    }
    private func generate() {
        var request = current
        request.generationMode = store.selectedGenerationMode
        if let editing { request.prompt = editPrompt; request.variations = ""; request.copies = 1; request.referenceIDs = [editing.id] + current.referenceIDs.filter { $0 != editing.id } }
        do {
            try store.enqueue(project: request, parentID: editing?.id)
            store.notice = "\(count)회 요청 · 총 \(totalImages)장 생성을 추가했습니다. 작업 탭에서 진행 상태를 확인할 수 있습니다."
            if session.status != .ready { session.connect() }
            if editing != nil { editPrompt = ""; editing = nil }
        } catch { store.report(error) }
    }
}
