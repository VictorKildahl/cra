import CraCore
import Testing

/// When a page's permission request asks, and the lines cra.log keeps about it (#286).
struct PermissionAskTests {
    // #286: a page behind (a call reconnecting after the Mac woke) put its microphone sheet over
    // the tab in front. Chrome asks only in the tab in front; Cra waits the same way, one sheet
    // at a time.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/286")) func onlyTheTabInFrontAsks() {
        #expect(!PermissionAsk.waits(tabShown: true, sheetUp: false))
        #expect(PermissionAsk.waits(tabShown: false, sheetUp: false))
        #expect(PermissionAsk.waits(tabShown: true, sheetUp: true))
        #expect(PermissionAsk.waits(tabShown: false, sheetUp: true))
    }

    // #371: the sheet took the whole window ("wants to access other devices on your network");
    // Arc asks in a popover that leaves the page and the tabs usable. A popover whose tab goes
    // behind steps aside and asks again when its tab is back.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/371")) func aPromptWhoseTabGoesBehindStepsAside() {
        #expect(PermissionAsk.stepsAside(tabShown: false))
        #expect(!PermissionAsk.stepsAside(tabShown: true))
        #expect(PermissionAsk.asideLine(origin: "https://router.example", kinds: 1 << 7)
                == "permission: router.example wants permission bits 0x80 → waits for its tab again")
    }

    @Test func requestLineNamesTheSiteTabAndMacOS() {
        #expect(PermissionAsk.requestLine(origin: "https://meet.google.com/", kinds: 2, tab: "1a2b3c4d", shown: false, waits: true,
                                          camera: .allowed, microphone: .notAsked)
                == "permission: meet.google.com wants microphone (tab 1a2b3c4d, behind; macOS microphone: not asked yet) → waits for its tab")
        #expect(PermissionAsk.requestLine(origin: "https://meet.google.com", kinds: 1 | 2, tab: "1a2b3c4d", shown: true, waits: false,
                                          camera: .denied, microphone: .allowed)
                == "permission: meet.google.com wants camera and microphone (tab 1a2b3c4d, in front; macOS camera: denied, microphone: allowed) → asks")
        #expect(PermissionAsk.requestLine(origin: "http://127.0.0.1:8080", kinds: 8, tab: "1a2b3c4d", shown: true, waits: true,
                                          camera: .allowed, microphone: .allowed)
                == "permission: 127.0.0.1 wants notifications (tab 1a2b3c4d, in front) → waits for the sheet before it")
        #expect(PermissionAsk.requestLine(origin: "https://maps.example", kinds: 4 | 1 << 5, tab: nil, shown: false, waits: false,
                                          camera: nil, microphone: nil)
                == "permission: maps.example wants location and permission bits 0x20 (no tab) → asks")
    }

    @Test func shownAndOutcomeLines() {
        #expect(PermissionAsk.shownLine(origin: "https://meet.google.com/", kinds: 2) == "permission: meet.google.com wants microphone → asks now")
        #expect(PermissionAsk.outcomeLine(origin: "https://meet.google.com/", kinds: 2, outcome: .allowed) == "permission: meet.google.com microphone: allowed")
        #expect(PermissionAsk.outcomeLine(origin: "https://meet.google.com/", kinds: 1, outcome: .blocked) == "permission: meet.google.com camera: blocked")
        #expect(PermissionAsk.outcomeLine(origin: "https://meet.google.com/", kinds: 2, outcome: .withdrawn) == "permission: meet.google.com microphone: withdrawn by the page")
        #expect(PermissionAsk.outcomeLine(origin: "https://meet.google.com/", kinds: 2, outcome: .tabGone) == "permission: meet.google.com microphone: dropped, its tab closed")
        #expect(PermissionAsk.kindNames(0) == "a permission")
        #expect(PermissionAsk.outcomeLine(origin: "file:///tmp/a.html", kinds: 0, outcome: .allowed) == "permission: file:///tmp/a.html a permission: allowed")
    }

    @Test func audioServiceAcrossASleep() {
        #expect(AudioServiceWake.line(beforeSleep: 30028, now: 30028) == "audio service: alive across the sleep (pid 30028)")
        #expect(AudioServiceWake.line(beforeSleep: 30028, now: 41200) == "audio service: restarted while the Mac slept (pid 30028 → 41200)")
        #expect(AudioServiceWake.line(beforeSleep: 30028, now: nil) == "audio service: ended while the Mac slept (pid 30028); Chromium starts it on the next sound")
        #expect(AudioServiceWake.line(beforeSleep: nil, now: 41200) == "audio service: started while the Mac slept (pid 41200)")
        #expect(AudioServiceWake.line(beforeSleep: nil, now: nil) == "audio service: not running")
        #expect(AudioServiceWake.sleepLine(pid: 30028) == "the Mac sleeps; audio service: pid 30028")
        #expect(AudioServiceWake.sleepLine(pid: nil) == "the Mac sleeps; audio service: not running")
    }
}
