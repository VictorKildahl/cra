import Foundation

/// What the performance recorder times, in milliseconds (GitHub #91). The raw values are the
/// keys in perf.json, so renaming one changes the file's schema.
public enum PerfMetric: String, Codable, CaseIterable, Sendable {
    /// One pass of the main run loop between two points where it could take input. The main
    /// thread is also Chromium's browser UI thread: a long pass is a frozen window.
    case mainLoop
    /// Putting other tabs on screen (BrowserManager.show), the part on the main thread, without
    /// making a page for a tab that had none (that is `pageCreate`).
    case tabSwitch
    /// Making a tab's page: Chromium's view, its window and the browser object.
    case pageCreate
    /// A main-frame navigation, from loading to loaded.
    case pageLoad
    /// A tab that tab sleeping closed, shown again until its page finished loading.
    case tabWake
    /// A data-folder JSON file decoded at launch, or encoded and written.
    case jsonLoad
    case jsonSave
    /// Long tasks (50 ms or more) in the visible tab's page.
    case longTask
    /// Framing an extension's popup once Chrome shows it (ExtensionPopupWindow.present).
    case extensionPopup
}

/// What the recorder counts. Some carry a key (`loadError` the error code, `sleepRefusal` the
/// reason); perf.json lists those per key.
public enum PerfCounter: String, Codable, CaseIterable, Sendable {
    /// A main-frame load that failed; the key is Chromium's net error code.
    case loadError
    /// A renderer that ended; the key is how (crashed, killed, out of memory…).
    case rendererTerminated
    /// Chromium's "Page Unresponsive" (about 15 s without handling input), and its recovery.
    case rendererUnresponsive
    case rendererResponsive
    /// Tab sleeping closed a page, or kept one awake; the key is why.
    case tabSlept
    case sleepRefusal
}

/// The kinds of process Cra runs, from the name macOS gives each one.
public enum PerfProcessKind: String, Codable, CaseIterable, Sendable {
    case browser, renderer, gpu, utility, other

    /// Chromium's `--type=` argument says what a helper is: CEF runs its GPU process from the plain
    /// `Cra Helper` app, so the app's name alone would call it a utility. Without one (it couldn't
    /// be read), the name decides: `Cra Helper (Renderer)`, `(GPU)`, other helpers are utilities, and
    /// anything that isn't a helper (`sample` at a hang) is other.
    public static func of(name: String, isSelf: Bool, type: String? = nil) -> PerfProcessKind {
        if isSelf { return .browser }
        switch type {
        case "renderer": return .renderer
        case "gpu-process": return .gpu
        case .some: return .utility
        case nil: break
        }
        guard name.contains("Helper") else { return .other }
        if name.hasSuffix("(Renderer)") { return .renderer }
        if name.hasSuffix("(GPU)") { return .gpu }
        return .utility
    }
}
