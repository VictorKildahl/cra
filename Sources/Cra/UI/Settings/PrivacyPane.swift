import AppKit
import SwiftUI

struct PrivacyPane: View {
    @Environment(SidebarStore.self) private var store
    let actions: SettingsActions

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            SettingsHeader("Content blocking")
            SettingsFeatureCard {
                SettingsToggleRow("Block ads and trackers",
                                  detail: "Requests to known ad and tracker domains are cancelled, unless the domain belongs to the site you’re on. To let one site load everything, turn it off in that site’s menu in the address bar.",
                                  isOn: $store.settings.blocksAdsAndTrackers)
                if store.settings.blocksAdsAndTrackers {
                    SettingsCardDivider()
                    SettingsPlainRow("Blocking",
                                       detail: store.settings.adBlockingLevel == .strict
                                           ? "Strict also blocks the ads and trackers EasyList and EasyPrivacy know about. It catches more, and now and then a page needs ads turned off for it."
                                           : "Standard blocks well-known ad and tracker servers and rarely gets in a page’s way.",
                                       trailing: {
                        Picker("Blocking", selection: $store.settings.adBlockingLevel) {
                            Text("Standard").tag(AdBlockingLevel.standard)
                            Text("Strict").tag(AdBlockingLevel.strict)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    })
                }
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
                SettingsCardDivider()
                SettingsPlainRow("Block lists",
                                   detail: "Pick lists one by one, add a list by its address or write your own filters."
                                       + (BlockLists.shared.inUse.map { " " + BlockListCount.inUse(rules: $0.rules, lists: $0.lists) } ?? ""),
                                   trailing: { Button("Advanced…") { showsBlockLists = true } })
            }

            SettingsHeader("Connection security").padding(.top, 20)
            SettingsFeatureCard {
                SettingsToggleRow("Always use secure connections",
                                  detail: "Pages load over HTTPS. Before opening a public site that doesn’t support it, Cra warns you first. Addresses on your own network, such as 192.168… or a .local name, load as they are.",
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
        .sheet(isPresented: $showsBlockLists) { BlockListsSheet().environment(store) }
    }

    @State private var dnsError: String?
    @State private var showsBlockLists = false

    private var dnsFootnote: String? {
        let dns = SecureDNSSetting.shared
        guard let summary = dns.inEffect?.summary, !summary.isEmpty else { return nil }
        return dns.isManaged ? "Your organization sets secure DNS. " + summary : summary
    }
}

/// Settings ▸ Privacy ▸ Block lists ▸ Advanced…: every list one by one (#507, #791), for people who know
/// them. The pane itself keeps one switch and Standard/Strict.
private struct BlockListsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Block lists").font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 10)
            Divider()
            ScrollView { BlockListRows().padding(24) }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
    }
}

/// Catalog entries stay visible when switched off. A custom subscription stays until removed.
private struct BlockListRows: View {
    @Environment(SidebarStore.self) private var store
    private let lists = BlockLists.shared
    @State private var expanded: Set<DesktopFilterList.Category> = [.ads, .tracking, .security]
    @State private var adding = false
    @State private var editingRules = false
    @State private var draft = ""
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader("Built-in lists")
            SettingsFeatureCard {
                SettingsToggleRow("AdAway", detail: "Built in. Blocks third-party ad and tracker domains, including in-app advertising networks.", isOn: $store.settings.adAwayEnabled) {
                    RuleCountLine(count: lists.builtInCounts["adaway"])
                }
                SettingsCardDivider()
                SettingsToggleRow("Anudeep’s Blacklist", detail: "Built in. Blocks third-party connections to known advertising and tracking servers.", isOn: $store.settings.anudeepEnabled) {
                    RuleCountLine(count: lists.builtInCounts["anudeep"])
                }
            }
            SettingsHeader("Filter lists").padding(.top, 14)
            ForEach(DesktopFilterList.Category.allCases, id: \.self) { category in
                categoryCard(category).padding(.bottom, 6)
            }
            SettingsFootnote("These lists block connections to third-party domains on pages you visit. Opening a listed address directly does not show a warning.")
            HStack {
                SettingsHeader("Manage lists")
                Spacer()
                Button("Update Enabled Lists") { store.settings.customBlocklists.forEach { lists.fetch($0) } }
                    .disabled(store.settings.customBlocklists.isEmpty || !lists.fetching.isEmpty)
                Button("Add List…") { error = nil; text = ""; adding = true }.disabled(adding)
            }.padding(.top, 14)
            if !store.settings.customFilterAddresses.isEmpty || adding {
                SettingsHeader("Your lists").padding(.top, 14)
                SettingsFeatureCard {
                    ForEach(store.settings.customFilterAddresses, id: \.self) { address in
                        listRow(address, name: lists.cached[address]?.name ?? address, detail: address, removable: true)
                        if address != store.settings.customFilterAddresses.last || adding { SettingsCardDivider() }
                    }
                    if adding { addListRow }
                }
            }
            if let failure = lists.networkFailure { SettingsFootnote(failure).foregroundStyle(.red) }
            if let error { SettingsFootnote(error).foregroundStyle(.red) }
            SettingsFootnote("Enabled lists update automatically. Downloads contact each list’s host, which can see your IP address. Filtering happens on this Mac.")
            SettingsHeader("Custom filters").padding(.top, 14)
            SettingsFeatureCard {
                SettingsToggleRow("Use my filters", detail: "Apply your saved rules.", isOn: $store.settings.personalFiltersEnabled)
                SettingsCardDivider()
                SettingsPlainRow("My filters", detail: "One domain, network rule, exception or element filter per line.", trailing: {
                    Button("Edit…") { draft = store.settings.personalBlockFilters ?? ""; editingRules = true }
                        .disabled(editingRules)
                }) {
                    RuleCountLine(count: lists.personalCount(store.settings.personalBlockFilters))
                    if editingRules {
                        TextEditor(text: $draft)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 84)
                            .accessibilityLabel("Custom filters")
                        Text("To allow network requests on a site, enter @@||example.org^$document.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Cancel") { editingRules = false }
                            Button("Save Changes") {
                                store.settings.personalBlockFilters = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft
                                editingRules = false
                            }
                            .disabled(draft == (store.settings.personalBlockFilters ?? ""))
                        }
                    }
                }
            }
        }
    }

    private func categoryCard(_ category: DesktopFilterList.Category) -> some View {
        var entries = DesktopFilterList.catalog.filter { $0.category == category }
        if category == .regional {
            entries.sort {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.detail.localizedStandardCompare($1.detail) == .orderedAscending : order == .orderedAscending
            }
        }
        let selected = Set(store.settings.customBlocklists)
        let count = entries.filter { selected.contains($0.address) }.count
        let selectable = entries.filter { !$0.referenceOnly || selected.contains($0.address) }.count
        let summary = "\(count) of \(selectable) selected"
        let isExpanded = expanded.contains(category)
        return SettingsFeatureCard {
            Button {
                if isExpanded { expanded.remove(category) } else { expanded.insert(category) }
            } label: {
                SettingsCardRow {
                    Text(category.rawValue).fontWeight(.medium)
                } trailing: {
                    Text(summary).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                        .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(category.rawValue)
            .accessibilityValue(isExpanded ? "Expanded, " + summary : "Collapsed, " + summary)
            if isExpanded {
                if category == .security {
                    SettingsCardDivider()
                    SettingsPlainRow("Online Malicious URL Blocklist", detail: "URLhaus uses full-page blocking rules that Cra cannot enforce yet.", trailing: {
                        Link("Source", destination: URL(string: "https://gitlab.com/malware-filter/urlhaus-filter")!)
                    })
                }
                ForEach(entries) { list in
                    SettingsCardDivider()
                    if list.referenceOnly && !selected.contains(list.address), let url = URL(string: list.address) {
                        SettingsPlainRow(list.name, detail: list.detail, trailing: { Link("Source", destination: url) })
                    } else {
                        listRow(list.address, name: list.name, detail: list.detail)
                    }
                }
            }
        }
    }

    private func listRow(_ address: String, name: String, detail: String, removable: Bool = false) -> some View {
        SettingsPlainRow(name, detail: name == detail ? "" : detail, trailing: {
            if lists.fetching.contains(address) { ProgressView().controlSize(.mini) }
            if removable {
                Button { store.settings.forgetFilterList(address) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Remove this list").accessibilityLabel("Remove " + name)
            }
            Toggle(name, isOn: Binding(
                get: { store.settings.customBlocklists.contains(address) },
                set: { store.settings.setFilterList(address, enabled: $0) }
            ))
            .toggleStyle(.arcSwitch).labelsHidden()
            .accessibilityLabel(Text(verbatim: name == detail ? name : name + ", " + detail))
            .help(address)
        }) {
            if let failure = lists.failures[address] { Text(failure).font(.caption).foregroundStyle(.red) }
            if store.settings.customBlocklists.contains(address) { RuleCountLine(count: lists.count(address)) }
        }
    }

    private var addListRow: some View {
        SettingsCardRow {
            TextField("List address", text: $text, prompt: Text("https://example.com/list.txt"))
                .textFieldStyle(.roundedBorder).onSubmit(addTyped)
        } trailing: {
            Button("Choose File…", action: chooseFile)
            Button("Cancel") { adding = false; error = nil }
            Button("Add", action: addTyped).keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addTyped() {
        apply(CustomBlocklist.adding(text, to: store.settings.customBlocklists, httpsOnly: false))
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a block list: a hosts file, a list of domains or an Adblock Plus list."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(CustomBlocklist.adding(url, to: store.settings.customBlocklists))
    }

    private func apply(_ addition: CustomBlocklist.Addition) {
        switch addition {
        case .invalid:
            error = "Enter the list’s web address, like https://example.com/list.txt."
            return
        case .added(let next):
            if let address = next.last { store.settings.setFilterList(address, enabled: true) }
        case .alreadyAdded:
            break
        }
        error = nil
        adding = false
    }

}

/// A block list's rules under its row: "48,210 rules · 3,102 Cra can’t use" (BlockListCount).
private struct RuleCountLine: View {
    let count: BlockListCount?

    var body: some View {
        if let summary = count?.summary, !summary.isEmpty {
            Text(summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .accessibilityIdentifier("ruleCount")
        }
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
