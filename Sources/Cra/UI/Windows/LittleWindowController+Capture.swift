import AppKit

extension LittleWindowController {
    var canCapturePage: Bool { !isCard && hasPage && !isParked && !closingPeek && window?.isVisible == true }

    /// The browser window hosting Capture for this window: a Peek's parent, or a Little Window's host.
    var captureOwner: MainWindowController? { isPeek ? peekParent : captureHost }

    func handleCapture(action id: String) -> Bool {
        guard id == "capturePage" else { return false }
        if let open = activeCaptureHost, open.hasCapture(in: self) {
            open.capturePage(in: self)
            return true
        }
        guard let owner = captureOwner else { return true }
        if let previous = activeCaptureHost, previous !== owner { previous.closeCapture(in: self) }
        activeCaptureHost = owner
        owner.capturePage(in: self)
        return true
    }

    func captureImage(at point: NSPoint) {
        guard let owner = captureOwner else { return }
        if let previous = activeCaptureHost, previous !== owner { previous.closeCapture(in: self) }
        activeCaptureHost = owner
        owner.capturePage(liftImageAt: point, in: self)
    }

    func closeCapture() {
        activeCaptureHost?.closeCapture(in: self)
        activeCaptureHost = nil
        captureOwner?.closeCapture(in: self)
    }
}
