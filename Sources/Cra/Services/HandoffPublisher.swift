import AppKit

/// Handoff from the Mac (GitHub #745): the front window's page is Cra's current NSUserActivity, so an iPhone's app
/// switcher offers to open it, as it does Safari's, Chrome's and Firefox's. Chrome's own sender (HandoffObserver in
/// its AppController) follows Chrome's browser windows, which Cra never shows, so Cra offers the page itself; which
/// pages go is HandoffPage's call. Pages handed to Cra come in through AppDelegate+Handoff (#254).
@MainActor
final class HandoffPublisher {
    struct Page { let address: String; let offTheRecord: Bool }

    /// What the iPhone is offered now, nil for nothing; cra://debug?handoff logs it.
    private(set) var offered: URL?
    private var activity: NSUserActivity?
    private let page: @MainActor () -> Page?

    /// `page`: the front window's page. A main window's selected tab and its address are observed; which window
    /// is key isn't observable, so a window becoming key looks again.
    init(page: @escaping @MainActor () -> Page?) {
        self.page = page
    }

    func start() {
        observeChanges(of: { [weak self] in self?.current() }) { [weak self] url in self?.offer(url ?? nil) }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() { offer(current()) }

    private func current() -> URL? {
        page().flatMap { HandoffPage.url(for: $0.address, offTheRecord: $0.offTheRecord) }
    }

    private func offer(_ url: URL?) {
        guard url != offered else { return }
        offered = url
        guard let url else {
            activity?.invalidate()
            activity = nil
            return
        }
        let activity = self.activity ?? NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        activity.becomeCurrent()
        self.activity = activity
    }
}
