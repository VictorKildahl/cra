import AppKit
import SwiftUI

struct PrivacyPane: View {
    @Environment(SidebarStore.self) private var store
    let actions: SettingsActions

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            BlockListRows()

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
    }

    @State private var dnsError: String?

    private var dnsFootnote: String? {
        let dns = SecureDNSSetting.shared
        guard let summary = dns.inEffect?.summary, !summary.isEmpty else { return nil }
        return dns.isManaged ? "Your organization sets secure DNS. " + summary : summary
    }
}

/// Catalog entries stay visible when switched off. A custom subscription stays until removed.
private struct BlockListRows: View {
    @Environment(SidebarStore.self) private var store
    private let lists = BlockLists.shared
    @State private var regionalListsExpanded = false
    @State private var adding = false
    @State private var editingRules = false
    @State private var draft = ""
    @State private var text = ""
    @State private var error: String?

    private func rows(_ category: DesktopFilterList.Category) -> some View {
        let entries = DesktopFilterList.catalog.filter { $0.category == category }
        return ForEach(entries) { list in
            SettingsCardDivider()
            listRow(list.address, name: list.name, detail: list.detail)
        }
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader("Ad blocking")
            SettingsFeatureCard {
                SettingsToggleRow("AdAway", detail: "Built in. Blocks third-party ad and tracker domains, including in-app advertising networks.", isOn: $store.settings.adAwayEnabled)
                SettingsCardDivider()
                SettingsToggleRow("Anudeep’s Blacklist", detail: "Built in. Blocks third-party connections to known advertising and tracking servers.", isOn: $store.settings.anudeepEnabled)
                rows(.ads)
            }
            regionalListCard.padding(.top, 14)
            SettingsHeader("Tracking protection").padding(.top, 14)
            SettingsFeatureCard {
                SettingsToggleRow("Fingerprinting protection",
                                  detail: "Makes it harder to recognise your browser across sites. Cra adds small variations to canvas, WebGL and offline audio readings for each site and session, and reports eight processor cores.",
                                  isOn: $store.settings.fingerprintingProtection)
                rows(.tracking)
            }
            SettingsHeader("Cookie banners and page annoyances").padding(.top, 14)
            SettingsFeatureCard {
                SettingsToggleRow("Hide common cookie banners",
                                  detail: "Hides notices from common consent tools. Open pages reload when you change this setting.",
                                  isOn: $store.settings.blockCookieBanners)
                rows(.annoyances)
            }
            SettingsHeader("Security and privacy lists").padding(.top, 14)
            SettingsFeatureCard {
                ForEach(DesktopFilterList.catalog.filter { $0.category == .mixed }) { list in
                    listRow(list.address, name: list.name, detail: list.detail)
                    if list.id != DesktopFilterList.catalog.last(where: { $0.category == .mixed })?.id { SettingsCardDivider() }
                }
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

    private var regionalListCard: some View {
        let regional = DesktopFilterList.catalog.filter(\.regional)
            .sorted { lhs, rhs in
                let languageOrder = lhs.name.localizedStandardCompare(rhs.name)
                if languageOrder == .orderedSame { return lhs.detail.localizedStandardCompare(rhs.detail) == .orderedAscending }
                return languageOrder == .orderedAscending
            }
        let selected = Set(store.settings.customBlocklists)
        let count = regional.filter { selected.contains($0.address) }.count
        let summary = "\(count) of \(regional.count) selected"
        return SettingsFeatureCard {
            Button {
                regionalListsExpanded.toggle()
            } label: {
                SettingsCardRow {
                    Label("Regional lists", systemImage: "globe")
                } trailing: {
                    Text(summary).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: regionalListsExpanded ? "chevron.down" : "chevron.forward")
                        .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Regional lists")
            .accessibilityValue(regionalListsExpanded ? "Expanded, " + summary : "Collapsed, " + summary)

            if regionalListsExpanded {
                ForEach(regional) { list in
                    SettingsCardDivider()
                    listRow(list.address, name: list.name, detail: list.detail)
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
