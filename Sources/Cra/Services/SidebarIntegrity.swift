import Foundation

extension SidebarStore {
    /// What must hold between any two mutations: a child points back at the parent that lists
    /// it, nothing is listed twice, every item hangs under a space's container, and a window's
    /// selected tab lives in the space it is selected for. Empty when the sidebar is sound.
    /// Scenarios check it at the end of a journey (cra://debug?checkStore=1, one fault line
    /// per problem) and the store tests after each kind of change.
    func integrityProblems() -> [String] {
        let all = items.all
        func name(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }
        var problems: [String] = []
        var listedBy: [UUID: UUID] = [:]
        for (id, it) in all {
            for c in it.children {
                if let other = listedBy[c], other != id { problems.append("\(name(c)) is listed by both \(name(other)) and \(name(id))") }
                listedBy[c] = id
                guard let child = all[c] else { problems.append("\(name(id)) lists missing item \(name(c))"); continue }
                if child.parentID != id { problems.append("\(name(c)) is listed by \(name(id)) but points at \(child.parentID.map(name) ?? "nothing")") }
            }
            if Set(it.children).count != it.children.count { problems.append("\(name(id)) lists a child twice") }
        }
        for (id, it) in all {
            if let p = it.parentID {
                if all[p] == nil { problems.append("\(name(id)) points at missing parent \(name(p))") }
                else if listedBy[id] == nil { problems.append("\(name(id)) is not listed by its parent \(name(p))") }
            } else if it.container == nil {
                problems.append("\(name(id)) hangs under nothing")
            }
            // A cycle would hang every walk up the tree (rootContainer, spaceID).
            var seen: Set<UUID> = [id]
            var up = it.parentID
            while let p = up {
                guard seen.insert(p).inserted else { problems.append("\(name(id)) is inside its own subtree"); break }
                up = all[p]?.parentID
            }
        }
        for space in spaces.values {
            for c in [space.favoritesContainerID, space.pinnedContainerID, space.todayContainerID] where all[c]?.container == nil {
                problems.append("space \(name(space.id)) has no container \(name(c))")
            }
        }
        for w in prefs.windows {
            for (sid, tid) in w.selectedTabPerSpace where all[tid] != nil && spaceID(ofItem: tid) != sid {
                problems.append("window \(name(w.id)) selects \(name(tid)) for space \(name(sid)), but it lives elsewhere")
            }
        }
        return problems.sorted()
    }
}
