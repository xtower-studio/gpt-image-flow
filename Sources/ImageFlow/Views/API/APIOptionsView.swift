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
        VStack(alignment: .leading, spacing: PanelSpacing.heading) {
            HStack {
                PanelSectionHeading(title: "출력 설정")
                Button(store.apiConnection.ready ? "연결 관리" : "API 연결") { connect = true }.buttonStyle(.borderless).font(StudioTypography.metadata)
            }
            VStack(spacing: 0) {
                APIModelPicker(options: $options, showsSummary: false)
                OutputDivider()
                APISizeControls(options: $options)
                OutputDivider()
                OutputMenuRow(title: "품질", value: Self.qualityName(options.quality)) {
                    ForEach(options.modelInfo?.qualities ?? ImageAPIOptions.qualities, id: \.self) { value in
                        Button(Self.qualityName(value)) { options.quality = value }
                    }
                }.accessibilityIdentifier("api-quality")
                OutputDivider()
                OutputMenuRow(title: "배경", value: options.background == "transparent" ? "투명" : options.background == "opaque" ? "불투명" : "자동") {
                    Button("자동") { options.background = "auto" }
                    Button("불투명") { options.background = "opaque" }
                    Button("투명") {
                        options.background = "transparent"
                        if options.outputFormat == "jpeg" { options.outputFormat = "png" }
                    }
                }.accessibilityIdentifier("api-background")
                OutputDivider()
                OutputQuantityRow(title: "요청당 이미지", value: $options.count, maximum: 10)
                    .accessibilityIdentifier("api-image-count")
                OutputDivider()
                OutputQuantityRow(title: "요청 횟수", value: $requests, maximum: 50, locked: countLocked)
            }.padding(.vertical, 4).frame(maxWidth: .infinity).panelSurface(radius: 12)
            Button { advanced = true } label: { Label("모든 API 옵션…", systemImage: "slider.horizontal.3") }.buttonStyle(.borderless).font(StudioTypography.control)
            APIBillingNotice().padding(.top, 4)
        }.sheet(isPresented: $advanced) { APIAdvancedView(options: $options, projectID: projectID, references: references) }
            .sheet(isPresented: $connect) { APIConnectionView() }
    }
    static func qualityName(_ value: String) -> String {
        switch value { case "auto": "자동"; case "low": "초안 · Low"; case "medium": "보통 · Medium"; case "high": "높음 · High"; case "xhigh": "매우 높음 · XHigh"; default: "최대 · Max" }
    }
}

struct APIBillingNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("앱 수수료 0원", systemImage: "checkmark.seal").font(StudioTypography.control)
            Text("API 사용료는 OpenAI가 직접 청구합니다. Image Flow는 어떠한 수수료도 받지 않습니다.")
                .font(StudioTypography.metadata).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct APIModelPicker: View {
    @Binding var options: ImageAPIOptions
    var showsSummary = true
    @State private var adjusted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OutputMenuRow(title: "모델", value: options.modelInfo?.name ?? options.model, horizontalInset: showsSummary ? 0 : 12) {
                ForEach(ImageAPIModel.all) { model in
                    Button {
                        let before = options; options.selectModel(model.id)
                        adjusted = before.quality != options.quality || before.size != options.size || before.inputFidelity != options.inputFidelity
                    } label: {
                        if options.modelInfo?.id == model.id { Label(model.name, systemImage: "checkmark") }
                        else { Text(model.name) }
                    }.disabled(model.hasRetired)
                }
            }.accessibilityIdentifier("api-model")
            if showsSummary, let model = options.modelInfo {
                Text(model.summary).font(StudioTypography.metadata).foregroundStyle(.secondary)
                if let retirement = model.retirement {
                    Text("OpenAI 제공 종료 예정: " + retirement).font(StudioTypography.metadata).foregroundStyle(.secondary)
                }
            }
            if adjusted { Text("모델이 지원하는 품질·크기·입력 설정으로 맞췄습니다.").font(StudioTypography.metadata).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8) }
        }
    }
}

struct APISizeControls: View {
    @Binding var options: ImageAPIOptions
    var horizontalInset: CGFloat = 12
    var body: some View {
        VStack(spacing: 0) {
            OutputMenuRow(title: "화면 비율", value: ImageSizeSelection.aspect(options.size), horizontalInset: horizontalInset) {
                Button("자동") { options.size = "auto" }
                ForEach(ImageSizeSelection.aspects(for: options), id: \.self) { value in
                    Button(value) { options.size = ImageSizeSelection.selectingAspect(value, in: options) }
                }
            }.accessibilityIdentifier("api-aspect")
            Divider().padding(.horizontal, horizontalInset)
            OutputMenuRow(title: "해상도", value: ImageSizeSelection.resolution(options.size), horizontalInset: horizontalInset) {
                if options.size == "auto" { Text("비율과 해상도를 자동으로 선택합니다") }
                let values = ImageSizeSelection.resolutions(for: options)
                if values.isEmpty { Text("화면 비율을 선택하면 해상도를 변경할 수 있습니다") }
                ForEach(values, id: \.self) { value in
                    Button(value) { options.size = ImageSizeSelection.selectingResolution(value, in: options) }
                }
            }.accessibilityIdentifier("api-resolution")
        }
    }
}
