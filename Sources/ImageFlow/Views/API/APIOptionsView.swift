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
                PanelSectionHeading(title: "Sunburst API 설정")
                Button(store.apiConnection.ready ? "연결 관리" : "API 연결") { connect = true }.buttonStyle(.borderless).font(StudioTypography.metadata)
            }
            Text("API 별도 과금 · 생성 버튼을 누르면 요금이 발생합니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
            VStack(spacing: 14) {
                Picker("품질", selection: $options.quality) { ForEach(ImageAPIOptions.qualities, id: \.self) { Text(Self.qualityName($0)).tag($0) } }
                Picker("이미지 크기", selection: $options.size) {
                    ForEach(ImageAPIOptions.sizes, id: \.self) { Text($0 == "auto" ? "자동" : $0).tag($0) }
                    if !ImageAPIOptions.sizes.contains(options.size) { Text(options.size + " · 사용자 지정").tag(options.size) }
                }
                Stepper("요청당 \(options.count)장", value: $options.count, in: 1...10)
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

private struct APIAdvancedView: View {
    @Binding var options: ImageAPIOptions
    let projectID: UUID
    let references: [Asset]
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var localError: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Sunburst · 모든 API 옵션").font(StudioTypography.title); Spacer(); Button("완료") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Form {
                Section("모델과 생성") {
                    Picker("모델 버전", selection: $options.model) { Text("Sunburst · 최신").tag(ImageAPIOptions.modelID); Text("2026-09-08 고정").tag(ImageAPIOptions.snapshotID) }
                    Picker("품질", selection: $options.quality) { ForEach(ImageAPIOptions.qualities, id: \.self) { Text(APIOptionsView.qualityName($0)).tag($0) } }
                    Stepper("요청당 \(options.count)장", value: $options.count, in: 1...10)
                    TextField("크기 (size)", text: $options.size).accessibilityIdentifier("api-custom-size")
                    Text("auto 또는 가로x세로. 각 변은 16의 배수, 최대 3,840px. 비율 1:3–3:1, 총 655,360–8,294,400픽셀. 2560×1440을 넘는 해상도는 실험적입니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                }
                Section("파일과 배경") {
                    Picker("형식", selection: $options.outputFormat) { Text("PNG").tag("png"); Text("JPEG").tag("jpeg"); Text("WebP").tag("webp") }
                    Picker("배경", selection: $options.background) { Text("자동").tag("auto"); Text("불투명").tag("opaque"); Text("투명").tag("transparent") }
                    Stepper("압축 값 \(options.compression)", value: $options.compression, in: 0...100).disabled(options.outputFormat == "png")
                    Text("압축 값은 JPEG·WebP에 적용합니다. PNG에는 보내지 않습니다. 투명 배경은 PNG·WebP만 지원합니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                }
                Section("참조와 부분 수정") {
                    Text(references.isEmpty ? "참조를 추가하면 수정 API를 사용합니다." : "\(references.count)개 참조 · 첫 원본: \(references.first?.title ?? "")").font(StudioTypography.supporting)
                    Picker("입력 충실도", selection: $options.inputFidelity) { Text("기본값 (생략)").tag("auto"); Text("High").tag("high"); Text("Low").tag("low") }.disabled(references.isEmpty)
                    HStack {
                        Text("마스크"); Spacer()
                        if let id = options.maskAssetID, let asset = store.asset(id) { Text(asset.title).lineLimit(1); Button("제거") { options.maskAssetID = nil } }
                        Button(importing ? "가져오는 중…" : "PNG 선택…", action: selectMask).disabled(references.isEmpty || importing)
                    }
                    Text("첫 참조와 크기가 같은 투명 PNG를 사용하세요. 투명한 부분이 수정 대상입니다. 원본 선택 순서는 만들기 탭의 참조 순서입니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                }
                Section("스트리밍과 필터") {
                    Toggle("생성 중 미리보기 받기 (stream)", isOn: $options.stream)
                    Stepper("중간 이미지 최대 \(options.partialImages)개", value: $options.partialImages, in: 0...3).disabled(!options.stream)
                    Text("중간 이미지는 추가 토큰을 사용합니다. 서버에서 지원하지 않으면 오류를 표시하며 옵션을 바꿔 다시 요청할 수 있습니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                    Picker("콘텐츠 필터 (moderation)", selection: $options.moderation) { Text("자동").tag("auto"); Text("덜 제한적 · Low").tag("low") }
                }
                Section("고급 식별 정보") {
                    TextField("사용자 식별자 (user, 선택)", text: $options.user)
                    Text("필요한 경우 개인정보 대신 임의 식별자를 사용하세요. 인증 키를 입력하는 칸이 아닙니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                }
                Section("요청 확인") {
                    Text(references.isEmpty ? "POST /v1/images/generations" : "POST /v1/images/edits").font(StudioTypography.code)
                    Text("프롬프트와 참조는 만들기 탭에서 지정합니다. 반환값은 Base64 이미지로 고정됩니다. style과 response_format은 Sunburst에서 지원하지 않아 전송하지 않습니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                    Link("공식 옵션 문서 ↗", destination: URL(string: "https://developers.openai.com/api/reference/resources/images/methods/generate")!)
                    if let error = validationError { Text(error).foregroundStyle(.orange).font(StudioTypography.supporting) }
                    if let localError { Text(localError).foregroundStyle(.orange).font(StudioTypography.supporting) }
                    Button("API 옵션 기본값으로 복원") { options = ImageAPIOptions() }
                }
            }.formStyle(.grouped)
        }.frame(width: 580, height: 690)
    }
    private var validationError: String? {
        do { try options.validate(prompt: "preview", referenceCount: references.count); return nil } catch { return error.localizedDescription }
    }
    private func selectMask() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importing = true
        Task {
            defer { importing = false }
            do { let asset = try await store.vault.ingest(url: url, projectID: projectID); store.upsert(asset); store.flush(); options.maskAssetID = asset.id }
            catch { localError = error.localizedDescription }
        }
    }
}
