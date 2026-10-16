import SwiftUI

struct EmptyStudioView: View {
    let filtered: Bool
    let running: Bool
    var create: () -> Void
    var importImages: () -> Void
    var clear: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            if running && !filtered { FlowGenerationMark().frame(width: 100, height: 100) }
            else {
                Image(systemName: filtered ? "photo.badge.magnifyingglass" : "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .light)).foregroundStyle(.secondary)
                    .frame(height: 96).accessibilityHidden(true)
            }
            VStack(spacing: 9) {
                Text(filtered ? "검색 결과가 없습니다" : running ? "첫 이미지를 만들고 있습니다" : "첫 아이디어를 펼쳐 보세요").font(.system(size: 20, weight: .semibold))
                Text(filtered ? "다른 검색어나 후보 필터를 사용해 보세요." : running ? "다른 아이디어를 준비하는 동안\n완료된 이미지가 여기에 나타납니다." : "오른쪽에서 참조를 추가하거나 장면을 설명하세요.\n만든 시안을 함께 보고, 다음 방향으로 이어갈 수 있습니다.").font(StudioTypography.body).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            }
            if filtered { Button("필터 지우기", action: clear) }
            else if !running {
                HStack(spacing: 10) {
                    Button("참조 가져오기…", action: importImages)
                    Button("이미지 만들기", action: create).studioActionButton(prominent: true)
                }.controlSize(.large)
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
