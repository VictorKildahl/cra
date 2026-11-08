import CraCore
import Testing

/// The update banner's news, and the toast that carries it while the sidebar is hidden (X DM 8 Nov 2026).
struct UpdateNoticeTests {
    @Test func aDownloadedUpdateComesBeforeAFoundOne() {
        #expect(UpdateNotice.current(ready: "0.1.36", found: "0.1.36", dismissed: false) == .ready(version: "0.1.36"))
        #expect(UpdateNotice.current(ready: nil, found: "0.1.36", dismissed: false) == .available(version: "0.1.36"))
        #expect(UpdateNotice.current(ready: nil, found: nil, dismissed: false) == nil)
        #expect(UpdateNotice.current(ready: "0.1.36", found: nil, dismissed: true) == nil)
    }

    @Test func theBannerKeepsArcsWords() {
        let ready = UpdateNotice.ready(version: "0.1.36"), found = UpdateNotice.available(version: "0.1.36")
        #expect((ready.title, ready.subtitle, ready.button) == ("An update is ready!", "Click to restart", "Restart"))
        #expect((found.title, found.subtitle, found.button) == ("New Cra Version Available", "Cra 0.1.36", "Update"))
    }

    /// With the sidebar out the banner says it; hidden, the toast does.
    @Test func onlyAHiddenSidebarGetsTheToast() {
        let ready = UpdateNotice.ready(version: "0.1.36")
        #expect(UpdateNotice.toast(ready, told: nil, sidebarVisible: false) == ready)
        #expect(UpdateNotice.toast(ready, told: nil, sidebarVisible: true) == nil)
        #expect(UpdateNotice.toast(nil, told: nil, sidebarVisible: false) == nil)
    }

    /// Once a launch per notice: hiding the sidebar again doesn't repeat it, a new notice does.
    @Test func eachNoticeIsToastedOnce() {
        let found = UpdateNotice.available(version: "0.1.36"), ready = UpdateNotice.ready(version: "0.1.36")
        #expect(UpdateNotice.toast(found, told: found, sidebarVisible: false) == nil)
        #expect(UpdateNotice.toast(ready, told: found, sidebarVisible: false) == ready)
        #expect(UpdateNotice.toast(.ready(version: "0.1.37"), told: ready, sidebarVisible: false) == .ready(version: "0.1.37"))
    }
}
