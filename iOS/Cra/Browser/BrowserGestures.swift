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
        pagePan.maximumNumberOfTouches = 1
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
            // Sideways for the neighbouring tab, upwards for the tab row (from the bar's left
            // end, the previous tab: `MobileSwipe.barDrag`).
            return !isSearching && switcher == nil && shownPage != nil && (abs(velocity.x) > abs(velocity.y) || velocity.y < 0)
        case Name.page:
            guard !isSearching, switcher == nil, menuHost == nil, let page = shownPage else { return false }
            let mode = settings.value.options(for: page.webView.url?.host).swipeToNavigate
            return MobileSwipe.pageSwipeStarts(at: pan.location(in: view).x - pan.translation(in: view).x, width: view.bounds.width,
                                               mode: mode, touches: pan.numberOfTouches, velocity: velocity,
                                               scrollers: scrollRooms(under: pageSwipeTouchView, in: page.webView))
        case Name.sheet:
            // From anywhere on the sheet, its suggestions too while they are at their top (#623).
            guard isSearching else { return false }
            let list = sheet.suggestionList, at = pan.location(in: list), moved = pan.translation(in: list)
            let onList = list.bounds.contains(CGPoint(x: at.x - moved.x, y: at.y - moved.y))
            return MobileSwipe.sheetDragStarts(velocity: velocity, onList: onList, listOffset: list.contentOffset.y + list.adjustedContentInset.top)
        default:
            return true
        }
    }

    public func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gesture.name == Name.pinch
    }

    /// The page's own scrolling waits until a sideways swipe has been ruled out. Its pinch to zoom
    /// doesn't wait (#628): two fingers never swipe the page.
    public func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard other is UIPanGestureRecognizer else { return false }
        switch gesture.name {
        case Name.page: return other.view is UIScrollView
        // The suggestions scroll once a drag down on the sheet has been ruled out (#623).
        case Name.sheet: return other.view === sheet.suggestionList
        default: return false
        }
    }

    /// Notes what a swipe across the page starts on, to find the scroll views under it.
    public func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gesture.name == Name.page, gesture.numberOfTouches == 0 { pageSwipeTouchView = touch.view }
        return true
    }

    /// How far each scroll view under the finger, from the innermost (a carousel, a wide table:
    /// WebKit gives each its own scroll view) out to the page's, can still scroll sideways (#627).
    private func scrollRooms(under touched: UIView?, in webView: UIView) -> [MobileSwipe.ScrollRoom] {
        var rooms: [MobileSwipe.ScrollRoom] = []
        var view = touched
        while let current = view, current !== webView {
            if let scroll = current as? UIScrollView, scroll.isScrollEnabled {
                rooms.append(MobileSwipe.ScrollRoom(offsetX: scroll.contentOffset.x, contentWidth: scroll.contentSize.width,
                                                    width: scroll.bounds.width, insetLeft: scroll.adjustedContentInset.left,
                                                    insetRight: scroll.adjustedContentInset.right))
            }
            view = current.superview
        }
        return rooms
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

    /// A drag up that starts on the tab button (#537), Arc Search's flick: the tab looked at
    /// before this one grows out of the button's back card under the finger while the page
    /// sinks back, and letting go puts it on screen. The next flick comes back.
    private func barFlickedUp(_ pan: UIPanGestureRecognizer, to target: MobileTab) {
        let up = -pan.translation(in: view).y
        let origin = bar.tabsButton.backCard(in: view)
        let full = view.bounds
        // The card starts page-shaped, as wide as the button's back card.
        let start = CGRect(x: origin.midX - origin.width / 2, y: origin.maxY - origin.width * full.height / full.width,
                           width: origin.width, height: origin.width * full.height / full.width)
        func place(_ progress: CGFloat) {
            let p = progress
            // As in Arc Search, the card heads for the middle sooner than it grows: half grown,
            // it is already centred across the screen.
            let across = min(1, 2 * p)
            let size = CGSize(width: start.width + (full.width - start.width) * p, height: start.height + (full.height - start.height) * p)
            let center = CGPoint(x: start.midX + (full.midX - start.midX) * across, y: start.midY + (full.midY - start.midY) * p)
            swipeNeighbour?.frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
            swipeNeighbour?.layer.cornerRadius = 5 + 35 * p
            let scale = 1 - 0.12 * p
            pageContainer.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        switch pan.state {
        case .began:
            captureSnapshot()
            let picture = UIImageView(image: store.snapshot(target.id))
            picture.backgroundColor = .systemBackground
            picture.contentMode = .scaleAspectFill
            picture.clipsToBounds = true
            picture.layer.cornerCurve = .continuous
            // A hairline, as on the tab button's cards, keeps a white page apart from a white page.
            picture.layer.borderWidth = 1 / max(1, view.traitCollection.displayScale)
            picture.layer.borderColor = UIColor(white: 0, alpha: 0.12).cgColor
            picture.accessibilityIdentifier = "previous-tab-card"
            view.insertSubview(picture, aboveSubview: pageContainer)
            swipeNeighbour?.removeFromSuperview()
            swipeNeighbour = picture
            place(0)
        case .changed:
            place(MobileSwipe.previousTabProgress(dragUp: up))
        case .ended, .cancelled:
            barSwipeTarget = nil
            let picture = swipeNeighbour
            let switches = pan.state == .ended && MobileSwipe.switchesToPreviousTab(dragUp: up, velocityUp: -pan.velocity(in: view).y)
            UIView.animate(spring: MobileMotion.tabOpen) {
                if switches {
                    place(1)
                    picture?.layer.cornerRadius = 0
                    picture?.layer.borderWidth = 0
                } else {
                    place(0)
                    picture?.alpha = 0
                }
            } completion: {
                if switches, self.store.tabs.contains(where: { $0.id == target.id }) {
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

    @objc func barSwiped(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began {
            let at = pan.location(in: bar), moved = pan.translation(in: bar)
            let startedAt = CGPoint(x: at.x - moved.x, y: at.y - moved.y)
            let zone = MobileBottomBar.previousTabZone(in: bar.bounds.size, safeBottom: bar.bounds.height - MobileBottomBar.height)
            let pullZone = MobileBottomBar.searchPullZone(in: bar.bounds.size, safeBottom: bar.bounds.height - MobileBottomBar.height)
            let previous = store.previousTab
            let drag = MobileSwipe.barDrag(velocity: pan.velocity(in: view), startsInPreviousTabZone: zone.contains(startedAt),
                                           hasPreviousTab: previous != nil, startsInSearchPullZone: pullZone.contains(startedAt))
            barSwipeOpensRow = drag == .tabRow
            barSwipeTarget = drag == .previousTab ? previous : nil
            barSwipePullsSearch = drag == .searchSheet
        }
        if barSwipePullsSearch { return barPulledUp(pan) }
        if let target = barSwipeTarget { return barFlickedUp(pan, to: target) }
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

    /// A drag up from the pill (#623), Arc Search's way to search: the sheet comes out of the
    /// pill under the finger, and letting go far enough up opens it with the keyboard; short of
    /// that it sinks back into the pill.
    private func barPulledUp(_ pan: UIPanGestureRecognizer) {
        let up = max(0, -pan.translation(in: view).y)
        switch pan.state {
        case .began:
            prepareSearchSheet(incognito: store.selected?.isIncognito ?? false)
            searchPull = 0
            UIView.performWithoutAnimation {
                self.layoutChrome()
                self.sheet.layoutIfNeeded()
            }
            searchPull = up
            layoutChrome()
        case .changed:
            searchPull = up
            layoutChrome()
            sheet.layoutIfNeeded()
        case .ended, .cancelled:
            barSwipePullsSearch = false
            if pan.state == .ended, MobileSwipe.searchPullOpens(dragUp: up, velocityUp: -pan.velocity(in: view).y) {
                setSearching(true)
            } else {
                searchPull = nil
                animateChrome(duration: 0.3, options: .curveEaseOut)
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

    /// The open sheet dragged down goes back the way a pull out of the pill brought it up (#655): the keyboard goes
    /// as the drag starts, the sheet's top stays under the finger and its field shrinks back into the pill. Let go
    /// far enough down (or flicked) it sinks into the pill; otherwise it rises back open with the keyboard.
    @objc func sheetDragged(_ pan: UIPanGestureRecognizer) {
        let down = pan.translation(in: view).y
        switch pan.state {
        case .began:
            sheetDragTrace = (0, 0)
            let start = max(0, bar.frame.minY - sheet.frame.minY)
            sheetDragStartPull = start
            setSearching(false, keepingPull: MobileSwipe.sheetDragDownPull(startPull: start, dragDown: down))
        case .changed:
            guard let start = sheetDragStartPull else { return }
            searchPull = MobileSwipe.sheetDragDownPull(startPull: start, dragDown: down)
            layoutChrome()
            sheet.layoutIfNeeded()
            traceSheetDrag()
        case .ended, .cancelled:
            sheetDragTraceView.accessibilityValue = "under the keyboard \(sheetDragTrace.hidden) of \(sheetDragTrace.frames)"
            guard sheetDragStartPull != nil else { return }
            sheetDragStartPull = nil
            if pan.state == .ended, !MobileSwipe.sheetDragDownCloses(dragDown: down, velocityDown: pan.velocity(in: view).y) {
                setSearching(true)
            } else {
                searchPull = nil
                animateChrome(duration: 0.3, options: .curveEaseOut)
            }
        default: break
        }
    }

    /// One frame of a drag down on the sheet, for `-CraTraceSheetDrag`: whether the sheet was in sight.
    func traceSheetDrag() {
        let keyboardTop = keyboardHeight > view.safeAreaInsets.bottom ? view.bounds.height - keyboardHeight : nil
        let top = sheet.frame.minY + sheet.transform.ty
        sheetDragTrace.frames += 1
        if MobileSwipe.sheetUnderKeyboard(sheetTop: top, keyboardTop: keyboardTop) { sheetDragTrace.hidden += 1 }
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
        voiceIsIncognito = store.selected?.isIncognito ?? false
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
        incognitoSearch = voiceIsIncognito
        open(searchDestination(heard))
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
