import SwiftUI

struct StudioActions {
    var selectedCount: Int
    var search: () -> Void
    var inspect: () -> Void
    var newProject: () -> Void
    var importImages: () -> Void
    var preview: () -> Void
    var compare: () -> Void
    var edit: () -> Void
    var export: () -> Void
    var favorite: () -> Void
    var hide: () -> Void
    var rename: () -> Void
    var showGrid: () -> Void
    var showCanvas: () -> Void
    var toggleInspector: () -> Void
    var create: () -> Void
    var showHelp: () -> Void
}
private struct StudioActionsKey: FocusedValueKey { typealias Value = StudioActions }
extension FocusedValues {
    var studioActions: StudioActions? {
        get { self[StudioActionsKey.self] }
        set { self[StudioActionsKey.self] = newValue }
    }
}
struct StudioCommands: Commands {
    @FocusedValue(\.studioActions) private var actions
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("새 프로젝트…") { actions?.newProject() }.keyboardShortcut("n").disabled(actions == nil)
            Button("참조 이미지 가져오기…") { actions?.importImages() }.keyboardShortcut("o").disabled(actions == nil)
            Divider()
            Button("선택한 이미지 내보내기…") { actions?.export() }.keyboardShortcut("e", modifiers: [.command,.shift]).disabled((actions?.selectedCount ?? 0) == 0)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("이미지 검색") { actions?.search() }.keyboardShortcut("f").disabled(actions == nil)
        }
        CommandMenu("이미지") {
            Button("새 이미지 만들기") { actions?.create() }.keyboardShortcut("n", modifiers: [.command,.shift])
            Divider()
            Button("빠른 보기") { actions?.preview() }.keyboardShortcut("y").disabled((actions?.selectedCount ?? 0) == 0)
            Button("선택한 이미지 비교") { actions?.compare() }.keyboardShortcut("c", modifiers: [.command,.shift]).disabled(!(2...4).contains(actions?.selectedCount ?? 0))
            Button("선택한 이미지 수정…") { actions?.edit() }.keyboardShortcut("e").disabled(actions?.selectedCount != 1)
            Button("이미지 정보") { actions?.inspect() }.keyboardShortcut("i").disabled((actions?.selectedCount ?? 0) == 0)
            Button("이름 변경…") { actions?.rename() }.disabled(actions?.selectedCount != 1)
            Button("후보 표시 전환") { actions?.favorite() }.keyboardShortcut("l", modifiers: [.command,.shift]).disabled((actions?.selectedCount ?? 0) == 0)
            Divider()
            Button("보관함에서 숨기기") { actions?.hide() }.disabled((actions?.selectedCount ?? 0) == 0)
        }
        CommandGroup(after: .sidebar) {
            Divider()
            Button("컬렉션 보기") { actions?.showGrid() }.keyboardShortcut("1")
            Button("캔버스 보기") { actions?.showCanvas() }.keyboardShortcut("2")
            Button("작업 패널 표시 / 가리기") { actions?.toggleInspector() }.keyboardShortcut("i", modifiers: [.command,.option])
        }
        CommandGroup(replacing: .help) { Button("Image Flow 사용법") { actions?.showHelp() } }
    }
}

struct StudioHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Image Flow 사용법").font(.title2.bold()); Spacer(); Button("완료") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("만들고, 고르고, 이어서 다듬으세요. 이미지 선택 단축키는 컬렉션에서 사용할 수 있습니다.").foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 36, verticalSpacing: 14) {
                row("새 프로젝트 / 참조 가져오기", "⌘N / ⌘O")
                row("이미지 생성 / 검색", "⌘Return / ⌘F")
                row("이동 / 범위 선택", "방향키 / ⇧방향키")
                row("모두 선택 / 개별 선택", "⌘A / ⌘클릭")
                row("빠른 보기 / 닫기", "Space / Esc")
                row("시안 수정 / 비교", "⌘E / ⇧⌘C")
                row("이름 변경 / 후보 표시", "Return / F")
                row("숨기기 / 되돌리기", "Delete / ⌘Z")
                row("컬렉션 / 캔버스", "⌘1 / ⌘2")
                row("작업 패널 열기 / 접기", "⌥⌘I")
            }.font(.system(size: 13))
            Divider()
            Text("이미지를 참조 영역으로 드래그하면 다시 사용할 수 있습니다. 캔버스에서는 카드 상단을 드래그해 배치하고, 빈 공간 드래그 또는 두 손가락 스크롤로 이동하세요.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 530)
    }
    private func row(_ title: String, _ keys: String) -> some View { GridRow { Text(title); Text(keys).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing) } }
}
