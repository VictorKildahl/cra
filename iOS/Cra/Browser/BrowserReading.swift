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
            self.pageContainer.addSubview(reader)
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
