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
        #expect(PermissionPrompt.message(origin: site, kinds: 1 | 2 | 4) == "https://www.messenger.com/ wants to use your camera, microphone and location")
    }

    @Test func devicesAndNotificationsTogether() {
        #expect(PermissionPrompt.message(origin: site, kinds: 1 | 8) == "https://www.messenger.com/ wants to use your camera and show notifications")
    }

    // #137: Calendar's sheet said "is asking for a browser permission" for a type CraCEF
    // didn't map. Every type CraCEF maps is named.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/137")) func chromesOtherTypesAreNamed() {
        let calendar = "https://calendar.google.com/"
        #expect(PermissionPrompt.message(origin: calendar, kinds: 1 << 18) == "https://calendar.google.com/ wants to open a kind of link, like email or calendar links")
        #expect(PermissionPrompt.message(origin: calendar, kinds: 1 << 7) == "https://calendar.google.com/ wants to access other devices on your local network")
        #expect(PermissionPrompt.message(origin: calendar, kinds: 1 << 6) == "https://calendar.google.com/ wants to manage windows on all your displays")
        #expect(PermissionPrompt.message(origin: calendar, kinds: 1 << 5 | 8 | 2) == "https://calendar.google.com/ wants to use your microphone, show notifications and see text and images copied to the clipboard")
        for request in PermissionPrompt.requests {
            #expect(!PermissionPrompt.message(origin: calendar, kinds: request.kind).contains("browser permission"))
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/137")) func eachTypeHasItsOwnBit() {
        let bits = PermissionPrompt.requests.map(\.kind)
        #expect(Set(bits).count == bits.count)
        #expect(bits.allSatisfy { $0.nonzeroBitCount == 1 && $0 & (1 | 2 | 4 | 16) == 0 })
    }

    @Test func anythingElseIsAGenericPermission() {
        #expect(PermissionPrompt.message(origin: site, kinds: 16) == "https://www.messenger.com/ is asking for a browser permission")
        #expect(PermissionPrompt.message(origin: site, kinds: 0) == "https://www.messenger.com/ is asking for a browser permission")
        #expect(PermissionPrompt.message(origin: site, kinds: 8 | 16) == "https://www.messenger.com/ wants to show notifications and use another browser permission")
    }
}
