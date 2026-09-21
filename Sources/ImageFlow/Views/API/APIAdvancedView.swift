import SwiftUI
import FlowCore

struct APIAdvancedView: View {
    @Binding var options: ImageAPIOptions
    let projectID: UUID
    let references: [Asset]
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var localError: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("고급 · 모든 API 옵션").font(StudioTypography.title); Spacer(); Button("완료") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Form {
                Section("모델과 생성") {
                    APIModelPicker(options: $options)
                    if let model = options.modelInfo, let snapshot = model.snapshot {
                        Picker("모델 버전", selection: $options.model) { Text("최신 버전").tag(model.id); Text(String(snapshot.suffix(10)) + " 고정").tag(snapshot) }
                    }
                    Picker("품질", selection: $options.quality) { ForEach(options.modelInfo?.qualities ?? ImageAPIOptions.qualities, id: \.self) { Text(APIOptionsView.qualityName($0)).tag($0) } }
                    Stepper("요청당 \(options.count)장", value: $options.count, in: 1...10)
                    Picker("이미지 크기", selection: $options.size) {
                        ForEach(options.modelInfo?.sizes ?? ImageAPIOptions.sizes, id: \.self) { Text(ImageAPISize.label($0)).tag($0) }
                        if !(options.modelInfo?.sizes ?? []).contains(options.size) { Text("사용자 지정").tag(options.size) }
                    }
                    Text("K는 긴 변 기준입니다. 4K는 UHD 기준이며, 큰 해상도에서는 생성 시간과 사용료가 늘어날 수 있습니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                    if options.modelInfo?.flexibleSize == true {
                        DisclosureGroup("정확한 크기 직접 지정") {
                            TextField("가로x세로", text: $options.size).accessibilityIdentifier("api-custom-size")
                            Text("auto 또는 가로x세로. 각 변은 16의 배수, 최대 3,840px. 비율 1:3–3:1, 총 655,360–8,294,400픽셀. 2560×1440을 넘는 해상도는 실험적입니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("파일과 배경") {
                    Picker("형식", selection: $options.outputFormat) { Text("PNG").tag("png"); Text("JPEG").tag("jpeg"); Text("WebP").tag("webp") }
                    Picker("배경", selection: $options.background) { Text("자동").tag("auto"); Text("불투명").tag("opaque"); Text("투명").tag("transparent") }
                    Stepper("압축 값 \(options.compression)", value: $options.compression, in: 0...100).disabled(options.outputFormat == "png")
                    Text("압축 값은 JPEG·WebP에 적용합니다. PNG에는 보내지 않습니다. 투명 배경은 PNG·WebP만 지원합니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
                }
                Section("참조와 부분 수정") {
                    Text(references.isEmpty ? "참조를 추가하면 수정 API를 사용합니다." : "\(references.count)개 참조 · 첫 원본: \(references.first?.title ?? "")").font(StudioTypography.supporting)
                    Picker("입력 충실도", selection: $options.inputFidelity) { Text("기본값 (생략)").tag("auto"); Text("High").tag("high"); Text("Low").tag("low") }.disabled(references.isEmpty || options.modelInfo?.adjustableFidelity == false)
                    if options.modelInfo?.adjustableFidelity == false { Text("이 모델은 모든 참조를 높은 입력 충실도로 자동 처리합니다.").font(StudioTypography.metadata).foregroundStyle(.secondary) }
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
                    APIBillingNotice()
                    Text(references.isEmpty ? "POST /v1/images/generations" : "POST /v1/images/edits").font(StudioTypography.code)
                    Text("프롬프트와 참조는 만들기 탭에서 지정합니다. 모델 사용 가능 여부는 OpenAI 계정의 접근 권한에 따라 달라집니다.").font(StudioTypography.metadata).foregroundStyle(.secondary)
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
