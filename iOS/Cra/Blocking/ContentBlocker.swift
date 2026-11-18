import CraCore
import WebKit

/// Arc Search's always-on blocking: ads and trackers by the Mac app's domain list, cookie
/// banners by their containers. WebKit compiles each into a rule list once and keeps it; a page
/// gets the lists its site's switches ask for (`MobileBlocklist.ruleLists(for:)`).
final class ContentBlocker {
    static let shared = ContentBlocker()

    private(set) var list = MobileBlocklist(text: "")
    /// The domains of the lists added in Default Site Settings ▸ Block Lists (#507), blocked as ads.
    private(set) var added = MobileBlocklist(text: "")
    /// How many rule lists the added domains were compiled into (MobileBlocklist.customChunks).
    private var addedLists = 0
    /// What the added lists were last compiled from, so the same domains aren't compiled twice.
    private var addedKey: String?
    private var compiled: [String: WKContentRuleList] = [:]
    private var waiting: [() -> Void] = []
    /// When pages may load: Cra's own lists, and at launch the added ones (MobileBlockerReadiness).
    private var readiness = MobileBlockerReadiness()
    var isReady: Bool { readiness.isReady }

    private init() {}

    /// Compiles what isn't compiled yet. The first launch takes a moment; later ones look the
    /// lists up. Safe to call more than once.
    func prepare() {
        guard list.domains.isEmpty, let url = Bundle.main.url(forResource: "domains", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        list = MobileBlocklist(text: text)
        // The list's size in the name, so a new list is compiled afresh.
        let version = "v1-\(list.domains.count)"
        let sources: [(String, () -> String)] = [
            (MobileBlocklist.Kind.ads.rawValue, { [list] in MobileBlocklist.rulesJSON(blocking: list.domains(of: .ads)) }),
            (MobileBlocklist.Kind.trackers.rawValue, { [list] in MobileBlocklist.rulesJSON(blocking: list.domains(of: .trackers)) }),
            ("cookie-banners", { MobileBlocklist.cookieBannerRulesJSON() }),
        ]
        let group = DispatchGroup()
        guard let store = WKContentRuleListStore.default() else { return }
        for (name, json) in sources {
            group.enter()
            let identifier = "cra-\(name)-\(version)"
            store.lookUpContentRuleList(forIdentifier: identifier) { [weak self] found, _ in
                if let found {
                    self?.compiled[name] = found
                    return group.leave()
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let rules = json()
                    DispatchQueue.main.async {
                        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, _ in
                            if let list { self?.compiled[name] = list }
                            group.leave()
                        }
                    }
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.readiness.ownListsCompiled()
            self.releaseWaiting()
        }
    }

    private func releaseWaiting() {
        guard isReady else { return }
        let waiting = self.waiting
        self.waiting = []
        waiting.forEach { $0() }
    }

    /// The setting's addresses at launch: with lists added, pages wait until `setAdded` has their
    /// rule lists (MobileBlockerReadiness).
    func launched(addresses: [String], first: Bool) {
        readiness.launched(addresses: addresses, first: first)
    }

    /// Runs `work` once the lists exist: at once from the second launch on.
    func whenReady(_ work: @escaping () -> Void) {
        if isReady { work() } else { waiting.append(work) }
    }

    /// Gives a web view's controller exactly the lists `options` ask for.
    func apply(_ options: MobileSiteOptions?, to controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
        guard let options else { return }
        for name in MobileBlocklist.ruleLists(for: options, customLists: addedLists) {
            if let list = compiled[name] { controller.add(list) }
        }
    }

    /// Whether a request to `host` is stopped on a site with `options`, by Cra's list or an added one.
    func stops(host: String, with options: MobileSiteOptions) -> Bool {
        list.stops(host: host, with: options) || (options.blockAds && added.blocks(host: host))
    }

    /// Compiles the added lists' domains into rule lists of their own, which pages get from their
    /// next load. Compiled lists are kept by WebKit under a name that carries their content, so a
    /// launch with the same domains looks them up; ones no longer used are removed.
    func setAdded(_ domains: [String]) {
        let key = "\(domains.count)-\(CustomBlocklist.cacheFileName(for: domains.joined(separator: "\n")).dropLast(4))"
        guard key != addedKey, let store = WKContentRuleListStore.default() else {
            readiness.addedListsCompiled()
            return releaseWaiting()
        }
        addedKey = key
        let chunks = MobileBlocklist.customChunks(domains)
        let identifiers = chunks.indices.map { "cra-\(MobileBlocklist.customRuleListName($0))-\(key)" }
        var lists: [String: WKContentRuleList] = [:]
        let group = DispatchGroup()
        for (index, chunk) in chunks.enumerated() {
            group.enter()
            let identifier = identifiers[index]
            store.lookUpContentRuleList(forIdentifier: identifier) { found, _ in
                if let found {
                    lists[MobileBlocklist.customRuleListName(index)] = found
                    return group.leave()
                }
                DispatchQueue.global(qos: .utility).async {
                    let rules = MobileBlocklist.rulesJSON(blocking: chunk)
                    DispatchQueue.main.async {
                        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, _ in
                            if let list { lists[MobileBlocklist.customRuleListName(index)] = list }
                            group.leave()
                        }
                    }
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.addedKey == key else { return }
            for name in self.compiled.keys where name.hasPrefix("custom-") { self.compiled[name] = nil }
            self.compiled.merge(lists) { $1 }
            self.addedLists = chunks.count  // a chunk that failed to compile is skipped by apply
            self.added = MobileBlocklist(text: domains.joined(separator: "\n"))
            self.readiness.addedListsCompiled()
            self.releaseWaiting()
            store.getAvailableContentRuleListIdentifiers { names in
                for name in names ?? [] where name.hasPrefix("cra-custom-") && !identifiers.contains(name) {
                    store.removeContentRuleList(forIdentifier: name) { _ in }
                }
            }
        }
    }
}
