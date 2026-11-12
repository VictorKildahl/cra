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
/// sidebar syncs into (`demo` for a made-up sidebar with two Spaces).
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
    static var summarizesFirstPage: Bool { UserDefaults.standard.string(forKey: "CraSummarize") == "YES" }
}
