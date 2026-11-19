import CraCore
import WebKit

/// Arc Search's always-on blocking: ads and trackers by the Mac app's domain list, ads also by
/// Cra's filters (paths that stay when an ad network changes domains, #570), cookie banners by
/// their containers. WebKit compiles each into a rule list once and keeps it; a page
/// gets the lists its site's switches ask for (`MobileBlocklist.ruleLists(for:)`).
final class ContentBlocker {
    static let shared = ContentBlocker()

    private(set) var list = MobileBlocklist(text: "")
    /// Cra's filters (resources/blocklist/filters.txt), compiled into the Block Ads list.
    private(set) var filters = FilterList(text: "")
    /// The domains of the lists added in Default Site Settings ▸ Block Lists (#507), blocked as ads.
    private(set) var added = MobileBlocklist(text: "")
    /// The full rules of added lists that have more than domains (#570), once read: for the count.
    private(set) var addedFilters: [FilterList] = []
    /// How many rule lists the added lists were compiled into: custom-0, custom-1, …
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
        let filterText = Bundle.main.url(forResource: "filters", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        filters = FilterList(text: filterText)
        // The list's size and the filters' hash in the name, so a new list is compiled afresh.
        let version = "v2-\(list.domains.count)-\(CustomBlocklist.cacheFileName(for: filterText).dropLast(4))"
        let sources: [(String, () -> String)] = [
            (MobileBlocklist.Kind.ads.rawValue, { [list, filters] in MobileBlocklist.adsRulesJSON(domains: list.domains(of: .ads), filters: filters) }),
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
            // Lists an earlier version of Cra compiled are never looked up again.
            let current = sources.map { "cra-\($0.0)-\(version)" }
            store.getAvailableContentRuleListIdentifiers { names in
                for name in names ?? [] where name.hasPrefix("cra-") && !name.hasPrefix("cra-custom-") && !current.contains(name) {
                    store.removeContentRuleList(forIdentifier: name) { _ in }
                }
            }
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

    /// Whether a request for `url` on a page of `pageHost` is stopped on a site with `options`: by
    /// Cra's list, its filters or an added list.
    func stops(url: String, onPage pageHost: String?, with options: MobileSiteOptions) -> Bool {
        if list.stops(url: url, onPage: pageHost, with: options, filters: filters) { return true }
        guard options.blockAds, let host = URL(string: url)?.host else { return false }
        return added.blocks(host: host) || addedFilters.contains { $0.blocks(url: url, onPage: pageHost) }
    }

    /// The added lists' full rules as read, for `stops`.
    func setAddedFilters(_ lists: [FilterList]) {
        addedFilters = lists
    }

    /// An added list with full rules (#570): the key its compiled rule lists are named by, and its
    /// rules, read only when they have to be compiled.
    struct AddedList {
        let key: String
        let rules: () -> BlocklistRules
    }

    /// Compiles the added lists into rule lists of their own, which pages get from their next load:
    /// the domain lists' merged domains (#507), then each list with full rules on its own (#570).
    /// WebKit keeps compiled lists under names that carry what they were made from, so a launch with
    /// the same lists looks them up; a list with full rules isn't even read for that (its names say
    /// how many it has). Ones no longer used are removed.
    func setAdded(_ domains: [String], lists added: [AddedList] = []) {
        let domainKey = "\(domains.count)-\(CustomBlocklist.cacheFileName(for: domains.joined(separator: "\n")).dropLast(4))"
        let key = ([domainKey] + added.map(\.key)).joined(separator: "+")
        guard key != addedKey, let store = WKContentRuleListStore.default() else {
            readiness.addedListsCompiled()
            return releaseWaiting()
        }
        addedKey = key
        let chunks = MobileBlocklist.customChunks(domains)
        let domainIdentifiers = chunks.indices.map { "cra-\(MobileBlocklist.customRuleListName($0))-\(domainKey)" }
        store.getAvailableContentRuleListIdentifiers { available in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.addedKey == key else { return }
                let available = available ?? []
                var domainLists = [WKContentRuleList?](repeating: nil, count: chunks.count)
                var ruleLists = [[WKContentRuleList?]](repeating: [], count: added.count)
                var used = Set(domainIdentifiers)
                let group = DispatchGroup()
                for (index, chunk) in chunks.enumerated() {
                    group.enter()
                    let identifier = domainIdentifiers[index]
                    store.lookUpContentRuleList(forIdentifier: identifier) { found, _ in
                        if let found {
                            domainLists[index] = found
                            return group.leave()
                        }
                        DispatchQueue.global(qos: .utility).async {
                            let rules = MobileBlocklist.rulesJSON(blocking: chunk)
                            DispatchQueue.main.async {
                                store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, _ in
                                    domainLists[index] = list
                                    group.leave()
                                }
                            }
                        }
                    }
                }
                for (n, list) in added.enumerated() {
                    if let names = MobileBlocklist.compiledRuleLists(key: list.key, in: available) {
                        used.formUnion(names)
                        ruleLists[n] = Array(repeating: nil, count: names.count)
                        for (j, name) in names.enumerated() {
                            group.enter()
                            store.lookUpContentRuleList(forIdentifier: name) { found, _ in
                                ruleLists[n][j] = found
                                group.leave()
                            }
                        }
                        continue
                    }
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let rules = list.rules()
                        let json = MobileBlocklist.customRuleLists(domains: [], filters: [rules.filters]).map { $0.json() }
                        DispatchQueue.main.async {
                            let names = json.indices.map { MobileBlocklist.ruleListIdentifier(key: list.key, index: $0, count: json.count) }
                            used.formUnion(names)
                            ruleLists[n] = Array(repeating: nil, count: names.count)
                            for (j, name) in names.enumerated() {
                                group.enter()
                                store.compileContentRuleList(forIdentifier: name, encodedContentRuleList: json[j]) { compiled, error in
                                    if let error { NSLog("Cra: added list %@ rule list %d didn't compile: %@", list.key, j, String(describing: error)) }
                                    ruleLists[n][j] = compiled
                                    group.leave()
                                }
                            }
                            group.leave()
                        }
                    }
                }
                group.notify(queue: .main) { [weak self] in
                    guard let self, self.addedKey == key else { return }
                    // A rule list that failed to compile is left out; the rest are named in order.
                    let lists = (domainLists + ruleLists.flatMap { $0 }).compactMap { $0 }
                    for name in self.compiled.keys where name.hasPrefix("custom-") { self.compiled[name] = nil }
                    for (index, list) in lists.enumerated() { self.compiled[MobileBlocklist.customRuleListName(index)] = list }
                    self.addedLists = lists.count
                    self.added = MobileBlocklist(text: domains.joined(separator: "\n"))
                    self.readiness.addedListsCompiled()
                    self.releaseWaiting()
                    store.getAvailableContentRuleListIdentifiers { names in
                        DispatchQueue.main.async { [weak self] in
                            // A later call may be compiling lists of its own by now.
                            guard self?.addedKey == key else { return }
                            for name in names ?? [] where name.hasPrefix("cra-custom-") && !used.contains(name) {
                                store.removeContentRuleList(forIdentifier: name) { _ in }
                            }
                        }
                    }
                }
            }
        }
    }
}
