import CraCore
import Testing

/// Addresses the iPhone app's web view can't load itself (mailto:, tel:, an app's own scheme): they
/// go to the app that handles them, as in Safari.
struct MobileExternalLinksTests {
    /// Regression in TestFlight 1086: the app only handed universal links to other apps, so a
    /// mailto: or tel: link went to WebKit, which failed it with -1002 "unsupported URL", and
    /// #568's error page then replaced the page. Every scheme WebKit can't load now goes out.
    @Test(.bug(id: "crash-1086-external-schemes"))
    func aTappedLinkToAnotherAppsAddressOpensThatApp() {
        for address in ["mailto:fixture@cra.test", "tel:+4512345678", "sms:+4512345678", "facetime:+4512345678",
                        "facetime-audio:+4512345678", "maps:?q=Copenhagen", "itms-apps://apps.apple.com/app/id1",
                        "itms-appss://apps.apple.com/app/id1", "spotify:track:1", "MAILTO:fixture@cra.test",
                        "x-my-app+v2.beta://open"] {
            #expect(MobileExternalLinks.answer(address: address, isMainFrame: true, isUserGesture: true) == .open, "\(address)")
            // A tap in a frame is still the user's.
            #expect(MobileExternalLinks.answer(address: address, isMainFrame: false, isUserGesture: true) == .open, "\(address)")
        }
    }

    /// What the web view loads itself stays in the web view.
    @Test(.bug(id: "crash-1086-external-schemes"))
    func whatWebKitLoadsStaysHere() {
        for address in ["https://example.com/", "http://cra.localhost:8080/plain", "HTTPS://EXAMPLE.COM", "about:blank",
                        "about:srcdoc", "data:text/html,<h1>Hi</h1>", "blob:https://example.com/1234", "file:///tmp/page.html",
                        "javascript:void(0)"] {
            for gesture in [true, false] {
                #expect(MobileExternalLinks.answer(address: address, isMainFrame: true, isUserGesture: gesture) == .load, "\(address)")
                #expect(MobileExternalLinks.answer(address: address, isMainFrame: false, isUserGesture: gesture) == .load, "\(address)")
            }
            #expect(!MobileExternalLinks.goesOut(address), "\(address)")
        }
        // No scheme to read: left to WebKit as before.
        for address in ["", "example.com", "//example.com/x", "1http://x"] {
            #expect(MobileExternalLinks.answer(address: address, isMainFrame: true, isUserGesture: true) == .load, "\(address)")
        }
    }

    /// Safari: a page that sends itself to another app's address without a tap (a script, a
    /// redirect) asks "Open this page in …?" first. iOS itself asks before a call, so tel:,
    /// telprompt:, facetime: and facetime-audio: go straight to it, with no second question.
    @Test(.bug(id: "crash-1086-external-schemes"))
    func withoutATapItAsksFirstExceptForCalls() {
        #expect(MobileExternalLinks.answer(address: "mailto:fixture@cra.test", isMainFrame: true, isUserGesture: false) == .ask(app: nil))
        #expect(MobileExternalLinks.answer(address: "spotify:track:1", isMainFrame: true, isUserGesture: false) == .ask(app: nil))
        #expect(MobileExternalLinks.answer(address: "sms:+4512345678", isMainFrame: true, isUserGesture: false) == .ask(app: "Messages"))
        #expect(MobileExternalLinks.answer(address: "maps:?q=Copenhagen", isMainFrame: true, isUserGesture: false) == .ask(app: "Maps"))
        #expect(MobileExternalLinks.answer(address: "itms-apps://apps.apple.com/app/id1", isMainFrame: true, isUserGesture: false) == .ask(app: "App Store"))
        #expect(MobileExternalLinks.answer(address: "itms-appss://apps.apple.com/app/id1", isMainFrame: true, isUserGesture: false) == .ask(app: "App Store"))
        for address in ["tel:+4512345678", "telprompt:+4512345678", "facetime:+4512345678", "facetime-audio:+4512345678", "TEL:112"] {
            #expect(MobileExternalLinks.answer(address: address, isMainFrame: true, isUserGesture: false) == .open, "\(address)")
        }
    }

    /// A frame of the page that goes to another app's address on its own (an ad's iframe) does
    /// nothing at all, as in Safari: no app, no question, and the page stays.
    @Test(.bug(id: "crash-1086-external-schemes"))
    func aFrameWithoutATapDoesNothing() {
        for address in ["mailto:fixture@cra.test", "tel:+4512345678", "itms-apps://apps.apple.com/app/id1", "spotify:track:1"] {
            #expect(MobileExternalLinks.answer(address: address, isMainFrame: false, isUserGesture: false) == .stay, "\(address)")
        }
    }

    /// The app's own addresses never leave it: `cra://` is what the widgets open, and a page must
    /// not drive the app through it (Cra for Mac's rule: pages never). cra-edit: and cra-browse:
    /// are a Browse for Me page's chips, which the page answers before this.
    @Test(.bug(id: "crash-1086-external-schemes"))
    func theAppsOwnAddressesStay() {
        for address in ["cra://search", "cra://spaces", "cra-edit:pizza", "cra-browse:pizza"] {
            for gesture in [true, false] {
                #expect(MobileExternalLinks.answer(address: address, isMainFrame: true, isUserGesture: gesture) == .stay, "\(address)")
            }
        }
    }

    /// Safari's question, with the app's name where it is known for the scheme (only Apple's apps
    /// own a scheme for sure; mailto: goes to whichever mail app the user picked).
    @Test(.bug(id: "crash-1086-external-schemes"))
    func theQuestionNamesTheApp() {
        #expect(MobileExternalLinks.question(app: "Messages") == "Open this page in “Messages”?")
        #expect(MobileExternalLinks.question(app: nil) == "Open this page in another app?")
        #expect(MobileExternalLinks.openButton == "Open")
        #expect(MobileExternalLinks.cancelButton == "Cancel")
    }
}
