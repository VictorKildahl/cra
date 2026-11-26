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

    /// Notes what a swipe across the page starts on, to find the scroll views under it, and
    /// where the bar swipe's finger came down, before the pan moves off it.
    public func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gesture.name == Name.page, gesture.numberOfTouches == 0 { pageSwipeTouchView = touch.view }
        if gesture.name == Name.bar, gesture.numberOfTouches == 0 { barSwipeStart = touch.location(in: bar) }
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
            page.takeSnapshot(height: pageViewHeight) { [weak self] image in
                guard let self, self.barSwipeOpensRow, self.switcher == nil else { return }
                if let image { self.store.setSnapshot(image, for: id) }
                _ = self.prepareSwitcher()
            }
        case .changed:
            guard let switcher, switcher.expandedID != nil else { return }
            switcher.expansion = 1 - MobileMotion.switcherProgress(dragUp: up)
            switcher.layoutIfNeeded()
            layoutChrome()
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
    /// before this one comes out of the button's front card in the hand, while the page on screen
    /// drops into a card and shrinks into the bottom-left; letting go puts that page into the
    /// button and the new tab into the page's place. The next flick comes back.
    private func barFlickedUp(_ pan: UIPanGestureRecognizer, to target: MobileTab) {
        let up = -pan.translation(in: view).y
        let origin = bar.tabsButton.frontCard(in: view)
        let full = view.bounds
        let area = tabArea
        let barTop = area.maxY
        let statusBar = area.minY
        let start = origin
        let previewWidth = full.width * 0.7
        // The page being left is the whole screen: it drops into a rounded card 20 pt in from the
        // screen and the bar, then shrinks with the hand into the bottom-left corner, half the tab
        // area's height (`MobileMotion.flickStartFrame`, `flickCardFrame`).
        let source = CGRect(origin: .zero, size: full.size)
        let liftFrame = MobileMotion.flickStartFrame(in: source, aboveBar: barTop)
        let oldFrame = MobileMotion.flickCardFrame(in: source, aboveBar: barTop, safeTop: statusBar)
        func frame(from a: CGRect, to b: CGRect, _ t: CGFloat) -> CGRect {
            CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                   width: a.width + (b.width - a.width) * t,
                   height: a.height + (b.height - a.height) * t)
        }
        func fitOld(_ lift: CGFloat) {
            guard let oldCard = flick.oldCard, let oldShot = flick.oldShot,
                  oldCard.bounds.width > 0, oldCard.bounds.height > 0 else { return }
            let l = max(0, min(1, lift))
            let fit = max(oldCard.bounds.width / source.width, oldCard.bounds.height / source.height)
            // The picture starts where the page was — not resized — and settles into the card as
            // the card lifts.
            let pageCenter = CGPoint(x: source.midX - oldCard.center.x + oldCard.bounds.midX,
                                     y: source.midY - oldCard.center.y + oldCard.bounds.midY)
            oldShot.bounds = CGRect(origin: .zero, size: source.size)
            oldShot.center = CGPoint(x: pageCenter.x + (oldCard.bounds.midX - pageCenter.x) * l,
                                     y: pageCenter.y + (oldCard.bounds.midY - pageCenter.y) * l)
            let scale = 1 + (fit - 1) * l
            oldShot.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
        func placeOld(_ progress: CGFloat, lift: CGFloat? = nil, intoButton: Bool = false) {
            guard let oldCard = flick.oldCard else { return }
            let p = max(0, min(1, progress))
            let l = max(0, min(1, lift ?? flick.lift))
            // Size and center rather than frame: a frame set on a rotated view is measured as the
            // rotated bounding box, which would shrink it.
            if intoButton {
                oldCard.bounds = CGRect(origin: .zero, size: origin.size)
                oldCard.center = CGPoint(x: origin.midX, y: origin.midY)
                oldCard.layer.cornerRadius = 5
                oldCard.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                               .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                oldCard.transform = CGAffineTransform(rotationAngle: MobileMotion.frontCardTilt)
                // The whole page, shrunk into the small card, as the button's picture will be.
                fitOld(1)
            } else {
                // Ease out: the drop off the page is quick to start and settles softly.
                let raised = MobileMotion.easeOut(l)
                let landed = frame(from: source, to: liftFrame, raised)
                let settled = frame(from: landed, to: oldFrame, p)
                oldCard.bounds = CGRect(origin: .zero, size: settled.size)
                oldCard.center = CGPoint(x: settled.midX, y: settled.midY)
                // The device's own rounding from the first frame of the drop, all four corners,
                // square again when the card is back at the page.
                oldCard.layer.cornerRadius = raised > 0.001 || p > 0.001 ? MobileMotion.flickCornerRadius : 0
                oldCard.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                               .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                oldCard.transform = .identity
                fitOld(raised)
            }
        }
        func place(_ progress: CGFloat, at drag: CGPoint = .zero) {
            let p = max(0, min(1, progress))
            // Pinned to the finger: the card keeps the grip it was picked up by and grows with the
            // hand. Its shape goes from the button's little card to the screen's own on a clock of
            // its own (`flick.aspect`), not the drag's.
            let width = start.width + (previewWidth - start.width) * p
            let buttonAspect = start.height / max(start.width, 1)
            let screenAspect = full.height / full.width
            var height = width * (buttonAspect + (screenAspect - buttonAspect) * flick.aspect)
            let fingerY = start.midY + drag.y
            // It grows slowly enough, and no further, that its bottom stays on the screen.
            let limit = MobileMotion.flickCardLimit(fingerY: fingerY, screenHeight: full.height)
            var size = CGSize(width: width, height: height)
            if height > limit {
                let shrink = limit / max(height, 1)
                height = limit
                size = CGSize(width: width * shrink, height: height)
            }
            // The hand holds the card's middle at first, then just under halfway down as it
            // grows: the tab hangs from the finger rather than sitting on it.
            let center = CGPoint(x: start.midX + drag.x, y: fingerY + 0.05 * (height - start.height))
            // The tab's own band under the status bar, scaled with the card.
            flick.band?.frame = CGRect(x: 0, y: 0, width: size.width,
                                      height: statusBar * size.width / max(full.width, 1))
            // Bounds and center, not frame: the card is rotated while dragging, and a frame set
            // through that rotation comes out smaller than the screen.
            flickCard?.bounds = CGRect(origin: .zero, size: size)
            flickCard?.center = center
            flickCard?.layer.cornerRadius = 5 + 17 * p
        }
        switch pan.state {
        case .began:
            // Anything left of an interrupted settle goes before this card does.
            flick.startGesture()
            dropFlickHandoff()
            swipeNeighbourCard?.removeFromSuperview()
            swipeNeighbourCard = nil
            // The tab on screen keeps its picture up to date, taken before the card covers it, and
            // the card shows that same picture. Right after a switch the page has not drawn: its
            // picture would be black, so the tab's stored one stands in.
            let drawn = CACurrentMediaTime() - pageShownAt > MobileMotion.pageDrawDelay
            if drawn { capturePageSnapshot() }
            // The front card hands its tab to the flick: the slot is left empty underneath it.
            bar.tabsButton.setFrontEmpty(true)
            let card = UIView()
            // Purely a picture: it sits over the bar after the drop, and must not eat the next
            // swipe on the tab button while it settles.
            card.isUserInteractionEnabled = false
            card.clipsToBounds = true
            card.backgroundColor = .systemBackground
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = 1 / max(1, view.traitCollection.displayScale)
            card.layer.borderColor = UIColor(white: 0, alpha: 0.12).cgColor
            // The card shows the page as it is on screen: a snapshot view is a copy the render
            // server already has, sharp and free. Only a page swapped in a moment ago, not drawn
            // yet, shows its stored picture instead.
            if drawn, let shot = pageContainer.snapshotView(afterScreenUpdates: false) {
                flick.oldShot = shot
            } else if let image = shownPage.flatMap({ store.snapshot($0.tabID) }) {
                let imageView = UIImageView(image: image)
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                flick.oldShot = imageView
            }
            if let oldShot = flick.oldShot { card.addSubview(oldShot) }
            flick.oldCard = card
            // Under the bar while it drops, so the bar keeps its controls; it comes over the bar
            // once the drop is done.
            view.insertSubview(card, aboveSubview: pageContainer)
            pageContainer.isHidden = true

            // The tab's stored picture: never a black one (`TabStore.snapshot`).
            let arrivingImage = store.snapshot(target.id)
            let picture = UIImageView(image: arrivingImage)
            picture.backgroundColor = .systemBackground
            picture.contentMode = .scaleAspectFill
            picture.clipsToBounds = true
            picture.layer.cornerCurve = .continuous
            // A hairline, as on the tab button's cards, keeps a white page apart from a white page.
            picture.layer.borderWidth = 1 / max(1, view.traitCollection.displayScale)
            picture.layer.borderColor = UIColor(white: 0, alpha: 0.12).cgColor
            picture.accessibilityIdentifier = "previous-tab-card"
            // The page's coloured band under the status bar is the app's, not the site's, so the
            // card carries it too: the arriving tab looks as it will when it is on screen.
            let bandColour = bandColour(for: target)
            flick.arrivingFill = bandColour.flatMap { Palette.hex($0, traits: traitCollection) }
            let band = UIView()
            if let bandColour {
                band.backgroundColor = bandColour
            } else {
                band.isHidden = true
            }
            picture.addSubview(band)
            flick.band = band
            // Above the bar: the card grows from the button itself, not out from behind it.
            view.addSubview(picture)
            flickCard?.removeFromSuperview()
            flickCard = picture
            place(0)
            // The page drops into a rounded card as soon as the drag starts, then follows the
            // hand into the corner.
            placeOld(0, lift: 0)
            flick.frameUpdate = { [weak self] in
                guard let self else { return }
                place(self.flick.progress, at: self.flick.dragPoint)
                placeOld(self.flick.travel)
            }
            // The card hangs from the finger from the first frame: straight, until the hand moves.
            flick.anchor = pan.translation(in: view)
            startFlickTilt()
            applyFlickTilt()
        case .changed:
            // The card grows straight with the hand, all the way to the top of the screen.
            let drag = pan.translation(in: view)
            let startY = pan.location(in: view).y - drag.y
            let progress = MobileSwipe.previousTabProgress(dragUp: up, to: startY)
            flick.swingTarget = MobileMotion.flickSwingTarget(velocityX: pan.velocity(in: view).x)
            flick.swingAt = CACurrentMediaTime()
            flick.progress = progress
            flick.dragPoint = CGPoint(x: drag.x - flick.anchor.x, y: drag.y - flick.anchor.y)
            place(progress, at: flick.dragPoint)
            applyFlickTilt()
            // Straight with the hand: the card keeps shrinking until the hand reaches the top of
            // the screen.
            flick.travel = MobileMotion.flickCardProgress(dragUp: up, startY: startY)
            placeOld(flick.travel)
        case .ended, .cancelled:
            barSwipeTarget = nil
            let generation = flick.generation
            let picture = flickCard
            let switches = pan.state == .ended && MobileSwipe.switchesToPreviousTab(dragUp: up, velocityUp: -pan.velocity(in: view).y)
            // Its lean's speed carries into the landing: read before the hand's clock stops.
            let spin = flick.swingRate
            stopFlickTilt()
            if switches {
                // The bar over the arriving tab changes as it comes in, not once it has landed.
                flick.statusFill = flick.arrivingFill
                flick.statusPage = target.id
                setNeedsStatusBarAppearanceUpdate()
            }
            let buttonFlight = MobileMotion.flickButtonFlight
            // The page card goes over the bar for its flight into the button.
            let liveIncoming = switches && store.existingPage(target.id)?.webView.url != nil
            if let oldCard = flick.oldCard {
                view.insertSubview(oldCard, aboveSubview: switches ? bar : pageContainer)
            }
            if liveIncoming {
                // Bar at the bottom, then the page card, then the arriving page on top.
                view.insertSubview(pageContainer, aboveSubview: flick.oldCard ?? bar)
            }
            // A tab let go already over the bar belongs under it, so it never covers it.
            if switches, let picture, picture.frame.intersects(bar.frame) {
                view.insertSubview(picture, aboveSubview: pageContainer)
            }
            func finish() {
                guard self.flick.generation == generation else { return }
                self.flick.end = nil
                settle()
            }
            func settle() {
                // The page's shape is layout's again, whether it flew in or not.
                // Taken off first, so its own end does not settle a second time.
                let landing = self.flick.landing
                self.flick.landing = nil
                landing?.layer.removeAnimation(forKey: UIView.flickLandingKey)
                self.flick.incoming = false
                self.pageContainer.clipsToBounds = false
                if switches, self.store.tabs.contains(where: { $0.id == target.id }) {
                    // The incoming card's last frame is the whole screen, edge to edge (its transform
                    // first: a frame set through a transform is not the frame it gets).
                    picture?.transform = .identity
                    picture?.frame = full
                    picture?.layer.cornerRadius = 0
                    self.store.bringToFront(target.id)
                    self.show(target)
                    self.refreshTabStack()
                }
                // The front card is the page left behind now, or the same one again.
                self.bar.tabsButton.setFrontEmpty(false)
                self.pageContainer.transform = .identity
                self.pageContainer.isHidden = false
                if switches, let card = self.flick.oldCard {
                    // The card becomes the button's picture itself, so nothing is swapped under
                    // it: no snapshot to render, nothing to go blank or black.
                    self.bar.tabsButton.keepFrontCard(card)
                    self.flick.oldCard = nil
                } else {
                    self.flick.oldCard?.removeFromSuperview()
                    self.flick.oldCard = nil
                }
                self.flick.oldShot = nil
                if switches, let picture, picture.superview != nil {
                    // Leave the card over the page for the frame it takes to draw, so the swap
                    // does not flash blank.
                    self.handOff(picture)
                } else {
                    picture?.removeFromSuperview()
                }
                if self.flickCard === picture { self.flickCard = nil }
                self.flick.band = nil
                self.flick.arrivingFill = nil
            }
            flick.end = { settle() }
            if switches {
                // The page card goes into the button while the arriving tab fills the page; part
                // of the way through that flight the tab goes under the bar, the page card above.
                UIView.animate(withDuration: buttonFlight, delay: 0, usingSpringWithDamping: 0.9,
                               initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    placeOld(1, intoButton: true)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + buttonFlight * MobileMotion.flickUnderBarAt) { [weak self] in
                    guard let self, self.flick.generation == generation else { return }
                    if liveIncoming {
                        self.view.insertSubview(self.pageContainer, belowSubview: self.bar)
                    } else if let picture, picture.superview != nil {
                        self.view.insertSubview(picture, aboveSubview: self.pageContainer)
                    }
                }
                if let picture {
                    // The arriving tab: the live page itself when the tab has one, taking the
                    // card's place, size, lean and corners so it can load and take touches the
                    // whole way, or else the card. Either is laid out at the page's size and
                    // drawn smaller, so only its transform changes and a page's viewport never
                    // does.
                    let center = picture.center
                    let angle = atan2(picture.transform.b, picture.transform.a)
                    let scale = max(0.02, min(1, picture.bounds.width / full.width))
                    let corner = picture.layer.cornerRadius
                    let card: UIView
                    if liveIncoming {
                        store.bringToFront(target.id)
                        show(target)
                        pageContainer.isHidden = false
                        flick.incoming = true
                        pageContainer.clipsToBounds = true
                        picture.removeFromSuperview()
                        card = pageContainer
                    } else {
                        picture.layer.borderWidth = 0
                        card = picture
                        flick.band?.frame = CGRect(x: 0, y: 0, width: full.width, height: statusBar)
                    }
                    let landing = MobileMotion.FlickLanding(
                        from: center, to: CGPoint(x: full.midX, y: full.midY),
                        velocity: MobileMotion.flickLaunch(velocity: pan.velocity(in: view)),
                        angle: angle, spin: spin, scale: scale)
                    card.bounds = CGRect(origin: .zero, size: full.size)
                    // One smooth arc on the hand's own throw, its lean letting go and a small
                    // overshoot in size, worked out ahead and played by the render server: the
                    // page arriving meanwhile cannot make it stutter.
                    let step = 1.0 / 120
                    flick.landing = card
                    card.playLanding(landing.frames(every: step), every: step, corner: corner) { [weak self, weak card] in
                        guard let self, let card, self.flick.landing === card else { return }
                        self.view.setNeedsLayout()
                        finish()
                    }
                } else {
                    finish()
                }
            } else {
                // Back into the button's little card: its shape goes back with it.
                flick.aspect = 0
                UIView.animate(spring: MobileMotion.tabOpen) {
                    place(0)
                    placeOld(0, lift: 0)
                    // Back into the button's card, leaning as it lies there, in full view: it is
                    // only taken away once it is in place.
                    picture?.transform = CGAffineTransform(rotationAngle: MobileMotion.frontCardTilt)
                } completion: { finish() }
            }
        default: break
        }
    }

    // MARK: The flick's card in the hand

    /// Holds the card over the page for the frame or two an unhidden page needs to draw — and no
    /// longer, so the page scrolls and takes taps the moment it is on screen.
    private func handOff(_ picture: UIImageView) {
        dropFlickHandoff()
        flick.handoff = picture
        DispatchQueue.main.asyncAfter(deadline: .now() + MobileMotion.flickHandoffHold) { [weak self, weak picture] in
            guard let self, self.flick.handoff === picture else { return }
            self.dropFlickHandoff()
        }
    }

    func dropFlickHandoff() {
        flick.handoff?.removeFromSuperview()
        flick.handoff = nil
    }

    /// The card hangs from the finger: straight until the hand pulls it sideways.
    private func applyFlickTilt() {
        guard let card = flickCard else { return }
        card.transform = CGAffineTransform(rotationAngle: flick.swing)
        // A leaning card's corners reach above its own top, so its place gives way: no part of
        // it ever crosses the top of the screen.
        let overhang = -card.frame.minY
        if overhang > 0 { card.center.y += overhang }
    }

    private func startFlickTilt() {
        flick.link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(flickSwung(_:)))
        link.add(to: .main, forMode: .common)
        flick.link = link
    }

    private func stopFlickTilt() {
        flick.link?.invalidate()
        flick.link = nil
        flick.frameUpdate = nil
        flick.swing = 0
        flick.swingRate = 0
        flick.swingTarget = 0
    }

    /// One frame of the flick's own clocks: the card rocking from the hand (held still, it hangs
    /// straight again), its shape becoming the screen's, and the page under it dropping into its
    /// first card.
    @objc private func flickSwung(_ link: CADisplayLink) {
        let dt = min(1.0 / 30, max(1.0 / 240, link.targetTimestamp - link.timestamp))
        // A hand that has stopped sending events asks for no lean at all, or the card would
        // hold the last angle it was given. A brief pause before letting go keeps it, so the
        // lean is still there to settle when the tab is released.
        if CACurrentMediaTime() - flick.swingAt > MobileMotion.flickHandStill { flick.swingTarget = 0 }
        (flick.swing, flick.swingRate) = MobileMotion.flickSwingStep(angle: flick.swing, speed: flick.swingRate,
                                                                     target: flick.swingTarget, dt: dt)
        if flick.aspect < 1 || flick.lift < 1 {
            flick.aspect = min(1, flick.aspect + dt / MobileMotion.flickReshape)
            let dropping = flick.lift < 1
            flick.lift = min(1, flick.lift + dt / MobileMotion.flickDrop)
            // One layout for both clocks.
            flick.frameUpdate?()
            if dropping, flick.lift >= 1, let card = flick.oldCard {
                // Over the bar from here, so its flight into the button is seen, but still behind
                // the tab coming in.
                view.insertSubview(card, aboveSubview: bar)
            }
        }
        // The lean last, after any layout, so it is what keeps the card below the screen's top.
        applyFlickTilt()
    }

    @objc func barSwiped(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began {
            // A flick still settling is finished before this drag is read, so the tab it brings
            // is the one read and nothing of it is left frozen over the page.
            flick.end?()
            flick.end = nil
            let at = pan.location(in: bar), moved = pan.translation(in: bar)
            let startedAt = barSwipeStart ?? CGPoint(x: at.x - moved.x, y: at.y - moved.y)
            barSwipeStart = nil
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
            showSwapBackdrop(for: shownPage)
            swipeNeighbourCard?.removeFromSuperview()
            swipeNeighbourCard = nil
        case .changed:
            if swipeNeighbourStep != step || swipeNeighbourCard == nil {
                swipeNeighbourCard?.removeFromSuperview()
                swipeNeighbourCard = nil
                swipeNeighbourStep = step
                if let tab {
                    let top = view.safeAreaInsets.top
                    let background = pageBackground(for: tab.id)
                    let card = UIView(frame: view.bounds)
                    card.backgroundColor = background
                    card.clipsToBounds = true
                    let content = UIImageView(image: store.snapshot(tab.id))
                    content.backgroundColor = background
                    content.contentMode = .scaleAspectFill
                    content.clipsToBounds = true
                    // The page's content sits below its band and runs on under the bar, as the
                    // page it becomes will.
                    content.frame = restingPageViewFrame
                    card.addSubview(content)
                    // The incoming tab already has its band at full height: only the tab row
                    // animates the band's size.
                    if let colour = bandColour(for: tab) {
                        let band = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: top))
                        band.backgroundColor = colour
                        band.autoresizingMask = [.flexibleWidth]
                        card.addSubview(band)
                    }
                    view.insertSubview(card, aboveSubview: pageContainer)
                    swipeNeighbourCard = card
                }
            }
            pageContainer.transform = CGAffineTransform(translationX: x, y: 0)
            swipeNeighbourCard?.frame = view.bounds.offsetBy(dx: x + CGFloat(step) * (width + gap), dy: 0)
        case .ended, .cancelled:
            let chosen = pan.state == .ended
                ? MobileSwipe.tabStep(translation: pan.translation(in: view).x, velocity: pan.velocity(in: view).x, width: width,
                                      hasOlder: neighbour(-1) != nil, hasNewer: neighbour(1) != nil) : 0
            let picture = swipeNeighbourCard
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
                    self.layoutChrome()
                    self.refreshTabStack()
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                self.pageContainer.transform = .identity
                picture?.removeFromSuperview()
                if self.swipeNeighbourCard === picture { self.swipeNeighbourCard = nil }
                self.hideSwapBackdrop()
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
            // The drawer belongs to the bar: its material takes the drawer's colour at once, and
            // the plus waits in the bar's top edge until the finger lets go.
            drawer.growsFromBar = true
            drawer.fieldHold = .closed
            setDrawerMaterial(true)
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
            bar.layoutIfNeeded()
            sheet.layoutIfNeeded()
            // The drag's last frame, for `-CraTraceNewTabDrawer`.
            traceNewTabDrawerDrag()
        case .ended, .cancelled:
            barSwipePullsSearch = false
            if pan.state == .ended, MobileSwipe.searchPullOpens(dragUp: up, velocityUp: -pan.velocity(in: view).y) {
                setSearching(true)
            } else {
                drawer.fieldHold = .none
                setDrawerMaterial(false)
                searchPull = nil
                animateChrome(duration: MobileSearchMotion.settleDuration, options: .curveEaseInOut)
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
            if pageContainer.transform != .identity { showSwapBackdrop(for: page) }
        case .ended, .cancelled:
            let decided = pan.state == .ended ? outcome(x, pan.velocity(in: view).x) : .none
            guard decided != .none else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
                    self.pageContainer.transform = .identity
                } completion: { _ in
                    self.hideSwapBackdrop()
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
        // What comes next arrives from the side the old page left to. The floor under it takes
        // the arriving page's colour, if it is another tab.
        showSwapBackdrop(for: shownPage)
        pageContainer.transform = CGAffineTransform(translationX: -away * 0.3, y: 0)
        pageContainer.alpha = 0
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.pageContainer.transform = .identity
            self.pageContainer.alpha = 1
        } completion: { _ in
            self.hideSwapBackdrop()
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
            // The field stays open, full size, while the drawer is dragged down; it only shrinks
            // into the pill once the finger lets go and the close starts.
            drawer.fieldHold = .open
            setSearching(false, keepingPull: MobileSwipe.sheetDragDownPull(startPull: start, dragDown: down),
                          deferDrawerMaterial: true)
        case .changed:
            guard let start = sheetDragStartPull else { return }
            searchPull = MobileSwipe.sheetDragDownPull(startPull: start, dragDown: down)
            layoutChrome()
            bar.layoutIfNeeded()
            sheet.layoutIfNeeded()
            traceNewTabDrawerDrag()
            traceSheetDrag()
        case .ended, .cancelled:
            sheetDragTraceView.accessibilityValue = "under the keyboard \(sheetDragTrace.hidden) of \(sheetDragTrace.frames)"
            guard sheetDragStartPull != nil else { return }
            sheetDragStartPull = nil
            drawer.fieldHold = .none
            if pan.state == .ended, !MobileSwipe.sheetDragDownCloses(dragDown: down, velocityDown: pan.velocity(in: view).y) {
                setSearching(true)
            } else {
                // Let go: the word and the drawer's incognito fade together.
                sheet.hideIncognitoLabel()
                restoreBarIncognito()
                // The colour only goes back to the bar's material once the finger is off and the
                // drawer is closing.
                if drawer.growsFromBar { setDrawerMaterial(false) }
                searchPull = nil
                // Let go of a drag down, the drawer falls the rest of the way on a short spring
                // with a small overshoot as it settles into the bar.
                animateChrome(spring: MobileNewTabDrawer.bounce)
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
