import AppKit
import Observation
import SwiftUI

// The onboarding and import flow, after Dia 1.54's Onboarding module (see
// docs/arc-reverse-engineering.md, "Dia import onboarding" and "Dia onboarding
// steps"). First launch runs Dia's order: cover page, default browser, privacy,
// import (browser → Safari export / unlock passwords → spaces → extensions →
// progress → passwords result), pinned tabs, personalization, outro. Import
// from the menu runs only the import part.

enum ImportStep: Int, Comparable {
    case cover, defaultBrowser, privacy
    case source, safariExport, passwordsFile, unlock, spaces, extensions, progress, credentialsResult
    case pinnedTabs, personalization, outro
    static func < (a: ImportStep, b: ImportStep) -> Bool { a.rawValue < b.rawValue }
}

/// One tile on the progress step (Dia's CategoryItemView).
struct ImportCategory: Identifiable {
    enum State { case waiting, working, done, failed }
    let id: String
    let title: String
    let symbol: String
    var detail: String
    var state: State = .waiting
}

extension ImportPlan {
    /// The plan restricted to what the user picked.
    func selecting(spaces: Set<Int>, favorites: Bool) -> ImportPlan {
        var p = self
        p.spaces = spaces.sorted().compactMap { $0 < self.spaces.count ? self.spaces[$0] : nil }
        if !favorites { p.favorites = [] }
        return p
    }

    var isEmpty: Bool { spaces.isEmpty && favorites.isEmpty && archive.isEmpty }
}

extension ImportedSpace {
    var itemCount: Int {
        func count(_ items: [ImportedItem]) -> Int { items.reduce(0) { $0 + ($1.isFolder ? count($1.children) : 1) } }
        return count(pinned) + count(today)
    }
}

/// What the app does once the flow ends: focus the first imported space and,
/// when extensions or passwords and cookies came in, relaunch so Chromium
/// loads them.
struct ImportOutcome {
    var focusSpaceID: UUID?
    var extensionsImported = 0
    var credentialsStaged = false
    var skipped = false
    var needsRelaunch: Bool { extensionsImported > 0 || credentialsStaged }
}

/// A site offered on the pinned tabs step (Dia's PinnedTabButton).
struct PinCandidate: Identifiable, Hashable {
    var id: String { host }
    let host: String
    let name: String
    let url: String
}

@MainActor
@Observable
final class ImportFlowModel {
    let sources = ImportSource.allCases.filter(\.isAvailable)
    var step: ImportStep
    /// Direction of the last step change, for the slide transition.
    var forward = true
    private(set) var source: ImportSource?
    private(set) var plan: ImportPlan?
    private(set) var loadError: String?

    var selectedSpaces: Set<Int> = []
    var includeFavorites = true
    var includeArchive = true
    var includeSettings = true
    /// The space the preview shows: the last one hovered or toggled.
    var previewSpace: Int?

    private(set) var extensions: [ImportableExtension] = []
    var selectedExtensions: Set<String> = []

    private(set) var categories: [ImportCategory] = []
    private(set) var failures: [String] = []
    private(set) var finished = false
    private(set) var importedExtensionCount = 0
    private var importedSpaceID: UUID?

    // Default browser step: Dia's NewDefaultBrowserViewModel options.
    var setAsDefault = true
    var addToDock = true
    var launchAtLogin = false
    private(set) var applyingSystemOptions = false
    private(set) var systemError: String?
    let system = SystemIntegration.shared

    // Unlock step (Dia's ImportProfilePickerView): profiles whose passwords and cookies come over.
    private(set) var credentialProfiles: [ChromiumProfile] = []
    var selectedProfiles: Set<String> = []
    private(set) var unlocking = false
    /// Read and decrypted, staged for the next launch once the import runs.
    private(set) var credentials = ImportedCredentials()
    private(set) var credentialError: String?
    private(set) var credentialsAttempted = false
    private(set) var credentialsStaged = false

    // Safari export / Firefox passwords file.
    private(set) var exportFileName: String?
    private(set) var exportError: String?
    private(set) var readingExport = false
    private var exportTopSites: [TopSite] = []

    // Pinned tabs step.
    private(set) var pinCandidates: [PinCandidate] = []
    private(set) var pinIcons: [String: NSImage] = [:]
    var selectedPins: Set<String> = []
    private var pinsLoaded = false

    // Personalization step.
    private(set) var chosenTheme: Int?

    private var faviconCache: [String: NSImage] = [:]
    private let store: SidebarStore
    private let favicons: FaviconCache
    /// First launch: the flow is the onboarding, so it cannot be closed, only skipped or finished.
    let firstRun: Bool
    let onClose: () -> Void
    private let onFinish: (ImportOutcome) -> Void

    /// Nothing to offer once Cra already opens links and sits in the Dock.
    static var offersDefaultBrowserStep: Bool {
        let s = SystemIntegration.shared
        s.refresh()
        return !(s.isDefaultBrowser && s.isInDock)
    }

    init(store: SidebarStore, favicons: FaviconCache, firstRun: Bool, onClose: @escaping () -> Void,
         onFinish: @escaping (ImportOutcome) -> Void) {
        self.store = store
        self.favicons = favicons
        self.firstRun = firstRun
        self.onClose = onClose
        self.onFinish = onFinish
        step = firstRun ? .cover : .source
        setAsDefault = !system.isDefaultBrowser
        addToDock = !system.isInDock
        launchAtLogin = system.launchesAtLogin
    }

    func finish() {
        onFinish(ImportOutcome(focusSpaceID: importedSpaceID, extensionsImported: importedExtensionCount,
                               credentialsStaged: credentialsStaged))
    }

    func go(_ s: ImportStep) {
        forward = s > step
        withAnimation(.easeInOut(duration: 0.28)) { step = s }
    }

    // MARK: Onboarding steps

    func continueFromCover() { go(Self.offersDefaultBrowserStep ? .defaultBrowser : .privacy) }

    /// Applies the ticked options in Dia's order (the default browser prompt
    /// first, then Dock and login item), then moves on.
    func continueFromDefaultBrowser(applying: Bool = true) {
        guard !applyingSystemOptions else { return }
        Task { @MainActor in
            // After a refusal has been shown, Continue moves on instead of asking again.
            if applying && systemError == nil {
                applyingSystemOptions = true
                systemError = nil
                if setAsDefault && !system.isDefaultBrowser { await system.makeDefaultBrowser() }
                if addToDock && !system.isInDock && !system.addToDock() { systemError = "Cra could not be added to the Dock." }
                if launchAtLogin != system.launchesAtLogin, let err = system.setLaunchAtLogin(launchAtLogin) { systemError = err }
                applyingSystemOptions = false
                // A refusal is worth reading before the step goes away.
                if systemError != nil { return }
            }
            go(.privacy)
        }
    }

    /// Dia's disclosure step: the ad and tracker blocker checkbox.
    var blockAdsAndTrackers: Bool {
        get { store.settings.blockAdsAndTrackers }
        set { store.settings.blockAdsAndTrackers = newValue }
    }

    func continueFromPrivacy() { go(.source) }

    /// Skipping the import on first launch still shows the rest of the onboarding.
    func skipImport() {
        if firstRun { goToOnboardingTail() } else { onClose() }
    }

    private func goToOnboardingTail() {
        go(offersPinnedTabs ? .pinnedTabs : .personalization)
    }

    /// Ends the import part: the rest of the onboarding, or close.
    func afterImport() {
        if firstRun { goToOnboardingTail() } else { finish() }
    }

    // MARK: Source

    func select(_ s: ImportSource) {
        guard s != source else { return }
        source = s
        loadError = nil
        credentials = ImportedCredentials()
        credentialError = nil
        credentialsAttempted = false
        exportFileName = nil
        exportError = nil
        exportTopSites = []
        if s.needsExportedFile {
            plan = nil
        } else {
            do {
                setPlan(try s.plan())
            } catch {
                plan = nil
                loadError = error.localizedDescription
            }
        }
        credentialProfiles = s.credentialProfiles
        selectedProfiles = Set(credentialProfiles.map(\.id))
        extensions = s.extensions()
        selectedExtensions = Set(extensions.filter { $0.isEnabled && !ExtensionStore.isInstalled(id: $0.id) }.map(\.id))
    }

    private func setPlan(_ p: ImportPlan) {
        plan = p
        selectedSpaces = Set(p.spaces.indices)
        previewSpace = p.spaces.isEmpty ? nil : 0
        includeFavorites = !p.favorites.isEmpty
        includeArchive = !p.archive.isEmpty
        includeSettings = !p.settings.isEmpty
    }

    var canContinueFromSource: Bool { source != nil && (plan != nil || source?.needsExportedFile == true) }

    func continueFromSource() {
        guard canContinueFromSource, let source else { return }
        switch source.kind {
        case .safari: go(.safariExport)
        case .firefox, .zen: go(.passwordsFile)
        case .arc, .dia, .chromium: credentialProfiles.isEmpty ? goToSpaces() : go(.unlock)
        }
    }

    /// The space picker, or straight on when the browser had nothing for the sidebar.
    func goToSpaces() {
        if plan?.isEmpty ?? true { continueFromSpaces() } else { go(.spaces) }
    }

    func toggleSpace(_ i: Int) {
        if selectedSpaces.contains(i) { selectedSpaces.remove(i) } else { selectedSpaces.insert(i) }
        previewSpace = i
    }

    func toggleExtension(_ id: String) {
        if selectedExtensions.contains(id) { selectedExtensions.remove(id) } else { selectedExtensions.insert(id) }
    }

    var hasAnythingSelected: Bool {
        !selectedSpaces.isEmpty || (includeFavorites && !(plan?.favorites.isEmpty ?? true)) || includeArchive || includeSettings
    }

    func continueFromSpaces() { if extensions.isEmpty { startImport(withExtensions: false) } else { go(.extensions) } }

    // MARK: Passwords and cookies

    func toggleProfile(_ id: String) {
        if selectedProfiles.contains(id) { selectedProfiles.remove(id) } else { selectedProfiles.insert(id) }
    }

    /// Reads the Keychain secret (macOS asks for the login password) and
    /// decrypts the picked profiles' passwords and cookies, then moves on.
    func unlock() {
        guard let source, let service = source.keychainService, let account = source.keychainAccount, !unlocking else { return }
        let profiles = credentialProfiles.filter { selectedProfiles.contains($0.id) }
        guard !profiles.isEmpty else { goToSpaces(); return }
        unlocking = true
        credentialError = nil
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImportedCredentials, Error> in
                Result { try ChromiumImporter.credentials(browser: source.name, profiles: profiles, keychainService: service,
                                                          keychainAccount: account, cookies: true, passwords: true) }
            }.value
            unlocking = false
            credentialsAttempted = true
            switch result {
            case .success(let c): credentials = c
            case .failure(let e): credentials = ImportedCredentials(); credentialError = e.localizedDescription
            }
            goToSpaces()
        }
    }

    func skipCredentials() {
        credentials = ImportedCredentials()
        credentialsAttempted = false
        goToSpaces()
    }

    /// Safari's exported .zip or folder (bookmarks, history, passwords) or
    /// Firefox's (or Zen's) exported passwords CSV.
    func readExport(_ url: URL) {
        guard let source, !readingExport else { return }
        readingExport = true
        exportError = nil
        let kind = source.kind
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<SafariExport, Error> in
                Result {
                    if kind == .safari { return try SafariImporter.read(url) }
                    guard url.pathExtension.lowercased() == "csv", let text = try? String(contentsOf: url, encoding: .utf8) else {
                        throw SafariExportError.invalid
                    }
                    let logins = PasswordCSV.logins(in: text)
                    if logins.isEmpty { throw SafariExportError.invalid }
                    return SafariExport(plan: ImportPlan(source: source.name), logins: logins, topSites: [])
                }
            }.value
            readingExport = false
            switch result {
            case .success(let export):
                exportFileName = url.lastPathComponent
                if kind == .safari { setPlan(export.plan) }
                exportTopSites = export.topSites
                credentials = ImportedCredentials(logins: export.logins)
                credentialsAttempted = !export.logins.isEmpty
            case .failure(let e):
                exportFileName = nil
                exportError = e.localizedDescription
            }
        }
    }

    func clearExport() {
        exportFileName = nil
        exportError = nil
        credentials = ImportedCredentials()
        credentialsAttempted = false
        if source?.kind == .safari { plan = nil }
    }

    func continueFromExport() { goToSpaces() }

    func skipExport() {
        clearExport()
        if source?.kind == .safari { afterImport() } else { goToSpaces() }
    }

    /// Back to the step that produced the passwords, for "Try Again".
    func retryCredentials() {
        guard let source else { return }
        credentialsStaged = false
        switch source.kind {
        case .safari: go(.safariExport)
        case .firefox, .zen: go(.passwordsFile)
        default: go(.unlock)
        }
    }

    var credentialsSucceeded: Bool { credentialError == nil && credentialsStaged }

    func continueFromProgress() {
        if credentialsAttempted { go(.credentialsResult) } else { afterImport() }
    }

    // MARK: Preview data

    var previewTheme: SpaceTheme? {
        // Personalization previews the picked swatch, or the space's current theme.
        if step == .personalization { return chosenTheme.map { SpaceTheme.presets[$0] } ?? store.focusedSpace.theme }
        guard let plan, let i = previewSpace, i < plan.spaces.count else { return nil }
        return plan.spaces[i].theme
    }

    func favicon(for item: ImportedItem) -> NSImage? {
        guard let url = item.url else { return nil }
        let key = item.faviconPath ?? url
        if let img = faviconCache[key] { return img }
        let img = item.faviconPath.flatMap { NSImage(contentsOfFile: $0) } ?? favicons.image(for: url)
        if let img { faviconCache[key] = img }
        return img
    }

    // MARK: Importing

    func startImport(withExtensions: Bool) {
        let plan = self.plan ?? ImportPlan(source: source?.name ?? "")
        let chosen = withExtensions ? extensions.filter { selectedExtensions.contains($0.id) } : []
        let selection = plan.selecting(spaces: selectedSpaces, favorites: includeFavorites)
        var cats: [ImportCategory] = []
        if !selection.spaces.isEmpty {
            cats.append(ImportCategory(id: "spaces", title: "Spaces", symbol: "square.stack.fill",
                                       detail: count(selection.spaces.count, "space")))
            cats.append(ImportCategory(id: "tabs", title: "Tabs & Folders", symbol: "pin.fill",
                                       detail: count(selection.spaces.reduce(0) { $0 + $1.itemCount }, "tab")))
        }
        let favoriteCount = selection.spaces.reduce(selection.favorites.count) { $0 + $1.favorites.count }
        if favoriteCount > 0 {
            cats.append(ImportCategory(id: "favorites", title: "Favorites", symbol: "star.fill", detail: count(favoriteCount, "favorite")))
        }
        if includeArchive && !plan.archive.isEmpty {
            cats.append(ImportCategory(id: "archive", title: "Archive", symbol: "archivebox.fill", detail: count(plan.archive.count, "tab")))
        }
        if !credentials.logins.isEmpty {
            cats.append(ImportCategory(id: "passwords", title: "Passwords", symbol: "key.fill", detail: count(credentials.logins.count, "password")))
        }
        if !credentials.cookies.isEmpty {
            cats.append(ImportCategory(id: "cookies", title: "Sign-ins", symbol: "person.badge.key.fill", detail: count(credentials.cookies.count, "cookie")))
        }
        if !chosen.isEmpty {
            cats.append(ImportCategory(id: "extensions", title: "Extensions", symbol: "puzzlepiece.extension.fill", detail: count(chosen.count, "extension")))
        }
        if includeSettings && !plan.settings.isEmpty {
            cats.append(ImportCategory(id: "settings", title: "Settings", symbol: "gearshape.fill", detail: "Auto-archive"))
        }
        categories = cats
        failures = []
        finished = false
        go(.progress)

        // A fresh install starts with one empty space; once real spaces arrive it only gets in the way.
        let emptyBefore = firstRun && !selection.spaces.isEmpty
            ? store.orderedSpaces.filter { store.tabs(under: $0.pinnedContainerID).isEmpty && store.tabs(under: $0.todayContainerID).isEmpty }
            : []
        let result = store.apply(selection, includeArchive: includeArchive, includeSettings: includeSettings,
                                 replacing: emptyBefore.map(\.id))
        importedSpaceID = result.spaceIDs.first
        favicons.reset()
        let creds = credentials
        Task { @MainActor in
            // Dia paces the tiles (ImportProgressController.progressUIIntervals) so
            // each category visibly lands; the sidebar work above is already done.
            for i in categories.indices {
                categories[i].state = .working
                switch categories[i].id {
                case "extensions":
                    await importExtensions(chosen, tile: i)
                case "passwords", "cookies":
                    // Both land in one staged file; the first tile writes it.
                    if !credentialsStaged && credentialError == nil {
                        let ok = await Task.detached(priority: .userInitiated) { CredentialImport.stage(creds) }.value
                        credentialsStaged = ok
                        if !ok { credentialError = "Cra could not save the imported passwords and cookies." }
                    }
                    try? await Task.sleep(nanoseconds: 420_000_000)
                    categories[i].state = credentialsStaged ? .done : .failed
                default:
                    if categories[i].id == "spaces" { categories[i].detail = count(result.spaces, "space") }
                    if categories[i].id == "tabs" { categories[i].detail = count(result.tabs, "new tab") }
                    try? await Task.sleep(nanoseconds: 420_000_000)
                    categories[i].state = .done
                }
            }
            finished = true
        }
    }

    private func importExtensions(_ chosen: [ImportableExtension], tile i: Int) async {
        var failed: [String] = []
        for ext in chosen {
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                (try? ExtensionStore.importExtension(ext)) != nil
            }.value
            if ok { importedExtensionCount += 1 } else { failed.append(ext.name) }
        }
        if importedExtensionCount > 0 { store.settings.chromeEngine = true }
        categories[i].detail = count(importedExtensionCount, "extension")
        categories[i].state = failed.isEmpty ? .done : .failed
        if !failed.isEmpty { failures.append("Extensions import failed for \(failed.joined(separator: ", "))") }
    }

    private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    /// Restarting is needed for extensions and for staged passwords and cookies.
    var needsRelaunch: Bool { importedExtensionCount > 0 || credentialsStaged }

    // MARK: Pinned tabs (Dia's PinnedTabsView)

    /// Shown unless the favorites grid already has a full row.
    var offersPinnedTabs: Bool { store.tabs(under: store.focusedSpace.favoritesContainerID).count < 4 }

    /// Dia's pre-pinnable apps (PinnedTabs/Icons/* in its Onboarding bundle).
    static let presetPins: [PinCandidate] = [
        PinCandidate(host: "mail.google.com", name: "Gmail", url: "https://mail.google.com/"),
        PinCandidate(host: "calendar.google.com", name: "Calendar", url: "https://calendar.google.com/"),
        PinCandidate(host: "app.slack.com", name: "Slack", url: "https://app.slack.com/"),
        PinCandidate(host: "notion.so", name: "Notion", url: "https://www.notion.so/"),
        PinCandidate(host: "github.com", name: "GitHub", url: "https://github.com/"),
        PinCandidate(host: "figma.com", name: "Figma", url: "https://www.figma.com/"),
        PinCandidate(host: "youtube.com", name: "YouTube", url: "https://www.youtube.com/"),
        PinCandidate(host: "open.spotify.com", name: "Spotify", url: "https://open.spotify.com/"),
        PinCandidate(host: "drive.google.com", name: "Drive", url: "https://drive.google.com/"),
        PinCandidate(host: "docs.google.com", name: "Docs", url: "https://docs.google.com/"),
        PinCandidate(host: "linear.app", name: "Linear", url: "https://linear.app/"),
        PinCandidate(host: "canva.com", name: "Canva", url: "https://www.canva.com/"),
    ]

    /// Most visited sites from the browser imported from (Dia's rankedTopSitesTask),
    /// then the presets, twelve in all; the first four visited sites start ticked.
    func loadPinCandidates() {
        guard !pinsLoaded else { return }
        pinsLoaded = true
        let source = self.source?.kind == .safari ? nil : (self.source ?? sources.first { $0.kind != .safari })
        let fromExport = exportTopSites
        let existing = Set(store.tabs(under: store.focusedSpace.favoritesContainerID).compactMap { $0.tab.flatMap { FaviconCache.key(for: $0.url) } })
        pinCandidates = Self.presetPins
        Task { @MainActor in
            let (sites, icons) = await Task.detached(priority: .userInitiated) { () -> ([TopSite], [String: NSImage]) in
                let sites = fromExport.isEmpty ? (source?.topSites(limit: 16) ?? []) : fromExport
                let hosts = sites.map(\.host) + Self.presetPins.map(\.host)
                return (sites, source?.favicons(hosts: hosts) ?? [:])
            }.value
            var seen = Set<String>()
            var out: [PinCandidate] = []
            for s in sites where out.count < 6 && seen.insert(s.host).inserted && !existing.contains(s.host) {
                let preset = Self.presetPins.first { $0.host == s.host }
                out.append(preset ?? PinCandidate(host: s.host, name: Self.displayName(s), url: s.url))
            }
            let visited = out.prefix(4).map(\.host)
            for p in Self.presetPins where out.count < 12 && seen.insert(p.host).inserted { out.append(p) }
            pinIcons = icons
            pinCandidates = out
            selectedPins = Set(visited)
        }
    }

    private static func displayName(_ s: TopSite) -> String {
        let title = s.title.split(whereSeparator: { "|–—-·:".contains($0) }).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !title.isEmpty && title.count <= 18 { return title }
        let base = s.host.split(separator: ".").dropLast().last.map(String.init) ?? s.host
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    func togglePin(_ host: String) {
        if selectedPins.contains(host) { selectedPins.remove(host) } else { selectedPins.insert(host) }
    }

    /// Adds the picked sites to the favorites grid and moves on.
    func continueFromPinnedTabs() {
        let picked = pinCandidates.filter { selectedPins.contains($0.host) }
        if !picked.isEmpty {
            var plan = ImportPlan(source: "Onboarding")
            plan.favorites = picked.map { ImportedItem(customTitle: $0.name, pageTitle: $0.name, url: $0.url) }
            store.apply(plan, includeArchive: false, includeSettings: false)
            for p in picked { if let icon = pinIcons[p.host], let key = FaviconCache.key(for: p.url) { favicons.store(icon, forKey: key) } }
        }
        go(.personalization)
    }

    // MARK: Personalization (Dia's PersonalizationView)

    func chooseTheme(_ i: Int) {
        chosenTheme = i
        var space = store.focusedSpace
        space.theme = SpaceTheme.presets[i]
        store.updateSpace(space)
    }

    var classicLayout: Bool {
        get { store.settings.showToolbar }
        set { store.settings.showToolbar = newValue }
    }

    func continueFromPersonalization() { go(.outro) }
}

/// Dia shows the import as its own 928×544 window with no title bar.
@MainActor
final class ImportWindowController: NSWindowController, NSWindowDelegate {
    static let size = NSSize(width: 928, height: 544)
    private let model: ImportFlowModel
    private let onClosed: () -> Void

    init(store: SidebarStore, favicons: FaviconCache, firstRun: Bool,
         onFinish: @escaping (ImportOutcome) -> Void, onClosed: @escaping () -> Void) {
        self.onClosed = onClosed
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: firstRun ? [.titled, .fullSizeContentView] : [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = firstRun ? "Welcome to Cra" : "Import"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(b)?.isHidden = true }
        var closeWindow: () -> Void = {}
        model = ImportFlowModel(store: store, favicons: favicons, firstRun: firstRun,
                                onClose: { closeWindow() },
                                onFinish: { outcome in closeWindow(); onFinish(outcome) })
        super.init(window: window)
        closeWindow = { [weak window] in window?.close() }
        window.delegate = self
        let host = NSHostingView(rootView: ImportFlowView(model: model))
        host.sizingOptions = []
        window.contentView = host
        // A titled window adds the title bar to the content rect; Dia's is 544 pt overall.
        window.setFrame(NSRect(origin: .zero, size: Self.size), display: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(over parent: NSWindow?) {
        guard let window else { return }
        if let p = parent {
            let f = p.frame
            window.setFrameOrigin(NSPoint(x: f.midX - Self.size.width / 2, y: f.midY - Self.size.height / 2))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { onClosed() }
}
