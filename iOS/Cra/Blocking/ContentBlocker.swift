import CraCore
import WebKit

/// Arc Search's always-on blocking: ads and trackers by the Mac app's domain list, cookie
/// banners by their containers. WebKit compiles each into a rule list once and keeps it; a page
/// gets the lists its site's switches ask for (`MobileBlocklist.ruleLists(for:)`).
final class ContentBlocker {
    static let shared = ContentBlocker()

    private(set) var list = MobileBlocklist(text: "")
    private var compiled: [String: WKContentRuleList] = [:]
    private var waiting: [() -> Void] = []
    private(set) var isReady = false

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
            self.isReady = true
            let waiting = self.waiting
            self.waiting = []
            waiting.forEach { $0() }
        }
    }

    /// Runs `work` once the lists exist: at once from the second launch on.
    func whenReady(_ work: @escaping () -> Void) {
        if isReady { work() } else { waiting.append(work) }
    }

    /// Gives a web view's controller exactly the lists `options` ask for.
    func apply(_ options: MobileSiteOptions?, to controller: WKUserContentController) {
        controller.removeAllContentRuleLists()
        guard let options else { return }
        for name in MobileBlocklist.ruleLists(for: options) {
            if let list = compiled[name] { controller.add(list) }
        }
    }
}
