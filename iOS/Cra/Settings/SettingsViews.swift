import CraCore
import SwiftUI

/// What the settings sheets read and change: `settings.json`, plus the things only the browser
/// can do (open the archive, clear data).
final class SettingsModel: ObservableObject {
    @Published private(set) var settings: MobileSettings
    private let store: MobileSettingsStore
    /// The site the sheet was opened on, when it was opened from a page.
    let host: String?
    let canSummarize: Bool
    var showArchive: () -> Void = {}
    var showDownloads: () -> Void = {}
    var clearData: (_ history: Bool, _ siteData: Bool) -> Void = { _, _ in }
    var exportData: () -> Void = {}
    var showOnboarding: () -> Void = {}
    var showWidgetGuide: () -> Void = {}
    var showIconDock: () -> Void = {}
    var showSpaces: () -> Void = {}
    var shareCra: () -> Void = {}
    var done: () -> Void = {}

    init(store: MobileSettingsStore, host: String?, canSummarize: Bool) {
        self.store = store
        self.host = host.map(MobileSettings.siteKey)
        self.canSummarize = canSummarize
        settings = store.value
    }

    func update(_ change: (inout MobileSettings) -> Void) {
        store.update(change)
        settings = store.value
    }

    /// The options of the sheet's site.
    var site: MobileSiteOptions {
        get { settings.options(for: host) }
        set {
            guard let host else { return }
            update { $0.setOptions(newValue, for: host) }
        }
    }

    func siteBinding<Value>(_ keyPath: WritableKeyPath<MobileSiteOptions, Value>) -> Binding<Value> {
        Binding(get: { self.site[keyPath: keyPath] }, set: { self.site[keyPath: keyPath] = $0 })
    }

    func globalBinding<Value>(_ keyPath: WritableKeyPath<MobileSiteOptions, Value>) -> Binding<Value> {
        Binding(get: { self.settings.siteDefaults[keyPath: keyPath] },
                set: { value in self.update { $0.siteDefaults[keyPath: keyPath] = value } })
    }

    func binding<Value>(_ keyPath: WritableKeyPath<MobileSettings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in self.update { $0[keyPath: keyPath] = value } })
    }
}

/// A row's icon: a white glyph on a rounded colour tile, as in Arc Search's settings.
struct SettingIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color)
            .frame(width: 29, height: 29)
            .overlay(Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
    }
}

private struct SettingLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var subtitle: String?

    var body: some View {
        HStack(spacing: 14) {
            SettingIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// A row that does something when tapped, with Arc Search's grey chevron when it leads somewhere.
private struct ActionRow: View {
    let label: SettingLabel
    var chevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                label
                Spacer()
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }
}

/// The six per-site options, bound either to one site or to the global defaults.
private struct SiteOptionRows {
    let model: SettingsModel
    let global: Bool

    private func bind<Value>(_ keyPath: WritableKeyPath<MobileSiteOptions, Value>) -> Binding<Value> {
        global ? model.globalBinding(keyPath) : model.siteBinding(keyPath)
    }

    @ViewBuilder var blockers: some View {
        Group {
            Toggle(isOn: bind(\.blockAds)) { SettingLabel(title: "Block Ads", symbol: "hand.raised.fill", color: Color(red: 1, green: 0.22, blue: 0.33)) }
                .accessibilityIdentifier("setting-block-ads")
            Toggle(isOn: bind(\.blockCookieBanners)) { SettingLabel(title: "Block Cookie Banners", symbol: "birthday.cake.fill", color: .orange) }
                .accessibilityIdentifier("setting-block-cookie-banners")
            Toggle(isOn: bind(\.blockTrackers)) { SettingLabel(title: "Block Trackers", symbol: "sunglasses.fill", color: Color(red: 1, green: 0.78, blue: 0.1)) }
                .accessibilityIdentifier("setting-block-trackers")
        }
    }

    @ViewBuilder var behaviour: some View {
        Group {
            if model.canSummarize {
                Toggle(isOn: bind(\.pinchToSummarize)) { SettingLabel(title: "Pinch to Summarize", symbol: "doc.richtext.fill", color: .blue) }
                    .accessibilityIdentifier("setting-pinch-to-summarize")
            }
            Toggle(isOn: bind(\.collapseBottomBar)) { SettingLabel(title: "Collapse Bottom Bar", symbol: "iphone.gen3", color: .purple) }
                .accessibilityIdentifier("setting-collapse-bottom-bar")
            ValueRow(label: SettingLabel(title: "Swipe to Navigate", symbol: "hand.point.up.left.fill", color: .green),
                     selection: bind(\.swipeToNavigate), options: MobileSwipeToNavigate.allCases, title: \.label)
                .accessibilityIdentifier("setting-swipe-to-navigate")
        }
    }
}

/// A row whose value sits at the right in grey and opens a menu of choices, on one line.
private struct ValueRow<Label: View, Value: Hashable>: View {
    let label: Label
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    init(label: Label, selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) {
        self.label = label
        _selection = selection
        self.options = options
        self.title = title
    }

    var body: some View {
        HStack {
            label
            Spacer(minLength: 8)
            Menu {
                Picker("", selection: $selection) {
                    ForEach(options, id: \.self) { Text(title($0)).tag($0) }
                }
            } label: {
                Text(title(selection)).font(.body).lineLimit(1)
            }
            .tint(.secondary)
        }
    }
}

extension View {
    /// Arc Search 1.49's settings lists (Victor's recording, in dark mode): the sheet's material
    /// showing through (grey ~49) with the groups lighter (~75), rows 52 pt.
    func settingsListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(.regularMaterial)
            .environment(\.defaultMinListRowHeight, 52)
            // Switches stay green while the bar's Done and back take the text colour, as in Arc Search.
            .tint(Color(.systemGreen))
    }

    func settingsRow() -> some View {
        listRowBackground(Color.primary.opacity(0.1))
    }
}

/// Site Settings: the page menu's last row. The site's blockers and behaviour, then App Settings.
struct SiteSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        NavigationStack {
            List {
                let rows = SiteOptionRows(model: model, global: model.host == nil)
                Section((model.host ?? "all sites").uppercased() + " SETTINGS") { rows.blockers }.settingsRow()
                Section { rows.behaviour }.settingsRow()
                Section {
                    NavigationLink { AppSettingsList(model: model).toolbarRole(.editor) } label: {
                        SettingLabel(title: "App Settings", symbol: "gearshape.fill", color: .gray)
                    }
                    .accessibilityIdentifier("setting-app-settings")
                }
                .settingsRow()
            }
            .settingsListStyle()
            .navigationTitle("Site Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.done() }.fontWeight(.semibold) } }
        }
        .tint(.primary)
    }
}

/// App Settings on its own, as the tab switcher's gear opens it.
struct AppSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        NavigationStack { AppSettingsList(model: model) }.tint(.primary)
    }
}

struct AppSettingsList: View {
    @ObservedObject var model: SettingsModel
    @State private var clearing = false
    @State private var editingCustom = false
    @State private var customAddress = ""

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Cra \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    capsule("Downloads", symbol: "folder", id: "settings-downloads") { model.showDownloads() }
                    capsule("Archive", symbol: "archivebox", id: "settings-archive") { model.showArchive() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .settingsRow()
            Section {
                NavigationLink { GlobalSiteSettingsView(model: model).toolbarRole(.editor) } label: {
                    SettingLabel(title: "Global Site Settings", symbol: "globe", color: .black)
                }
                .accessibilityIdentifier("setting-global-site-settings")
            }
            .settingsRow()
            // Arc Search keeps these three in one group.
            Section {
                ActionRow(label: SettingLabel(title: "Set Cra as Default Browser", symbol: "safari.fill", color: .indigo)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .accessibilityIdentifier("setting-default-browser")
                ActionRow(label: SettingLabel(title: "Change App Icon", symbol: "app.badge.fill", color: .blue)) { model.showIconDock() }
                    .accessibilityIdentifier("setting-app-icon")
                ActionRow(label: SettingLabel(title: "Add to Home Screen", symbol: "iphone.gen3", color: .purple), chevron: false) { model.showWidgetGuide() }
                    .accessibilityIdentifier("setting-add-widget")
            }
            .settingsRow()
            Section {
                ValueRow(label: SettingLabel(title: "Search Engine", symbol: "magnifyingglass", color: .blue),
                         selection: Binding(get: { model.settings.searchChoice }, set: { choice in
                             // Custom asks for its address first (and again to change it).
                             if choice == .custom {
                                 customAddress = model.settings.customSearchURL ?? "https://"
                                 editingCustom = true
                             } else {
                                 model.update { $0.searchChoice = choice }
                             }
                         }),
                         options: MobileSearchChoice.all(browseForMeAvailable: BrowseForMe.isAvailable),
                         title: { $0 == .custom && model.settings.customSearchURL != nil ? model.settings.search.label : $0.label })
                    .accessibilityIdentifier("setting-search-engine")
                ValueRow(label: SettingLabel(title: "Languages", symbol: "character.bubble.fill", color: .green),
                         selection: model.binding(\.answerLanguage),
                         options: [nil] + MobileLanguages.codes.map(Optional.some),
                         title: { code in code.map { Locale.current.localizedString(forLanguageCode: $0)?.capitalized ?? $0 } ?? "Same as iPhone" })
                    .accessibilityIdentifier("setting-languages")
            }
            .settingsRow()
            Section {
                Toggle(isOn: model.binding(\.opensKeyboardOnLaunch)) {
                    SettingLabel(title: "Auto-Open Keyboard", symbol: "keyboard.fill", color: .yellow)
                }
                .accessibilityIdentifier("setting-keyboard-on-launch")
                ValueRow(label: SettingLabel(title: "Archive Inactive Tabs", symbol: "archivebox.fill", color: .purple),
                         selection: model.binding(\.archiveAfter), options: MobileArchiveAfter.allCases, title: \.settingValue)
                    .accessibilityIdentifier("setting-archive-after")
                ValueRow(label: SettingLabel(title: "Open App Links in...", symbol: "arrow.up.forward.square", color: .blue),
                         selection: model.binding(\.openAppLinksIn), options: MobileAppLinks.allCases, title: \.label)
                    .accessibilityIdentifier("setting-app-links")
                ActionRow(label: SettingLabel(title: "Clear Browsing Data...", symbol: "eraser.fill", color: .red), chevron: false) { clearing = true }
                    .accessibilityIdentifier("setting-clear-data")
                ActionRow(label: SettingLabel(title: "Export Data", symbol: "square.and.arrow.up", color: .blue,
                                              subtitle: "Share your open tab URLs"), chevron: false) { model.exportData() }
                    .accessibilityIdentifier("setting-export-data")
            }
            .settingsRow()
            // Arc Search's "Sync with Arc Desktop / Sign in": Cra's Mac shares its Spaces through iCloud.
            Section {
                ActionRow(label: SettingLabel(title: "Sync with Cra for Mac", symbol: "arrow.triangle.2.circlepath", color: Color(red: 0.55, green: 0.1, blue: 0.5),
                                              subtitle: FileManager.default.ubiquityIdentityToken == nil ? "Sign in to iCloud" : "Through iCloud")) { model.showSpaces() }
                    .accessibilityIdentifier("setting-sync")
            }
            .settingsRow()
            // Arc Search's "Gift Arc to a friend" capsule; Cra has nothing to gift, so it shares the app.
            Section {
                Button { model.shareCra() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "gift.fill").font(.system(size: 19, weight: .semibold))
                        Text("Share Cra with a friend").font(.body.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(LinearGradient(colors: [Color(red: 0.32, green: 0.12, blue: 0.75), Color(red: 0.86, green: 0.3, blue: 0.55),
                                                        Color(red: 0.2, green: 0.15, blue: 0.85), Color(red: 0.12, green: 0.2, blue: 0.95)],
                                               startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("setting-share-cra")
            }
            Section {
                ActionRow(label: SettingLabel(title: "Contact the Team", symbol: "envelope.fill", color: .gray), chevron: false) {
                    UIApplication.shared.open(URL(string: "https://github.com/VictorKildahl/cra/issues")!)
                }
                .accessibilityIdentifier("setting-contact")
                ActionRow(label: SettingLabel(title: "Show Onboarding", symbol: "hand.wave.fill", color: .gray), chevron: false) { model.showOnboarding() }
                    .accessibilityIdentifier("setting-show-onboarding")
                ActionRow(label: SettingLabel(title: "Privacy Policy", symbol: "doc.text.fill", color: .gray), chevron: false) {
                    UIApplication.shared.open(URL(string: "https://crabrowser.app/privacy")!)
                }
                .accessibilityIdentifier("setting-privacy")
                NavigationLink { LicensesView().toolbarRole(.editor) } label: {
                    SettingLabel(title: "Open Source Licenses", symbol: "doc.fill", color: .gray)
                }
                .accessibilityIdentifier("setting-licenses")
            } footer: {
                Text(version).frame(maxWidth: .infinity).padding(.top, 12)
                    .accessibilityIdentifier("setting-version")
            }
            .settingsRow()
        }
        .settingsListStyle()
        .alert("Custom Search Engine", isPresented: $editingCustom) {
            TextField("https://example.com/search?q=%s", text: $customAddress)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("custom-engine-address")
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let address = customAddress.trimmingCharacters(in: .whitespaces)
                guard MobileSearch.isValidTemplate(address) else { return }
                model.update { $0.customSearchURL = address; $0.searchChoice = .custom }
            }
        } message: {
            Text("The search page's address with %s where the search goes, such as https://search.brave.com/search?q=%s")
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.done() }.fontWeight(.semibold) } }
        .sheet(isPresented: $clearing) {
            ClearDataView { history, siteData in model.clearData(history, siteData) }
                .presentationDetents([.height(300)])
        }
    }

    private func capsule(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 41)
                .background(Color.primary.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Global Site Settings: the same options for every site that made no choice of its own.
struct GlobalSiteSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        List {
            let rows = SiteOptionRows(model: model, global: true)
            Section {
                rows.blockers
            } header: {
                Text("Settings will apply to all websites unless overridden.")
                    .font(.subheadline).textCase(nil)
                    .accessibilityIdentifier("default-site-settings-caption")
            }
            .settingsRow()
            Section { rows.behaviour }.settingsRow()
        }
        .settingsListStyle()
        .navigationTitle("Default Site Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.done() }.fontWeight(.semibold) } }
    }
}

/// Open Source Licenses: Cra's own licence and the notices of the block list it ships.
struct LicensesView: View {
    private static func text(_ name: String, _ ext: String) -> String {
        Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Cra is open source under the MIT License, © 2026 Victor Kildahl. Its code is at github.com/VictorKildahl/cra.")
                Text(Self.text("NOTICE", "txt")).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("licenses-notice")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.regularMaterial)
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Clear Data: two switches and a wide Clear button.
struct ClearDataView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var history = true
    @State private var siteData = true
    let clear: (_ history: Bool, _ siteData: Bool) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                List {
                    Toggle("Clear History", isOn: $history).accessibilityIdentifier("clear-history")
                    Toggle("Clear Cookies and Site Data", isOn: $siteData).accessibilityIdentifier("clear-site-data")
                }
                .scrollDisabled(true)
                .frame(height: 140)
                Button {
                    clear(history, siteData)
                    dismiss()
                } label: {
                    Text("Clear").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!history && !siteData)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("clear-confirm")
                Spacer(minLength: 0)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Clear Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Close")
                }
            }
        }
    }
}

/// The Archive: tabs that were closed or timed out, by day, searchable. A tap reopens one.
struct ArchiveView: View {
    @ObservedObject var model: ArchiveModel
    @State private var query = ""
    @State private var editing: EditMode = .inactive
    @State private var picked = Set<UUID>()

    var body: some View {
        NavigationStack {
            let sections = MobileArchive.sections(model.tabs, matching: query, now: Date())
            List(selection: $picked) {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.tabs) { tab in
                            Button { model.restore(tab.id) } label: {
                                HStack(spacing: 12) {
                                    FaviconView(image: model.favicon(tab))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tab.displayTitle).lineLimit(1).foregroundStyle(.primary)
                                        Text(MobileArchive.subtitle(for: tab)).font(.footnote).lineLimit(1).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                            .tag(tab.id)
                            .accessibilityIdentifier("archive-row-\(tab.displayTitle)")
                        }
                        .onDelete { offsets in model.remove(Set(offsets.map { section.tabs[$0].id })) }
                    }
                }
            }
            .overlay {
                if model.tabs.isEmpty {
                    // Arc Search 1.49's empty Archive (Victor's recording, 3:15).
                    VStack(spacing: 14) {
                        Text("Nothing here yet!").font(.title2.weight(.bold))
                        Text("Manually closed and auto-archived tabs will appear here. You can adjust the auto-archive frequency in Settings.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("archive-empty")
                } else if sections.isEmpty {
                    Text("No Results").foregroundStyle(.secondary)
                }
            }
            .modifier(ArchiveSearch(query: $query, shown: !model.tabs.isEmpty))
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editing)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if editing == .active, !picked.isEmpty {
                        Button("Delete", role: .destructive) {
                            model.remove(picked)
                            picked = []
                            editing = .inactive
                        }
                    } else if !model.tabs.isEmpty {
                        Button(editing == .active ? "Cancel" : "Edit") { editing = editing == .active ? .inactive : .active }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Arc Search's Archive closes with a blue round check.
                    Button { model.done() } label: {
                        Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color(red: 0.30, green: 0.37, blue: 0.99), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done")
                    .accessibilityIdentifier("archive-done")
                }
            }
        }
    }
}

/// The Archive's search field, left out while there is nothing to search (Arc Search shows none then).
private struct ArchiveSearch: ViewModifier {
    @Binding var query: String
    let shown: Bool

    func body(content: Content) -> some View {
        if shown {
            content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        } else {
            content
        }
    }
}

final class ArchiveModel: ObservableObject {
    @Published var tabs: [MobileTab]
    var favicon: (MobileTab) -> UIImage? = { _ in nil }
    var restore: (UUID) -> Void = { _ in }
    var removeTabs: (Set<UUID>) -> Void = { _ in }
    var done: () -> Void = {}

    init(tabs: [MobileTab]) { self.tabs = tabs }

    func remove(_ ids: Set<UUID>) {
        removeTabs(ids)
        tabs.removeAll { ids.contains($0.id) }
    }
}

struct FaviconView: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
