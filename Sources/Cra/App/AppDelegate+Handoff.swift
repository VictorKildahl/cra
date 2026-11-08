import AppKit

extension AppDelegate {
    func application(_ application: NSApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        userActivityType == NSUserActivityTypeBrowsingWeb
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL, let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host?.isEmpty == false else { return false }
        // The normal external-link path also queues pages received before launch finishes.
        self.application(application, open: [url])
        return true
    }
}
