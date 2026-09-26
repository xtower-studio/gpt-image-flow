import AppKit
import SwiftUI
import FlowCore

/// AppKit supplies desktop selection, range extension, rubber-band selection,
/// keyboard navigation, scrolling, accessibility and file dragging in one responder.
struct NativeImageCollection: NSViewRepresentable {
    let assets: [Asset]
    let jobs: [Job]
    var slots: [ProjectImageSlot] { ProjectImageSlot.make(assets: assets, jobs: jobs) }
    var openJob: (Job) -> Void
    let store: WorkspaceStore
    let cardSize: Double
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selection: Set<UUID>
    var preview: ([Asset]) -> Void
    var edit: (Asset) -> Void
    var inspect: () -> Void
    var attach: (Asset) -> Void
    var rename: (Asset) -> Void
    var hide: ([Asset]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let collection = ImageCollectionView()
        collection.backgroundColors = [.clear]; collection.isSelectable = true
        collection.allowsMultipleSelection = true; collection.allowsEmptySelection = true
        collection.dataSource = context.coordinator; collection.delegate = context.coordinator
        // Set the modern layout before registering: switching from legacy layout clears registrations.
        collection.collectionViewLayout = NSCollectionViewFlowLayout()
        collection.register(ImageCollectionItem.self, forItemWithIdentifier: ImageCollectionItem.identifier)
        collection.register(GenerationCollectionItem.self, forItemWithIdentifier: GenerationCollectionItem.identifier)
        collection.setDraggingSourceOperationMask(.copy, forLocal: true)
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)
        collection.setAccessibilityLabel("프로젝트 이미지")
        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.quickLook))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        collection.addGestureRecognizer(doubleClick)
        scroll.documentView = collection
        context.coordinator.collection = collection
        configure(collection, coordinator: context.coordinator)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let nextSlots = slots
        let changed = coordinator.slots != nextSlots || coordinator.phase != scenePhase
        coordinator.parent = self; coordinator.slots = nextSlots; coordinator.phase = scenePhase
        guard let collection = scroll.documentView as? ImageCollectionView else { return }
        configure(collection, coordinator: coordinator)
        coordinator.applying = true
        if changed { collection.reloadData() }
        let indexes = Set(nextSlots.enumerated().filter { $0.element.asset.map { selection.contains($0.id) } ?? false }.map { IndexPath(item: $0.offset, section: 0) })
        let selectionChanged = collection.selectionIndexPaths != indexes
        if selectionChanged { collection.selectionIndexPaths = indexes }
        if changed || selectionChanged {
            for item in collection.visibleItems() { if let item = item as? ImageCollectionItem, let path = collection.indexPath(for: item) { coordinator.configure(item, at: path) } }
        }
        coordinator.applying = false
    }
    private func configure(_ collection: ImageCollectionView, coordinator: Coordinator) {
        if collection.preferredSize != cardSize { collection.preferredSize = cardSize; collection.needsLayout = true }
        collection.perform = { [weak coordinator] action in coordinator?.perform(action) }
        collection.context = { [weak coordinator] event in coordinator?.menu(event) }
    }
    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: NativeImageCollection
        weak var collection: ImageCollectionView?
        var applying = false
        var slots: [ProjectImageSlot]
        var phase: ScenePhase
        init(_ parent: NativeImageCollection) { self.parent = parent; slots = parent.slots; phase = parent.scenePhase }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { slots.count }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let slot = slots[indexPath.item]
            if slot.asset == nil, let job = slot.job {
                let item = collectionView.makeItem(withIdentifier: GenerationCollectionItem.identifier, for: indexPath) as! GenerationCollectionItem
                item.render(job: job, ordinal: slot.ordinal, phase: phase) { [weak self] in self?.parent.openJob(job) }
                return item
            }
            let item = collectionView.makeItem(withIdentifier: ImageCollectionItem.identifier, for: indexPath) as! ImageCollectionItem
            configure(item, at: indexPath); return item
        }
        func configure(_ item: ImageCollectionItem, at path: IndexPath) {
            guard slots.indices.contains(path.item), let asset = slots[path.item].asset else { return }
            item.select = { [weak self] in
                guard let self, let collection = self.collection, let index = self.slots.firstIndex(where: { $0.asset?.id == asset.id }) else { return }
                collection.selectionIndexPaths = [IndexPath(item: index, section: 0)]
                collection.window?.makeFirstResponder(collection); self.changed()
            }
            item.render(asset: asset, store: parent.store, selected: collection?.selectionIndexPaths.contains(path) == true,
                        edit: { [weak self] in self?.parent.edit(asset) }, attach: { [weak self] in self?.parent.attach(asset) })
        }
        func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
            Set(indexPaths.filter { slots.indices.contains($0.item) && slots[$0.item].asset != nil })
        }
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { changed() }
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { changed() }
        func changed() {
            guard !applying, let collection else { return }
            parent.selection = Set(collection.selectionIndexPaths.compactMap { slots.indices.contains($0.item) ? slots[$0.item].asset?.id : nil })
            for item in collection.visibleItems() { if let item = item as? ImageCollectionItem, let path = collection.indexPath(for: item) { configure(item, at: path) } }
        }
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
            guard slots.indices.contains(indexPath.item), let asset = slots[indexPath.item].asset else { return nil }
            return parent.store.vault.original(asset) as NSURL
        }
        var selected: [Asset] { parent.assets.filter { parent.selection.contains($0.id) } }
        func perform(_ action: ImageCollectionView.Action) {
            switch action {
            case .preview: if !selected.isEmpty { parent.preview(selected) }
            case .edit: if let first = selected.first { parent.edit(first) }
            case .inspect: parent.inspect()
            case .hide: if !selected.isEmpty { parent.hide(selected) }
            case .favorite: for asset in selected { parent.store.toggleFavorite(asset) }
            case .rename: if selected.count == 1, let first = selected.first { parent.rename(first) }
            case .copy: NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(selected.map { parent.store.vault.original($0) as NSURL })
            }
        }
        func menu(_ event: NSEvent) -> NSMenu? {
            guard let collection else { return nil }
            let point = collection.convert(event.locationInWindow, from: nil)
            if let path = collection.indexPathForItem(at: point), slots[path.item].asset == nil { return nil }
            if let path = collection.indexPathForItem(at: point), !collection.selectionIndexPaths.contains(path) { collection.selectionIndexPaths = [path]; changed() }
            guard !selected.isEmpty else { return nil }
            let menu = NSMenu()
            add("빠른 보기", to: menu, action: #selector(quickLook))
            if selected.count == 1 { add("이 이미지 수정…", to: menu, action: #selector(editImage)); add("이름 변경…", to: menu, action: #selector(renameImage)) }
            add("참조에 추가", to: menu, action: #selector(attachImages))
            add("후보 표시 전환", to: menu, action: #selector(favoriteImages))
            menu.addItem(.separator())
            add("이미지 복사", to: menu, action: #selector(copyImages)); add("내보내기…", to: menu, action: #selector(exportImages))
            add("Finder에서 보기", to: menu, action: #selector(revealImages)); menu.addItem(.separator())
            add("보관함에서 숨기기", to: menu, action: #selector(hideImages))
            return menu
        }
        private func add(_ title: String, to menu: NSMenu, action: Selector) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
        @objc func quickLook() { perform(.preview) }
        @objc func editImage() { perform(.edit) }
        @objc func renameImage() { perform(.rename) }
        @objc func attachImages() { for asset in selected { parent.attach(asset) } }
        @objc func favoriteImages() { perform(.favorite) }
        @objc func copyImages() { perform(.copy) }
        @objc func exportImages() { parent.store.export(selected) }
        @objc func revealImages() { NSWorkspace.shared.activateFileViewerSelecting(selected.map { parent.store.vault.original($0) }) }
        @objc func hideImages() { perform(.hide) }
    }
}

final class ImageCollectionView: NSCollectionView {
    enum Action { case preview, edit, inspect, hide, favorite, rename, copy }
    var preferredSize = 230.0
    var perform: ((Action) -> Void)?
    var context: ((NSEvent) -> NSMenu?)?
    override func layout() {
        if let layout = collectionViewLayout as? NSCollectionViewFlowLayout {
            let available = max(180, (enclosingScrollView?.contentSize.width ?? bounds.width) - 40)
            let target = available < 470 ? min(preferredSize, 180) : preferredSize
            let count = max(1, floor((available + 18) / (target + 18)))
            let width = floor((available - (count - 1) * 18) / count)
            let size = NSSize(width: width, height: width + 56)
            if layout.itemSize != size {
                layout.itemSize = size; layout.minimumInteritemSpacing = 18; layout.minimumLineSpacing = 22
                layout.sectionInset = NSEdgeInsets(top: 20, left: 20, bottom: 24, right: 20); layout.invalidateLayout()
            }
        }
        super.layout()
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command,.option,.control]).isEmpty {
            switch event.keyCode {
            case 49: perform?(.preview); return
            case 36: perform?(.rename); return
            case 51,117: perform?(.hide); return
            case 53: deselectAll(nil); return
            case 3: perform?(.favorite); return
            default: break
            }
        }
        super.keyDown(with: event)
    }
    @objc func copy(_ sender: Any?) { perform?(.copy) }
    override func menu(for event: NSEvent) -> NSMenu? { context?(event) }
}

final class ImageCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ImageCell")
    private var host: CollectionHostingView?
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    var select: (() -> Void)? { didSet { (view as? CollectionItemContainer)?.select = select } }
    override func loadView() { view = CollectionItemContainer(); view.setAccessibilityElement(true); view.setAccessibilityRole(.button) }
    func render(asset: Asset, store: WorkspaceStore, selected: Bool, edit: @escaping () -> Void, attach: @escaping () -> Void) {
        let content = CollectionImageCell(asset: asset, store: store, selected: selected, edit: edit, attach: attach)
        if let host { host.rootView = content }
        else {
            let host = CollectionHostingView(rootView: content); host.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host); NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: view.leadingAnchor),host.trailingAnchor.constraint(equalTo: view.trailingAnchor),host.topAnchor.constraint(equalTo: view.topAnchor),host.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
            self.host = host
        }
        view.setAccessibilityLabel("\(asset.title), \(asset.displayDetails)\(asset.isFavorite ? ", 후보" : "")")
        view.setAccessibilitySelected(selected)
    }
}

struct CollectionImageCell: View {
    let asset: Asset
    let store: WorkspaceStore
    let selected: Bool
    var edit: () -> Void
    var attach: () -> Void
    @State private var hovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                AssetThumbnail(url: store.vault.thumbnail(asset)).frame(width: geometry.size.width, height: geometry.size.height)
            }.aspectRatio(1, contentMode: .fit)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1) }
                .overlay(alignment: .topLeading) {
                    if asset.isReference { Label("참조", systemImage: "paperclip").font(StudioTypography.metadata).padding(6).background(.regularMaterial, in: Capsule()).padding(8) }
                }
                .overlay(alignment: .topTrailing) {
                    if asset.isFavorite { Image(systemName: "star.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).padding(7).background(.black.opacity(0.65), in: Circle()).padding(8) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.title).font(StudioTypography.item).lineLimit(1).foregroundStyle(selected ? Color.accentColor : .primary)
                    Text(asset.displayDetails).font(StudioTypography.metadata).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if hovered || selected {
                    Button(action: attach) { Image(systemName: "paperclip") }.help("참조에 추가").accessibilityLabel("참조에 추가")
                    Button(action: edit) { Image(systemName: "slider.horizontal.3") }.help("이 이미지 수정").accessibilityLabel("이 이미지 수정")
                }
                Button { store.toggleFavorite(asset) } label: { Image(systemName: asset.isFavorite ? "star.fill" : "star") }.help("후보 표시 · F").accessibilityLabel("후보 표시")
            }.buttonStyle(.borderless).font(.system(size: 12)).padding(.horizontal, 3)
        }.padding(3).onHover { hovered = $0 }
    }
}

/// Keep the image surface in the collection's responder chain; only the footer
/// buttons need SwiftUI hit testing. This preserves AppKit selection and dragging.
final class CollectionHostingView: NSHostingView<CollectionImageCell> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let footerY = isFlipped ? local.y : bounds.height - local.y
        guard footerY > bounds.width + 4 && local.x > bounds.width - 98 else { return nil }
        return super.hitTest(point)
    }
}

final class CollectionItemContainer: NSView {
    var select: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { guard let select else { return false }; select(); return true }
}
