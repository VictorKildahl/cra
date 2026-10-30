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
            }
            // Arc's Links pane: the Little Arc switch and "Choose where links open inside
            // Arc." with an "Air Traffic Control…" button.
            SettingsFormRow(label: "Links:") {
                SettingsCheckbox(title: "Links from other apps open in a Little Window", isOn: $store.settings.openExternalLinksInLittleWindow)
                SettingsCheckbox(title: "Open a Peek window when clicking on links to other sites", isOn: $store.settings.peekLinksToOtherSites)
                Text("Only links in Favorites and Pinned tabs.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                SettingsCheckbox(title: "Open a Peek window when clicking on links with Shift held", isOn: $store.settings.peekOnShiftClick)
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
                HStack(spacing: 6) {
                    SettingsCheckbox(title: "Sleep tabs I haven’t looked at in:", isOn: $store.settings.tabSleepEnabled)
                    Picker("", selection: $store.settings.tabSleep) {
                        ForEach(TabSleepThreshold.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!store.settings.tabSleepEnabled)
                }
                Text("Sleeping tabs free their memory and reload when you open them. Tabs playing sound or holding something you typed stay awake.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showsAirTrafficControl) {
            AirTrafficControlView().environment(store)
        }
    }

    @State private var showsAirTrafficControl = false

    private var routesSummary: String {
        switch store.settings.linkRoutes.count {
        case 0: return ""
        case 1: return "1 route"
        case let n: return "\(n) routes"
        }
    }
}
