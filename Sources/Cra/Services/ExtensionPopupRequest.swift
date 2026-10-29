import Foundation

/// URL matching finds candidates only. A normal extension tab can have the same URL
/// and DevTools type as a popup, so closing still requires the view-type self-check.
struct ExtensionPopupRequest {
    let extensionID: String
    let popupPath: String
    let existingTargets: Set<String>

    func matches(_ info: [String: Any]) -> Bool {
        guard let target = info["targetId"] as? String, !existingTargets.contains(target),
              let type = info["type"] as? String, type == "page" || type == "other",
              let url = (info["url"] as? String).flatMap(URL.init(string:)),
              url.scheme == "chrome-extension", url.host == extensionID else { return false }
        return url.path == "/" + popupPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Evaluated only in the matching target. This never enumerates vault data or closes
    /// a guessed native window: the target closes itself only if Chrome calls it a popup.
    static func closeExpression(extensionID: String) -> String {
        let id = String(decoding: try! JSONSerialization.data(withJSONObject: [extensionID]), as: UTF8.self)
        return """
        (() => { try {
          if (location.protocol !== 'chrome-extension:' || location.hostname !== \(id)[0]) return false;
          const views = globalThis.chrome?.extension?.getViews?.({type: 'popup'});
          if (!Array.isArray(views) || !views.includes(window)) return false;
          window.close();
          return true;
        } catch { return false; } })()
        """
    }
}
