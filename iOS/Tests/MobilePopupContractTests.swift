import Foundation

// The production WKUIDelegate method is compiled below against value-only platform stand-ins.
// The assertions check its returned navigation owner and original request, not view rendering.
final class WKWebViewConfiguration {}
final class UIImage {
    init?(contentsOfFile: String) { return nil }
    func jpegData(compressionQuality: Double) -> Data? { nil }
}
final class WKWebView {}
final class WKWindowFeatures {}
struct WKNavigationAction { let request: URLRequest }
protocol WebPageDelegate: AnyObject {
    func webPage(_ page: WebPage, openInNewTab url: URL)
    func webPage(_ page: WebPage, createPopupWith configuration: WKWebViewConfiguration, request: URLRequest) -> WKWebView?
}
final class WebPage {
    let tabID: UUID
    let opener: WebPage?
    let webView = WKWebView()
    weak var delegate: WebPageDelegate?
    init(tab: MobileTab = MobileTab(url: "about:blank", lastActive: .distantPast),
         configuration: WKWebViewConfiguration? = nil, opener: WebPage? = nil) {
        tabID = tab.id
        self.opener = opener
    }
    // PRODUCTION_POPUP_CALLBACK
}
final class PopupOwner: WebPageDelegate {
    let view = WKWebView()
    var request: URLRequest?
    var configuration: WKWebViewConfiguration?
    func webPage(_ page: WebPage, openInNewTab url: URL) {}
    func webPage(_ page: WebPage, createPopupWith configuration: WKWebViewConfiguration, request: URLRequest) -> WKWebView? {
        self.configuration = configuration
        self.request = request
        return view
    }
}
@main struct MobilePopupContractTests {
    static var checks = 0
    static func main() {
        let page = WebPage(), owner = PopupOwner(), configuration = WKWebViewConfiguration()
        page.delegate = owner
        var request = URLRequest(url: URL(string: "https://synthetic.example/checkout")!)
        request.httpMethod = "POST"
        request.httpBody = Data("order=synthetic-123&quantity=2".utf8)
        let popup = page.webView(WKWebView(), createWebViewWith: configuration,
                                for: WKNavigationAction(request: request), windowFeatures: WKWindowFeatures())
        check(popup === owner.view, "a target-blank POST must return its new WebKit navigation owner instead of cancelling it")
        check(owner.configuration === configuration, "a popup keeps WebKit's supplied related configuration")
        check(owner.request?.httpMethod == "POST" && owner.request?.httpBody == request.httpBody,
              "the popup ownership path keeps the complete POST request")
        page.delegate = nil
        check(page.webView(WKWebView(), createWebViewWith: configuration,
                           for: WKNavigationAction(request: request), windowFeatures: WKWindowFeatures()) == nil,
              "an unowned page cannot open a popup")
        storeOwnership()
        print("Mobile popup ownership: \(checks) checks passed")
    }
    static func storeOwnership() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cra-popup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TabStore(directory: directory, now: { Date(timeIntervalSinceReferenceDate: 42) })
        let sourceTab = store.open(url: "https://source.example/")
        let source = store.page(for: sourceTab)
        let selectedPrivate = store.open(url: "https://private.example/", incognito: true)
        let request = URLRequest(url: URL(string: "https://source.example/popup")!)
        let popup = store.openPopup(configuration: WKWebViewConfiguration(), request: request, from: source)!
        check(store.selected?.id == popup.tabID && store.selected?.isIncognito == false,
              "a popup inherits its actual source, not a different selected private tab")
        check(!store.tabs.contains { $0.id == selectedPrivate.id }, "leaving an unrelated private tab closes it")
        check(store.existingPage(popup.tabID) === popup && popup.opener === source,
              "the returned popup and its source remain the store's live pages")
        store.close(popup.tabID)
        check(store.selected?.id == sourceTab.id, "closing a popup returns to its still-open source")

        let privateTab = store.open(url: "https://secret.example/", incognito: true)
        let privateSource = store.page(for: privateTab)
        let child = store.openPopup(configuration: WKWebViewConfiguration(), request: request, from: privateSource)!
        check(store.selected?.isIncognito == true, "a private source creates a private popup")
        check(store.tabs.contains { $0.id == privateTab.id }, "a private popup keeps its opener available")
        let grandchild = store.openPopup(configuration: WKWebViewConfiguration(), request: request, from: child)!
        check(store.tabs.filter(\.isIncognito).count == 3, "nested private popups keep their live opener chain")
        store.saveNow()
        let restored = TabStore(directory: directory)
        check(restored.tabs.allSatisfy { !$0.isIncognito } && restored.archived.allSatisfy { !$0.isIncognito },
              "no private popup or retained opener is persisted")
        store.close(grandchild.tabID)
        check(store.selected?.id == child.tabID, "a nested popup closes back to its immediate source")
        store.close(child.tabID)
        check(store.selected?.id == privateTab.id, "the last private popup closes back to its private source")
        let lastChild = store.openPopup(configuration: WKWebViewConfiguration(), request: request, from: privateSource)!
        store.close(privateTab.id)
        store.close(lastChild.tabID)
        check(!store.tabs.contains { $0.id == privateTab.id }, "closing a child never recreates an explicitly closed opener")
        check(store.openPopup(configuration: WKWebViewConfiguration(), request: request, from: privateSource) == nil,
              "a closed source cannot create another popup")
        let nextPrivate = store.open(url: "https://secret.example/again", incognito: true)
        let nextPage = store.page(for: nextPrivate)
        _ = store.openPopup(configuration: WKWebViewConfiguration(), request: request, from: nextPage)
        store.select(sourceTab.id)
        check(store.tabs.allSatisfy { !$0.isIncognito }, "leaving the live chain removes every private popup and opener")
        check(store.existingPage(nextPrivate.id) == nil, "private opener storage is released after leaving the chain")
        check(store.archived.allSatisfy { !$0.isIncognito }, "private relationship cleanup never archives secret tabs")
        let archivedSource = store.open(url: "https://secret.example/archive", incognito: true)
        let archivedPage = store.page(for: archivedSource)
        let archivedChild = store.openPopup(configuration: WKWebViewConfiguration(), request: request, from: archivedPage)!
        store.archive(archivedSource.id)
        store.archive(archivedChild.tabID)
        check(store.tabs.allSatisfy { !$0.isIncognito } && store.archived.allSatisfy { !$0.isIncognito },
              "explicitly archiving a private opener and its popup leaves neither recoverable")
        check(store.existingPage(archivedSource.id) == nil && store.existingPage(archivedChild.tabID) == nil,
              "private archive removes both live-page store entries")
    }
    static func check(_ value: Bool, _ message: String) {
        checks += 1
        guard value else { print("FAIL: \(message)"); exit(1) }
    }
}
