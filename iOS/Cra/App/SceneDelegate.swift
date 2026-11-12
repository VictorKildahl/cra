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
        if let url = LaunchOptions.openURL ?? connectionOptions.urlContexts.first?.url.absoluteString {
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
        guard let url = URLContexts.first?.url else { return }
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
    /// Worked out once: every store of a launch shares the folder.
    static let dataDirectory: URL = {
        guard let value = UserDefaults.standard.string(forKey: "CraDataDir") else { return TabStore.defaultDirectory }
        if value == "fresh" {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Cra-\(UUID().uuidString)", isDirectory: true)
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }()

    static var openURL: String? { UserDefaults.standard.string(forKey: "CraOpenURL") }
    static var typedText: String? { UserDefaults.standard.string(forKey: "CraType") }
    static var skipsSearch: Bool { UserDefaults.standard.string(forKey: "CraSearch") == "NO" }
    static var fakeModel: Bool { UserDefaults.standard.string(forKey: "CraFakeModel") == "YES" }
    /// First launch shows onboarding; a test's own data folder skips it unless `-CraOnboarding YES`.
    static func showsOnboarding(seen: Bool) -> Bool {
        if let asked = UserDefaults.standard.string(forKey: "CraOnboarding") { return asked == "YES" }
        return !seen && UserDefaults.standard.string(forKey: "CraDataDir") == nil
    }

    static var fakeVoice: String? { UserDefaults.standard.string(forKey: "CraFakeVoice") }
    static var showsVoiceOverlay: Bool { UserDefaults.standard.string(forKey: "CraShowVoice") == "YES" }
    static var summarizesFirstPage: Bool { UserDefaults.standard.string(forKey: "CraSummarize") == "YES" }
}
