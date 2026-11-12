import CraCore
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var browser: BrowserViewController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let directory = LaunchOptions.dataDirectory
        let browser = BrowserViewController(store: TabStore(directory: directory), settings: MobileSettingsStore(directory: directory))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = browser
        window.makeKeyAndVisible()
        self.window = window
        self.browser = browser
        let opened = connectionOptions.urlContexts.first?.url
        if let action = opened.flatMap(LaunchAction.init(link:)) {
            LaunchAction.pending = action
        } else if let url = LaunchOptions.openURL ?? opened?.absoluteString {
            browser.loadViewIfNeeded()
            browser.open(url)
        }
        if let item = connectionOptions.shortcutItem, let action = LaunchAction(shortcutType: item.type) {
            LaunchAction.pending = action
        }
    }

    /// A home-screen quick action while the app is running.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard let action = LaunchAction(shortcutType: shortcutItem.type) else { return completionHandler(false) }
        LaunchAction.perform(action)
        completionHandler(true)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let context = URLContexts.first else { return }
        let url = context.url
        if url.scheme == "cra" {
            guard var action = LaunchAction(link: url) else { return }
            // Another app may bring the search sheet up, but not start the microphone: only
            // Cra's own widget does that.
            let fromElsewhere = context.options.sourceApplication.map { !$0.hasPrefix("dk.kildahl.cra") } ?? false
            if fromElsewhere, action == .voiceSearch { action = .search(nil) }
            LaunchAction.perform(action)
            return
        }
        browser?.open(url.absoluteString)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        browser?.store.saveNow()
    }
}

/// What a test run passes on the command line: `-CraDataDir <path>` for a data folder of its own
/// (`fresh` for an empty one), `-CraOpenURL <address>` to start on a page, `-CraType <text>` to
/// start with that typed in the search field, `-CraSearch NO` to launch without the search sheet,
/// `-CraFakeModel YES` for canned answers in place of the on-device model, `-CraSummarize YES`
/// to summarize the first page once it has loaded, `-CraSyncDir <folder>` for the folder the Mac's
/// sidebar syncs into (`demo` for a made-up sidebar with two Spaces), `-CraFakeVoice <text>` for
/// what voice search hears instead of the microphone (`-CraShowVoice YES` holds the voice overlay
/// up with it, for a screenshot), `-CraOnboarding YES` to show onboarding on a test's data folder.
enum LaunchOptions {
    /// The argument after `-<name>` on the command line, exactly as given. (UserDefaults would
    /// read it as a property list and drop quotes from it.)
    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Worked out once: every store of a launch shares the folder.
    static let dataDirectory: URL = {
        guard let value = LaunchOptions.value("CraDataDir") else { return TabStore.defaultDirectory }
        if value == "fresh" {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Cra-\(UUID().uuidString)", isDirectory: true)
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }()

    static var openURL: String? { LaunchOptions.value("CraOpenURL") }
    static var typedText: String? { LaunchOptions.value("CraType") }
    static var skipsSearch: Bool { LaunchOptions.value("CraSearch") == "NO" }
    static var fakeModel: Bool { LaunchOptions.value("CraFakeModel") == "YES" }
    /// First launch shows onboarding; a test's own data folder skips it unless `-CraOnboarding YES`.
    static func showsOnboarding(seen: Bool) -> Bool {
        if let asked = LaunchOptions.value("CraOnboarding") { return asked == "YES" }
        return !seen && LaunchOptions.value("CraDataDir") == nil
    }

    static var fakeVoice: String? { LaunchOptions.value("CraFakeVoice") }
    static var showsVoiceOverlay: Bool { LaunchOptions.value("CraShowVoice") == "YES" }
    static var summarizesFirstPage: Bool { LaunchOptions.value("CraSummarize") == "YES" }
}
