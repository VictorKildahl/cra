import Foundation

extension SpaceListView {
    func applyDrop(_ drop: SidebarListDrop) {
        store.withPinningWindow(ui.windowID) {
            let id = drop.draggedID
            // A picked tab carries the other picks along (a split still takes one pane).
            let group = ui.group(for: id, in: store)
            switch drop.target {
            case .insert(let parent, let index)?:
                store.moveItems(group, to: parent, index: index)
            case .split(let tab, let leading)?:
                // Arc opens the tab a drag picks up, so the new split ends up open on its pane (#180).
                if store.combineIntoSplit(id, onto: tab, leading: leading) != nil { store.selectTab(id, window: ui.windowID) }
            case .into(let target)?:
                if store.item(target)?.isFolder == true {
                    store.dropIntoFolder(group, folder: target)
                } else {
                    store.moveItem(id, to: target, index: nil)
                }
            case nil:
                break
            }
        }
    }
}
