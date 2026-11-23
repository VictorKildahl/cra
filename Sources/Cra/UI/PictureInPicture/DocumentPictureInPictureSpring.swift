import AppKit
import QuartzCore

/// Document Picture in Picture windows (Google Meet's call window, any site's
/// `documentPictureInPicture.requestWindow`) let go past the screen's edge slide back on screen, 10 pt
/// in, as Arc's Document PiP does (#702).
///
/// The window is Chromium's own (TYPE_FLOATING), moved by the system when its top bar is dragged, so
/// Cra hears only that it moved. A move with the left button held starts a drag
/// (`DocumentPictureInPictureDrag`); once the button is up, a window partly off screen goes the
/// shortest way back onto its display on the video PiP's spring (`PictureInPictureFlight`), at its own size.
@MainActor
final class DocumentPictureInPictureSpring {
    static let shared = DocumentPictureInPictureSpring()

    private var observer: NSObjectProtocol?
    private var drags: [ObjectIdentifier: DocumentPictureInPictureDrag] = [:]
    private var release: Timer?
    private var flights: [ObjectIdentifier: (window: NSWindow, flight: PictureInPictureFlight, link: CADisplayLink)] = [:]
    private var lastTick: [ObjectIdentifier: CFTimeInterval] = [:]

    private init() {}

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { DocumentPictureInPictureSpring.shared.moved(window, buttonDown: NSEvent.pressedMouseButtons & 1 != 0) }
        }
    }

    static func isDocumentWindow(_ window: NSWindow) -> Bool {
        DocumentPictureInPictureDrag.isDocumentWindow(className: NSStringFromClass(type(of: window)), floating: window.level == .floating,
                                                      hasParent: window.parent != nil,
                                                      isVideo: PictureInPictureChrome.shared.isVideoWindow(window))
    }

    /// The Document PiP windows on screen.
    static func windows() -> [NSWindow] { NSApp.windows.filter { $0.isVisible && isDocumentWindow($0) } }

    func moved(_ window: NSWindow, buttonDown: Bool) {
        let id = ObjectIdentifier(window)
        guard flights[id] == nil, Self.isDocumentWindow(window) else { return }
        var drag = drags[id] ?? DocumentPictureInPictureDrag()
        drag.moved(buttonDown: buttonDown)
        drags[id] = drag
        guard drag.isDragging, release == nil else { return }
        // The system drags the window and keeps the mouse-up to itself: watch the button.
        release = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                DocumentPictureInPictureSpring.shared.letGo()
            }
        }
    }

    /// The button came up: every window dragged since slides back on screen, or stays where it was let go.
    func letGo() {
        release?.invalidate()
        release = nil
        let displays = NSScreen.screens.map(PictureInPictureChrome.display)
        let shown = Self.windows()
        drags = drags.filter { id, _ in shown.contains { ObjectIdentifier($0) == id } }
        for window in shown {
            let id = ObjectIdentifier(window)
            guard var drag = drags[id] else { continue }
            let end = drag.released(frame: window.frame, displays: displays)
            drags[id] = drag
            guard let end else { continue }
            CraLog.note("pip: document window let go past the edge, back to \(Int(end.minX)),\(Int(end.minY))")
            fly(window, to: end.origin)
        }
    }

    private func fly(_ window: NSWindow, to origin: NSPoint) {
        let id = ObjectIdentifier(window)
        flights[id]?.link.invalidate()
        let link = window.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        flights[id] = (window, PictureInPictureFlight(from: window.frame.origin, velocity: .zero, to: origin), link)
        lastTick[id] = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let found = flights.first(where: { $0.value.link === link }) else { return link.invalidate() }
        let id = found.key, entry = found.value
        guard entry.window.isVisible else {
            link.invalidate()
            flights[id] = nil
            return
        }
        let last = lastTick[id] ?? 0
        let dt = last == 0 ? link.targetTimestamp - link.timestamp : link.timestamp - last
        lastTick[id] = link.timestamp
        var flight = entry.flight
        entry.window.setFrameOrigin(flight.step(max(dt, 1.0 / 240)))
        flights[id]?.flight = flight
        if flight.isSettled {
            link.invalidate()
            flights[id] = nil
            lastTick[id] = nil
        }
    }

    /// `cra://debug?docPip=<label>`: the Document PiP windows and whether each is wholly on screen.
    func readout() -> String {
        let shown = Self.windows()
        let displays = NSScreen.screens.map(PictureInPictureChrome.display)
        return "windows=\(shown.count)" + shown.map { w in
            " frame=\(Int(w.frame.minX)),\(Int(w.frame.minY)),\(Int(w.frame.width)),\(Int(w.frame.height)) onScreen=\(PictureInPictureLayout.landing(afterDropping: w.frame, displays: displays) == nil ? 1 : 0)"
        }.joined()
    }

    /// `cra://debug?docPipDrop=left|right|bottom`: the first Document PiP window let go half past that
    /// edge of its screen, as a mouse drag of its top bar does: moved with the button down, then let go.
    func debugDrop(_ edge: String) {
        guard let window = Self.windows().first, let screen = window.screen ?? NSScreen.main else { return }
        let f = window.frame, s = screen.frame
        let origin: NSPoint = switch edge {
        case "right": NSPoint(x: s.maxX - f.width / 2, y: f.minY)
        case "bottom": NSPoint(x: f.minX, y: s.minY - f.height / 2)
        default: NSPoint(x: s.minX - f.width / 2, y: f.minY)
        }
        window.setFrameOrigin(origin)
        moved(window, buttonDown: true)
        CraLog.note("pip: document window let go at \(Int(window.frame.minX)),\(Int(window.frame.minY))")
        letGo()
    }
}
