import AppKit

/// A sidebar tab, or a page's link, dragged over a window's panes makes a split where it is let
/// go (SplitDropProposal decides where): Arc's drag-to-split for tabs, and Cra's for links
/// (GitHub #419, Arc takes no link there). While the drag offers a split the window shows the
/// drop region and the drag image is Arc's dark card with the tab's icon and title.
@MainActor
final class PageSplitDrop: PageDropTarget {
    weak var owner: MainWindowController?

    enum Payload: Equatable {
        case tab(UUID)
        case link(SidebarLinkDrop.Tab)

        var isLink: Bool { if case .link = self { true } else { false } }
    }

    private var current: SplitDropProposal.Target?
    /// The dragged tab the press switched to, while the window shows the tab from before the
    /// press in its place (Arc does: the split is made with the page you were on).
    private var swapped: (dragged: UUID, shown: UUID)?
    private var exitPending = 0
    /// The drag image before Cra's card replaced it, given back when the drag leaves.
    private var savedImages: [Int: [NSDraggingImageComponent]] = [:]
    private var savedFrames: [Int: NSRect] = [:]
    /// The drag whose images those are (NSDraggingInfo.draggingSequenceNumber).
    private var cardDrag: Int?

    init(owner: MainWindowController) { self.owner = owner }

    static func payload(on pb: NSPasteboard) -> Payload? {
        if let data = pb.data(forType: .craSidebarItem), let item = try? JSONDecoder().decode(SidebarDragItem.self, from: data) {
            return .tab(item.id)
        }
        return SpaceListView.link(on: pb).map(Payload.link)
    }

    // MARK: PageDropTarget

    func pageDragUpdated(_ info: NSDraggingInfo) -> NSDragOperation? {
        exitPending += 1
        guard let owner, let shell = owner.shell, let payload = Self.payload(on: info.draggingPasteboard) else { return clear(info) }
        let store = owner.store
        // The press switched to the dragged tab: where the drag offers a split, Arc shows the
        // tab from before the press again and splits with it.
        var swapTo: (dragged: UUID, shown: UUID)?
        if case .tab(let id) = payload {
            guard store.item(id)?.isTab == true else { return clear(info) }
            if swapped == nil, shell.dropLayout.ids.contains(id) {
                guard let before = owner.sidebarUI.tabBeforePress, before != id, store.item(before)?.isTab == true,
                      !store.paneTabIDs(for: before).contains(id), shell.dropLayout.ids == [id] else { return clear(info) }
                swapTo = (id, before)
            }
        }
        let point = shell.contentContainer.convert(info.draggingLocation, from: nil)
        let layout = shell.dropLayout
        guard let proposal = SplitDropProposal.propose(at: point, ids: layout.ids, frames: shell.dropBaseFrames, orientation: layout.orientation,
                                                       area: layout.area, region: layout.frames[ShellView.dropRegionID], current: current,
                                                       sidebarSide: owner.sidebarDocksLeft, link: payload.isLink) else { return clear(info) }
        if let swapTo {
            swapped = swapTo
            store.selectTab(swapTo.shown, window: owner.windowID)
            owner.refresh()
            // The panes changed under the drag; the next update proposes against them, unless
            // they are one page as before.
            guard owner.shell.dropLayout.ids.count == 1 else { showCard(info, for: payload); return .move }
        }
        show(proposal)
        showCard(info, for: payload)
        if case .tab = payload { return .move }
        return .copy
    }

    /// The drag left: the page under it may take it at once, and the shell's own view may take
    /// it in the same pass, so the region waits a turn of the run loop before it goes.
    func pageDragExited() {
        if current != nil { CraLog.note("splitDrop: exited") }
        exitPending += 1
        let mark = exitPending
        DispatchQueue.main.async { [weak self] in
            guard let self, self.exitPending == mark else { return }
            _ = self.clear(nil)
        }
    }

    func pageDragPerform(_ info: NSDraggingInfo) -> Bool {
        CraLog.note("splitDrop: perform \(current.map(Self.describe) ?? "nothing")")
        defer { savedImages = [:]; savedFrames = [:]; cardDrag = nil }
        guard let owner, let target = current, let payload = Self.payload(on: info.draggingPasteboard) else { return false }
        let layout = owner.shell.dropLayout
        let orientation = owner.shell.splitOrientation
        swapped = nil
        current = nil
        owner.shell.setDropPreview(nil, animated: false)
        owner.shell.dropReplaceID = nil
        guard Self.drop(payload, at: target, panes: layout.ids, splitOrientation: orientation, store: owner.store, window: owner.windowID) != nil else { return false }
        owner.refresh()
        return true
    }

    // MARK: Dropping

    /// Puts the tab or link in the window's split at `target` (a new split with the page shown
    /// when there is one page) and opens it; a replaced pane goes back to the sidebar, right after
    /// the split. Returns the new pane, nil when nothing changed.
    @discardableResult
    static func drop(_ payload: Payload, at target: SplitDropProposal.Target, panes: [UUID], splitOrientation: SplitOrientation,
                     store: SidebarStore, window: UUID?) -> UUID? {
        guard let anchor = panes.first else { return nil }
        let insert: SplitDropProposal.Insert
        var replaced: UUID?
        switch target {
        case .insert(let i):
            guard panes.count < SplitDropProposal.maximumPanes else { return nil }
            insert = i
        case .replace(let index):
            guard panes.indices.contains(index), panes.count > 1 else { return nil }
            insert = .init(index: index, orientation: splitOrientation)
            replaced = panes[index]
        }
        let index = min(max(0, insert.index), panes.count)
        let pane: UUID
        switch payload {
        case .tab(let id):
            guard !panes.contains(id), store.item(id)?.isTab == true else { return nil }
            if let split = store.splitContaining(anchor) {
                store.addToSplit(split.id, tabID: id, at: index)
                guard let s = store.splitContaining(anchor), let p = store.paneID(for: id, in: s) else { return nil }
                pane = p
            } else {
                var order = panes
                order.insert(id, at: index)
                guard let s = store.createSplit(with: order, at: anchor), let p = store.paneID(for: id, in: s) else { return nil }
                pane = p
            }
        case .link(let link):
            let ref = index < panes.count ? panes[index] : panes[panes.count - 1]
            guard let tab = store.addEmptyPane(nextTo: ref, after: index >= panes.count, url: link.url, title: link.title, window: window) else { return nil }
            pane = tab.id
        }
        guard let split = store.splitContaining(pane) else { return nil }
        let others = (store.item(split.id)?.children ?? []).filter { $0 != pane }
        var factors = SplitPaneLayout.normalizedFactors(ids: others, stored: split.split?.widthFactors ?? [:])
        if let replaced {
            store.separateFromSplit(replaced)
            // The page takes the replaced pane's share.
            factors[pane] = factors.removeValue(forKey: replaced)
            store.setSplitWidthFactors(split.id, factors.mapValues(Double.init))
        } else {
            if split.split?.orientation != insert.orientation { store.flipSplitOrientation(split.id) }
            // The others keep their proportions and make room, as the region showed.
            let shares = SplitDropProposal.panes(others.map { SplitPaneLayout.Pane(id: $0, factor: factors[$0] ?? 0) }, inserting: pane, at: insert)
            store.setSplitWidthFactors(split.id, Dictionary(uniqueKeysWithValues: shares.map { ($0.id, Double($0.factor)) }))
        }
        store.selectTab(pane, window: window)
        return pane
    }

    /// The region for a new pane, or the ring on the pane a drop would replace.
    private func show(_ target: SplitDropProposal.Target) {
        guard target != current, let shell = owner?.shell else { return }
        current = target
        shell.setDropPreview(target.insert)
        if case .replace(let index) = target {
            let ids = shell.dropLayout.ids
            shell.dropReplaceID = ids.indices.contains(index) ? ids[index] : nil
        } else {
            shell.dropReplaceID = nil
        }
    }

    static func describe(_ t: SplitDropProposal.Target) -> String {
        switch t {
        case .insert(let i): "\(i.orientation.rawValue) \(i.index)"
        case .replace(let i): "replace \(i)"
        }
    }

    // MARK: Testing

    /// `cra://debug?dropSplit`: the tab whose address holds `text` (or, with `link`, a page's link
    /// to `text`) let go at a point of the panes, `x` and `y` as fractions from their top left.
    /// It goes through the live proposal, the drop region's layout and the drop itself, and logs
    /// each: the proposal, the region's share and side, then the split the window shows.
    func test(_ text: String, link: Bool, name: String?, x: Double, y: Double) {
        guard let owner, let shell = owner.shell else { return }
        let store = owner.store
        let payload: Payload
        if link {
            let pb = NSPasteboard(name: .init("dk.kildahl.cra.test-drop-split"))
            defer { pb.releaseGlobally() }
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setString(text, forType: .URL)
            if let name { item.setString(name, forType: .urlName) }
            pb.writeObjects([item])
            guard let p = Self.payload(on: pb) else { CraLog.note("dropSplit: refused \(text)"); return }
            payload = p
        } else {
            let space = owner.focusedSpaceID
            guard let tab = store.allTabs().first(where: { $0.tab?.url.contains(text) == true && store.spaceID(ofItem: $0.id) == space }) else {
                CraLog.note("dropSplit: no tab with \(text)"); return
            }
            payload = .tab(tab.id)
        }
        let layout = shell.dropLayout
        let point = CGPoint(x: layout.area.minX + layout.area.width * x, y: layout.area.maxY - layout.area.height * y)
        let onScreen: Bool = { if case .tab(let id) = payload { return layout.ids.contains(id) } else { return false } }()
        let proposal = onScreen ? nil : SplitDropProposal.propose(at: point, ids: layout.ids, frames: shell.dropBaseFrames, orientation: layout.orientation,
                                                                    area: layout.area, region: nil, current: nil, sidebarSide: owner.sidebarDocksLeft, link: payload.isLink)
        guard let proposal else { CraLog.note("dropSplit: none"); return }
        switch proposal {
        case .insert(let insert):
            shell.setDropPreview(insert, animated: false)
            shell.layoutSubtreeIfNeeded()
            if let r = shell.dropLayout.frames[ShellView.dropRegionID] {
                let area = layout.area
                let share = insert.orientation == .horizontal ? r.width / area.width : r.height / area.height
                let side = insert.orientation == .horizontal ? (r.minX <= area.minX ? "left" : r.maxX >= area.maxX ? "right" : "middle")
                                                             : (r.maxY >= area.maxY ? "top" : r.minY <= area.minY ? "bottom" : "middle")
                CraLog.note("dropSplit: proposed \(insert.orientation.rawValue) \(insert.index), region \(side) \(String(format: "%.2f", share))")
            }
            shell.setDropPreview(nil, animated: false)
        case .replace(let index):
            let url = store.item(layout.ids[index])?.tab?.url.split(separator: "?").last.map(String.init) ?? "-"
            CraLog.note("dropSplit: proposed replace \(index) (\(url))")
        }
        guard let pane = Self.drop(payload, at: proposal, panes: layout.ids, splitOrientation: shell.splitOrientation, store: store, window: owner.windowID),
              let split = store.splitContaining(pane) else { CraLog.note("dropSplit: refused"); return }
        owner.refresh()
        let urls = split.children.compactMap { store.item($0)?.tab?.url }.map { $0.split(separator: "?").last.map(String.init) ?? $0 }
        let focused = store.item(pane)?.tab?.url.split(separator: "?").last.map(String.init) ?? "-"
        let factors = SplitPaneLayout.normalizedFactors(ids: split.children, stored: store.item(split.id)?.split?.widthFactors ?? [:])
        CraLog.note("dropSplit: split \(store.item(split.id)?.split?.orientation.rawValue ?? "-") \(urls.joined(separator: " | ")) open=\(focused) shares=\(split.children.map { String(format: "%.2f", factors[$0] ?? 0) }.joined(separator: " "))")
    }

    // MARK: Leaving

    /// Takes the region and the card away and shows the dragged tab again; nil, for the page.
    @discardableResult
    private func clear(_ info: NSDraggingInfo?) -> NSDragOperation? {
        guard let owner else { return nil }
        if current != nil {
            current = nil
            owner.shell.setDropPreview(nil)
            owner.shell.dropReplaceID = nil
        }
        if let s = swapped {
            swapped = nil
            if owner.store.item(s.dragged) != nil {
                owner.store.selectTab(s.dragged, window: owner.windowID)
                owner.refresh()
            }
        }
        if let info { restoreCard(info) }
        return nil
    }

    // MARK: The drag image

    /// Arc's SplitDragPreviewView over the panes: a dark card with the tab's icon and title
    /// (1.173.1, measured 216 × 238 pt, black at 90 %).
    static let cardSize = NSSize(width: 216, height: 238)

    private func showCard(_ info: NSDraggingInfo, for payload: Payload) {
        guard let owner else { return }
        if cardDrag != info.draggingSequenceNumber { savedImages = [:]; savedFrames = [:] }
        guard savedImages.isEmpty else { return }
        cardDrag = info.draggingSequenceNumber
        let title: String
        let icon: NSImage?
        switch payload {
        case .tab(let id):
            let item = owner.store.item(id)
            title = item?.displayTitle ?? ""
            icon = item?.tab.flatMap { owner.app.favicons.image(for: $0.url) }
        case .link(let link):
            title = link.title.isEmpty ? (URL(string: link.url)?.host ?? link.url) : link.title
            icon = owner.app.favicons.image(for: link.url)
        }
        let image = Self.card(title: title, icon: icon)
        info.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, index, _ in
            self.savedImages[index] = item.imageComponents ?? []
            self.savedFrames[index] = item.draggingFrame
            let at = item.draggingFrame
            item.setDraggingFrame(NSRect(x: at.midX - Self.cardSize.width / 2, y: at.midY - Self.cardSize.height / 2,
                                         width: Self.cardSize.width, height: Self.cardSize.height), contents: image)
        }
    }

    private func restoreCard(_ info: NSDraggingInfo) {
        guard !savedImages.isEmpty else { return }
        let images = savedImages, frames = savedFrames
        savedImages = [:]
        savedFrames = [:]
        info.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, index, _ in
            guard let components = images[index], let frame = frames[index] else { return }
            item.draggingFrame = frame
            item.imageComponentsProvider = { components }
        }
    }

    static func card(title: String, icon: NSImage?) -> NSImage {
        NSImage(size: cardSize, flipped: false) { r in
            NSColor.black.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: r, xRadius: 22, yRadius: 22).fill()
            let iconSize: CGFloat = 16
            let iconRect = NSRect(x: r.midX - iconSize / 2, y: r.midY + 4, width: iconSize, height: iconSize)
            if let icon {
                icon.draw(in: iconRect)
            } else {
                NSColor.white.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: iconRect, xRadius: 3, yRadius: 3).fill()
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                        .foregroundColor: NSColor.white, .paragraphStyle: style]
            (title as NSString).draw(in: NSRect(x: 16, y: r.midY - 22, width: r.width - 32, height: 16), withAttributes: attrs)
            return true
        }
    }
}
