import SwiftUI

/// Dia's Privacy pane: a "Content blocking" card of switch rows with coloured glyphs
/// (Block ads / Block cookie banners / Block trackers) and a "Data" card. Cra ships one
/// ad-and-tracker domain list, so it has one switch and no usage-data row; "Connections"
/// is Chrome's "Always use secure connections". "Data" holds Arc's Clear Browsing Data (Arc keeps
/// it in Settings ▸ Profiles and opens Chrome's Privacy and security page; Cra opens Chrome's
/// Delete browsing data dialog itself, the step after). "Connections" also holds Chromium's
/// secure DNS setting, which Arc and Dia leave to chrome://settings/security (#133).
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
                SettingsCardDivider()
                // Arc: Settings ▸ General "Block Cookie Banners", off by default.
                SettingsCardRow {
                    HStack(spacing: 5.5) {
                        SettingsGlyph(symbol: "eye.slash.fill", color: Color(nsColor: .systemOrange))
                        Text("Block cookie banners").font(.system(size: 13))
                    }
                } trailing: {
                    Toggle("Block cookie banners", isOn: $store.settings.blockCookieBanners)
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            SettingsFootnote("Requests to known ad and tracker domains are cancelled unless they are first-party to the page. Cookie banners from the common consent tools are hidden; pages load again with the change.")

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
                SettingsCardDivider()
                SecureDNSRows(error: $dnsError)
            }
            SettingsFootnote("Pages load over HTTPS. Before opening a site that doesn’t support it, Cra warns you first.")
            if let line = dnsFootnote { SettingsFootnote(line) }
            if let dnsError { SettingsFootnote(dnsError).foregroundStyle(.red) }

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

    @State private var dnsError: String?

    private var dnsFootnote: String? {
        let dns = SecureDNSSetting.shared
        guard let summary = dns.inEffect?.summary, !summary.isEmpty else { return nil }
        return dns.isManaged ? "Your organization sets secure DNS. " + summary : summary
    }
}

/// Chromium's secure DNS setting (chrome://settings/security) as a menu, under "Always use
/// secure connections": the lookup before the page (#133). Custom adds a row for the template.
private struct SecureDNSRows: View {
    @Binding var error: String?
    private let dns = SecureDNSSetting.shared
    @State private var editingCustom = false
    @State private var customText = ""

    var body: some View {
        SettingsCardRow {
            HStack(spacing: 5.5) {
                SettingsGlyph(symbol: "network.badge.shield.half.filled", color: Color(nsColor: .systemBlue))
                Text("Secure DNS").font(.system(size: 13))
            }
        } trailing: {
            Picker("Secure DNS", selection: choice) {
                Text("Automatic").tag(SecureDNSChoice.automatic)
                Text("Off").tag(SecureDNSChoice.off)
                Divider()
                ForEach(SecureDNSProvider.all) { Text($0.name).tag(SecureDNSChoice.provider($0)) }
                Divider()
                Text("Custom…").tag(SecureDNSChoice.custom)
            }
            .labelsHidden()
            .fixedSize()
            .disabled(dns.prefs == nil || dns.isManaged)
            .onAppear { dns.refresh() }
            .onChange(of: liveCustom, initial: true) { if let liveCustom { customText = liveCustom } }
        }
        if showsCustom {
            SettingsCardDivider()
            SettingsCardRow {
                TextField("Custom provider", text: $customText, prompt: Text("https://dns.example/dns-query{?dns}"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(saveCustom)
                    .disabled(dns.isManaged)
            } trailing: {
                Button("Use", action: saveCustom)
                    .disabled(dns.isManaged || customText.trimmingCharacters(in: .whitespacesAndNewlines) == liveCustom)
            }
        }
    }

    private var current: SecureDNSChoice { dns.prefs?.choice ?? .automatic }
    private var liveCustom: String? { current == .custom ? dns.prefs?.templates : nil }
    private var showsCustom: Bool { editingCustom || current == .custom }

    private var choice: Binding<SecureDNSChoice> {
        Binding(get: { editingCustom ? .custom : current }, set: { new in
            error = nil
            if new == .custom {
                if !showsCustom { customText = "" }
                editingCustom = true
                return
            }
            editingCustom = false
            if let prefs = SecureDNSPrefs(new), !dns.apply(prefs) { error = "Cra couldn’t change secure DNS." }
        })
    }

    private func saveCustom() {
        guard let prefs = SecureDNSPrefs(.custom, custom: customText) else {
            error = "Enter one or more https:// templates, like https://dns.example/dns-query{?dns}."
            return
        }
        error = nil
        if dns.apply(prefs) {
            editingCustom = false
            customText = prefs.templates
        } else {
            error = "Cra couldn’t change secure DNS."
        }
    }
}
