import AppKit
import CraCEF

/// Pause All Media (GitHub #438; CraCore's MediaPause decides which pages and what to say): the
/// command bar's command and AppleScript's `pause media`. Each page is asked with Cra.pauseMedia
/// (the engine pauses its media session and every frame's media elements; a WebKit page answers
/// it with pauseAllMediaPlayback), then checked for sound a moment later.
@MainActor
enum PauseAllMedia {
    /// A loaded page and how to reach it.
    struct Target {
        let page: MediaPause.Page
        let browser: CraBrowser
        let title: String
        /// The page's sound as it starts or stops (not the speaker's 2 s hold).
        let soundNow: () -> Bool
        /// Brings the page on screen (the toast's Show).
        let show: () -> Void
    }

    /// Pauses every target, then reports the targets (indices into `targets`) it paused and the
    /// ones that kept playing, in the order given.
    static func run(_ targets: [Target], closingPictureInPicture: Bool, done: @escaping (MediaPause.Report<Int>) -> Void) {
        guard !targets.isEmpty else { return done(.init()) }
        var outcomes = [MediaPause.Outcome?](repeating: nil, count: targets.count)
        var left = targets.count
        for (i, target) in targets.enumerated() {
            pause(target, closingPictureInPicture: closingPictureInPicture) { outcome in
                outcomes[i] = outcome
                left -= 1
                guard left == 0 else { return }
                var report = MediaPause.Report<Int>()
                for (i, o) in outcomes.enumerated() { report.add(i, o ?? .quiet) }
                done(report)
            }
        }
    }

    private static func pause(_ target: Target, closingPictureInPicture: Bool, done: @escaping (MediaPause.Outcome) -> Void) {
        let before = target.soundNow()
        let browser = target.browser
        var answered = false
        let finish = { (answer: MediaPause.EngineAnswer?) in
            guard !answered else { return }
            answered = true
            // Picture in Picture's close button: the video pauses and goes back to its page.
            if closingPictureInPicture, browser.isInPictureInPicture { browser.closePictureInPicture() }
            DispatchQueue.main.asyncAfter(deadline: .now() + MediaPause.checkDelay) {
                done(MediaPause.outcome(answer: answer, playingBefore: before, playingAfter: target.soundNow()))
            }
        }
        browser.sendDevToolsMethod("Cra.pauseMedia", params: "{}") { result, error in
            MainActor.assumeIsolated {
                CraLog.note("pause media \(target.title) (\(browser is WebKitBrowser ? "WebKit" : "Chromium"), sound \(before)): \(result ?? "error: \(error ?? "?")")")
                guard let o = result.flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }) else {
                    // CEF, or an engine from before Cra.pauseMedia.
                    pauseMainFrame(browser)
                    return finish(nil)
                }
                guard o["playing"] as? Bool == true else { return finish(.init()) }
                finish(.init(session: o["session"] as? Bool ?? false, paused: o["paused"] as? Int ?? 0, resisted: o["resisted"] as? Int ?? 0))
            }
        }
        // The engine answers within 1.5 s; a page that's gone may not answer at all.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish(nil) }
    }

    /// Without Cra.pauseMedia: the page's media session pause handler, then its top frame's media
    /// elements, as the sidebar player pauses.
    private static func pauseMainFrame(_ browser: CraBrowser) {
        browser.sendDevToolsMethod("Cra.mediaSession", params: #"{"action":"pause"}"#) { _, _ in }
        let js = "document.querySelectorAll('video,audio').forEach(m => m.pause())"
        guard let data = try? JSONSerialization.data(withJSONObject: ["expression": js, "returnByValue": true, "userGesture": false]),
              let params = String(data: data, encoding: .utf8) else { return }
        browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { _, _ in }
    }
}

extension AppDelegate {
    /// Every page Cra has open: each browser window's tabs (a sleeping tab as not loaded), then
    /// Little Windows and Peeks.
    func mediaPauseTargets() -> [PauseAllMedia.Target] {
        var list: [PauseAllMedia.Target] = []
        for w in mainWindows {
            let windowID = w.windowID
            for rt in w.browsers.runtimes.values.sorted(by: { $0.tabID.uuidString < $1.tabID.uuidString }) {
                let tabID = rt.tabID
                let space = store.spaceID(ofItem: tabID, window: windowID)
                let page = MediaPause.Page(id: tabID, window: windowID, space: space,
                                           profile: space.flatMap { store.space($0)?.profileID }, loaded: !rt.discarded)
                list.append(.init(page: page, browser: rt.browser, title: store.item(tabID)?.displayTitle ?? rt.browser.currentTitle,
                                  soundNow: { [weak rt] in rt?.soundPlaying ?? false },
                                  show: { [weak self, weak w] in
                                      guard let self, let w else { return }
                                      self.store.selectTab(tabID, window: w.windowID)
                                      w.showWindow(nil)
                                  }))
            }
        }
        for l in littleWindows {
            guard let browser = l.browser else { continue }
            let page = MediaPause.Page(id: l.pageID, window: l.peekParent?.windowID, space: l.state.targetSpaceID,
                                       profile: l.state.profileID, loaded: true)
            list.append(.init(page: page, browser: browser, title: l.state.title,
                              soundNow: { [weak l] in l?.soundPlaying ?? false },
                              show: { [weak l] in
                                  guard let l else { return }
                                  // A Peek waiting on its tab comes back with the tab.
                                  if l.isPeek, let parent = l.peekParent, let tab = l.peekSourceTab {
                                      parent.store.selectTab(tab, window: parent.windowID)
                                      parent.showWindow(nil)
                                  } else {
                                      l.show()
                                  }
                              }))
        }
        return list
    }

    /// The command bar's Pause All Media: every page, Picture in Picture left open (paused), and a
    /// toast in the window it ran in. When a page kept playing, the toast's Show goes to it.
    func pauseAllMediaFromCommand() {
        let little = keyLittleWindow
        let window = main
        let all = mediaPauseTargets().filter { MediaPause.isTarget($0.page, in: .everything) }
        PauseAllMedia.run(all, closingPictureInPicture: false) { report in
            CraLog.note("pause all media: \(all.count) pages, paused \(report.paused.count), kept playing \(report.keptPlaying.map { all[$0].title })")
            let show = report.keptPlaying.first.map { i in ShinyToast.Action(title: "Show") { all[i].show() } }
            if let little, little.window?.isVisible == true {
                little.showToast(report.toast, action: show)
            } else {
                window?.showToast(report.toast, action: show)
            }
        }
    }
}
