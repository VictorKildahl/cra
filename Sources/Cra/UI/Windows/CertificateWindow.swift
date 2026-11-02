import AppKit
import SecurityInterface

/// The Site Control Center's lock (GitHub #90): the page's certificate chain in macOS's
/// certificate sheet, trust evaluated for the host, as Arc opens Chromium's viewer from it.
/// Like Chrome's SSLCertificateViewerMac, the sheet hangs off a clear window laid over the
/// browser window, so the page's own child windows can't cover it.
@MainActor
final class CertificateWindow: NSObject {
    private static var current: CertificateWindow?
    private let overlay: NSWindow

    /// `certificates`: DER, the server's first, then its issuers.
    static func show(_ certificates: [Data], host: String, over window: NSWindow) {
        let chain = certificates.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        var trust: SecTrust?
        guard current == nil, !chain.isEmpty,
              SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateSSL(true, host as CFString), &trust) == errSecSuccess,
              let trust else { return }
        // Only what Chromium already fetched; no revocation or issuer requests from here.
        SecTrustSetNetworkFetchAllowed(trust, false)
        let viewer = CertificateWindow(over: window)
        current = viewer
        SFCertificatePanel.shared().beginSheet(for: viewer.overlay, modalDelegate: viewer,
                                               didEnd: #selector(sheetDidEnd(_:returnCode:contextInfo:)), contextInfo: nil,
                                               trust: trust, showGroup: true)
    }

    private init(over window: NSWindow) {
        overlay = NSWindow(contentRect: window.frame, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.isReleasedWhenClosed = false
        super.init()
        window.addChildWindow(overlay, ordered: .above)
    }

    @objc private func sheetDidEnd(_ sheet: NSWindow, returnCode: Int, contextInfo: UnsafeMutableRawPointer?) {
        overlay.parent?.removeChildWindow(overlay)
        overlay.orderOut(nil)
        Self.current = nil
    }
}
