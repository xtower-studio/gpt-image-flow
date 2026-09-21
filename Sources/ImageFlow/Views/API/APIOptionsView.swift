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
            APIModelPicker(options: $options)
                .font(StudioTypography.supporting).padding(PanelSpacing.card).panelSurface(radius: 16)
            VStack(spacing: PanelSpacing.related) {
                APISizeControls(options: $options)
                HStack(spacing: PanelSpacing.related) {
                    OptionTile(title: "품질", symbol: "sparkles") {
                        Menu {
                            ForEach(options.modelInfo?.qualities ?? ImageAPIOptions.qualities, id: \.self) { value in
                                Button(Self.qualityName(value)) { options.quality = value }
                            }
                        } label: { Text(Self.qualityName(options.quality)) }
                        .accessibilityIdentifier("api-quality")
                    }
                    OptionTile(title: "배경", symbol: "square.on.square") {
                        Menu {
                            Button("자동") { options.background = "auto" }
                            Button("불투명") { options.background = "opaque" }
                            Button("투명") {
                                options.background = "transparent"
                                if options.outputFormat == "jpeg" { options.outputFormat = "png" }
                            }
                        } label: { Text(options.background == "transparent" ? "투명" : options.background == "opaque" ? "불투명" : "자동") }
                        .accessibilityIdentifier("api-background")
                    }
                }
            }
            VStack(spacing: PanelSpacing.related) {
                APIQuantityRow(title: "요청당 이미지", value: $options.count, maximum: 10)
                    .accessibilityIdentifier("api-image-count")
                APIQuantityRow(title: "요청 횟수", value: $requests, maximum: 50).disabled(countLocked)
            }.padding(.vertical, 4)
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

struct APISizeControls: View {
    @Binding var options: ImageAPIOptions
    var body: some View {
        HStack(spacing: PanelSpacing.related) {
            OptionTile(title: "화면 비율", symbol: "aspectratio") {
                Menu {
                    Button("자동") { options.size = "auto" }
                    ForEach(ImageSizeSelection.aspects(for: options), id: \.self) { value in
                        Button(value) { options.size = ImageSizeSelection.selectingAspect(value, in: options) }
                    }
                } label: { Text(ImageSizeSelection.aspect(options.size)) }
                .accessibilityLabel("화면 비율").accessibilityIdentifier("api-aspect")
            }
            OptionTile(title: "해상도", symbol: "arrow.up.left.and.arrow.down.right") {
                Menu {
                    if options.size == "auto" { Text("비율과 해상도를 자동으로 선택합니다") }
                    ForEach(ImageSizeSelection.resolutions(for: options), id: \.self) { value in
                        Button(value) { options.size = ImageSizeSelection.selectingResolution(value, in: options) }
                    }
                } label: { Text(ImageSizeSelection.resolution(options.size)) }
                .accessibilityLabel("해상도").accessibilityIdentifier("api-resolution")
            }
        }
    }
}

private struct APIQuantityRow: View {
    let title: String
    @Binding var value: Int
    let maximum: Int
    var body: some View {
        HStack {
            Text(title).font(StudioTypography.control)
            Spacer()
            HStack(spacing: 2) {
                Button { value = max(1, value - 1) } label: { Image(systemName: "minus").frame(width: 28, height: 30).contentShape(Rectangle()) }
                    .disabled(value <= 1).accessibilityLabel(title + " 줄이기")
                TextField(title, value: $value, format: .number.grouping(.never))
                    .textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 32).monospacedDigit()
                    .accessibilityLabel(title + " 입력")
                    .onChange(of: value) { _, number in value = min(maximum, max(1, number)) }
                Button { value = min(maximum, value + 1) } label: { Image(systemName: "plus").frame(width: 28, height: 30).contentShape(Rectangle()) }
                    .disabled(value >= maximum).accessibilityLabel(title + " 늘리기")
            }.buttonStyle(.plain).font(StudioTypography.item).panelSurface(radius: 12)
        }
    }
}
