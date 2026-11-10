import AppKit
import SwiftUI

/// Dia's paging container in AppKit: every space's column (favorites, header, tab list) sits
/// side by side on a strip, the strip follows a swipe 1:1, then a spring settles it on a page.
/// The strip only ever moves by frame. AppKit draws just the views it knows are inside the pager,
/// so a column brought in or kept on screen by a layer translation alone showed blank: the next
/// space while the fingers moved, the last one while a space change sprang (issue #12). Neither
/// the swipe nor the settle lays out or diffs a row.
@MainActor
final class SpacePagerView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let favicons: FaviconCache
    private let strip = NSView()
    private var columns: [UUID: NSView] = [:]
    /// The page the strip was placed at, and the width it was placed with.
    private var placedIndex = 0
    private var placedWidth: CGFloat = 0
    private var placedSwipe: CGFloat = 0
    /// Release speed for the next settle, relative to the distance left (Dia's spring).
    private var pendingVelocity: Double = 0
    private var ownSettle: Int?
    private var spring: Spring?
    private var link: CADisplayLink?

    /// Dia's zero-bounce spring (CASpringAnimation perceptualDuration 0.4, bounce 0): critically
    /// damped, so the offset from the page is (x0 + (v0 + ω·x0)·t)·e^(−ω·t).
    private struct Spring {
        let index: Int
        let start: CFTimeInterval
        let x0: CGFloat
        let v0: CGFloat
        static let omega: CGFloat = 2 * .pi / 0.4

        func offset(at time: CFTimeInterval) -> CGFloat {
            let t = CGFloat(max(0, time - start))
            return (x0 + (v0 + Self.omega * x0) * t) * exp(-Self.omega * t)
        }
    }

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        super.init(frame: .zero)
        wantsLayer = true
        // SidebarView's mask clips the pages with room above the top favorites for notes.
        strip.wantsLayer = true
        addSubview(strip)
        ui.observeSpaceSwipe { [weak self] in self?.swipeChanged() }
        observeSpaces()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // The strip takes no clicks or hovers under the fingers, nor while the Library covers it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        ui.spaceSwipe != 0 || ui.libraryPage != nil ? nil : super.hitTest(point)
    }

    private func observeSpaces() {
        withObservationTracking {
            _ = store.pagedSpaces(window: ui.windowID).map(\.id)
            _ = store.focusedSpaceID(window: ui.windowID)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSpaces() }
        }
        needsLayout = true
    }

    private func swipeChanged() {
        let swipe = ui.spaceSwipe
        if swipe == 0 {
            pendingVelocity = ui.spaceSettleVelocity
            needsLayout = true
            return
        }
        if placedSwipe == 0 { SpaceListView.endHover(for: ui) }
        // Under the fingers the strip follows at once, without a layout pass. The swipe counts
        // from the space shown, which a release can change before this view lays out.
        let index = store.pagedSpaces(window: ui.windowID).map(\.id).firstIndex(of: store.focusedSpaceID(window: ui.windowID)) ?? placedIndex
        stopSpring()
        place(index: index, offset: -swipe * placedWidth)
        placedSwipe = swipe
    }

    /// The strip at `index`'s page, `offset` points to the right of it.
    private func place(index: Int, offset: CGFloat) {
        let x = -CGFloat(index) * placedWidth + offset
        guard strip.frame.minX != x else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.setFrameOrigin(NSPoint(x: x, y: 0))
        CATransaction.commit()
        holdSharedFavorites()
    }

    /// Between two pages that show one favorites list (#154) the tiles stay where they are,
    /// as Arc's do: each page's copy is held back by the page's offset, the nearer one shown.
    private func holdSharedFavorites() {
        guard placedWidth > 0 else { return }
        let ids = store.pagedSpaces(window: ui.windowID).map(\.id)
        let shown = -strip.frame.minX / placedWidth
        let left = Int(shown.rounded(.down))
        let moving = abs(shown - shown.rounded()) > 0.001
        func list(_ i: Int) -> UUID? { ids.indices.contains(i) ? store.space(ids[i])?.favoritesContainerID : nil }
        let shared = moving && list(left) != nil && list(left) == list(left + 1)
        for (i, id) in ids.enumerated() {
            guard let column = columns[id] as? SpaceColumnView else { continue }
            guard shared, i == left || i == left + 1 else { column.holdFavorites(shift: 0, shown: true); continue }
            let dx = column.frame.minX + strip.frame.minX
            column.holdFavorites(shift: -dx, shown: i == Int(shown.rounded()))
        }
    }

    private func column(for id: UUID) -> NSView {
        if let c = columns[id] { return c }
        let host = SpaceColumnView(spaceID: id, store: store, ui: ui, actions: actions, favicons: favicons)
        columns[id] = host
        strip.addSubview(host)
        return host
    }

    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height
        let ids = store.pagedSpaces(window: ui.windowID).map(\.id)
        let index = ids.firstIndex(of: store.focusedSpaceID(window: ui.windowID)) ?? 0
        for (id, c) in columns where !ids.contains(id) {
            c.removeFromSuperview()
            columns[id] = nil
        }
        // Where the strip shows now, in pages (mid-spring if one runs).
        let shown = placedWidth > 0 ? -strip.frame.minX / placedWidth : nil
        let swipe = ui.spaceSwipe
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.setFrameSize(NSSize(width: CGFloat(max(1, ids.count)) * width, height: height))
        for (i, id) in ids.enumerated() {
            let f = NSRect(x: CGFloat(i) * width, y: 0, width: width, height: height)
            let c = column(for: id)
            if c.frame != f { c.frame = f }
        }
        CATransaction.commit()

        let moved = index != placedIndex || placedSwipe != 0
        placedIndex = index
        placedWidth = width
        placedSwipe = swipe
        if swipe != 0 {
            // Fingers on the trackpad: follow them exactly.
            stopSpring()
            place(index: index, offset: -swipe * width)
        } else if moved, let shown, abs(shown - CGFloat(index)) > 0.002, width > 0 {
            settle(index: index, from: -(shown - CGFloat(index)) * width)
        } else if let spring, spring.index == index {
            place(index: index, offset: spring.offset(at: CACurrentMediaTime()))
        } else {
            stopSpring()
            place(index: index, offset: 0)
        }
    }

    /// Dia settles pages with a zero-bounce spring that picks up the release speed.
    private func settle(index: Int, from x: CGFloat) {
        // CASpringAnimation's initialVelocity: the distance to travel per second.
        spring = Spring(index: index, start: CACurrentMediaTime(), x0: x, v0: -CGFloat(pendingVelocity) * x)
        pendingVelocity = 0
        place(index: index, offset: x)
        ownSettle = ui.beginSpaceSettle()
        guard window != nil else { finishSpring(); return }
        if link == nil {
            let l = displayLink(target: self, selector: #selector(step))
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let spring else { stopSpring(); return }
        let time = link.targetTimestamp
        let x = spring.offset(at: time)
        let speed = abs(x - spring.offset(at: time - 0.01)) * 100
        if abs(x) < 0.25 && speed < 5 {
            finishSpring()
        } else {
            place(index: spring.index, offset: x)
        }
    }

    private func finishSpring() {
        let index = spring?.index ?? placedIndex
        stopSpring()
        place(index: index, offset: 0)
        if let generation = ownSettle {
            ownSettle = nil
            ui.endSpaceSettle(generation)
        }
        SpaceListView.refreshHover(for: ui)
    }

    private func stopSpring() {
        spring = nil
        link?.invalidate()
        link = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, spring != nil { finishSpring() }
    }
}
