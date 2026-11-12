import AppKit
import CraCEF
import ImageIO

/// A capture shown live (Arc's WebCardState.live: "See an up-to-date, interactive view of whatever
/// you've captured. This does not work on all sites."). The page runs windowless (an agent page,
/// as MCP's), laid out at the size it was captured at and scrolled where it was; the card shows
/// the captured part of it, taken again every second while the easel is on screen. A click on the
/// card reaches the page there; a link opens in a tab, as Arc's DisableInlineLinks does.
@MainActor
final class EaselLivePage {
    private var browser: CraBrowser?
    private let capture: Easel.Capture
    private var timer: Timer?
    private var started = Date()
    private var prepared = false
    private var inFlight = false
    /// Each new picture of the captured area.
    var onFrame: (NSImage) -> Void = { _ in }
    /// The page failed to load or never drew: the card goes back to the screenshot.
    var onFail: () -> Void = {}

    /// How often the card is redrawn from the page.
    static let interval: TimeInterval = 1
    static let giveUp: TimeInterval = 30

    init?(capture: Easel.Capture, profilePath: String?) {
        guard capture.canGoLive, Easel.webAddress(capture.url) != nil else { return nil }
        self.capture = capture
        browser = CraBrowser(agentURL: capture.url, profilePath: profilePath)
        browser?.setAudioMuted(true)
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let b = browser else { return }
        if !prepared {
            if Date().timeIntervalSince(started) > Self.giveUp { fail(); return }
            guard b.isCreated, b.hasCommittedLoad, !b.isLoading else { return }
            prepare(b)
            return
        }
        guard !inFlight else { return }
        inFlight = true
        shoot(b)
    }

    /// The captured viewport, and the captured scroll position.
    private func prepare(_ b: CraBrowser) {
        prepared = true
        timer?.invalidate()
        guard let vp = capture.viewport else { fail(); return }
        let metrics: [String: Any] = ["width": Int(vp.width), "height": Int(vp.height), "deviceScaleFactor": 2, "mobile": false]
        b.sendDevToolsMethod("Emulation.setDeviceMetricsOverride", params: Self.json(metrics)) { _, _ in }
        let s = capture.scroll ?? Easel.Point(0, 0)
        // Arc's live card doesn't scroll (its EaselWebCardView disables wheel and arrow keys).
        let script = """
        window.scrollTo(\(s.x), \(s.y));
        addEventListener('wheel', e => e.preventDefault(), {passive: false, capture: true});
        addEventListener('keydown', e => { if ([32, 33, 34, 35, 36, 37, 38, 39, 40].includes(e.keyCode)) e.preventDefault(); }, true);
        """
        b.sendDevToolsMethod("Runtime.evaluate", params: Self.json(["expression": script])) { _, _ in }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func shoot(_ b: CraBrowser) {
        guard let area = capture.area else { return }
        let s = capture.scroll ?? Easel.Point(0, 0)
        let clip: [String: Any] = ["x": s.x + area.x, "y": s.y + area.y, "width": area.width, "height": area.height, "scale": 1]
        let previous = last
        b.sendDevToolsMethod("Page.captureScreenshot", params: Self.json(["format": "png", "optimizeForSpeed": true, "clip": clip])) { [weak self] result, _ in
            // Decoding a page-sized PNG takes tens of milliseconds: off the main thread, and only
            // when the page looks different from last time.
            Self.decoder.async {
                let data = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                    .flatMap { $0["data"] as? String }.flatMap { Data(base64Encoded: $0) }
                let digest = data.map { $0.hashValue }
                let image = data.flatMap { d in digest == previous ? nil : Self.decoded(d) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.inFlight = false
                    guard let image, let digest else { return }
                    self.last = digest
                    let picture = NSImage(cgImage: image, size: NSSize(width: area.width, height: area.height))
                    self.onFrame(picture)
                }
            }
        }
    }

    private nonisolated static let decoder = DispatchQueue(label: "dk.kildahl.cra.easel-live", qos: .utility)
    /// The last picture's hash: the same picture again isn't decoded or drawn.
    private var last: Int?

    /// A PNG's pixels, drawn once so the card's redraw doesn't decode them.
    private nonisolated static func decoded(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return image
    }

    /// A click on the card at `p` (a point in the captured area): a link opens through `open`,
    /// anything else gets the click.
    func click(at p: Easel.Point, open: @escaping (String) -> Void) {
        guard let b = browser, prepared, let area = capture.area else { return }
        let x = p.x + area.x, y = p.y + area.y
        let probe = "(() => { const a = document.elementFromPoint(\(x), \(y))?.closest('a[href]'); return a ? a.href : ''; })()"
        b.sendDevToolsMethod("Runtime.evaluate", params: Self.json(["expression": probe, "returnByValue": true])) { [weak self] result, _ in
            let href = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                .flatMap { ($0["result"] as? [String: Any])?["value"] as? String } ?? ""
            DispatchQueue.main.async {
                if let url = Easel.webAddress(href) { open(url); return }
                self?.press(x: x, y: y)
            }
        }
    }

    private func press(x: Double, y: Double) {
        for type in ["mousePressed", "mouseReleased"] {
            let e: [String: Any] = ["type": type, "x": x, "y": y, "button": "left", "clickCount": 1]
            browser?.sendDevToolsMethod("Input.dispatchMouseEvent", params: Self.json(e)) { _, _ in }
        }
    }

    private func fail() {
        close()
        onFail()
    }

    func close() {
        timer?.invalidate()
        timer = nil
        browser?.close()
        browser = nil
    }

    private static func json(_ o: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
