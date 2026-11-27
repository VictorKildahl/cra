import CryptoKit
import Foundation
import WebKit

/// Ad and tracker blocking in WebKit pages (the protected-media tabs and the sites switched to Safari's engine). The
/// lists Chromium pages block with (BlockLists) go to WebKit as content-blocker lists (WebKitContentRules), which
/// WebKit compiles into the data folder's Blocklists/WebKit store once per change and keeps across launches. Each
/// list's name is its rules' digest, so an unchanged selection compiles nothing. A page takes the lists before it
/// loads a site, and leaves them off on a site whose Ad Blocking is paused. The filter lists' scriptlets and hiding
/// reach WebKit pages the way they reach Chromium's (FilterPageScripts, BrowserManager.applyElementHiding).
@MainActor
final class WebKitContentBlocking {
    static let shared = WebKitContentBlocking()

    /// The compiled lists in use; empty while nothing blocks.
    private(set) var lists: [WKContentRuleList] = []
    /// Settings ▸ Privacy's switch, with every list and My filters (AppSettings.hasActiveBlockFilters).
    var enabled = true {
        didSet { if enabled != oldValue { pagesChanged() } }
    }
    private var identifiers: [String] = []
    private var complete = false
    /// How many rules the lists hold (cra.log); unknown for the lists kept from the last run.
    private var ruleCount: Int?
    private var generation = 0
    private let pages = NSHashTable<WebKitBrowser>.weakObjects()

    nonisolated static var folder: URL { BlockLists.folder.appendingPathComponent("WebKit", isDirectory: true) }
    nonisolated private static var keptURL: URL { folder.appendingPathComponent("lists.json") }

    private lazy var store: WKContentRuleListStore? = {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        return WKContentRuleListStore(url: Self.folder)
    }()

    private init() {}

    /// The lists a page loading `url` gets: none on a paused site or with blocking off.
    func lists(for url: URL?) -> [WKContentRuleList] {
        guard enabled, !lists.isEmpty else { return [] }
        if let url, BlockLists.shared.isPaused(url: url.absoluteString) { return [] }
        return lists
    }

    func register(_ page: WebKitBrowser) { pages.add(page) }

    /// At launch: the lists the last run compiled, so pages restored before the filter lists are read block from
    /// their first load.
    func restore() {
        guard identifiers.isEmpty, let data = try? Data(contentsOf: Self.keptURL),
              let kept = try? JSONDecoder().decode([String].self, from: data), !kept.isEmpty else { return }
        ruleCount = nil
        load(kept, sources: nil)
    }

    /// The lists for the rules in use now (WebKitContentRules.lists, from BlockLists); none blocks nothing.
    func set(_ sources: [String], rules: Int) {
        let ids = sources.map(Self.identifier)
        guard ids != identifiers || !complete else { return }
        ruleCount = rules
        load(ids, sources: sources)
    }

    private static func identifier(_ json: String) -> String {
        "cra-" + SHA256.hash(data: Data(json.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Looks each list up in the store and compiles the ones it lacks (`sources`; nil at launch, when a missing one
    /// waits for the filter lists).
    private func load(_ ids: [String], sources: [String]?) {
        generation += 1
        let current = generation
        identifiers = ids
        complete = false
        guard let store else { return }
        Task { @MainActor [weak self] in
            var found: [WKContentRuleList] = []
            var compiled = 0
            let started = Date()
            for (i, id) in ids.enumerated() {
                if let list = try? await store.contentRuleList(forIdentifier: id) {
                    found.append(list)
                    continue
                }
                guard let sources, i < sources.count else { continue }
                do {
                    if let list = try await store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: sources[i]) {
                        found.append(list)
                        compiled += 1
                    }
                } catch {
                    CraLog.note("webkit content rules: list \(i + 1) of \(ids.count) not compiled: \(error.localizedDescription)")
                }
                guard self?.generation == current else { return }
            }
            guard let self, generation == current else { return }
            lists = found
            complete = found.count == ids.count
            CraLog.note("webkit content rules: \(found.count) \(found.count == 1 ? "list" : "lists") in use"
                + (sources != nil && found.count == ids.count ? " (\(ruleCount ?? 0) rules)" : sources == nil ? " (kept from the last run)" : "")
                + (compiled > 0 ? ", \(compiled) compiled in \(String(format: "%.1f", Date().timeIntervalSince(started))) s" : ""))
            if sources != nil { keep(ids, in: store) }
            pagesChanged()
        }
    }

    /// Remembers the lists for the next launch and drops the ones no selection names any more.
    private func keep(_ ids: [String], in store: WKContentRuleListStore) {
        if let data = try? JSONEncoder().encode(ids) { try? data.write(to: Self.keptURL, options: .atomic) }
        store.getAvailableContentRuleListIdentifiers { available in
            for old in available ?? [] where old.hasPrefix("cra-") && !ids.contains(old) {
                store.removeContentRuleList(forIdentifier: old) { _ in }
            }
        }
    }

    /// Open pages take the new lists for their next load.
    private func pagesChanged() {
        for page in pages.allObjects { page.applyContentRules() }
    }

    /// The filter lists' scriptlets changed (FilterPageScripts): open pages run the new ones from their next load.
    func scriptsChanged() {
        for page in pages.allObjects { page.reinstallUserScripts() }
    }
}
