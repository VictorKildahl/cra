import AppKit
import SwiftUI

/// Dia's Privacy pane: a "Content blocking" card of switches (Block ads / Block cookie banners /
/// Block trackers) and a "Data" card, each setting a row with what it does under its name. Cra ships one
/// ad-and-tracker domain list, so it has one switch, with the lists people add under it (#507). Fingerprinting protection, under them, is Cra's
/// own (neither Arc nor Dia has it). The Data card's usage-data row ("Share
/// content data to help improve Dia") is Cra's usage stats, with crash reports under it; "Connections"
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
            SettingsFeatureCard {
                SettingsToggleRow("Block ads and trackers",
                                  detail: "Requests to known ad and tracker domains are cancelled, unless the domain belongs to the site you’re on.",
                                  isOn: $store.settings.blockAdsAndTrackers)
                SettingsCardDivider()
                BlockListRows(addresses: $store.settings.customBlocklists, enabled: store.settings.blockAdsAndTrackers)
                SettingsCardDivider()
                // Arc: Settings ▸ General "Block Cookie Banners", off by default.
                SettingsToggleRow("Block cookie banners",
                                  detail: "Cookie banners from the common consent tools are hidden. Pages load again with the change.",
                                  isOn: $store.settings.blockCookieBanners)
                SettingsCardDivider()
                // Not in Arc: Cra's Chromium (fingerprinting-protection.patch).
                SettingsToggleRow("Fingerprinting protection",
                                  detail: "Sites that tell browsers apart by reading back drawings, 3D graphics or sound get faint noise in what they read, different for each site and each time Cra opens. Sites also see 8 processor cores.",
                                  isOn: $store.settings.fingerprintingProtection)
            }

            SettingsHeader("Connections").padding(.top, 20)
            SettingsFeatureCard {
                SettingsToggleRow("Always use secure connections",
                                  detail: "Pages load over HTTPS. Before opening a site that doesn’t support it, Cra warns you first.",
                                  isOn: $store.settings.httpsOnly)
                SettingsCardDivider()
                SecureDNSRows(error: $dnsError, footnote: dnsFootnote)
            }
            if let dnsError { SettingsFootnote(dnsError).foregroundStyle(.red) }

            SettingsHeader("Data").padding(.top, 20)
            SettingsFeatureCard {
                SettingsPlainRow("Clear browsing data",
                                   detail: "Delete history, cookies and cached files for the current space’s profile. History you delete also leaves the command bar.",
                                   trailing: { Button("Clear…") { actions.openURL(BrowsingDataClear.pageURL) } })
                SettingsCardDivider()
                SettingsToggleRow("Share anonymous usage stats",
                                  detail: "Once a day: your Cra and macOS versions, the kind of Mac, rough counts of spaces, tabs and extensions, and which settings you changed. Never the sites you visit, what you search or anything on a page. Each report has a new random ID, so reports can’t be tied together or to you.",
                                  isOn: $store.settings.shareUsageStats) {
                    HStack(spacing: 12) {
                        Button("Show What’s Sent") { SharingService.shared.showStats() }
                        Link("How Cra handles your data", destination: URL(string: SiteLinks.tagged("https://crabrowser.app/privacy", from: .privacy))!)
                    }
                }
                SettingsCardDivider()
                SettingsPlainRow("Crash reports",
                                   detail: "A report shows what Cra was doing when it crashed, without your name, file paths or anything that identifies this Mac.",
                                   trailing: { EmptyView() }) {
                    Picker("Crash reports", selection: $store.settings.crashReports) {
                        Text("Ask each time").tag(CrashReportChoice.ask)
                        Text("Send automatically").tag(CrashReportChoice.send)
                        Text("Never send").tag(CrashReportChoice.never)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    @State private var dnsError: String?

    private var dnsFootnote: String? {
        let dns = SecureDNSSetting.shared
        guard let summary = dns.inEffect?.summary, !summary.isEmpty else { return nil }
        return dns.isManaged ? "Your organization sets secure DNS. " + summary : summary
    }
}

/// Block lists added on top of Cra's own (#507, in neither Arc nor Dia): a regional list or a
/// bigger one, by address or from a file, blocked under "Block ads and trackers" (BlockLists).
/// Each added list is a line with its name, what it blocks and a remove button.
private struct BlockListRows: View {
    @Binding var addresses: [String]
    let enabled: Bool
    private let lists = BlockLists.shared
    @State private var adding = false
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        SettingsPlainRow("Block lists",
                         detail: "Add a list to block more, like ads in your country. Cra uses its domain rules (hosts files, domain lists and Adblock Plus “||domain^” rules) and fetches it again when Cra opens, once a day at most.",
                         trailing: {
                             Button("Add List…") { error = nil; text = ""; adding = true }
                                 .disabled(!enabled || adding)
                         }) {
            if !addresses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(addresses, id: \.self) { BlockListLine(address: $0, lists: lists, remove: remove) }
                }
                .padding(.top, 4)
                .opacity(enabled ? 1 : 0.5)
            }
        }
        if adding {
            SettingsCardDivider()
            SettingsCardRow {
                TextField("List address", text: $text, prompt: Text("https://example.com/list.txt"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(addTyped)
            } trailing: {
                Button("Choose File…", action: chooseFile)
                Button("Cancel") { adding = false; error = nil }
                Button("Add", action: addTyped)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        if let error {
            SettingsFootnote(error).foregroundStyle(.red).padding(.bottom, 8)
        }
    }

    private func addTyped() {
        apply(CustomBlocklist.adding(text, to: addresses, httpsOnly: false))
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a block list: a hosts file, a list of domains or an Adblock Plus list."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(CustomBlocklist.adding(url, to: addresses))
    }

    private func apply(_ addition: CustomBlocklist.Addition) {
        switch addition {
        case .invalid:
            error = "Enter the list’s web address, like https://example.com/list.txt."
            return
        case .added(let next):
            addresses = next
        case .alreadyAdded:
            break
        }
        error = nil
        adding = false
    }

    private func remove(_ address: String) {
        addresses.removeAll { $0 == address }
    }
}

/// One added list: its name, then what it blocks and when it was fetched, or why it couldn't be.
private struct BlockListLine: View {
    let address: String
    let lists: BlockLists
    let remove: (String) -> Void

    var body: some View {
        let list = lists.cached[address]
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(list?.name ?? fallbackName).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.middle)
                    .help(address)
                if let failure = lists.failures[address] {
                    Text(failure).foregroundStyle(.red)
                } else if let list {
                    Text(CustomBlocklist.summary(domains: list.domains.count, skippedRules: list.skippedRules)
                         + " · Updated " + list.fetched.formatted(.relative(presentation: .named)))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Fetching…").foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if lists.fetching.contains(address) {
                ProgressView().controlSize(.mini)
            } else if lists.failures[address] != nil {
                Button("Try Again") { lists.fetch(address) }.buttonStyle(.link)
            }
            Button { remove(address) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove this list")
                .accessibilityLabel("Remove \(list?.name ?? fallbackName)")
        }
    }

    private var fallbackName: String {
        guard let url = URL(string: address) else { return address }
        return url.isFileURL ? url.lastPathComponent : (url.host ?? address)
    }
}

/// Chromium's secure DNS setting (chrome://settings/security) as a menu, under "Always use
/// secure connections": the lookup before the page (#133). Custom adds a row for the template.
private struct SecureDNSRows: View {
    @Binding var error: String?
    /// What the current setting does, or that the organization sets it.
    let footnote: String?
    private let dns = SecureDNSSetting.shared
    @State private var editingCustom = false
    @State private var customText = ""

    var body: some View {
        SettingsPlainRow("Secure DNS",
                           detail: "Before a page loads, the site’s address is looked up over an encrypted connection, so the network you’re on can’t see or change it." + (footnote.map { " " + $0 } ?? ""),
                           trailing: { EmptyView() }) {
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
