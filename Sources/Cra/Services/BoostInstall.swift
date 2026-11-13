import AppKit
import CraCore

/// Boosts from the gallery (crabrowser.app/boosts) and Share Boost… links. The site's Open in Cra
/// button is a `cra-boost:` address with the boost packed in it (SharedBoost): macOS hands it to Cra
/// from any browser, and a Cra page's click on one comes here directly (AppLinkPrompt, CraCEF's
/// OnBeforeBrowse). Nothing is added without the user's yes, and only a boost's look ever is: the
/// format has no JavaScript, and CSS that would load anything is refused (`SharedBoost.problems`).
@MainActor
enum BoostInstall {
    /// Whether `url` is a boost to install. Then it is dealt with here and must not load or open.
    static func isBoostLink(_ url: String) -> Bool {
        url.lowercased().hasPrefix(SharedBoost.installScheme + ":")
    }

    /// Asks over `window` (the page's, or the front browser window) whether to add the boost.
    static func offer(_ url: String, over window: NSWindow?, from page: String) {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        guard let window = window ?? app.main?.window else { return }
        // One question at a time: a page asking again while it is up gets nothing.
        guard window.attachedSheet == nil else {
            CraLog.note("boost link from \(page) while a sheet is up, ignored")
            return
        }
        guard let shared = SharedBoost.from(link: url) else {
            CraLog.note("boost link from \(page) doesn't read")
            AppDialog(title: "This Boost Link Doesn’t Work",
                      message: "It may have been cut short when it was copied.").present(over: window) { _ in }
            return
        }
        let problems = shared.problems
        guard problems.isEmpty else {
            CraLog.note("boost link from \(page) refused: \(problems.joined(separator: " "))")
            AppDialog(title: "Cra Can’t Add “\(shared.name)”",
                      message: problems.joined(separator: "\n")).present(over: window) { _ in }
            return
        }
        let store = app.store
        let existing = BoostStore.shared.boosts.first { $0.host == shared.host && $0.name == shared.name }
        var message = shared.about.map { $0 + "\n\n" } ?? ""
        message += "It changes how \(shared.host) looks. No code runs."
        if !store.settings.boostsEnabled { message += " Boosts are turned off; adding this turns them on." }
        if existing != nil { message += "\n\nYou already have a Boost by this name for \(shared.host); this replaces it." }
        CraLog.note("boost link from \(page) offers \(shared.host)")
        let alert = AppDialog(title: "Add the “\(shared.name)” Boost to \(shared.host)?", message: message,
                              actions: [DialogAction(existing == nil ? "Add Boost" : "Replace Boost"), .cancel])
        alert.present(over: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            var boost = shared.boost()
            if let existing { boost.id = existing.id }
            BoostStore.shared.add(boost)
            store.settings.boostsEnabled = true
            CraLog.note("boost added for \(shared.host)")
            (app.mainWindows.first { $0.window === window } ?? app.main)?.showToast("Boost Added")
        }
    }

    /// Share Boost…: the boost's look in a crabrowser.app link, copied. A boost's JavaScript stays
    /// on this Mac, and the toast says so.
    static func share(_ boost: Boost, toast: (String) -> Void) {
        let shared = SharedBoost(boost)
        guard let link = shared.link else {
            toast(shared.isEmpty ? "This Boost Doesn’t Change Anything Yet" : "This Boost Can’t Be Shared")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        toast(boost.js.isEmpty ? "Copied Boost URL" : "Copied Boost URL, Without Its JavaScript")
    }

    /// Whether Share Boost… has anything to share.
    static func canShare(_ boost: Boost) -> Bool { SharedBoost(boost).link != nil }
}
