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

    var body: some View {
        HStack(spacing: 14) {
            SettingIcon(symbol: symbol, color: color)
            Text(title).font(.system(size: 15))
        }
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
            Toggle(isOn: bind(\.blockCookieBanners)) { SettingLabel(title: "Block Cookie Banners", symbol: "circle.hexagongrid.fill", color: .orange) }
                .accessibilityIdentifier("setting-block-cookie-banners")
            Toggle(isOn: bind(\.blockTrackers)) { SettingLabel(title: "Block Trackers", symbol: "sunglasses.fill", color: Color(red: 1, green: 0.78, blue: 0.1)) }
                .accessibilityIdentifier("setting-block-trackers")
        }
    }

    @ViewBuilder var behaviour: some View {
        Group {
            if model.canSummarize {
                Toggle(isOn: bind(\.pinchToSummarize)) { SettingLabel(title: "Pinch to Summarize", symbol: "doc.text.fill", color: .blue) }
                    .accessibilityIdentifier("setting-pinch-to-summarize")
            }
            Toggle(isOn: bind(\.collapseBottomBar)) { SettingLabel(title: "Collapse Bottom Bar", symbol: "platter.filled.bottom.iphone", color: .purple) }
                .accessibilityIdentifier("setting-collapse-bottom-bar")
            ValueRow(label: SettingLabel(title: "Swipe to Navigate", symbol: "hand.draw.fill", color: .green),
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
                Text(title(selection)).font(.system(size: 15)).lineLimit(1)
            }
            .tint(.secondary)
        }
    }
}

extension View {
    /// Arc Search's settings lists: the sheet's translucent backdrop showing through, with the
    /// groups a shade darker.
    func settingsListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(.regularMaterial)
            .environment(\.defaultMinListRowHeight, 45)
    }

    func settingsRow() -> some View {
        listRowBackground(Color.primary.opacity(0.07))
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
                    NavigationLink { AppSettingsList(model: model) } label: {
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
    }
}

/// App Settings on its own, as the tab switcher's gear opens it.
struct AppSettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        NavigationStack { AppSettingsList(model: model) }
    }
}

struct AppSettingsList: View {
    @ObservedObject var model: SettingsModel
    @State private var clearing = false

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
                NavigationLink { GlobalSiteSettingsView(model: model) } label: {
                    SettingLabel(title: "Global Site Settings", symbol: "globe", color: .black)
                }
                .accessibilityIdentifier("setting-global-site-settings")
            }
            .settingsRow()
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    HStack {
                        SettingLabel(title: "Set Cra as Default Browser", symbol: "safari.fill", color: .indigo)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("setting-default-browser")
            }
            .settingsRow()
            Section {
                ValueRow(label: SettingLabel(title: "Search Engine", symbol: "magnifyingglass", color: .blue),
                         selection: model.binding(\.searchEngine), options: MobileSearchEngine.allCases, title: \.label)
                    .accessibilityIdentifier("setting-search-engine")
            }
            .settingsRow()
            Section {
                ValueRow(label: SettingLabel(title: "Archive Inactive Tabs", symbol: "archivebox.fill", color: .purple),
                         selection: model.binding(\.archiveAfter), options: MobileArchiveAfter.allCases, title: \.settingValue)
                    .accessibilityIdentifier("setting-archive-after")
            }
            .settingsRow()
            Section {
                Toggle(isOn: model.binding(\.opensKeyboardOnLaunch)) {
                    SettingLabel(title: "Open Keyboard on Launch", symbol: "keyboard.fill", color: .teal)
                }
                .accessibilityIdentifier("setting-keyboard-on-launch")
                ValueRow(label: SettingLabel(title: "Open App Links in...", symbol: "arrow.up.forward.app.fill", color: .orange),
                         selection: model.binding(\.openAppLinksIn), options: MobileAppLinks.allCases, title: \.label)
                    .accessibilityIdentifier("setting-app-links")
            }
            .settingsRow()
            Section {
                NavigationLink { AppIconPicker() } label: {
                    SettingLabel(title: "App Icon", symbol: "app.fill", color: .pink)
                }
                .accessibilityIdentifier("setting-app-icon")
            }
            .settingsRow()
            Section {
                Button("Clear Browsing Data...") { clearing = true }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("setting-clear-data")
                Button("Export Data") { model.exportData() }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("setting-export-data")
            }
            .settingsRow()
            Section {
                Link("Report a Problem", destination: URL(string: "https://github.com/VictorKildahl/cra/issues")!)
                    .foregroundStyle(.primary)
                Link("Privacy Policy", destination: URL(string: "https://crabrowser.app/privacy")!)
                    .foregroundStyle(.primary)
                Button("Show Onboarding") { model.showOnboarding() }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("setting-show-onboarding")
            } footer: {
                Text(version).frame(maxWidth: .infinity).padding(.top, 12)
            }
            .settingsRow()
        }
        .settingsListStyle()
        .font(.system(size: 15))
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
            Section { rows.blockers }.settingsRow()
            Section { rows.behaviour }.settingsRow()
        }
        .settingsListStyle()
        .navigationTitle("Global Site Settings")
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
                if sections.isEmpty {
                    Text(query.isEmpty ? "No Archived Tabs" : "No Results").foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
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
                    } else {
                        Button(editing == .active ? "Cancel" : "Edit") { editing = editing == .active ? .inactive : .active }
                            .disabled(model.tabs.isEmpty)
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { model.done() }.fontWeight(.semibold) }
            }
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
