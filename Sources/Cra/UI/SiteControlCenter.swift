import AppKit

/// Arc 1.170's Site Control Center: the sliders button at the end of the toolbar and of the
/// sidebar's URL pill (SiteControlCenterView in ARC_SiteControlCenter). Geometry and colours
/// were read from Arc's accessibility tree and captures of the open popover (26 Oct 2026):
/// a 236 pt column, a row of four 48×32 action buttons, "Extensions" with a 4-column grid of
/// 48×32 tiles (pinned first, then by name, then "+"), "Settings" rows of 208×33 and a footer
/// with the connection state and a More menu. Arc 1.172.2 (17 Nov 2026, #478): the actions are
/// Share, New Boost, Capture and Capture Full Page; a site with boosts gets a "Boosts" section
/// before Settings, one row each (a click turns it on or off, the chevron edits it); the More
/// menu has Manage Boosts… and New Boost…. A tile's 14 pt badge pins it to the toolbar:
/// filled for pinned extensions, grey on hover for the others.
struct SiteControlCenterActions {
    /// Gets the Share button, to hang the share list from.
    var share: (NSView) -> Void = { _ in }
    var copyURL: () -> Void = {}
    var capture: () -> Void = {}
    var captureFullPage: () -> Void = {}
    var runExtension: (String) -> Void = { _ in }
    var addExtension: () -> Void = {}
    var manageExtensions: () -> Void = {}
    var clearCache: () -> Void = {}
    var clearCookies: () -> Void = {}
    var siteSettings: () -> Void = {}
    /// The lock: the page's certificate. nil without one (http, Chromium's pages).
    var showCertificate: (() -> Void)?
    /// A WebKit page's "Learn more" (docs/protected-media.md).
    var learnAboutProtectedMedia: () -> Void = {}
    /// The Safari's Engine row's click, with the row as it stood (SafariEngineRow says what each does).
    var pressSafariEngine: (SafariEngineRow) -> Void = { _ in }
    /// Arc's New Boost, in the second action slot and the More menu; nil where a page can't be
    /// boosted (not a website, or Boosts off in Settings), and Copy URL takes the slot.
    var newBoost: (() -> Void)?
    /// A row's chevron: that boost in the editor.
    var editBoost: (UUID) -> Void = { _ in }
    /// A row's click: the boost on or off.
    var toggleBoost: (UUID) -> Void = { _ in }
    /// The Boosts header's Manage and the More menu's Manage Boosts…: Library ▸ Boosts.
    var manageBoosts: () -> Void = {}
}

enum SiteControlCenterMetrics {
    static let width: CGFloat = 236
    static let inset: CGFloat = 10
    static let tile = CGSize(width: 48, height: 32)
    static let gap: CGFloat = 8
}

/// The popover's content: built in one pass from the store and the extension list, and built
/// again when either changes (pinning, a setting switch).
@MainActor
final class SiteControlCenterView: NSView {
    private typealias M = SiteControlCenterMetrics
    private let url: String
    /// The connection badge (ConnectionSecurity).
    private let secure: Bool
    private let colors: SiteControlCenterColors
    private let actions: SiteControlCenterActions
    private let store: SidebarStore
    /// The page's Chromium profile folder: only its extensions are offered.
    private let profile: String
    /// An incognito page: only the extensions its profile allows in incognito are offered (#620).
    private let incognito: Bool
    /// The page's tab, whose extension icons the tiles show.
    private let tab: UUID?
    /// A WebKit page's service ("Spotify"): the card that says why takes the extensions' place,
    /// and the ad blocker's switch goes (it is Chromium's).
    private let protectedMedia: String?
    /// The Safari's Engine row, nil without it (a page that uses no DRM).
    private let safariEngine: SafariEngineRow?
    private var extensions: ExtensionStore { .shared }
    /// The tiles by extension ID, whose icons follow the extensions' own changes in place.
    private var extensionTiles: [String: SiteExtensionTile] = [:]

    init(url: String, secure: Bool, dark: Bool, profile: String, incognito: Bool = false, tab: UUID?, protectedMedia: String? = nil,
         safariEngine: SafariEngineRow? = nil, actions: SiteControlCenterActions, store: SidebarStore) {
        self.protectedMedia = protectedMedia
        self.safariEngine = safariEngine
        self.url = url
        self.secure = secure
        self.profile = profile
        self.incognito = incognito
        self.tab = tab
        colors = SiteControlCenterColors(dark: dark)
        self.actions = actions
        self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: M.width, height: 100))
        wantsLayer = true
        layer?.backgroundColor = colors.background.cgColor
        observe()
        // An extension changing its icon redraws only its tile, so the one under the pointer
        // keeps its hover. Ends with the view: then nothing observable is read.
        observeChanges(of: { [weak self] in self?.liveIcons() ?? [:] }) { [weak self] icons in
            for (id, icon) in icons { self?.extensionTiles[id]?.show(icon: icon) }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var onResize: (NSSize) -> Void = { _ in }

    /// The extension ringed by ⌘E's picker (ExtensionPicker, #709), by its place in the grid; nil: none.
    var picked: Int? { didSet { if picked != oldValue { showPicked() } } }

    /// The extensions the grid shows, in its order: none while a WebKit page's card takes their place.
    var extensionCount: Int { protectedMedia == nil ? orderedExtensions.count : 0 }

    /// The ringed extension's name, for `cra://debug?siteControlsRead`.
    var pickedName: String? { pickedEntry?.name }

    private var pickedEntry: ExtensionStore.Entry? {
        guard let i = picked, protectedMedia == nil else { return nil }
        let all = orderedExtensions
        return all.indices.contains(i) ? all[i] : nil
    }

    /// ⌘ let go: the ringed extension runs, as a click on its tile does. False when nothing is ringed.
    func runPicked() -> Bool {
        guard let e = pickedEntry else { return false }
        actions.runExtension(e.extensionID)
        return true
    }

    private func showPicked() {
        let id = pickedEntry?.extensionID
        for (tileID, tile) in extensionTiles { tile.ringed = tileID == id }
    }

    /// Arc: pinned extensions in toolbar order, then the rest by name.
    private var orderedExtensions: [ExtensionStore.Entry] {
        extensions.pinned.menuOrder(extensions.entries(inProfile: profile, incognito: incognito), inProfile: profile, id: \.extensionID, name: \.name)
    }

    private func observe() {
        withObservationTracking {
            _ = extensions.entries
            _ = extensions.pinned
            _ = store.settings
            _ = BoostStore.shared.boosts
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        build()
    }

    /// The tiles' icons as the extensions set them now, badge included (chrome.action.setIcon,
    /// setBadgeText; Arc's tiles show both).
    private func liveIcons() -> [String: NSImage?] {
        Dictionary(uniqueKeysWithValues: orderedExtensions.map { ($0.extensionID, liveIcon($0)) })
    }

    private func liveIcon(_ e: ExtensionStore.Entry) -> NSImage? {
        extensions.badged(extensions.liveIcon(for: e, profile: profile, tab: tab), extensions.badge(for: e, profile: profile, tab: tab),
                          tint: colors.secondary)
    }

    private func build() {
        subviews.forEach { $0.removeFromSuperview() }
        let x = M.inset, w = M.width - 2 * M.inset
        var y: CGFloat = 9
        // The four raised action buttons.
        let share = actions.share
        let second: (String, String, () -> Void) = actions.newBoost.map { (BoostGlyph.symbol, "New Boost", $0) } ?? ("link", "Copy URL", actions.copyURL)
        for (i, (symbol, help, run)) in [("square.and.arrow.up", "Share", {}), second,
                                         ("camera", "Capture this page", actions.capture),
                                         ("text.viewfinder", "Capture the full page", actions.captureFullPage)].enumerated() {
            let b = SiteActionButton(symbol: symbol, help: help, colors: colors, action: run)
            if i == 0 { b.onClick = { [weak b] in if let b { share(b) } } }
            b.frame = NSRect(x: x + CGFloat(i) * (M.tile.width + M.gap), y: y, width: M.tile.width, height: M.tile.height)
            addSubview(b)
        }
        y += M.tile.height + 11
        if let service = protectedMedia {
            // A WebKit page: no extensions run in it, so the card says why instead (Arc has none).
            let card = SiteProtectedMediaCard(service: service, width: w, colors: colors, learnMore: actions.learnAboutProtectedMedia)
            card.frame.origin = NSPoint(x: x, y: y)
            addSubview(card)
            y += card.frame.height + 15
        } else {
            // Extensions: a 4-column grid of tiles, then "+".
            let ext = SiteSectionView(title: "Extensions", hoverText: "Manage", colors: colors, onHeaderClick: actions.manageExtensions)
            extensionTiles = [:]
            var tiles: [NSView] = orderedExtensions.map { e in
                let tile = SiteExtensionTile(entry: e, pinned: extensions.isPinned(e.extensionID, inProfile: profile), colors: colors,
                                             run: { [actions] in actions.runExtension(e.extensionID) },
                                             togglePin: { [profile] in
                                                 ExtensionStore.shared.setPinned(e.extensionID, !ExtensionStore.shared.isPinned(e.extensionID, inProfile: profile), inProfile: profile)
                                             })
                tile.show(icon: liveIcon(e))
                extensionTiles[e.extensionID] = tile
                return tile
            }
            let add = SiteTile(colors: colors, help: "Add Extension", action: actions.addExtension)
            add.setGlyph(SidebarSymbols.image("plus", size: 14, weight: .medium), tint: colors.text)
            tiles.append(add)
            for (i, t) in tiles.enumerated() {
                t.frame = NSRect(x: CGFloat(i % 4) * (M.tile.width + M.gap), y: 27 + CGFloat(i / 4) * (M.tile.height + M.gap),
                                 width: M.tile.width, height: M.tile.height)
                ext.addSubview(t)
            }
            for case let t as SiteExtensionTile in tiles { ext.addSubview(t.badge) }
            showPicked()
            let rows = (tiles.count + 3) / 4
            let extH = 27 + CGFloat(rows) * M.tile.height + CGFloat(rows - 1) * M.gap
            ext.frame = NSRect(x: x, y: y, width: w, height: extH)
            addSubview(ext)
            y += extH + 15
        }
        // Boosts: the site's own, on or off.
        let boosts = Boost.onSite(of: url, from: BoostStore.shared.boosts)
        if !boosts.isEmpty, actions.newBoost != nil {
            let section = SiteSectionView(title: "Boosts", hoverText: "Manage", colors: colors, onHeaderClick: actions.manageBoosts)
            for (i, b) in boosts.enumerated() {
                let row = SiteSettingRow(symbol: BoostGlyph.symbol, title: b.name, subtitle: b.enabled ? "Enabled" : "Disabled", active: b.enabled,
                                         colors: colors, action: { [actions] in actions.toggleBoost(b.id) },
                                         accessory: { [actions] in actions.editBoost(b.id) })
                row.frame = NSRect(x: 0, y: 27 + CGFloat(i) * 43, width: 208, height: 33)
                section.addSubview(row)
            }
            let h = 27 + boosts.count * 33 + (boosts.count - 1) * 10
            section.frame = NSRect(x: x, y: y, width: w, height: CGFloat(h))
            addSubview(section)
            y += CGFloat(h) + 15
        }
        // Settings: three switch rows.
        let settings = SiteSectionView(title: "Settings", hoverText: nil, colors: colors, onHeaderClick: {})
        let developer = store.settings.isDeveloperMode(url: url)
        // Per site like Arc (#326); Settings ▸ Tabs keeps the default for the others.
        let autoPiP = store.settings.allowsAutoPictureInPicture(url: url)
        let store = store, url = url
        var rowsSpec: [(String, String, String, Bool, () -> Void)] = [
            ("hammer.fill", "Developer Mode", developer ? "On" : "Off", developer, { store.settings.toggleDeveloperMode(url: url) }),
            ("shield.fill", "Block Ads & Trackers", store.settings.blockAdsAndTrackers ? "On" : "Off",
             store.settings.blockAdsAndTrackers, { store.settings.blockAdsAndTrackers.toggle() }),
            ("gearshape.fill", "Automatic Picture-In-Picture", autoPiP ? "Allowed" : "Disabled",
             autoPiP, { store.settings.toggleAutoPictureInPicture(url: url) }),
        ]
        // Chromium's blocker doesn't see a WebKit page: no switch that does nothing there.
        if protectedMedia != nil { rowsSpec.remove(at: 1) }
        // A page that plays DRM, or one in WebKit: which engine plays this site, or for a mixed
        // site (YouTube) its protected videos or just this one (docs/protected-media.md).
        if let row = safariEngine {
            let press = actions.pressSafariEngine
            rowsSpec.append(("safari", "Safari’s Engine", row.state, row.isOn, { press(row) }))
        }
        for (i, r) in rowsSpec.enumerated() {
            let row = SiteSettingRow(symbol: r.0, title: r.1, subtitle: r.2, active: r.3, colors: colors, action: r.4)
            row.frame = NSRect(x: 0, y: 27 + CGFloat(i) * 43, width: 208, height: 33)
            settings.addSubview(row)
        }
        let setH = 27 + rowsSpec.count * 33 + (rowsSpec.count - 1) * 10
        settings.frame = NSRect(x: x, y: y, width: w, height: CGFloat(setH))
        addSubview(settings)
        y += CGFloat(setH) + 13
        let divider = NSView(frame: NSRect(x: x, y: y, width: w, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = colors.divider.cgColor
        addSubview(divider)
        y += 1 + 12
        // Footer: the connection state, the More menu.
        let secure = SiteSecurityPill(secure: secure, colors: colors, action: actions.showCertificate)
        secure.frame.origin = NSPoint(x: x, y: y)
        addSubview(secure)
        let more = SiteMoreButton(colors: colors, actions: actions)
        more.frame = NSRect(x: x + w - 32, y: y, width: 32, height: 32)
        addSubview(more)
        y += 32 + M.inset
        let size = NSSize(width: M.width, height: y)
        if frame.size != size {
            setFrameSize(size)
            onResize(size)
        }
    }
}

/// Arc's site control center palette (dark values sampled from Arc 1.170; light ones mirror them).
/// `dark` is macOS's appearance, not the space's: like Arc's menus, the popover follows the Mac (#171).
struct SiteControlCenterColors {
    let dark: Bool
    var background: NSColor { dark ? NSColor(hex: "#272728") : NSColor(hex: "#F4F4F5") }
    var tile: NSColor { dark ? .white.withAlphaComponent(0.07) : .black.withAlphaComponent(0.05) }
    var tileHover: NSColor { dark ? .white.withAlphaComponent(0.09) : .black.withAlphaComponent(0.08) }
    var text: NSColor { dark ? NSColor(hex: "#DCDCDC") : NSColor(hex: "#232325") }
    var header: NSColor { dark ? NSColor(hex: "#D4D4D5") : NSColor(hex: "#2A2A2C") }
    var secondary: NSColor { dark ? NSColor(hex: "#979798") : NSColor(hex: "#6E6E73") }
    var divider: NSColor { dark ? .white.withAlphaComponent(0.1) : .black.withAlphaComponent(0.1) }
    var footerFill: NSColor { dark ? NSColor(hex: "#363536") : .black.withAlphaComponent(0.05) }
    var moreFill: NSColor { dark ? NSColor(hex: "#403F40") : .black.withAlphaComponent(0.08) }
    /// Pinned badge and active setting circles.
    /// Light themes invert Arc's dark-theme pair: a near-white badge vanishes on light tiles.
    var accent: NSColor { dark ? NSColor(hex: "#F0F1FE") : NSColor(hex: "#232325") }
    var inactive: NSColor { dark ? NSColor(hex: "#6A6A6F") : NSColor(hex: "#C7C7CC") }
    var pinHover: NSColor { dark ? NSColor(hex: "#7F7E85") : NSColor(hex: "#8E8E93") }
    var glyphOnAccent: NSColor { dark ? NSColor(hex: "#232325") : .white }
    var glyphOnInactive: NSColor { dark ? NSColor(hex: "#232325") : NSColor(hex: "#3A3A3C") }
    /// The pin glyph: cut out of the badge in the panel colour (dark), white on light themes.
    var pinGlyph: NSColor { dark ? background : .white }
    func actionFill(hovered: Bool) -> [NSColor] {
        dark ? [NSColor(hex: hovered ? "#3C3C3C" : "#363636"), NSColor(hex: hovered ? "#272727" : "#212121")]
             : [NSColor(hex: hovered ? "#FFFFFF" : "#FDFDFD"), NSColor(hex: hovered ? "#F2F2F2" : "#EDEDED")]
    }
    var actionHighlight: NSColor { dark ? NSColor(hex: "#69696A") : .white }
    var actionOutline: NSColor { dark ? NSColor(hex: "#141115") : .black.withAlphaComponent(0.14) }
}

/// A view that tracks the pointer and acts on release, the base of the popover's controls.
private class SiteHoverView: NSView {
    var hovered = false { didSet { if hovered != oldValue { refresh(); onHover() } } }
    var onClick: () -> Void = {}
    var onHover: () -> Void = {}

    override var isFlipped: Bool { true }

    func refresh() {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }

    /// VoiceOver's press is a click.
    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }
}

/// A titled section; hovering it shows `hoverText` at the header's right end (Arc: "Manage").
private final class SiteSectionView: SiteHoverView {
    private let manage: NSTextField?
    private let onHeaderClick: () -> Void

    init(title: String, hoverText: String?, colors: SiteControlCenterColors, onHeaderClick: @escaping () -> Void) {
        self.onHeaderClick = onHeaderClick
        manage = hoverText.map { t in
            let l = NSTextField.sidebarLabel(size: 12, weight: .semibold)
            l.stringValue = t
            l.textColor = colors.secondary
            l.alignment = .right
            return l
        }
        super.init(frame: .zero)
        let label = NSTextField.sidebarLabel(size: 14, weight: .bold)
        label.stringValue = title
        label.textColor = colors.header
        label.frame = NSRect(x: -SidebarText.inset, y: 0, width: 200, height: 17)
        addSubview(label)
        if let manage {
            manage.isHidden = true
            addSubview(manage)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func refresh() { manage?.isHidden = !hovered }

    override func layout() {
        super.layout()
        manage?.frame = NSRect(x: bounds.width - 80 + SidebarText.inset, y: 1, width: 80, height: 15)
    }

    override func mouseUp(with event: NSEvent) {
        guard let manage, !manage.isHidden, manage.frame.contains(convert(event.locationInWindow, from: nil)) else { return }
        onHeaderClick()
    }
}

private class SiteTile: SiteHoverView {
    let colors: SiteControlCenterColors
    private let glyph = NSImageView()

    init(colors: SiteControlCenterColors, help: String, action: @escaping () -> Void) {
        self.colors = colors
        super.init(frame: .zero)
        onClick = action
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        glyph.imageScaling = .scaleProportionallyDown
        addSubview(glyph)
        if !help.isEmpty { _ = ArcTooltipAnchorView.attach(to: self, help: help) }
        // A button to VoiceOver, like the popover's other controls.
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(help)
        glyph.setAccessibilityElement(false)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setGlyph(_ image: NSImage?, tint: NSColor?, size: CGFloat? = nil) {
        glyph.image = image
        glyph.contentTintColor = tint
        glyph.imageScaling = size == nil ? .scaleNone : .scaleProportionallyUpOrDown
        glyphSize = size
        needsLayout = true
    }

    private var glyphSize: CGFloat?

    override func refresh() { layer?.backgroundColor = (hovered ? colors.tileHover : colors.tile).cgColor }

    override func layout() {
        super.layout()
        if let s = glyphSize {
            glyph.frame = NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
        } else {
            glyph.frame = bounds
        }
    }
}

/// An extension tile: click runs it, the badge pins or unpins it (Arc's
/// SiteControlCenterExtensionPinButton, "Pin" / "Unpin").
private final class SiteExtensionTile: SiteTile {
    private let pinned: Bool
    private var shownIcon: NSImage??
    /// The 14 pt pin badge hangs off the tile's bottom-right corner, 37 × 21 pt in. It sits
    /// next to the tile in the grid, above it, so nothing clips it (SwiftUI's .offset).
    let badge = SiteHoverView()
    private let pinGlyph = NSImageView()

    init(entry: ExtensionStore.Entry, pinned: Bool, colors: SiteControlCenterColors, run: @escaping () -> Void, togglePin: @escaping () -> Void) {
        self.pinned = pinned
        super.init(colors: colors, help: entry.name, action: run)
        show(icon: entry.icon)
        setAccessibilityLabel(entry.name)
        badge.onClick = togglePin
        badge.onHover = { [weak self] in self?.refresh() }
        pinGlyph.image = Self.badgeImage(fill: pinned ? colors.accent : colors.pinHover, ring: colors.background, glyph: colors.pinGlyph)
        pinGlyph.imageScaling = .scaleNone
        pinGlyph.frame = NSRect(x: 0, y: 0, width: 14, height: 14)
        badge.addSubview(pinGlyph)
        _ = ArcTooltipAnchorView.attach(to: badge, help: pinned ? "Unpin" : "Pin")
        badge.setAccessibilityElement(true)
        badge.setAccessibilityRole(.button)
        badge.setAccessibilityLabel(pinned ? "Unpin" : "Pin")
        pinGlyph.setAccessibilityElement(false)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The extension's icon as it is now, else the puzzle piece.
    func show(icon: NSImage?) {
        guard shownIcon.map({ $0 !== icon }) ?? true else { return }
        shownIcon = .some(icon)
        if let icon {
            setGlyph(icon, tint: nil, size: 16)
        } else {
            setGlyph(SidebarSymbols.image("puzzlepiece.extension.fill", size: 13), tint: colors.secondary)
        }
    }

    /// The badge as one image: the circle, a 1 pt ring in the panel colour inside its edge, and
    /// the pin turned 45° clockwise.
    private static func badgeImage(fill: NSColor, ring: NSColor, glyph: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            fill.setFill()
            NSBezierPath(ovalIn: r).fill()
            ring.setStroke()
            let edge = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            edge.lineWidth = 1
            edge.stroke()
            guard let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .bold).applying(.init(paletteColors: [glyph]))) else { return true }
            let t = NSAffineTransform()
            t.translateX(by: r.midX, yBy: r.midY)
            t.rotate(byDegrees: -45)
            t.concat()
            pin.draw(in: NSRect(x: -pin.size.width / 2, y: -pin.size.height / 2, width: pin.size.width, height: pin.size.height))
            return true
        }
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        badge.frame = NSRect(x: newOrigin.x + 37, y: newOrigin.y + 21, width: 14, height: 14)
    }

    /// Ringed by ⌘E's picker (#709). Arc 1.172: a 2 pt line in the accent colour (the pinned badge's) centred
    /// on the tile's edge, 1 pt outside it and 1 pt in; the tile's fill stays as it is.
    var ringed = false {
        didSet {
            guard ringed != oldValue else { return }
            ring.isHidden = !ringed
            setAccessibilityValue(ringed ? "Selected" : nil)
        }
    }

    private lazy var ring: CALayer = {
        let r = CALayer()
        r.borderWidth = 2
        r.borderColor = colors.accent.cgColor
        r.cornerRadius = 8
        r.cornerCurve = .continuous
        r.isHidden = true
        layer?.addSublayer(r)
        return r
    }()

    override func layout() {
        super.layout()
        ring.frame = bounds.insetBy(dx: -1, dy: -1)
    }

    override func refresh() {
        super.refresh()
        badge.isHidden = !(pinned || hovered || badge.hovered)
    }
}

/// Arc draws these raised: a top-lit gradient, a light top edge and a dark outline.
private final class SiteActionButton: SiteHoverView {
    private let colors: SiteControlCenterColors
    private let fill = CAGradientLayer()
    private let highlight = CAGradientLayer()
    private let highlightMask = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let glyph = NSImageView()

    init(symbol: String, help: String, colors: SiteControlCenterColors, action: @escaping () -> Void) {
        self.colors = colors
        super.init(frame: .zero)
        onClick = action
        wantsLayer = true
        fill.cornerRadius = 7
        fill.cornerCurve = .continuous
        fill.masksToBounds = true
        layer?.addSublayer(fill)
        highlight.colors = [colors.actionHighlight.cgColor, colors.actionHighlight.withAlphaComponent(0).cgColor]
        highlight.locations = [0, 1]
        highlightMask.fillColor = nil
        highlightMask.strokeColor = NSColor.black.cgColor
        highlightMask.lineWidth = 1
        highlight.mask = highlightMask
        layer?.addSublayer(highlight)
        outline.fillColor = nil
        outline.strokeColor = colors.actionOutline.cgColor
        outline.lineWidth = 0.5
        layer?.addSublayer(outline)
        glyph.image = symbol == BoostGlyph.symbol ? BoostGlyph.image(size: 15) : SidebarSymbols.image(symbol, size: 15)
        glyph.contentTintColor = colors.text
        glyph.imageScaling = .scaleNone
        addSubview(glyph)
        _ = ArcTooltipAnchorView.attach(to: self, help: help)
        setAccessibilityElement(true)
        setAccessibilityLabel(help)
        setAccessibilityRole(.button)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.colors = colors.actionFill(hovered: hovered).map(\.cgColor)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        // Flipped: the fill and highlight run from the top (y 0) down.
        fill.startPoint = CGPoint(x: 0.5, y: 0)
        fill.endPoint = CGPoint(x: 0.5, y: 1)
        highlight.frame = bounds
        highlight.startPoint = CGPoint(x: 0.5, y: 0)
        highlight.endPoint = CGPoint(x: 0.5, y: 0.5)
        highlightMask.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 6.5, cornerHeight: 6.5, transform: nil)
        outline.path = CGPath(roundedRect: bounds, cornerWidth: 7, cornerHeight: 7, transform: nil)
        CATransaction.commit()
        glyph.frame = bounds
    }
}

private final class SiteSettingRow: SiteHoverView {
    /// Arc's boost rows: a chevron at the right end on hover, which edits instead of switching.
    private let chevron: NSImageView?
    private let accessory: (() -> Void)?

    init(symbol: String, title: String, subtitle: String, active: Bool, colors: SiteControlCenterColors, action: @escaping () -> Void,
         accessory: (() -> Void)? = nil) {
        self.accessory = accessory
        chevron = accessory.map { _ in
            let v = NSImageView(frame: NSRect(x: 208 - 22, y: 8.5, width: 16, height: 16))
            v.image = SidebarSymbols.image("chevron.right", size: 13, weight: .semibold)
            v.contentTintColor = colors.secondary
            v.imageScaling = .scaleNone
            v.isHidden = true
            return v
        }
        super.init(frame: .zero)
        onClick = action
        wantsLayer = true
        let circle = NSView(frame: NSRect(x: 0, y: 0.5, width: 32, height: 32))
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 16
        circle.layer?.backgroundColor = (active ? colors.accent : colors.inactive).cgColor
        let glyph = NSImageView(frame: circle.bounds)
        glyph.image = symbol == BoostGlyph.symbol ? BoostGlyph.image(size: 13, filled: true) : SidebarSymbols.image(symbol, size: 13, weight: .semibold)
        glyph.contentTintColor = active ? colors.glyphOnAccent : colors.glyphOnInactive
        glyph.imageScaling = .scaleNone
        circle.addSubview(glyph)
        addSubview(circle)
        // VStack(spacing: 0) of 17 + 16, 8 pt after the circle and 8 pt before the Spacer.
        let t = NSTextField.sidebarLabel(size: 14, weight: .semibold)
        t.stringValue = title
        t.textColor = colors.text
        t.frame = NSRect(x: 40 - SidebarText.inset, y: 0, width: 160 + 2 * SidebarText.inset, height: 17)
        addSubview(t)
        let s = NSTextField.sidebarLabel(size: 13)
        s.stringValue = subtitle
        s.textColor = colors.secondary
        s.frame = NSRect(x: 40 - SidebarText.inset, y: 17, width: 160 + 2 * SidebarText.inset, height: 16)
        addSubview(s)
        // One button for VoiceOver, which an NSView isn't unless it says so.
        setAccessibilityElement(true)
        setAccessibilityLabel("\(title), \(subtitle)")
        setAccessibilityRole(.button)
        if let chevron { addSubview(chevron) }
        if let accessory {
            setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Edit") { accessory(); return true }])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func refresh() {
        alphaValue = hovered ? 0.85 : 1
        chevron?.isHidden = !hovered
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let accessory, bounds.contains(p), p.x >= bounds.width - 36 { accessory(); return }
        super.mouseUp(with: event)
    }

    /// The chevron's press, for scenarios.
    func pressAccessory() { accessory?() }
}

/// Arc's Boost glyph (boost.sparkle.fill): a flat brush with a sparkle at its top left.
enum BoostGlyph {
    /// What callers pass for it where a symbol name goes.
    static let symbol = "cra.boost"

    static func image(size: CGFloat, filled: Bool = false) -> NSImage? {
        guard let brush = SidebarSymbols.image(filled ? "paintbrush.fill" : "paintbrush", size: size * 0.92, weight: filled ? .semibold : .regular),
              let spark = SidebarSymbols.image("sparkle", size: size * 0.5, weight: .semibold) else { return nil }
        let w = brush.size.width + spark.size.width * 0.45, h = brush.size.height + spark.size.height * 0.45
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
            brush.draw(in: NSRect(x: w - brush.size.width, y: 0, width: brush.size.width, height: brush.size.height))
            spark.draw(in: NSRect(x: 0, y: h - spark.size.height, width: spark.size.width, height: spark.size.height))
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// A WebKit page's place for the extensions: which engine plays it, and what that means here
/// (docs/protected-media.md). Header like the other sections, a line of text, three facts with
/// their glyphs, then "Learn more".
private final class SiteProtectedMediaCard: NSView {
    init(service: String, width: CGFloat, colors: SiteControlCenterColors, learnMore: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        let header = NSTextField.sidebarLabel(size: 14, weight: .bold)
        header.stringValue = "Protected Media"
        header.textColor = colors.header
        header.frame = NSRect(x: -SidebarText.inset, y: 0, width: width + SidebarText.inset, height: 17)
        addSubview(header)
        var y: CGFloat = 25
        let body = NSTextField(wrappingLabelWithString: "\(service) plays with Safari’s engine, which has the DRM it needs. Here, that means:")
        body.font = .systemFont(ofSize: 13)
        body.textColor = colors.text
        body.isSelectable = false
        body.preferredMaxLayoutWidth = width
        let bodyH = ceil(body.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 400)).height ?? 34)
        body.frame = NSRect(x: 0, y: y, width: width, height: bodyH)
        addSubview(body)
        y += bodyH + 9
        for (symbol, text) in [("person.crop.circle", "You sign in here once"), ("puzzlepiece.extension", "Extensions don’t run here"),
                               ("hammer", "Web Inspector instead of DevTools")] {
            let glyph = NSImageView(frame: NSRect(x: 0, y: y, width: 18, height: 18))
            glyph.image = SidebarSymbols.image(symbol, size: 13, weight: .medium)
            glyph.contentTintColor = colors.secondary
            glyph.imageScaling = .scaleNone
            addSubview(glyph)
            // Wraps rather than truncates: the popover is narrow (236 pt) and the facts must read whole.
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 13)
            label.textColor = colors.text
            label.isSelectable = false
            let textW = width - 26
            let h = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textW, height: 200)).height ?? 16)
            label.frame = NSRect(x: 26, y: y + 1, width: textW, height: h)
            addSubview(label)
            y += max(24, h + 8)
        }
        let link = SiteLinkLabel(text: "Learn more", colors: colors, action: learnMore)
        link.frame = NSRect(x: 0, y: y + 2, width: 90, height: 18)
        addSubview(link)
        y += 22
        setFrameSize(NSSize(width: width, height: y))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Protected Media. \(service) plays with Safari’s engine. You sign in here once, extensions don’t run here, Web Inspector instead of DevTools.")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
}

/// "Learn more": secondary text that turns the text colour under the pointer.
private final class SiteLinkLabel: SiteHoverView {
    private let label = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let colors: SiteControlCenterColors

    init(text: String, colors: SiteControlCenterColors, action: @escaping () -> Void) {
        self.colors = colors
        super.init(frame: .zero)
        onClick = action
        label.stringValue = text
        label.textColor = colors.secondary
        addSubview(label)
        setAccessibilityLabel(text)
        setAccessibilityRole(.link)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: -SidebarText.inset, y: 0, width: bounds.width + 2 * SidebarText.inset, height: bounds.height)
    }

    override func refresh() { label.textColor = hovered ? colors.text : colors.secondary }
}

/// Pressed, it shows the page's certificate (Arc closes the control center and opens it).
private final class SiteSecurityPill: SiteHoverView {
    private let colors: SiteControlCenterColors
    private let clickable: Bool

    init(secure: Bool, colors: SiteControlCenterColors, action: (() -> Void)?) {
        self.colors = colors
        clickable = action != nil
        super.init(frame: .zero)
        if let action { onClick = action }
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = colors.footerFill.cgColor
        let lock = NSImageView()
        lock.image = SidebarSymbols.image(secure ? "lock.fill" : "lock.open.fill", size: 12, weight: .semibold)
        lock.contentTintColor = colors.text
        lock.imageScaling = .scaleNone
        let label = NSTextField.sidebarLabel(size: 14, weight: .semibold)
        label.stringValue = secure ? "Secure" : "Not Secure"
        label.textColor = colors.text
        let lw = lock.image?.size.width ?? 10
        let tw = ceil(label.attributedStringValue.size().width)
        setFrameSize(NSSize(width: 10 + lw + 6 + tw + 10, height: 32))
        lock.frame = NSRect(x: 10, y: 0, width: lw, height: 32)
        label.frame = NSRect(x: 10 + lw + 6 - SidebarText.inset, y: (32 - 17) / 2, width: tw + 2 * SidebarText.inset, height: 17)
        addSubview(lock)
        addSubview(label)
        _ = ArcTooltipAnchorView.attach(to: self, help: secure ? "Your connection to this site is secure" : "Your connection to this site is not secure")
        setAccessibilityElement(true)
        setAccessibilityLabel(secure ? "Secure" : "Not Secure")
        setAccessibilityRole(clickable ? .button : .staticText)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func refresh() {
        // The More button's hover: SwiftUI's .brightness(0.04).
        let c = colors.footerFill.usingColorSpace(.sRGB) ?? colors.footerFill
        layer?.backgroundColor = (hovered && clickable ? NSColor(srgbRed: min(1, c.redComponent + 0.04), green: min(1, c.greenComponent + 0.04),
                                                                  blue: min(1, c.blueComponent + 0.04), alpha: c.alphaComponent) : c).cgColor
    }
}

/// Arc's footer "…": Clear Cache, Clear Cookies, Manage Extensions, Add Extension, All Site Settings.
private final class SiteMoreButton: SiteHoverView {
    private let colors: SiteControlCenterColors

    init(colors: SiteControlCenterColors, actions: SiteControlCenterActions) {
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        let glyph = NSImageView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        glyph.image = SidebarSymbols.image("ellipsis", size: 13, weight: .bold)
        glyph.contentTintColor = colors.text
        glyph.imageScaling = .scaleNone
        addSubview(glyph)
        _ = ArcTooltipAnchorView.attach(to: self, help: "More")
        setAccessibilityLabel("More")
        setAccessibilityRole(.button)
        onClick = {
            let menu = NSMenu()
            func add(_ title: String, _ action: @escaping () -> Void) { menu.addItem(BlockMenuItem(title: title, action: action)) }
            add("Clear Cache", actions.clearCache)
            add("Clear Cookies", actions.clearCookies)
            menu.addItem(.separator())
            // Arc 1.172.2's order.
            add("Manage Boosts…", actions.manageBoosts)
            let newBoost = BlockMenuItem(title: "New Boost…", action: { actions.newBoost?() })
            newBoost.isEnabled = actions.newBoost != nil
            menu.autoenablesItems = false
            menu.addItem(newBoost)
            menu.addItem(.separator())
            add("Manage Extensions…", actions.manageExtensions)
            add("Add Extension…", actions.addExtension)
            menu.addItem(.separator())
            add("All Site Settings", actions.siteSettings)
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func refresh() {
        // SwiftUI's .brightness(0.04) on hover.
        let c = colors.moreFill.usingColorSpace(.sRGB) ?? colors.moreFill
        layer?.backgroundColor = (hovered ? NSColor(srgbRed: min(1, c.redComponent + 0.04), green: min(1, c.greenComponent + 0.04),
                                                    blue: min(1, c.blueComponent + 0.04), alpha: c.alphaComponent) : c).cgColor
    }
}

final class BlockMenuItem: NSMenuItem {
    private let block: () -> Void
    init(title: String, action: @escaping () -> Void) {
        block = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { block() }
}

/// Shows the Site Control Center in an NSPopover under a toolbar or pill button.
@MainActor
final class SiteControlCenterPopover: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    /// When the mouse-down that closed the popover from outside happened (event time).
    private var closingClick: TimeInterval?

    var isShown: Bool { popover?.isShown == true }

    /// The sliders button pressed while the popover is up, or by the click that just closed it:
    /// it closes (and stays closed) instead of opening again. Asked before anything slower than
    /// the click itself (the page's DRM question), while the click is still the current event.
    func closesInstead() -> Bool {
        // A transient popover closes on the mouse-down outside it; the button fires on that
        // click's mouse-up. The same click on the sliders button closes it, as in Arc,
        // however long the press took (GitHub #42): the latest mouse-down is the closing one.
        let closedByThisClick = closingClick.map { t in
            NSApp.currentEvent?.type == .leftMouseUp
                && abs(ProcessInfo.processInfo.systemUptime - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown) - t) < 0.05
        } ?? false
        closingClick = nil
        if let popover, popover.isShown { popover.performClose(nil); return true }
        return closedByThisClick
    }

    func show(relativeTo rect: NSRect, of view: NSView, url: String, secure: Bool, dark: Bool, profile: String, incognito: Bool = false, tab: UUID?,
              protectedMedia: String? = nil, safariEngine: SafariEngineRow? = nil, toggleChecked: Bool = false,
              store: SidebarStore, actions: SiteControlCenterActions) {
        if !toggleChecked, closesInstead() { endPicking(); return }
        if let popover, popover.isShown { replacing = true; popover.performClose(nil); replacing = false }
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        p.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var acts = actions
        // Every action ends the popover, as in Arc (pinning keeps it open, and the share list
        // opens over it).
        func closing(_ f: @escaping () -> Void) -> () -> Void { { [weak p] in p?.performClose(nil); f() } }
        acts.copyURL = closing(actions.copyURL)
        acts.capture = closing(actions.capture)
        acts.captureFullPage = closing(actions.captureFullPage)
        acts.runExtension = { [weak p] id in p?.performClose(nil); actions.runExtension(id) }
        acts.addExtension = closing(actions.addExtension)
        acts.manageExtensions = closing(actions.manageExtensions)
        acts.siteSettings = closing(actions.siteSettings)
        acts.clearCache = closing(actions.clearCache)
        acts.clearCookies = closing(actions.clearCookies)
        acts.showCertificate = actions.showCertificate.map(closing)
        acts.learnAboutProtectedMedia = closing(actions.learnAboutProtectedMedia)
        // The page opens again in the other engine: the popover's content would be the old page's.
        acts.pressSafariEngine = { [weak p] row in p?.performClose(nil); actions.pressSafariEngine(row) }
        acts.newBoost = actions.newBoost.map(closing)
        acts.editBoost = { [weak p] id in p?.performClose(nil); actions.editBoost(id) }
        acts.manageBoosts = closing(actions.manageBoosts)
        let content = SiteControlCenterView(url: url, secure: secure, dark: dark, profile: profile, incognito: incognito, tab: tab, protectedMedia: protectedMedia,
                                            safariEngine: safariEngine, actions: acts, store: store)
        let host = NSViewController()
        host.view = content
        host.preferredContentSize = content.frame.size
        content.onResize = { [weak host] in host?.preferredContentSize = $0 }
        p.contentViewController = host
        popover = p
        p.show(relativeTo: rect, of: view, preferredEdge: .minY)
        showPicked()
        if letGoBeforeShown { letGo() }
    }

    /// An old popover closing for a new one: a picker started for the new one goes on.
    private var replacing = false

    func close() { popover?.performClose(nil) }

    // MARK: ⌘E's picker (#709)

    private var picker: ExtensionPicker?
    private var pickerMonitors: [Any] = []
    /// ⌘ was let go before the popover was up (it waits up to 0.3 s on the page): it runs once it is.
    private var letGoBeforeShown = false

    var isPicking: Bool { picker != nil }

    private var content: SiteControlCenterView? { popover?.contentViewController?.view as? SiteControlCenterView }

    /// Rings the first extension and follows the keyboard: `isPickerKey` (the Open Extensions shortcut) rings the
    /// next one, letting go of ⌘ runs the ringed one, Esc closes. The popover is up or about to be.
    func startPicking(isPickerKey: @escaping (NSEvent) -> Bool) {
        endPicking()
        picker = ExtensionPicker()
        letGoBeforeShown = false
        showPicked()
        pickerMonitors = [
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.picker != nil else { return event }
                    if event.keyCode == 53 { self.endPicking(); self.close(); return nil }
                    guard isPickerKey(event) else { return event }
                    self.step()
                    return nil
                }
            },
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                MainActor.assumeIsolated {
                    if !event.modifierFlags.contains(.command) { self?.letGo() }
                    return event
                }
            },
        ].compactMap { $0 }
    }

    /// The shortcut again, ⌘ still held: the next extension.
    func step() {
        picker?.press()
        showPicked()
    }

    private func showPicked() {
        guard let picker, let content else { return }
        content.picked = picker.picked(among: content.extensionCount)
    }

    private func letGo() {
        guard picker != nil else { return }
        guard let content, popover?.isShown == true else {
            // Shown within the page's 0.3 s, it runs then; a popover that never came (no window) ends the picker.
            letGoBeforeShown = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.letGoBeforeShown, self.popover?.isShown != true else { return }
                self.endPicking()
            }
            return
        }
        endPicking()
        // Nothing ringed (no extensions): the Site Control Center stays up, as opened by its button.
        let name = content.pickedName
        if content.runPicked() { CraLog.note("extension picker: runs \(name ?? "?")") } else { content.picked = nil }
    }

    private func endPicking() {
        pickerMonitors.forEach(NSEvent.removeMonitor)
        pickerMonitors = []
        picker = nil
        letGoBeforeShown = false
    }

    /// cra://debug?siteControlsRead=1 (#478): "site controls: actions=Share|New Boost|… boosts=My Boost, Enabled|…".
    func debugRead(label: String = "1") {
        guard let root = popover?.contentViewController?.view, popover?.isShown == true else { return CraLog.note("site controls: closed") }
        var actions: [String] = [], rows: [String] = []
        func walk(_ v: NSView) {
            if v is SiteActionButton { actions.append(v.accessibilityLabel() ?? "") }
            if v is SiteSettingRow, v.accessibilityCustomActions()?.isEmpty == false { rows.append(v.accessibilityLabel() ?? "") }
            v.subviews.forEach(walk)
        }
        walk(root)
        CraLog.note("site controls: actions=\(actions.joined(separator: "|")) boosts=\(rows.joined(separator: "|"))")
        // The extension ⌘E's picker rings (#709), under the read's label.
        CraLog.note("site controls picked \(label): \((root as? SiteControlCenterView)?.pickedName ?? "none")")
        // The Settings rows, each "title, state" ("Safari’s Engine, This Video").
        var settings: [String] = []
        func rowsOf(_ v: NSView) {
            if v is SiteSettingRow, v.accessibilityCustomActions()?.isEmpty != false { settings.append(v.accessibilityLabel() ?? "") }
            v.subviews.forEach(rowsOf)
        }
        rowsOf(root)
        CraLog.note("site controls settings: \(settings.joined(separator: "|"))")
    }

    /// cra://debug?siteControlsPress=<label>[&accessory=1] (#478): the button or row with that
    /// accessibility label (a row's chevron with `accessory`) pressed as a click would.
    func debugPress(_ label: String, accessory: Bool) {
        guard let root = popover?.contentViewController?.view else { return CraLog.note("site controls press: closed") }
        func find(_ v: NSView) -> NSView? {
            // An extension's tile by its name too (#531).
            if (v is SiteActionButton || v is SiteSettingRow || v is SiteExtensionTile), v.accessibilityLabel() == label { return v }
            for s in v.subviews { if let f = find(s) { return f } }
            return nil
        }
        guard let v = find(root) else { return CraLog.note("site controls press: no \(label)") }
        if accessory, let row = v as? SiteSettingRow { row.pressAccessory() } else { _ = v.accessibilityPerformPress() }
        CraLog.note("site controls pressed \(label)")
    }

    /// While the share list is up the popover only closes when Cra closes it: a transient one
    /// can go when a menu opens over it.
    func holdOpen(_ hold: Bool) { popover?.behavior = hold ? .applicationDefined : .transient }

    func popoverWillClose(_ notification: Notification) {
        if let e = NSApp.currentEvent, e.type == .leftMouseDown { closingClick = e.timestamp }
    }

    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === popover else { return }
        popover = nil
        if !replacing { endPicking() }
    }
}

/// The Site Control Center's share list (GitHub #90). macOS finds the share extensions the
/// first time a process asks, about 0.3 s on the main thread, so that happens once off it
/// soon after launch. The list keeps the system's own services, as Arc's shorter one does.
@MainActor
final class SharePicker: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    static let shared = SharePicker()
    private static let kept: [NSSharingService.Name] = [
        .composeMessage, .composeEmail, .sendViaAirDrop, .init("com.apple.Notes.SharingExtension"),
        .init("com.apple.reminders.sharingextension"),
    ]
    private var picker: NSSharingServicePicker?
    private var done: (_ chose: Bool) -> Void = { _ in }

    nonisolated static func warmUp() {
        DispatchQueue.global(qos: .utility).async {
            // Deprecated, but the only call that finds them without showing a menu.
            _ = NSSharingService.sharingServices(forItems: [URL(string: "https://example.com")!])
        }
    }

    /// Arc's Share ▸ submenu on a sidebar tab: the same services, as menu items.
    static func addMenu(to menu: NSMenu, url: URL) {
        let sub = NSMenu()
        for name in kept {
            guard let service = NSSharingService(named: name), service.canPerform(withItems: [url]) else { continue }
            let item = MenuItems.add(sub, service.title, image: service.image) { service.perform(withItems: [url]) }
            item.image?.size = NSSize(width: 16, height: 16)
        }
        guard !sub.items.isEmpty else { return }
        let share = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
        share.submenu = sub
        menu.addItem(share)
    }

    /// `done` runs when the list goes, `chose` when a service was picked.
    func show(_ url: URL, relativeTo anchor: NSView, done: @escaping (_ chose: Bool) -> Void) {
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = self
        self.picker = picker
        self.done = done
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any],
                              proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
        // NSSharingService has no public name: match the titles of the named services.
        let titles = Set(Self.kept.compactMap { NSSharingService(named: $0)?.title })
        let kept = proposedServices.filter { titles.contains($0.title) }
        return kept.isEmpty ? proposedServices : kept
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard sharingServicePicker === picker else { return }
        picker = nil
        done(service != nil)
    }
}
