import CraCore
import SwiftUI
import UIKit

/// Reader and Summarize: both read the page's article (`Article`).
extension BrowserViewController {
    // MARK: Reader

    func toggleReader() {
        if readerView != nil { return closeReader() }
        guard let page = shownPage else { return }
        Article.extract(from: page.webView) { [weak self] article in
            guard let self, page === self.shownPage, let article, !article.text.isEmpty else { return }
            let reader = ReaderView(article: article)
            reader.onLink = { [weak self] url in
                self?.closeReader()
                page.webView.load(URLRequest(url: url))
            }
            reader.frame = self.pageContainer.bounds
            reader.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            reader.alpha = 0
            self.pageContainer.insertSubview(reader, belowSubview: self.pageDim)
            self.readerView = reader
            UIView.animate(withDuration: 0.22) { reader.alpha = 1 }
        }
    }

    func closeReader() {
        guard let reader = readerView else { return }
        readerView = nil
        UIView.animate(withDuration: 0.18) { reader.alpha = 0 } completion: { _ in reader.removeFromSuperview() }
    }

    // MARK: Summarize

    /// Whether a pinch may summarize the page on screen: the device can, and the site lets it.
    var pinchSummarizes: Bool {
        guard BrowseForMe.isAvailable, let page = shownPage, summaryHost == nil, !isSearching, switcher == nil else { return false }
        return settings.value.options(for: page.webView.url?.host).pinchToSummarize
    }

    func summarize() {
        guard let page = shownPage, summaryHost == nil else { return }
        let id = page.tabID
        let tab = store.tabs.first { $0.id == id }
        page.takeSnapshot { [weak self] image in
            guard let self else { return }
            if let image { self.store.setSnapshot(image, for: id) }
            let model = SummaryModel(title: tab?.displayTitle ?? "", favicon: tab.flatMap { self.favicons.icon(for: $0.url) },
                                     snapshot: image ?? self.store.snapshot(id))
            model.close = { [weak self] in self?.closeSummary() }
            model.address = page.webView.url?.absoluteString
            model.share = { [weak self] text in
                guard let self else { return }
                let share = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = self.view
                self.topPresenter.present(share, animated: true)
            }
            let host = UIHostingController(rootView: SummaryView(model: model))
            host.view.frame = self.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.view.alpha = 0
            self.addChild(host)
            self.view.addSubview(host.view)
            host.didMove(toParent: self)
            self.summaryHost = host
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // The page shrinks towards where its card sits while the summary screen comes in.
            UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0, options: []) {
                host.view.alpha = 1
                self.pageContainer.transform = Self.summaryCardTransform(in: self.view.bounds)
            } completion: { _ in
                self.pageContainer.transform = .identity
            }
            Article.extract(from: page.webView) { article in
                Task { @MainActor in
                    let answer = await Summarizer.summarize(title: article?.title ?? model.title, text: article?.text ?? "")
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        model.state = answer.map(SummaryModel.State.done) ?? .failed
                    }
                    if answer != nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            }
        }
    }

    func closeSummary() {
        guard let host = summaryHost else { return }
        summaryHost = nil
        pageContainer.transform = Self.summaryCardTransform(in: view.bounds)
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            host.view.alpha = 0
            self.pageContainer.transform = .identity
        } completion: { _ in
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
    }

    /// The page scaled to the summary screen's 222 pt card, near the top.
    private static func summaryCardTransform(in bounds: CGRect) -> CGAffineTransform {
        let scale = 222 / max(1, bounds.width)
        let cardCentreY = bounds.height * 0.24
        return CGAffineTransform(translationX: 0, y: cardCentreY - bounds.midY).scaledBy(x: scale, y: scale)
    }

    // MARK: Browse for Me

    private static func browseCache(_ id: UUID) -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Browse", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(id.uuidString).html")
    }

    /// Fills a Browse for Me tab: its saved page when there is one, otherwise the loading screen
    /// while the page is made. When no answer comes, the tab becomes the search for the query.
    private static func browseCacheMarker(_ query: String) -> String {
        "<!-- cra-browse: \((query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)) -->\n"
    }

    // MARK: The Browse for Me / search engine switch

    /// Works out which side the page on screen is (a Browse for Me tab, or the engine's results
    /// for a search) and lays the switch out again.
    func updateBrowseToggle() {
        let engine = settings.value.search
        if let page = shownPage, let tab = store.tabs.first(where: { $0.id == page.tabID }) {
            browseToggleState = MobileBrowseToggle.state(tabAddress: tab.url, pageURL: page.webView.url?.absoluteString, engine: engine)
        } else {
            browseToggleState = nil
        }
        if let state = browseToggleState { browseToggle.configure(side: state.side, engine: engine) }
        view.setNeedsLayout()
    }

    /// Above the bar at the right; only with the device's own model, and only while the page is
    /// on screen with its bar.
    func layoutBrowseToggle(barTop: CGFloat) {
        browseToggle.frame = MobileBrowseToggle.frame(screenWidth: view.bounds.width, barTop: barTop)
        let visible = browseToggleState != nil && BrowseForMe.isAvailable && !isSearching && switcher == nil
            && !barHiddenByScroll && !(shownPage?.isBrowsing ?? false) && readerView == nil
        browseToggle.alpha = visible ? 1 : 0
        browseToggle.isUserInteractionEnabled = visible
        browseToggle.accessibilityElementsHidden = !visible
    }

    func browseTogglePicked(_ side: MobileBrowseToggle.Side) {
        guard let page = shownPage, let state = browseToggleState else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        switch side {
        case .engine:
            page.load(settings.value.search.searchURL(state.query))
        case .browseForMe:
            store.update(page.tabID, url: MobileBrowseForMe.tabAddress(query: state.query), title: state.query)
            browse(for: state.query, in: page)
            updateBrowseToggle()
        }
    }

    func browse(for query: String, in page: WebPage) {
        let id = page.tabID
        let incognito = store.tabs.first { $0.id == id }?.isIncognito ?? false
        // The saved page names its query on its first line: a tab switched to the engine and
        // back to Browse for Me for another query makes a new page.
        let marker = Self.browseCacheMarker(query)
        if !incognito, let saved = try? String(contentsOf: Self.browseCache(id), encoding: .utf8), saved.hasPrefix(marker) {
            page.webView.loadHTMLString(saved, baseURL: nil)
            return
        }
        page.isBrowsing = true
        store.update(id, url: nil, title: query)
        let loading = BrowseLoadingView(query: query)
        loading.tabID = id
        loading.frame = pageContainer.bounds
        loading.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageContainer.insertSubview(loading, belowSubview: pageDim)
        browseLoading?.removeFromSuperview()
        browseLoading = loading
        let engine = settings.value.search
        Task { @MainActor [weak self] in
            await BrowseForMe.run(query: query, engine: engine) { step in
                switch step {
                case .reading(let sites): loading.showReading(sites)
                case .making: loading.showMaking()
                case .done(let html, _):
                    page.isBrowsing = false
                    page.webView.loadHTMLString(html, baseURL: nil)
                    if !incognito { try? (marker + html).write(to: Self.browseCache(id), atomically: true, encoding: .utf8) }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    UIView.animate(withDuration: 0.4, delay: 0.25, options: []) { loading.alpha = 0 } completion: { _ in
                        loading.removeFromSuperview()
                        if self?.browseLoading === loading { self?.browseLoading = nil }
                    }
                case .failed:
                    page.isBrowsing = false
                    page.load(engine.searchURL(query))
                    UIView.animate(withDuration: 0.3) { loading.alpha = 0 } completion: { _ in
                        loading.removeFromSuperview()
                        if self?.browseLoading === loading { self?.browseLoading = nil }
                    }
                }
            }
        }
    }

    // MARK: Pinch to Summarize

    @objc func pagePinched(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .changed:
            // The page follows the fingers down to the card's size.
            let scale = min(1, max(0.5, pinch.scale))
            pageContainer.transform = CGAffineTransform(scaleX: scale, y: scale)
            pageContainer.layer.cornerRadius = (1 - scale) * 60
            pageContainer.clipsToBounds = true
        case .ended, .cancelled:
            let summarizes = pinch.state == .ended && pinch.scale < 0.78
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
                self.pageContainer.transform = .identity
                self.pageContainer.layer.cornerRadius = 0
            }
            if summarizes { summarize() }
        default: break
        }
    }
}
