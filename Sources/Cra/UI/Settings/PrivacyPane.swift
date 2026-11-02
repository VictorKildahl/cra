import SwiftUI

/// Dia's Privacy pane: a "Content blocking" card of switch rows with coloured glyphs
/// (Block ads / Block cookie banners / Block trackers) and a "Data" card. Cra ships one
/// ad-and-tracker domain list, so it has one switch and no usage-data row; "Connections"
/// is Chrome's "Always use secure connections". "Data" holds Arc's Clear Browsing Data (Arc keeps
/// it in Settings ▸ Profiles and opens Chrome's Privacy and security page; Cra opens Chrome's
/// Delete browsing data dialog itself, the step after).
struct PrivacyPane: View {
    @Environment(SidebarStore.self) private var store
    let actions: SettingsActions

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            SettingsHeader("Content blocking")
            SettingsCard {
                SettingsCardRow {
                    HStack(spacing: 5.5) {
                        SettingsGlyph(symbol: "hand.raised.fill", color: Color(nsColor: .systemRed))
                        Text("Block ads and trackers").font(.system(size: 13))
                    }
                } trailing: {
                    Toggle("Block ads and trackers", isOn: $store.settings.blockAdsAndTrackers)
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            SettingsFootnote("Requests to known ad and tracker domains are cancelled unless they are first-party to the page.")

            SettingsHeader("Connections").padding(.top, 20)
            SettingsCard {
                SettingsCardRow {
                    HStack(spacing: 5.5) {
                        SettingsGlyph(symbol: "lock.fill", color: Color(nsColor: .systemGreen))
                        Text("Always use secure connections").font(.system(size: 13))
                    }
                } trailing: {
                    Toggle("Always use secure connections", isOn: $store.settings.httpsOnly)
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            SettingsFootnote("Pages load over HTTPS. Before opening a site that doesn’t support it, Cra warns you first.")

            SettingsHeader("Data").padding(.top, 20)
            SettingsCard {
                SettingsCardRow {
                    HStack(spacing: 5.5) {
                        SettingsGlyph(symbol: "trash.fill", color: Color(nsColor: .systemGray))
                        Text("Browsing data").font(.system(size: 13))
                    }
                } trailing: {
                    Button("Clear Browsing Data…") { actions.openURL(BrowsingDataClear.pageURL) }
                }
            }
            SettingsFootnote("Delete history, cookies and cached files for the current space’s profile. History you delete also leaves the command bar.")
        }
    }
}
