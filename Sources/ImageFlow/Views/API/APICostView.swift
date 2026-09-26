import SwiftUI
import FlowCore

struct APICostView: View {
    let options: ImageAPIOptions
    var requests = 1
    @State private var details = false
    var body: some View {
        let estimate = ImageCostEstimate.calculate(options, requests: requests)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("이미지 출력 예상").font(StudioTypography.supporting).foregroundStyle(.secondary)
                Spacer()
                Text(estimate?.label ?? "계산 불가").font(StudioTypography.control).monospacedDigit()
                Button { details.toggle() } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).help("비용 계산 기준")
                    .popover(isPresented: $details) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("예상 비용의 범위").font(.headline)
                            Text("\(requests)회 × \(options.count)장 기준의 이미지 출력 비용입니다. 텍스트와 참조 이미지 입력 비용은 추가됩니다. 자동 크기는 1K 정사각형을 예시로 계산하며 실제 크기에 따라 달라집니다. 자동 품질은 지원 품질의 범위로 표시합니다. 스트리밍 중간 이미지의 최대 추가 비용을 포함합니다.")
                            Text("OpenAI 공개 요금 · 2026.09.26 확인\n세금·환율·계정별 요금은 반영하지 않습니다. 최종 청구는 OpenAI 사용량에서 확인하세요.").foregroundStyle(.secondary)
                            Link("OpenAI 계산 기준 ↗", destination: ImageCostEstimate.source)
                        }.font(StudioTypography.supporting).padding(20).frame(width: 340)
                    }
            }
            Text(estimate?.usesExampleSize == true ? "자동 크기: 1K 기준 · 입력 비용 별도" : "텍스트·참조 입력 비용 별도 · USD")
                .font(StudioTypography.metadata).foregroundStyle(.secondary)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("api-estimated-cost")
    }
}
