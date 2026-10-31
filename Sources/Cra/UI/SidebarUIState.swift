import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Transient sidebar UI state shared between AppKit and SwiftUI.
@MainActor
@Observable
final class SidebarUIState {
    /// The browser window this sidebar belongs to (its space and open tab, see WindowSession).
    @ObservationIgnored var windowID = UUID()
    var renamingID: UUID?
    var draggingID: UUID?
    var hoveredTabID: UUID?
    /// Loading progress per tab (0...1), fed by the browser manager.
    var progress: [UUID: Double] = [:]
    var loadedTabIDs: Set<UUID> = []
    /// Tabs using the camera or microphone (Arc's recording indicator).
    var capturingTabIDs: Set<UUID> = []
    /// Tabs playing sound (Arc's speaker button).
    var audibleTabIDs: Set<UUID> = []
    /// The window's sidebar player (NowPlayingTrayView), fed by its BrowserManager.
    @ObservationIgnored let nowPlaying = NowPlaying()
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var isCompact = false
    /// Cra is the frontmost app (Arc darkens the sidebar header's glyphs then).
    var appActive = true
    /// Page theme colour of the visible tab ("#RRGGBB" or "").
    var pageThemeColor = ""
    /// The latest download, drawn over the Library button the way Arc does (its
    /// DownloadToLibrary "bin": the file's thumbnail that the download glyph flies into).
    var recentDownload: RecentDownload?
    /// The Library button's view, where download flights land.
    @ObservationIgnored weak var libraryAnchor: NSView?
    /// Arc's downloads list over the bottom of the sidebar, open while the Library
    /// button (or the list) is hovered.
    var downloadsListOpen = false
    @ObservationIgnored var libraryHovered = false
    @ObservationIgnored var downloadsListHovered = false
    @ObservationIgnored var downloadsListWork: DispatchWorkItem?
    /// The Library page this window's sidebar shows, nil while it shows the tabs (Arc keeps the
    /// Library per window and reopens it on the page last shown).
    var libraryPage: LibraryPage?
    @ObservationIgnored var lastLibraryPage: LibraryPage = .downloads
    /// Tab chosen from the keyboard in another space (the tab switcher); Arc draws its
    /// yellow/black dashed ring around it until the mouse picks another tab.
    var keyboardFocusID: UUID?
    /// The pointer is over a draggable sidebar row or tile. The window is
    /// movable by its background; the window controller turns that off while
    /// this is true so a press starts SwiftUI's `.draggable`, not a window drag.
    var pointerOverDraggable: Bool { draggableUnderPointer != nil }
    @ObservationIgnored var onPointerOverDraggableChange: (Bool) -> Void = { _ in }
    /// Moving between rows, the next row's hover can arrive before the last
    /// one's exit; a shared flag then ended up false over a row and the press
    /// dragged the window instead of the tab. Each row clears only itself.
    @ObservationIgnored private var draggableUnderPointer: UUID? {
        didSet { if (oldValue != nil) != (draggableUnderPointer != nil) { onPointerOverDraggableChange(pointerOverDraggable) } }
    }

    func hoverDraggable(_ id: UUID, _ inside: Bool) {
        if inside { draggableUnderPointer = id } else if draggableUnderPointer == id { draggableUnderPointer = nil }
    }
    /// Per-tab navigation state for split panes (each pane has its own toolbar).
    var navStates: [UUID: TabNavState] = [:]
    /// Panes currently shown in the window (empty when a single page shows).
    var splitPaneIDs: [UUID] = []
    /// A sidebar tab is being dragged over the content area; which pane edge it would land on.
    var splitDropTarget: SplitDropTarget?
    /// Live space swipe, in pages away from the focused space (+ toward the next one);
    /// 0 at rest. The sidebar pages and the window tint follow it (Dia: PageSwipeController).
    var spaceSwipe: CGFloat = 0 { didSet { for f in spaceSwipeObservers { f() } } }
    /// The space pager and the window tint follow the swipe directly in AppKit, not through SwiftUI.
    @ObservationIgnored private var spaceSwipeObservers: [() -> Void] = []
    func observeSpaceSwipe(_ f: @escaping () -> Void) { spaceSwipeObservers.append(f) }
    /// Release velocity for the settle spring, relative to the distance left to travel.
    var spaceSettleVelocity: Double = 0
    /// The strip is springing onto its page (after a swipe or a space change); it takes no
    /// clicks or hovers until then.
    var spaceSettling = false
    @ObservationIgnored private var settleGeneration = 0

    /// Returns the settle's number for `endSpaceSettle`.
    func beginSpaceSettle() -> Int {
        spaceSettling = true
        settleGeneration &+= 1
        let generation = settleGeneration
        // A spring cut short may never report back: don't leave the strip ignoring clicks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.endSpaceSettle(generation) }
        return generation
    }

    /// An earlier settle ending late leaves a newer one alone.
    func endSpaceSettle(_ generation: Int) {
        guard generation == settleGeneration, spaceSettling else { return }
        spaceSettling = false
        HitchMonitor.mark("swipe-settled")
    }
    /// Dia settles pages with a zero-bounce spring that picks up the release speed.
    var spaceSettleAnimation: Animation {
        .interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: spaceSettleVelocity)
    }
    /// Tabs picked with ⌘/⇧-click; closing acts on all of them.
    var multiSelection: Set<UUID> = []
    /// Where the next ⇧-click range starts.
    var selectionAnchor: UUID?
    /// A sidebar drag over the space's list and what releasing it would do.
    var listDrop: SidebarListDrop?
    /// Dia's nav-bar status: a short confirmation shown in place of the URL
    /// ("Copied Current URL"), then the URL comes back.
    var toolbarStatus: ToolbarStatus?
    @ObservationIgnored private var statusClear: Task<Void, Never>?

    func flashStatus(_ text: String, symbol: String, for seconds: Double = 2) {
        let status = ToolbarStatus(symbol: symbol, text: text)
        withAnimation(.easeOut(duration: 0.15)) { toolbarStatus = status }
        statusClear?.cancel()
        statusClear = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.toolbarStatus?.id == status.id else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.toolbarStatus = nil }
        }
    }

    func navState(for id: UUID) -> TabNavState { navStates[id] ?? TabNavState() }

    /// ⌘-click toggles a tab, ⇧-click adds the run of rows from the anchor.
    /// The open tab counts as picked when a selection starts (Finder-style).
    func pick(_ id: UUID, range: Bool, in store: SidebarStore) {
        let order = store.listedTabIDs(in: store.focusedSpaceID(window: windowID))
        let open = store.selectedTabID(window: windowID)
        if multiSelection.isEmpty, let open, order.contains(open) { multiSelection = [open] }
        if range, let a = order.firstIndex(of: selectionAnchor ?? open ?? id), let b = order.firstIndex(of: id) {
            multiSelection.formUnion(order[min(a, b)...max(a, b)])
        } else {
            if multiSelection.contains(id) { multiSelection.remove(id) } else { multiSelection.insert(id) }
            selectionAnchor = id
        }
    }

    /// The tabs an action on this row moves: every picked tab, in sidebar
    /// order, when the row is one of several picks; otherwise just the row.
    func group(for id: UUID, in store: SidebarStore) -> [UUID] {
        guard multiSelection.count > 1, multiSelection.contains(id) else { return [id] }
        return store.listedTabIDs(in: store.focusedSpaceID(window: windowID)).filter { multiSelection.contains($0) }
    }

    func clearPicks(anchor: UUID? = nil) {
        if !multiSelection.isEmpty { multiSelection = [] }
        selectionAnchor = anchor
    }
}

struct ToolbarStatus: Equatable, Identifiable {
    let id = UUID()
    let symbol: String
    let text: String
}

struct RecentDownload: Equatable {
    let id: UInt32
    var path: String
    /// The file type's icon until the download finishes, then its Quick Look thumbnail.
    var image: NSImage
}

struct TabNavState: Equatable {
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var themeColor = ""
}

/// Where a dragged tab or link would go in the split (Arc: SplitViewControllerLayout.DropTarget).
enum SplitDropTarget: Equatable {
    case insert(index: Int)
    case replace(index: Int)
}

/// Things the sidebar needs AppKit to do.
@MainActor
final class SidebarActions {
    var openCommandBar: (CommandBarMode) -> Void = { _ in }
    var closeTab: (UUID) -> Void = { _ in }
    var goBack: () -> Void = {}
    var goForward: () -> Void = {}
    var reload: () -> Void = {}
    var editSpace: (Space?) -> Void = { _ in }
    var toggleSidebar: () -> Void = {}
    var toggleLibrary: () -> Void = {}
    /// The Library in the sidebar: open it on a page, leave it, restore an archived tab from it.
    var showLibrary: (LibraryPage) -> Void = { _ in }
    var closeLibrary: () -> Void = {}
    var restoreArchived: (UUID) -> Void = { _ in }
    var resetPinnedTab: (UUID) -> Void = { _ in }
    var openURL: (String) -> Void = { _ in }
    var performAction: (String) -> Void = { _ in }
    /// Double-click on an empty part of the header strip (sidebar title row or toolbar).
    var titleBarDoubleClick: () -> Void = {}
    /// Split view: make a pane the focused one (its toolbar acts on it).
    var focusPane: (UUID) -> Void = { _ in }
    /// Split view: close one pane (Arc: "Close this Split Pane").
    var closePane: (UUID) -> Void = { _ in }
    /// Split view: move a pane out into its own tab (Arc: "Separate Tab from Split").
    var separatePane: (UUID) -> Void = { _ in }
    /// Split view: pane-level navigation (goBack/goForward/reload by tab).
    var paneNavigate: (UUID, String) -> Void = { _, _ in }
    /// Split view: open the command bar for one pane (edit its URL / fill an empty pane).
    var editPaneURL: (UUID) -> Void = { _ in }
    /// Toolbar extension button (Chromium extension ID): run its action on the focused page.
    var runExtension: (String) -> Void = { _ in }
    /// Toolbar Extensions button: the extensions menu, under the pointer.
    var showExtensionsMenu: () -> Void = {}
}

private struct SidebarActionsKey: EnvironmentKey {
    @MainActor static var defaultValue: SidebarActions { SidebarActions() }
}

extension EnvironmentValues {
    var sidebarActions: SidebarActions {
        get { self[SidebarActionsKey.self] }
        set { self[SidebarActionsKey.self] = newValue }
    }
}

extension UTType {
    static let craSidebarItem = UTType(exportedAs: "dk.kildahl.cra.sidebar-item")
}

struct SidebarDragItem: Codable, Transferable {
    let id: UUID

    /// `.draggable` evaluates its payload when the drag starts; record what
    /// is being dragged so drop targets can preview before the drop.
    static func begin(_ id: UUID, _ ui: SidebarUIState) -> SidebarDragItem {
        MainActor.assumeIsolated { ui.draggingID = id }
        return SidebarDragItem(id: id)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .craSidebarItem)
    }
}
