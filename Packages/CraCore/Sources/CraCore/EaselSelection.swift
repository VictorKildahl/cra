import Foundation

/// Picking several items on an Easel (#580). Arc's Easel picks one item at a time; Cra picks the way
/// the rest of the Mac does (Victor, 20 Nov 2026): ⌘- or ⇧-click adds an item or takes it out, and a
/// drag from empty canvas draws a box that picks every item it touches. The group then moves, snaps,
/// layers, copies, duplicates, deletes and takes a colour together.
extension Easel {
    /// What a click picks, from `current`. With ⌘ or ⇧ (`extend`) the clicked item goes in or out and
    /// a click on empty canvas keeps the picks. Without, a click on a picked item keeps the group so it
    /// can be dragged, another item is picked alone, and empty canvas picks nothing.
    public static func picked(_ current: [UUID], click hit: UUID?, extend: Bool) -> [UUID] {
        guard let hit else { return extend ? current : [] }
        if extend { return current.contains(hit) ? current.filter { $0 != hit } : current + [hit] }
        return current.contains(hit) ? current : [hit]
    }

    /// What a drawn box picks: the items it `touched`, or with ⌘ or ⇧ held, those flipped in the picks
    /// from `before` the drag (Finder's way).
    public static func picked(_ before: [UUID], band touched: [UUID], extend: Bool) -> [UUID] {
        guard extend else { return touched }
        return before.filter { !touched.contains($0) } + touched.filter { !before.contains($0) }
    }

    /// The items whose frames `band` touches, bottom to top (a flat arrow's frame has no height and
    /// still counts).
    public func touching(_ band: Rect) -> [UUID] {
        items.filter { i in
            let f = i.frame
            return f.x <= band.x + band.width && band.x <= f.x + f.width && f.y <= band.y + band.height && band.y <= f.y + f.height
        }.map(\.id)
    }

    /// One box round `frames`, or nil for none.
    public static func bounds(of frames: [Rect]) -> Rect? {
        guard let first = frames.first else { return nil }
        let minX = frames.map(\.x).min() ?? first.x, minY = frames.map(\.y).min() ?? first.y
        let maxX = frames.map { $0.x + $0.width }.max() ?? first.x, maxY = frames.map { $0.y + $0.height }.max() ?? first.y
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The easel with the items `ids` moved by `d`. With `snap` (Use Alignment Guides) their box goes
    /// onto the nearest edges of the other items, and all of them move with it; the guides to draw come
    /// back too.
    public func moving(_ ids: [UUID], by d: Point, snap: Bool) -> (easel: Easel, guides: [Guide]) {
        let picked = Set(ids)
        var delta = d
        var guides: [Guide] = []
        if snap, let box = Self.bounds(of: items.filter { picked.contains($0.id) }.map(\.frame)) {
            let moved = box.offset(by: d)
            let snapped = Self.snapped(moved, to: items.filter { !picked.contains($0.id) }.map(\.frame))
            delta = Point(d.x + snapped.frame.x - moved.x, d.y + snapped.frame.y - moved.y)
            guides = snapped.guides
        }
        var out = self
        for i in out.items.indices where picked.contains(out.items[i].id) { out.items[i] = out.items[i].moved(by: delta) }
        return (out, guides)
    }

    // MARK: Layering a group (the object menu's Bring to Front, Send to Back)

    /// The items `ids` drawn above all the others, in the order they were among themselves.
    public mutating func bringToFront(_ ids: [UUID]) {
        let set = Set(ids)
        items = items.filter { !set.contains($0.id) } + items.filter { set.contains($0.id) }
    }

    /// The items `ids` drawn below all the others, in the order they were among themselves.
    public mutating func sendToBack(_ ids: [UUID]) {
        let set = Set(ids)
        items = items.filter { set.contains($0.id) } + items.filter { !set.contains($0.id) }
    }

    /// Whether the items `ids` are already the top of the stack.
    public func isFront(_ ids: [UUID]) -> Bool { Set(items.suffix(ids.count).map(\.id)) == Set(ids) }

    /// Whether the items `ids` are already the bottom of the stack.
    public func isBack(_ ids: [UUID]) -> Bool { Set(items.prefix(ids.count).map(\.id)) == Set(ids) }
}
