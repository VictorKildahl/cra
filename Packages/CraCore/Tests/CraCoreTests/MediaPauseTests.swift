import CraCore
import Foundation
import Testing

/// Pause All Media (#438): which pages it asks, and what it says it did.
struct MediaPauseTests {
    let w1 = UUID(), w2 = UUID(), s1 = UUID(), s2 = UUID(), work = UUID()

    func page(window: UUID?, space: UUID?, profile: UUID? = nil, loaded: Bool = true) -> MediaPause.Page {
        MediaPause.Page(id: UUID(), window: window, space: space, profile: profile, loaded: loaded)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/438")) func everyLoadedPageEverywhereButNoSleepingTab() {
        let tab = page(window: w1, space: s1)
        let otherWindow = page(window: w2, space: s2, profile: work)
        let little = page(window: nil, space: s1)
        let sleeping = page(window: w1, space: s1, loaded: false)
        let targets = MediaPause.targets([tab, otherWindow, little, sleeping], in: .everything)
        #expect(targets == [tab, otherWindow, little], "a sleeping tab isn't loaded to be paused")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/438")) func aWindowSpaceOrTabScopeAndExclusions() {
        let a = page(window: w1, space: s1), b = page(window: w1, space: s2), c = page(window: w2, space: s2)
        let peekOverW1 = page(window: w1, space: s1), little = page(window: nil, space: s2)
        let all = [a, b, c, peekOverW1, little]

        let window = MediaPause.Scope(only: .init(windows: [w1]))
        #expect(MediaPause.targets(all, in: window) == [a, b, peekOverW1], "a Peek goes with the window under it")

        let space = MediaPause.Scope(only: .init(spaces: [s2]))
        #expect(MediaPause.targets(all, in: space) == [b, c, little])

        let tabs = MediaPause.Scope(only: .init(tabs: [a.id, c.id]))
        #expect(MediaPause.targets(all, in: tabs) == [a, c])

        let allBut = MediaPause.Scope(except: .init(windows: [w2], tabs: [a.id]))
        #expect(MediaPause.targets(all, in: allBut) == [b, peekOverW1, little])

        let windowButSpace = MediaPause.Scope(only: .init(windows: [w1]), except: .init(spaces: [s2]))
        #expect(MediaPause.targets(all, in: windowButSpace) == [a, peekOverW1])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/438")) func aProfileScope() {
        let personal = page(window: w1, space: s1), workTab = page(window: w2, space: s2, profile: work)
        #expect(MediaPause.targets([personal, workTab], in: .init(profile: .some(work))) == [workTab])
        #expect(MediaPause.targets([personal, workTab], in: .init(profile: .some(nil))) == [personal], "nil is the Default profile")
    }

    /// The engine's answer and the sound before and after decide; a page isn't said to be quiet
    /// while it still makes sound.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/438")) func outcomes() {
        typealias A = MediaPause.EngineAnswer
        #expect(MediaPause.outcome(answer: A(), playingBefore: false, playingAfter: false) == .quiet)
        #expect(MediaPause.outcome(answer: nil, playingBefore: false, playingAfter: false) == .quiet)
        #expect(MediaPause.outcome(answer: A(session: true), playingBefore: true, playingAfter: false) == .paused)
        #expect(MediaPause.outcome(answer: A(paused: 2), playingBefore: false, playingAfter: false) == .paused,
                "a muted video counts as playing media")
        #expect(MediaPause.outcome(answer: A(session: true, paused: 1), playingBefore: true, playingAfter: true) == .keptPlaying,
                "still making sound a moment later (Web Audio, a frame that never answered)")
        #expect(MediaPause.outcome(answer: A(paused: 1, resisted: 1), playingBefore: true, playingAfter: false) == .keptPlaying)
        #expect(MediaPause.outcome(answer: nil, playingBefore: true, playingAfter: false) == .paused, "WebKit, or an older engine")
        #expect(MediaPause.outcome(answer: A(), playingBefore: false, playingAfter: true) == .quiet,
                "a page that starts playing after the pause began wasn't one it paused")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/438")) func theToastSaysWhatHappened() {
        var r = MediaPause.Report<Int>()
        #expect(r.toast == "Nothing Is Playing")
        r.add(1, .paused)
        r.add(2, .quiet)
        #expect(r.toast == "Paused 1 Tab")
        r.add(3, .paused)
        #expect(r.toast == "Paused 2 Tabs")
        r.add(4, .keptPlaying)
        #expect(r.toast == "Paused 2 Tabs, 1 Kept Playing")
        #expect(r.keptPlaying == [4])
        #expect(MediaPause.Report<Int>(keptPlaying: [1, 2]).toast == "2 Tabs Kept Playing")
    }
}
