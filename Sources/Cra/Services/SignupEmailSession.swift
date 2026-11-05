import AppKit
import CraCEF

/// One offer per window. Switching the focused tab moves the opt-in renderer binding with it.
@MainActor
final class SignupEmailSession: NSObject {
    private struct Field: Decodable {
        let token, url, hints: String
        let signup: Bool
        let x, y, width, height, viewportWidth, viewportHeight: CGFloat

        func rect(in view: NSView) -> NSRect? {
            guard viewportWidth > 0, viewportHeight > 0, width > 0, height > 0 else { return nil }
            let bounds = view.bounds
            let scaleX = bounds.width / viewportWidth, scaleY = bounds.height / viewportHeight
            let rect = NSRect(x: bounds.minX + x * scaleX,
                              y: view.isFlipped ? bounds.minY + y * scaleY : bounds.maxY - (y + height) * scaleY,
                              width: width * scaleX, height: height * scaleY)
            let visible = rect.intersection(view.visibleRect)
            return visible.isEmpty ? nil : visible
        }

        func matches(_ address: String) -> Bool {
            guard let origin = URLComponents(string: url), let current = URLComponents(string: address),
                  let host = current.host?.lowercased(), origin.host?.lowercased() == host,
                  let scheme = current.scheme, scheme == origin.scheme,
                  scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host))
            else { return false }
            let defaultPort = scheme == "https" ? 443 : 80
            return (origin.port ?? defaultPort) == (current.port ?? defaultPort)
        }
    }

    private weak var active: CraBrowser?
    private var address: String?
    private var token: String?
    private var selection = false
    private var classify: Task<Void, Never>?
    private var suggestion: SignupEmailSuggestion?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPreference),
                                               name: SignupEmailPreferences.didChange, object: nil)
    }

    func activate(_ browser: CraBrowser?) {
        guard browser !== active else { return }
        active?.signupEmailEnabled = false
        active = browser
        refreshPreference()
    }

    @objc private func refreshPreference() {
        dismiss()
        guard let browser = active, !browser.isIncognito, PageEngines.engine(of: browser) == .chromium else {
            address = nil
            return
        }
        address = SignupEmailPreferences.address(profilePath: browser.profilePath)
        browser.signupEmailEnabled = address != nil
    }

    func dismiss() {
        classify?.cancel()
        classify = nil
        token = nil
        selection = false
        suggestion?.dismiss()
    }

    func changed(_ json: String?, in browser: CraBrowser) {
        guard browser === active else { return }
        dismiss()
        guard let address, let json, json.utf8.count <= 8192,
              let field = try? JSONDecoder().decode(Field.self, from: Data(json.utf8)),
              field.signup, !field.token.isEmpty, field.matches(browser.currentURL) else { return }
        token = field.token
        classify = Task { [weak self, weak browser] in
            guard await SignupEmailClassifier.isEmail(hints: field.hints, signup: field.signup),
                  !Task.isCancelled, let self, let browser, self.active === browser, self.token == field.token else { return }
            Self.call("signupMatches", [field.token], in: browser) { [weak self, weak browser] matches in
                guard matches, let self, let browser, self.active === browser, self.token == field.token,
                      field.matches(browser.currentURL) else { return }
                self.show(field, address: address, in: browser)
            }
        }
    }

    private func show(_ field: Field, address: String, in browser: CraBrowser) {
        let view = browser.hostWindow.flatMap { EmbeddedPages.pageViews(of: $0)?.last } ?? browser.containerView
        guard let window = view.window, window.isVisible, NSApp.isActive,
              window.isKeyWindow || window.parent?.isKeyWindow == true,
              !view.isHiddenOrHasHiddenAncestor, let rect = field.rect(in: view) else { return }

        let fill = { [weak self, weak browser] in
            guard let self, let browser, self.active === browser, self.token == field.token,
                  field.matches(browser.currentURL), self.address == address else { return }
            self.dismiss()
            // The isolated world checks the token, focus and current empty input again.
            Self.call("signupFill", [field.token, address], in: browser) { _ in }
        }
        let panel = suggestion ?? SignupEmailSuggestion()
        suggestion = panel
        panel.show(address: address, fieldRect: rect, in: view, accept: fill)
    }

    /// Address and token are always data arguments inside the isolated world.
    private static func call(_ function: String, _ arguments: [String], in browser: CraBrowser,
                             completion: @escaping (Bool) -> Void) {
        guard let args = try? JSONEncoder().encode(arguments), let values = String(data: args, encoding: .utf8),
              let data = try? JSONSerialization.data(withJSONObject: [
                "expression": "window.__cra?.\(function)(...\(values))", "returnByValue": true
              ]), let params = String(data: data, encoding: .utf8) else { completion(false); return }
        browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { result, _ in
            let json = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            completion((json?["result"] as? [String: Any])?["value"] as? Bool == true)
        }
    }

    func key(_ event: NSEvent, in browser: CraBrowser) -> Bool {
        guard active === browser, let suggestion, suggestion.isVisible,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        switch event.keyCode {
        case 125: // Down selects the offer. Plain Return and Tab keep the page's usual behavior.
            selection = true
            suggestion.setSelected(true)
        case 126 where selection:
            selection = false
            suggestion.setSelected(false)
        case 36 where selection, 76 where selection:
            return suggestion.acceptIfShown()
        case 53:
            if let token { Self.call("signupDismiss", [token], in: browser) { _ in } }
            dismiss()
        default:
            return false
        }
        return true
    }
}
