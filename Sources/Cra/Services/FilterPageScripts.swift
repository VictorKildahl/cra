import CraCEF
import Foundation

/// The filter lists' page scripts (#845): their scriptlets run in every frame's own world before the page's
/// scripts (Resources/blocklist/scriptlets.js, given the ScriptletTable of the lists in use), and their procedural
/// hiding runs in Cra's world once a page commits (Resources/blocklist/procedural.js, BrowserManager). The scriptlets
/// go in with PageScript's own document-start script, so the Chromium engine installs them in a page before its first
/// load, and installs them again in open pages when the lists or the paused sites change. WebKit pages run the same
/// script as a user script (`mainWorld`, WebKitBrowser), installed again in open pages the same way.
@MainActor
enum FilterPageScripts {
    static let scriptlets = bundled("scriptlets")
    static let procedural = bundled("procedural")

    private static func bundled(_ name: String) -> String {
        Bundle.main.path(forResource: name, ofType: "js", inDirectory: "blocklist")
            .flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
    }

    /// The table the last run ended with, so pages restored at launch get their scriptlets from their first load,
    /// before the lists are read again.
    nonisolated static var keptURL: URL { BlockLists.folder.appendingPathComponent("page-scriptlets.json") }

    private static var installed: String?

    /// PageScript's page-world script with the scriptlets in use: what WebKit pages run (WebKitBrowser).
    private(set) static var mainWorld = PageScript.mainWorld

    /// PageScript's scripts, with the scriptlets of `table` (ScriptletTable.json; nil: the copy kept from the last
    /// run). Unchanged scripts aren't installed again.
    static func install(table json: String?) {
        let table = json ?? (try? String(contentsOf: keptURL, encoding: .utf8)) ?? ""
        let runs = !scriptlets.isEmpty && table.hasPrefix("{")
        let main = runs ? PageScript.mainWorld + "\n;(" + scriptlets + ")(" + table + ", globalThis);" : PageScript.mainWorld
        if let json {
            let url = keptURL
            DispatchQueue.global(qos: .utility).async { try? json.write(to: url, atomically: true, encoding: .utf8) }
        }
        guard main != installed else { return }
        installed = main
        mainWorld = main
        CraCEFRuntime.setDocumentStartScript(main, isolatedScript: PageScript.isolatedWorld, world: PageScript.world)
        WebKitContentBlocking.shared.scriptsChanged()
        if json != nil { CraLog.note("filter page scripts: scriptlets \(runs ? "on" : "off"), \(table.utf8.count / 1024) KB") }
    }

    /// The expression that runs the procedural selectors of a page's host in Cra's world (an empty list takes back
    /// what an earlier one hid).
    static func proceduralExpression(_ selectors: [String]) -> String? {
        guard !procedural.isEmpty, let data = try? JSONSerialization.data(withJSONObject: selectors),
              let list = String(data: data, encoding: .utf8) else { return nil }
        return "(" + procedural + ")(" + list + ", globalThis)"
    }
}
