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
    @State private var dropTarget = false
    @State private var recipeName = ""
    @State private var savingRecipe = false
    @State private var editorFocused = false
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
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(editing == nil ? "새 이미지" : "이미지 수정").font(.system(size: 18, weight: .semibold))
                            if let editing { Text(editing.title).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                            else { Text("아이디어를 이미지로 만드세요.").font(.callout).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 4)
                        if editing != nil { Button { editing = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("수정 모드 닫기") }
                        else { recipes }
                    }
                    referencesView
                    VStack(alignment: .leading, spacing: 8) {
                        Text(editing == nil ? "프롬프트" : "수정할 내용").fontWeight(.medium)
                        ZStack(alignment: .topLeading) {
                            if prompt.wrappedValue.isEmpty {
                                Text(editing == nil ? "피사체, 분위기, 색감과 빛을 설명해 주세요." : "바꿀 부분과 유지할 부분을 설명해 주세요.").font(.system(size: 13)).foregroundStyle(.secondary).padding(12).allowsHitTesting(false)
                            }
                            DropTextEditor(text: prompt, onFiles: { store.importImages($0, projectID: project.id) }, onFocusChanged: { editorFocused = $0 }, focusRequest: focusRequest)
                                .frame(height: 134).padding(4).accessibilityLabel("이미지 프롬프트")
                        }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(editorFocused ? Color.accentColor : Color.primary.opacity(0.16), lineWidth: editorFocused ? 2 : 1) }
                    }
                    VStack(spacing: 14) {
                        GenerationModeControl(selection: Binding(get: { store.selectedGenerationMode }, set: { store.selectedGenerationMode = $0 }))
                        HStack {
                            Text("화면 비율")
                            Spacer()
                            Picker("화면 비율", selection: binding(\.aspect)) { ForEach(["자유", "1:1", "3:2", "2:3", "16:9"], id: \.self) { Text($0 == "자유" ? "자동" : $0).tag($0) } }.labelsHidden().frame(width: 165)
                        }
                        HStack {
                            Text("배경")
                            Spacer()
                            Picker("배경", selection: Binding(get: { current.background ?? .automatic }, set: { var copy = current; copy.background = $0; store.updateProject(copy) })) {
                                ForEach(BackgroundOption.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.labelsHidden().frame(width: 165)
                        }
                        HStack {
                            Text("요청 횟수")
                            Spacer()
                            TextField("요청 횟수", value: Binding(get: { count }, set: { value in var copy = current; copy.copies = min(50, max(1, value)); store.updateProject(copy) }), format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 52).monospacedDigit().accessibilityLabel("요청 횟수 입력")
                            Text("회").foregroundStyle(.secondary)
                            Stepper("요청 횟수", value: binding(\.copies), in: 1...50).labelsHidden().fixedSize()
                        }.disabled(editing != nil || !current.variations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(.vertical, 2)
                    Divider()
                    DisclosureGroup("요청별 변형", isExpanded: $showVariations) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("공통 프롬프트에 더할 내용을 한 줄씩 적으세요. 각 줄을 별도 요청으로 보냅니다. 요청마다 선택한 방식의 장수만큼 생성합니다.").font(.callout).foregroundStyle(.secondary)
                            TextEditor(text: binding(\.variations)).font(.system(size: 13)).frame(height: 90).padding(5).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6)).overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary) }
                        }.padding(.top, 10)
                    }.disabled(editing != nil)
                }.font(.system(size: 13)).padding(20)
            }
            VStack(spacing: 10) {
                Text("\(count)회 요청 × \(store.selectedGenerationMode.imagesPerRequest)장 = 총 \(totalImages)장")
                    .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().accessibilityIdentifier("generation-total")
                Button(action: generate) {
                    HStack { Image(systemName: "sparkles"); Text(editing == nil ? "\(totalImages)개 이미지 생성" : "\(totalImages)개 수정본 생성").fontWeight(.semibold); Spacer(); Text("⌘ ↵").font(.system(size: 12)).opacity(0.8) }.frame(maxWidth: .infinity).padding(.vertical, 3)
                }.studioActionButton(prominent: true).buttonBorderShape(.capsule).controlSize(.large).keyboardShortcut(.return, modifiers: .command).disabled(!canGenerate)
                HStack(spacing: 5) {
                    if store.importing { ProgressView().controlSize(.mini); Text("참조 이미지 가져오는 중…") }
                    else if store.journal.paused { Image(systemName: "pause.circle"); Text("대기열 일시정지 · 작업 탭에서 계속") }
                    else { Image(systemName: engine.eco ? "leaf" : "square.stack.3d.up"); Text(engine.eco ? "절전 모드 · 요청 1개씩 실행" : "최대 3개 요청 동시 실행") }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(16)
        }
        .alert("레시피 저장", isPresented: $savingRecipe) {
            TextField("레시피 이름", text: $recipeName)
            Button("저장") { store.saveRecipe(project: current, name: recipeName) }.disabled(recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("취소", role: .cancel) {}
        } message: { Text("프롬프트, 참조와 생성 설정을 함께 저장합니다.") }
        .onAppear { showVariations = !current.variations.isEmpty }
    }
    private var referencesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("참조 이미지").fontWeight(.medium)
                if !references.isEmpty { Text("\(references.count)").foregroundStyle(.secondary) }
                Spacer()
                Button { store.selectImages(projectID: project.id) } label: { Image(systemName: "plus") }.buttonStyle(.borderless).help("참조 이미지 추가 · ⌘O")
            }
            if references.isEmpty {
                Button { store.selectImages(projectID: project.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 23, weight: .light))
                        VStack(alignment: .leading, spacing: 4) { Text("이미지를 여기에 놓으세요").font(.system(size: 12, weight: .medium)); Text("또는 클릭해서 선택 · 선택 사항").font(.system(size: 11)) }
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 74)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4,3])) }
                }.buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(references) { asset in
                            AssetThumbnail(url: store.vault.thumbnail(asset)).frame(width: 68, height: 68)
                                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                                .help(editing?.id == asset.id ? "수정 원본: \(asset.title)" : asset.title)
                                .overlay(alignment: .topTrailing) {
                                    if editing?.id != asset.id {
                                        Button { var copy = current; copy.referenceIDs.removeAll { $0 == asset.id }; store.updateProject(copy) } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7)).font(.system(size: 17)) }.buttonStyle(.plain).padding(3).help("\(asset.title) 참조 제거").accessibilityLabel("\(asset.title) 참조 제거")
                                    }
                                }
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
        .contentShape(Rectangle())
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).allowsHitTesting(false) } }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            store.importImages(files, projectID: project.id); return true
        } isTargeted: { dropTarget = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("참조 이미지 영역")
        .accessibilityIdentifier("reference-drop-region")
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
