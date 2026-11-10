import AppKit

extension LittleWindowController {
    var canCapturePage: Bool { isPeek && !isParked && !closingPeek && window?.isVisible == true }

    func handleCapture(action id: String) -> Bool {
        guard id == "capturePage" else { return false }
        if isPeek { peekParent?.capturePage(in: self) }
        return true
    }
}
