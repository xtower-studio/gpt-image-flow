import SwiftUI
import FlowCore

struct APIOptionsView: View {
    @Binding var options: ImageAPIOptions
    @Binding var requests: Int
    let countLocked: Bool
    let projectID: UUID
    let references: [Asset]
    @Environment(WorkspaceStore.self) private var store
    @State private var advanced = false
    @State private var connect = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PanelSectionHeading(title: "고급 설정")
                Button(store.apiConnection.ready ? "연결 관리" : "API 연결") { connect = true }.buttonStyle(.borderless).font(StudioTypography.metadata)
            }
            APIBillingNotice()
            VStack(spacing: 14) {
                APIModelPicker(options: $options)
                Picker("품질", selection: $options.quality) { ForEach(options.modelInfo?.qualities ?? ImageAPIOptions.qualities, id: \.self) { Text(Self.qualityName($0)).tag($0) } }
                    .accessibilityIdentifier("api-quality")
                Picker("이미지 크기", selection: $options.size) {
                    ForEach(options.modelInfo?.sizes ?? ImageAPIOptions.sizes, id: \.self) { Text(ImageAPISize.label($0)).tag($0) }
                    if !(options.modelInfo?.sizes ?? ImageAPIOptions.sizes).contains(options.size) { Text(ImageAPISize.label(options.size) + " · 사용자 지정").tag(options.size) }
                }.accessibilityIdentifier("api-size")
                Stepper("요청당 \(options.count)장", value: $options.count, in: 1...10).accessibilityIdentifier("api-image-count")
                HStack { Text("요청 횟수"); Spacer(); TextField("횟수", value: $requests, format: .number.grouping(.never)).frame(width: 50).multilineTextAlignment(.trailing).disabled(countLocked).accessibilityLabel("API 요청 횟수") }
            }.font(StudioTypography.supporting).padding(14).panelSurface()
            Button { advanced = true } label: { Label("모든 API 옵션…", systemImage: "slider.horizontal.3") }.buttonStyle(.borderless).font(StudioTypography.control)
        }.sheet(isPresented: $advanced) { APIAdvancedView(options: $options, projectID: projectID, references: references) }
            .sheet(isPresented: $connect) { APIConnectionView() }
    }
    static func qualityName(_ value: String) -> String {
        switch value { case "auto": "자동"; case "low": "초안 · Low"; case "medium": "보통 · Medium"; case "high": "높음 · High"; case "xhigh": "매우 높음 · XHigh"; default: "최대 · Max" }
    }
}

struct APIBillingNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("앱 수수료 0원", systemImage: "checkmark.seal").font(StudioTypography.control)
            Text("API 사용료는 OpenAI가 직접 청구합니다. Image Flow는 어떠한 수수료도 받지 않습니다.")
                .font(StudioTypography.metadata).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct APIModelPicker: View {
    @Binding var options: ImageAPIOptions
    @State private var adjusted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("모델", selection: Binding(get: { options.modelInfo?.id ?? options.model }, set: { id in
                let before = options; options.selectModel(id)
                adjusted = before.quality != options.quality || before.size != options.size || before.inputFidelity != options.inputFidelity
            })) {
                ForEach(ImageAPIModel.all) { model in Text(model.name).tag(model.id).disabled(model.hasRetired) }
            }.accessibilityIdentifier("api-model")
            if let model = options.modelInfo {
                Text(model.summary).font(StudioTypography.metadata).foregroundStyle(.secondary)
                if let retirement = model.retirement {
                    Text("OpenAI 제공 종료 예정: " + retirement).font(StudioTypography.metadata).foregroundStyle(.secondary)
                }
            }
            if adjusted { Text("모델이 지원하는 품질·크기·입력 설정으로 맞췄습니다.").font(StudioTypography.metadata).foregroundStyle(.secondary) }
        }
    }
}
