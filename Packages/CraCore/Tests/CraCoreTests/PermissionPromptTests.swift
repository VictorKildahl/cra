import CraCore
import Testing

/// The permission sheet's question for each kind of request.
struct PermissionPromptTests {
    let site = "https://www.messenger.com/"

    @Test func notificationsAskToShowNotifications() {
        #expect(PermissionPrompt.message(origin: site, kinds: 8) == "https://www.messenger.com/ wants to show notifications")
    }

    @Test func devicesAreUsed() {
        #expect(PermissionPrompt.message(origin: site, kinds: 1 | 2) == "https://www.messenger.com/ wants to use your camera and microphone")
        #expect(PermissionPrompt.message(origin: site, kinds: 4) == "https://www.messenger.com/ wants to use your location")
    }

    @Test func devicesAndNotificationsTogether() {
        #expect(PermissionPrompt.message(origin: site, kinds: 1 | 8) == "https://www.messenger.com/ wants to use your camera and show notifications")
    }

    @Test func anythingElseIsAGenericPermission() {
        #expect(PermissionPrompt.message(origin: site, kinds: 16) == "https://www.messenger.com/ is asking for a browser permission")
        #expect(PermissionPrompt.message(origin: site, kinds: 0) == "https://www.messenger.com/ is asking for a browser permission")
    }
}
