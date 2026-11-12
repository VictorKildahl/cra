import CraCore
import UIKit

/// The browser's swipes. `MobileSwipe` decides what each one does when the finger lifts.
extension BrowserViewController: UIGestureRecognizerDelegate {
    private enum Name {
        static let bar = "bar-swipe", page = "page-swipe", sheet = "sheet-drag", pinch = "page-pinch"
    }

    func installGestures() {
        let barPan = UIPanGestureRecognizer(target: self, action: #selector(barSwiped(_:)))
        barPan.name = Name.bar
        barPan.delegate = self
        bar.addGestureRecognizer(barPan)

        let pagePan = UIPanGestureRecognizer(target: self, action: #selector(pageSwiped(_:)))
        pagePan.name = Name.page
        pagePan.delegate = self
        pageContainer.addGestureRecognizer(pagePan)

        let sheetPan = UIPanGestureRecognizer(target: self, action: #selector(sheetDragged(_:)))
        sheetPan.name = Name.sheet
        sheetPan.delegate = self
        sheet.addGestureRecognizer(sheetPan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pagePinched(_:)))
        pinch.name = Name.pinch
        pinch.delegate = self
        pageContainer.addGestureRecognizer(pinch)

        // Holding the pill is voice search: speak while it is held, let go to search.
        let talk = UILongPressGestureRecognizer(target: self, action: #selector(pillHeld(_:)))
        talk.minimumPressDuration = 0.35
        bar.pill.addGestureRecognizer(talk)

        // Holding the up arrow goes straight to the share sheet.
        bar.menuButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(menuHeld(_:))))
    }

    public func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        if let pinch = gesture as? UIPinchGestureRecognizer, pinch.name == Name.pinch {
            // Pinching in on a page that is not zoomed: there is nothing to zoom out of, so it summarizes.
            guard pinchSummarizes, readerView == nil, let scroll = shownPage?.webView.scrollView else { return false }
            return pinch.scale < 1 && scroll.zoomScale <= scroll.minimumZoomScale + 0.01
        }
        guard let pan = gesture as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        switch pan.name {
        case Name.bar:
            // Sideways for the neighbouring tab, upwards for the tab row.
            return !isSearching && switcher == nil && shownPage != nil && (abs(velocity.x) > abs(velocity.y) || velocity.y < 0)
        case Name.page:
            guard !isSearching, switcher == nil, menuHost == nil, let page = shownPage, abs(velocity.x) > 1.5 * abs(velocity.y) else { return false }
            let mode = settings.value.options(for: page.webView.url?.host).swipeToNavigate
            return MobileSwipe.mayStart(at: pan.location(in: view).x - pan.translation(in: view).x, width: view.bounds.width, mode: mode)
        case Name.sheet:
            return isSearching && velocity.y > abs(velocity.x)
        default:
            return true
        }
    }

    public func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gesture.name == Name.pinch
    }

    /// The page's own scrolling waits until a sideways swipe has been ruled out.
    public func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        gesture.name == Name.page && other.view is UIScrollView
    }

    // MARK: Along the bar: the neighbouring tab

    private func neighbour(_ step: Int) -> MobileTab? {
        let tabs = store.rowTabs
        guard let current = store.selected, let index = tabs.firstIndex(where: { $0.id == current.id }),
              tabs.indices.contains(index + step) else { return nil }
        return tabs[index + step]
    }

    /// A drag up from the bar: the page shrinks towards its card under the finger, and letting
    /// go settles into the tab row or back into the page.
    private func barDraggedUp(_ pan: UIPanGestureRecognizer) {
        let up = -pan.translation(in: view).y
        switch pan.state {
        case .began:
            guard let page = shownPage else { return }
            let id = page.tabID
            page.takeSnapshot { [weak self] image in
                guard let self, self.barSwipeOpensRow, self.switcher == nil else { return }
                if let image { self.store.setSnapshot(image, for: id) }
                _ = self.prepareSwitcher()
            }
        case .changed:
            guard let switcher, switcher.expandedID != nil else { return }
            switcher.expansion = 1 - MobileMotion.switcherProgress(dragUp: up)
            switcher.layoutIfNeeded()
        case .ended, .cancelled:
            barSwipeOpensRow = false
            let opens = pan.state == .ended && MobileMotion.opensSwitcher(dragUp: up, velocityUp: -pan.velocity(in: view).y)
            if let switcher {
                if opens { settleSwitcher(switcher) } else { cancelSwitcher(switcher) }
            } else if opens {
                showTabs()
            }
        default: break
        }
    }

    @objc func barSwiped(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began {
            let velocity = pan.velocity(in: view)
            barSwipeOpensRow = abs(velocity.y) > abs(velocity.x)
        }
        if barSwipeOpensRow { return barDraggedUp(pan) }
        let width = view.bounds.width, gap: CGFloat = 20
        var x = pan.translation(in: view).x
        // Dragging right brings the older tab in from the left.
        let step = x > 0 ? -1 : 1
        let tab = neighbour(step)
        if tab == nil { x /= 3 }
        switch pan.state {
        case .began:
            captureSnapshot()
        case .changed:
            if swipeNeighbourStep != step || swipeNeighbour == nil {
                swipeNeighbour?.removeFromSuperview()
                swipeNeighbour = nil
                swipeNeighbourStep = step
                if let tab {
                    let picture = UIImageView(image: store.snapshot(tab.id))
                    picture.backgroundColor = .systemBackground
                    picture.contentMode = .scaleAspectFill
                    picture.clipsToBounds = true
                    view.insertSubview(picture, aboveSubview: pageContainer)
                    swipeNeighbour = picture
                }
            }
            pageContainer.transform = CGAffineTransform(translationX: x, y: 0)
            swipeNeighbour?.frame = view.bounds.offsetBy(dx: x + CGFloat(step) * (width + gap), dy: 0)
        case .ended, .cancelled:
            let chosen = pan.state == .ended
                ? MobileSwipe.tabStep(translation: pan.translation(in: view).x, velocity: pan.velocity(in: view).x, width: width,
                                      hasOlder: neighbour(-1) != nil, hasNewer: neighbour(1) != nil) : 0
            let picture = swipeNeighbour
            let target = chosen == 0 ? nil : neighbour(chosen)
            UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                if target != nil {
                    self.pageContainer.transform = CGAffineTransform(translationX: -CGFloat(chosen) * (width + gap), y: 0)
                    picture?.frame = self.view.bounds
                } else {
                    self.pageContainer.transform = .identity
                    picture?.frame = self.view.bounds.offsetBy(dx: CGFloat(self.swipeNeighbourStep) * (width + gap), dy: 0)
                }
            } completion: { _ in
                if let target {
                    self.store.select(target.id)
                    self.show(target)
                    self.refreshTabStack()
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                self.pageContainer.transform = .identity
                picture?.removeFromSuperview()
                if self.swipeNeighbour === picture { self.swipeNeighbour = nil }
            }
        default: break
        }
    }

    // MARK: Across the page: back, forward, and the tab itself

    private var canReopenSwipedTab: Bool {
        tabArchivedBySwipe.map { id in store.archived.contains { $0.id == id } } ?? false
    }

    @objc func pageSwiped(_ pan: UIPanGestureRecognizer) {
        guard let page = shownPage else { return }
        let width = view.bounds.width
        let x = pan.translation(in: view).x
        func outcome(_ translation: CGFloat, _ velocity: CGFloat) -> MobileSwipe.Navigation {
            MobileSwipe.navigation(translation: translation, velocity: velocity, width: width, canGoBack: page.webView.canGoBack,
                                   canGoForward: page.webView.canGoForward, hasOtherTab: store.tabs.count > 1,
                                   canReopenTab: canReopenSwipedTab)
        }
        switch pan.state {
        case .changed:
            // Follows the finger where the swipe leads somewhere, and drags its feet where it doesn't.
            let leads = outcome(x > 0 ? width : -width, 0) != .none
            pageContainer.transform = CGAffineTransform(translationX: leads ? x : x / 4, y: 0)
        case .ended, .cancelled:
            let decided = pan.state == .ended ? outcome(x, pan.velocity(in: view).x) : .none
            guard decided != .none else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
                    self.pageContainer.transform = .identity
                }
                return
            }
            let away: CGFloat = x > 0 ? width : -width
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                self.pageContainer.transform = CGAffineTransform(translationX: away, y: 0)
            } completion: { _ in
                self.finishPageSwipe(decided, from: away)
            }
        default: break
        }
    }

    private func finishPageSwipe(_ navigation: MobileSwipe.Navigation, from away: CGFloat) {
        guard let page = shownPage else { return }
        switch navigation {
        case .back: page.webView.goBack()
        case .forward: page.webView.goForward()
        case .archiveTab:
            let id = page.tabID
            page.webView.removeFromSuperview()
            page.delegate = nil
            shownPage = nil
            store.archive(id)
            tabArchivedBySwipe = id
            if let tab = store.selected { show(tab) }
            refreshTabStack()
        case .reopenTab:
            if let id = tabArchivedBySwipe {
                captureSnapshot()
                store.restore(id)
                tabArchivedBySwipe = nil
                if let tab = store.selected { show(tab) }
                refreshTabStack()
            }
        case .none: break
        }
        // What comes next arrives from the side the old page left to.
        pageContainer.transform = CGAffineTransform(translationX: -away * 0.3, y: 0)
        pageContainer.alpha = 0
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.pageContainer.transform = .identity
            self.pageContainer.alpha = 1
        }
    }

    // MARK: The search sheet, dragged down

    @objc func sheetDragged(_ pan: UIPanGestureRecognizer) {
        let y = max(0, pan.translation(in: view).y)
        switch pan.state {
        case .changed:
            sheet.transform = CGAffineTransform(translationX: 0, y: y)
        case .ended, .cancelled:
            let leaves = pan.state == .ended && (y > 70 || pan.velocity(in: view).y > 700)
            if leaves {
                setSearching(false)
                UIView.animate(withDuration: 0.25) { self.sheet.transform = .identity }
            } else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
                    self.sheet.transform = .identity
                }
            }
        default: break
        }
    }

    // MARK: Holding the pill: voice search

    @objc func pillHeld(_ hold: UILongPressGestureRecognizer) {
        switch hold.state {
        case .began:
            guard !isSearching else { return }
            beginVoiceSearch(handsFree: false)
        case .ended:
            endVoiceSearch(searching: true)
        case .cancelled, .failed:
            endVoiceSearch(searching: false)
        default: break
        }
    }

    /// Starts listening under the voice overlay. Held, it ends when the pill is let go; hands
    /// free (a shortcut, a quick action), a tap on the overlay ends it.
    func beginVoiceSearch(handsFree: Bool) {
        guard voiceOverlay == nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let overlay = VoiceOverlayView(frame: view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if handsFree { overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(voiceOverlayTapped))) }
        view.addSubview(overlay)
        overlay.appear()
        voiceOverlay = overlay
        let voice = VoiceSearch()
        voice.onTranscript = { [weak overlay] in overlay?.setTranscript($0) }
        voice.onLevel = { [weak overlay] in overlay?.setLevel($0) }
        voice.onFailure = { [weak overlay] failure in
            overlay?.setMessage(failure == .denied ? "Allow the microphone and speech recognition in Settings to search by voice."
                                                   : "Voice search needs on-device speech recognition, which this iPhone doesn't have for your language.")
        }
        self.voice = voice
        voice.start()
    }

    @objc func voiceOverlayTapped() {
        endVoiceSearch(searching: true)
    }

    func endVoiceSearch(searching: Bool) {
        guard let overlay = voiceOverlay else { return }
        let heard = voice?.stop() ?? ""
        voice = nil
        voiceOverlay = nil
        overlay.disappear()
        guard searching, !heard.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        incognitoSearch = store.selected?.isIncognito ?? false
        open(MobileSuggestions.destination(forTyped: heard, engine: settings.value.searchEngine))
    }

    // MARK: Holding the up arrow

    @objc func menuHeld(_ hold: UILongPressGestureRecognizer) {
        guard hold.state == .began, let address = shareableAddress, let url = URL(string: address) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = bar.menuButton
        present(share, animated: true)
    }
}
