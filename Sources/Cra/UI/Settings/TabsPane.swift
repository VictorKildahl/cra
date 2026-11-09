import SwiftUI

/// Dia's Tabs pane is a two-column form: "General:" checkboxes, "Tab Groups:" checkboxes and
/// "Tab Cleanup:" with a checkbox that enables a duration popup. Cra keeps the groups it has
/// behaviour for.
struct TabsPane: View {
    @Environment(SidebarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SettingsFormPane {
            SettingsFormRow(label: "General:") {
                SettingsCheckbox(title: "Add new tabs to the top", isOn: $store.settings.newTabsAtTop)
                SettingsCheckbox(title: "Show the New Tab button above tabs", isOn: $store.settings.newTabButtonAtTop)
                SettingsCheckbox(title: "Haptic feedback when reordering tabs", isOn: $store.settings.hapticFeedbackOnReorder)
                SettingsCheckbox(title: "Preview a folder’s tabs when hovering over it", isOn: $store.settings.folderPreviews)
                // Arc: Settings ▸ General ▸ Previews (Gmail's unread mail on its favorite).
                SettingsCheckbox(title: "Preview unread Gmail when hovering its favorite", isOn: $store.settings.favoritePreviews)
                SettingsCheckbox(title: "Show toolbar above the page", isOn: $store.settings.showToolbar)
                SettingsCheckbox(title: "Pages fill the window edge to edge", isOn: $store.settings.edgeToEdgeContent)
                SettingsCheckbox(title: "Enable Picture in Picture when you leave a video tab", isOn: $store.settings.autoPictureInPicture)
            }
            // Arc's single-space mode ("Hide Space Header" on the space's menu), for people who
            // don't use spaces.
            SettingsFormRow(label: "Spaces:") {
                SettingsCheckbox(title: "Show the space header with only one space", isOn: $store.settings.showSpaceHeaderOnSingleSpace)
                Text("Off hides the space’s name and its icon at the bottom of the sidebar while you have one space.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                // #154: Arc's favorites, one set per profile.
                SettingsCheckbox(title: "Share Favorites across Spaces with the same profile",
                                 isOn: Binding(get: { store.settings.sharedFavorites }, set: { store.setFavoritesShared($0) }))
                Text("Spaces on one profile show the same Favorites, as in Arc. Turning it on combines their Favorites; turning it off gives each Space its own copy.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Arc's Links pane: the Little Arc switch and "Choose where links open inside
            // Arc." with an "Air Traffic Control…" button.
            SettingsFormRow(label: "Links:") {
                SettingsCheckbox(title: "Links from other apps open in a Little Window", isOn: $store.settings.openExternalLinksInLittleWindow)
                // Arc's "Open Little Arc when I press ⌥⌘N" (#195): New Little Window's shortcut from any app.
                SettingsCheckbox(title: "Open a Little Window when I press \(KeyBindingRegistry.shared.action("newLittleWindow")?.primary?.display ?? "⌥⌘N") in any app",
                                 isOn: $store.settings.littleWindowShortcutEverywhere)
                // Arc: "Archive Little Arcs after:" 1 hour, 6 hours (default), 12 hours.
                HStack(spacing: 6) {
                    Text("Archive Little Windows after:")
                    Picker("", selection: $store.settings.littleWindowArchiveAfter) {
                        ForEach(LittleWindowArchive.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsCheckbox(title: "Open a Peek window when clicking on links to other sites", isOn: $store.settings.peekLinksToOtherSites)
                SettingsCheckbox(title: "In every tab, not only Favorites and Pinned tabs", isOn: $store.settings.peekInEveryTab)
                    .disabled(!store.settings.peekLinksToOtherSites)
                    .padding(.leading, 20)
                SettingsCheckbox(title: "Open a Peek window when clicking on links with Shift held", isOn: $store.settings.peekOnShiftClick)
                // Off as in Arc, whose "Open Link in New Tab" keeps the page in front (#276).
                SettingsCheckbox(title: "“Open Link in New Tab” switches to the new tab", isOn: $store.settings.openLinksInForeground)
                Text("Off, the page you’re reading stays in front, as in Arc. ⌘-click opens a link behind the page and ⇧⌘-click switches to it, whatever this says.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Air Traffic Control…") { showsAirTrafficControl = true }
                    Text(routesSummary).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Choose which space links from other apps open in.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SettingsFormRow(label: "Tab Cleanup:") {
                HStack(spacing: 6) {
                    SettingsCheckbox(title: "Archive tabs I haven’t used in:", isOn: $store.settings.autoArchiveEnabled)
                    Picker("", selection: $store.settings.autoArchive) {
                        ForEach(AutoArchiveThreshold.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!store.settings.autoArchiveEnabled)
                }
                // Tab sleeping (GitHub #153): Arc's 4 hours and nothing more unless you ask.
                HStack(spacing: 6) {
                    SettingsCheckbox(title: "Force tabs out of memory after:", isOn: $store.settings.tabSleepTimerEnabled)
                    Picker("", selection: $store.settings.tabSleepAfter) {
                        ForEach(TabSleepThreshold.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!store.settings.tabSleepTimerEnabled)
                }
                SettingsCheckbox(title: "Force tabs out of memory when the Mac is short of memory",
                                 isOn: $store.settings.tabSleepOnMemoryPressure)
                Text(tabSleepNote).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showsAirTrafficControl) {
            AirTrafficControlView().environment(store)
        }
    }

    @State private var showsAirTrafficControl = false

    /// Says what a forced-out tab costs, and which tabs stay, before the user finds out.
    private var tabSleepNote: String {
        let s = store.settings
        let note = "A tab forced out of memory reloads when you open it. Tabs playing sound, recording or holding text you typed stay."
        guard s.tabSleepTimerEnabled, TabSleepPolicy.timer(s.tabSleepAfter).keepsRecentTabs else { return note }
        return note + (s.tabSleepOnMemoryPressure ? " So do the 10 tabs you used last, unless the Mac is short of memory." : " So do the 10 tabs you used last.")
    }

    private var routesSummary: String {
        switch store.settings.linkRoutes.count {
        case 0: return ""
        case 1: return "1 route"
        case let n: return "\(n) routes"
        }
    }
}
