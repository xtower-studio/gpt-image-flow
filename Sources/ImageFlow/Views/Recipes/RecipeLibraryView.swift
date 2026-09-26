import SwiftUI
import FlowCore

struct RecipeLibraryView: View {
    let projectID: UUID
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: UUID?
    @State private var name = ""
    @State private var text = ""
    @State private var fields: [String: String] = [:]
    @State private var includeSettings = false
    @State private var includeReferences = false
    @State private var editing = false
    @State private var deleted: Recipe?
    var saved: [Recipe] { store.library.recipes ?? [] }
    var recipes: [Recipe] { saved + RecipeTemplates.starters }
    var selected: Recipe? { recipes.first { $0.id == selection } }
    var isSaved: Bool { saved.contains { $0.id == selection } }
    var rendered: String { RecipeTemplates.render(text, values: fields) }
    var missing: [String] { RecipeTemplates.fields(in: text).filter { (fields[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("프롬프트 레시피", systemImage: "bookmark").font(.title2.weight(.semibold)); Spacer()
                Button("현재 작업 저장", action: saveCurrent).accessibilityIdentifier("recipe-save-current")
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    TextField("이름 또는 프롬프트 검색", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 12).padding(.top, 14)
                    List(selection: $selection) {
                        Section("내 레시피 · \(saved.count)") { ForEach(filtered(saved)) { recipe in row(recipe) } }
                        Section("시작 템플릿") { ForEach(filtered(RecipeTemplates.starters)) { recipe in row(recipe) } }
                    }.listStyle(.sidebar)
                    if let deleted { HStack { Text("레시피 삭제됨"); Button("되돌리기") { store.library.recipes?.append(deleted); store.flush(); self.deleted = nil } }.font(StudioTypography.metadata).padding(12) }
                }.frame(width: 235)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    if let selected {
                        HStack {
                            if editing { TextField("레시피 이름", text: $name).textFieldStyle(.roundedBorder).font(.title3) }
                            else { Text(selected.name).font(.title3.weight(.semibold)) }
                            Spacer()
                            Button(editing ? "편집 완료" : "편집") { if editing { saveEdits() }; editing.toggle() }.disabled(editing && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if isSaved { Button(role: .destructive) { deleted = selected; store.library.recipes?.removeAll { $0.id == selected.id }; store.flush(); selection = recipes.first?.id } label: { Image(systemName: "trash") }.help("레시피 삭제") }
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if editing {
                                    TextEditor(text: $text).font(StudioTypography.body).scrollContentBackground(.hidden).frame(height: 170).padding(12).panelSurface(radius: 12, editor: true)
                                    Text("바꿔 쓸 부분을 {{제품}}처럼 적으면 적용할 때 입력할 수 있습니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                                } else {
                                    Text(rendered).font(StudioTypography.body).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16).panelSurface(radius: 12)
                                    ForEach(RecipeTemplates.fields(in: text), id: \.self) { key in
                                        VStack(alignment: .leading, spacing: 5) { Text(key).font(StudioTypography.control); TextField(key + " 입력", text: Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0 })).textFieldStyle(.roundedBorder) }
                                    }
                                }
                                Divider()
                                Toggle("생성 설정도 적용", isOn: $includeSettings).font(StudioTypography.control)
                                Text("\(selected.settings.generationMode?.label ?? "자동") · \(selected.settings.aspect) · \(selected.settings.copies)회 요청").font(StudioTypography.metadata).foregroundStyle(.secondary)
                                if !selected.settings.referenceIDs.isEmpty {
                                    Toggle("저장한 참조 이미지로 교체", isOn: $includeReferences).font(StudioTypography.control)
                                    HStack { ForEach(selected.settings.referenceIDs.compactMap { store.asset($0) }.prefix(5)) { asset in AssetThumbnail(url: store.vault.thumbnail(asset)).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 8)) } }
                                }
                            }.padding(.trailing, 4)
                        }
                        HStack {
                            Text("적용 후 ⌘Z로 되돌릴 수 있습니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                            Spacer()
                            Button("이 프롬프트 사용") {
                                var recipe = selected; recipe.settings.prompt = rendered
                                store.applyRecipe(recipe, to: projectID, includeSettings: includeSettings, includeReferences: includeReferences)
                                dismiss()
                            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(editing || !missing.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("recipe-apply")
                        }
                    } else { ContentUnavailableView("레시피를 선택하세요", systemImage: "bookmark", description: Text("현재 작업을 저장하거나 시작 템플릿을 골라 보세요.")) }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(width: 830, height: 590)
        .onAppear { selection = recipes.first?.id }
        .onChange(of: selection) { _, _ in name = selected?.name ?? ""; text = selected?.settings.prompt ?? ""; fields = [:]; editing = false; includeSettings = false; includeReferences = false }
    }
    private func filtered(_ values: [Recipe]) -> [Recipe] { query.isEmpty ? values : values.filter { ($0.name + " " + $0.settings.prompt).localizedCaseInsensitiveContains(query) } }
    private func row(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(recipe.name).font(StudioTypography.control); Text(recipe.settings.prompt).font(StudioTypography.metadata).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 5).tag(recipe.id)
    }
    private func saveCurrent() {
        guard let project = store.project(projectID) else { return }
        store.saveRecipe(project: project, name: project.name + " 레시피")
        selection = store.library.recipes?.last?.id
    }
    private func saveEdits() {
        guard var recipe = selected else { return }
        recipe.name = name.trimmingCharacters(in: .whitespacesAndNewlines); recipe.settings.prompt = text
        if let index = store.library.recipes?.firstIndex(where: { $0.id == recipe.id }) { store.library.recipes?[index] = recipe }
        else { recipe.id = UUID(); if store.library.recipes == nil { store.library.recipes = [] }; store.library.recipes?.append(recipe); selection = recipe.id }
        store.flush()
    }
}
