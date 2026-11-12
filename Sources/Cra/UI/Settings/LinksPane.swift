import SwiftUI

/// Arc's Links pane: where links open. Little Windows for links from other apps (Arc's Little
/// Arc switch and "Archive Little Arcs after:"), Peek for links to other sites, what "Open Link in
/// New Tab" does, and the "Air Traffic Control…" button. Little Windows and Peek, which open
/// a different kind of window, carry a picture like Settings ▸ Tabs; the rest are plain rows.
struct LinksPane: View {
    @Environment(SidebarStore.self) private var store
    @State private var showsAirTrafficControl = false

    var body: some View {
        @Bindable var store = store
        let newLittleWindow = KeyBindingRegistry.shared.action("newLittleWindow")?.primary?.display ?? "⌥⌘N"
        SettingsCardPane {
            SettingsHeader("Little Windows")
            SettingsFeatureCard {
                SettingsSwitchRow("Open links from other apps in a Little Window",
                                  detail: "A link you click in Mail, Slack or another app opens in a small window you can read and close, instead of a new tab in your sidebar.",
                                  isOn: $store.settings.openExternalLinksInLittleWindow) { SettingsArt.littleWindowFromApps }
                SettingsCardDivider()
                // Arc's "Open Little Arc when I press ⌥⌘N" (#195): New Little Window's shortcut from any app.
                SettingsToggleRow("\(newLittleWindow) in any app",
                                  detail: "Press \(newLittleWindow) wherever you are to open a Little Window, even while Cra isn’t in front.",
                                  isOn: $store.settings.littleWindowShortcutEverywhere)
                    .settingsTextColumn()
                SettingsCardDivider()
                // Arc's "Open Little Arc when clicking on links with ⌥⌘ held" (LittleWindowTrigger). Off in Cra:
                // a ⌘⌥-click opens Split View otherwise (#298).
                SettingsToggleRow("⌥⌘-click opens a Little Window",
                                  detail: "Hold ⌥ and ⌘ while you click a link to open it in a Little Window instead of Split View.",
                                  isOn: $store.settings.littleWindowOnOptionCommandClick)
                    .settingsTextColumn()
                SettingsCardDivider()
                // Arc: "Archive Little Arcs after:" 1 hour, 6 hours (default), 12 hours.
                SettingsPlainRow("Archive Little Windows",
                                 detail: "A Little Window you leave alone closes into the archive, where you can find it again.") {
                    Picker("Archive Little Windows after", selection: $store.settings.littleWindowArchiveAfter) {
                        ForEach(LittleWindowArchive.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .settingsTextColumn()
            }

            SettingsHeader("Peek").padding(.top, 20)
            SettingsFeatureCard {
                SettingsSwitchRow("Peek at links to other sites",
                                  detail: "A link to another site opens in a Peek over the page, so you can read it and close it without losing your place.",
                                  isOn: $store.settings.peekLinksToOtherSites) {
                    SettingsArt.peekLinks
                } below: {
                    Toggle("In every tab, not only Favorites and Pinned tabs", isOn: $store.settings.peekInEveryTab)
                        .toggleStyle(.checkbox)
                        .disabled(!store.settings.peekLinksToOtherSites)
                }
                SettingsCardDivider()
                SettingsToggleRow("Peek with ⇧-click",
                                  detail: "Hold ⇧ while you click any link to open it in a Peek.",
                                  isOn: $store.settings.peekOnShiftClick)
                    .settingsTextColumn()
                SettingsCardDivider()
                // Not in Arc (GitHub #380): off by default, Expand makes a new tab as in Arc.
                SettingsToggleRow("⌘-click Expand opens in the tab",
                                  detail: "Hold ⌘ while you click a Peek’s Expand button to open the page in the tab you were peeking from, instead of a new tab. Back takes that tab to where it was, and a pinned tab keeps its pinned page.",
                                  isOn: $store.settings.peekExpandInSourceTab)
                    .settingsTextColumn()
            }

            SettingsHeader("New tabs").padding(.top, 20)
            SettingsFeatureCard {
                // Off as in Arc, whose "Open Link in New Tab" keeps the page in front (#276).
                SettingsToggleRow("Switch to links opened in new tabs",
                                  detail: "“Open Link in New Tab” brings the new tab to the front. Off, the page you’re reading stays in front, as in Arc. ⌘-click opens a link behind the page and ⇧⌘-click switches to it either way.",
                                  isOn: $store.settings.openLinksInForeground)
                SettingsCardDivider()
                SettingsPlainRow("Air Traffic Control", detail: routesDetail) {
                    Button("Edit Routes…") { showsAirTrafficControl = true }
                }
            }
        }
        .sheet(isPresented: $showsAirTrafficControl) {
            AirTrafficControlView().environment(store)
        }
    }

    private var routesDetail: String {
        let lead = "Send links from other apps to the space you choose, by what their address contains."
        switch store.settings.linkRoutes.count {
        case 0: return lead
        case 1: return lead + " 1 route set."
        case let n: return lead + " \(n) routes set."
        }
    }
}
