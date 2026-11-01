import CraCore
import Observation
import Testing

/// SidebarStore in miniature: one @Observable stored property holding a settings struct.
@Observable @MainActor
private final class Store {
    var settings = Settings()
}

private struct Settings {
    var httpsOnly = false
    var sidebarWidth = 240
}

/// Lets the main-actor tasks Observation's onChange queued run.
@MainActor
private func settle() async {
    for _ in 0..<10 { await Task.yield() }
}

@MainActor
struct ObserveChangesTests {
    /// Why observeChanges exists: watching one field of the struct fires on any settings write.
    /// The HTTPS-only observer re-applied Chromium's preference on every write, including the
    /// ones during CefShutdown (#36).
    @Test func plainTrackingFiresOnAnUnrelatedSettingsWrite() {
        final class Fired: @unchecked Sendable { var value = false }
        let store = Store(), fired = Fired()
        _ = withObservationTracking { store.settings.httpsOnly } onChange: { fired.value = true }
        store.settings.sidebarWidth = 300
        #expect(fired.value)
    }

    @Test func appliesOnceThenOnlyRealChanges() async {
        let store = Store()
        var applied: [Bool] = []
        observeChanges(of: { store.settings.httpsOnly }, apply: { applied.append($0) })
        #expect(applied == [false])

        store.settings.sidebarWidth = 300
        await settle()
        store.settings.httpsOnly = false
        await settle()
        #expect(applied == [false], "unrelated and same-value writes apply nothing")

        store.settings.httpsOnly = true
        await settle()
        #expect(applied == [false, true])

        store.settings.sidebarWidth = 200
        await settle()
        store.settings.httpsOnly = false
        await settle()
        #expect(applied == [false, true, false], "it keeps watching after each change")
    }
}
