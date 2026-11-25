import Foundation
import Testing
@testable import CraCore
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// Widevine that fails moves its site to WebKit (docs/protected-media.md, "Widevine that fails"):
/// which pages may move, what keeps a site in Chromium, what goes along and how the page tells.
struct WidevineFailureTests {
    let sites = ProtectedMediaSites()

    // MARK: Which pages move

    @Test func anySiteNoOneChoseMovesWhenItsWidevineFails() {
        let none = ProtectedMediaChoices()
        #expect(sites.movesWhenWidevineFails(at: "https://watch.example.tv/film/42", choices: none, incognito: false))
        #expect(sites.movesWhenWidevineFails(at: "http://127.0.0.1:8123/drm.html", choices: none, incognito: false))
        // A listed service is WebKit's already; a mixed site asks per video instead.
        #expect(!sites.movesWhenWidevineFails(at: "https://www.netflix.com/watch/1", choices: none, incognito: false))
        #expect(!sites.movesWhenWidevineFails(at: "https://www.youtube.com/watch?v=film1", choices: none, incognito: false))
        #expect(!sites.movesWhenWidevineFails(at: "https://athome.fandango.com/content/browse/play/1/movie", choices: none, incognito: false))
        // An incognito page writes no site to disk: it keeps the switch.
        #expect(!sites.movesWhenWidevineFails(at: "https://watch.example.tv/film/42", choices: none, incognito: true))
        // Off, nothing moves; nor does anything that isn't a web page.
        #expect(!ProtectedMediaSites(isEnabled: false).movesWhenWidevineFails(at: "https://watch.example.tv/", choices: none, incognito: false))
        #expect(!sites.movesWhenWidevineFails(at: "chrome://settings", choices: none, incognito: false))
        #expect(!sites.movesWhenWidevineFails(at: "file:///tmp/a.html", choices: none, incognito: false))
    }

    @Test func aSiteTakenBackToChromiumStaysThere() {
        // The switch to Chromium keeps the site there, its subdomains with it.
        let kept = ProtectedMediaChoices().choosing(.chromium, for: "https://watch.example.tv/film/42")
        #expect(kept.kept == ["watch.example.tv"])
        #expect(!sites.movesWhenWidevineFails(at: "https://watch.example.tv/other", choices: kept, incognito: false))
        #expect(!sites.movesWhenWidevineFails(at: "https://eu.watch.example.tv/", choices: kept, incognito: false))
        #expect(sites.movesWhenWidevineFails(at: "https://example.tv/", choices: kept, incognito: false), "a parent domain wasn't taken back")
        #expect(sites.movesWhenWidevineFails(at: "https://notwatch.example.tv/", choices: kept, incognito: false))
        // Choosing it twice keeps one entry; choosing WebKit lifts it, for a subdomain's page too.
        #expect(kept.choosing(.chromium, for: "https://watch.example.tv/").kept == ["watch.example.tv"])
        let back = kept.choosing(.webKit, for: "https://eu.watch.example.tv/")
        #expect(back.kept.isEmpty && back.added == ["eu.watch.example.tv"])
        // A listed service taken back is kept too: its own Widevine failing there was the user's choice.
        let netflix = ProtectedMediaChoices().choosing(.chromium, for: "https://www.netflix.com/")
        #expect(netflix.removed == ["netflix.com"] && netflix.kept == ["www.netflix.com"])
    }

    @Test func keptIsAFieldOfItsOwnInTheFile() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // A file from before the field loads with none, and is written back as it was.
        let json = #"{"added":["a.com"],"removed":[],"told":["Netflix"]}"#
        let old = try JSONDecoder().decode(ProtectedMediaChoices.self, from: Data(json.utf8))
        #expect(old.kept.isEmpty)
        #expect(String(data: try encoder.encode(old), encoding: .utf8) == json)
        let chosen = old.choosing(.chromium, for: "https://a.com/film")
        let written = try #require(String(data: try encoder.encode(chosen), encoding: .utf8))
        #expect(written == #"{"added":[],"kept":["a.com"],"removed":[],"told":["Netflix"]}"#)
        #expect(try JSONDecoder().decode(ProtectedMediaChoices.self, from: Data(written.utf8)) == chosen)
    }

    // MARK: What goes along

    /// The page's own sign-in goes with the site: the cookies it sends (its host's and its parent
    /// domains') and its subdomains'. Nothing of another site, nothing expired or partitioned.
    @Test func theCookiesThePageSendsGoAlong() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let answer = """
        {"cookies":[
          {"name":"host","value":"1","domain":"watch.example.tv","path":"/","expires":-1,"session":true},
          {"name":"parent","value":"1","domain":".example.tv","path":"/","expires":1900000000,"session":false,"secure":true,"httpOnly":true,"sameSite":"Lax"},
          {"name":"sub","value":"1","domain":"eu.watch.example.tv","path":"/","expires":-1,"session":true},
          {"name":"sibling","value":"1","domain":"shop.example.tv","path":"/","expires":-1,"session":true},
          {"name":"lookalike","value":"1","domain":"notwatch.example.tv","path":"/","expires":-1,"session":true},
          {"name":"other","value":"1","domain":".bank.example","path":"/","expires":1900000000,"session":false},
          {"name":"tld","value":"1","domain":".tv","path":"/","expires":-1,"session":true},
          {"name":"old","value":"1","domain":".example.tv","path":"/","expires":1700000000,"session":false},
          {"name":"embed","value":"1","domain":".example.tv","path":"/","expires":-1,"session":true,"partitionKey":{"topLevelSite":"https://x.example"}}
        ]}
        """
        let copied = ProtectedVideoHandoff.cookies(fromProtocolAnswer: answer, forPageAt: "https://watch.example.tv/film/42", now: now)
        // A cookie for a bare ".tv" can't be set by any site; if one were there, the page would send it.
        #expect(copied.map(\.name) == ["host", "parent", "sub", "tld"])
        let parent = copied[1]
        #expect(parent.domain == ".example.tv" && parent.isSecure && parent.isHTTPOnly && !parent.isSessionOnly && parent.expiresDate != nil)
        #expect(copied[0].isSessionOnly)
        #expect(ProtectedVideoHandoff.cookies(fromProtocolAnswer: answer, forPageAt: "chrome://settings", now: now).isEmpty)
        #expect(ProtectedVideoHandoff.cookies(fromProtocolAnswer: "", forPageAt: "https://watch.example.tv/", now: now).isEmpty)
    }

    #if canImport(JavaScriptCore)
    // MARK: How the page tells

    /// A top frame and a player frame of its origin, each with the page's world (the wrapper and
    /// the watch) and Cra's world, as PageScript runs them, over stand-ins for the browser's media
    /// keys: `play(w, opts)` runs a player in window `w` and returns its session; `tick()` runs
    /// the timers that are due; `failures` is what the top frame's drmFailNext answered.
    private func page(keySystems: [String] = WidevineSignal.failingKeySystems) throws -> JSContext {
        let context = try #require(JSContext())
        context.exceptionHandler = { _, error in Issue.record("script threw: \(error?.toString() ?? "?")") }
        let pageWorld = try #require(String(data: JSONEncoder().encode(WidevineSignal.pageWorld(channel: "chan", keySystems: keySystems, answerWithin: 1000)), encoding: .utf8))
        let isolated = try #require(String(data: JSONEncoder().encode(WidevineSignal.isolatedWorld(channel: "chan")), encoding: .utf8))
        context.evaluateScript("""
        function CustomEvent(type) { this.type = type; }
        var timers = [];
        function setTimeout(f, ms) { timers.push(f); }
        function tick() { const due = timers; timers = []; due.forEach(f => f()); }
        function target(o) {
          o.listeners = [];
          o.addEventListener = (type, f) => o.listeners.push({ type, f });
          o.dispatchEvent = e => {
            let stopped = false;
            e.stopImmediatePropagation = () => { stopped = true; };
            for (const l of o.listeners.slice()) { if (l.type === e.type && !stopped) l.f(e); }
          };
          return o;
        }
        function makeWindow(href, top) {
          const w = target({ location: { href } });
          w.top = top || w;
          w.postMessage = (data) => w.dispatchEvent({ type: 'message', data });
          function MediaKeySession() { target(this); this.keyStatuses = new Map(); this.closed = new Promise(r => { this.close = () => r(); }); }
          MediaKeySession.prototype.generateRequest = function () { this.dispatchEvent({ type: 'message', messageType: 'license-request' }); return Promise.resolve(); };
          MediaKeySession.prototype.update = function (licence) { return licence === 'good' ? Promise.resolve() : Promise.reject(new Error('refused')); };
          function MediaKeys() {}
          MediaKeys.prototype.createSession = function () { return new MediaKeySession(); };
          function MediaKeySystemAccess(keySystem) { this.keySystem = keySystem; }
          MediaKeySystemAccess.prototype.createMediaKeys = function () { return Promise.resolve(new MediaKeys()); };
          function HTMLMediaElement() {}
          HTMLMediaElement.prototype.setMediaKeys = function (keys) { this.mediaKeys = keys; return Promise.resolve(); };
          function Navigator() {
            // Shaka Player 4 finds its key system here, never through requestMediaKeySystemAccess.
            this.mediaCapabilities = { decodingInfo: c => Promise.resolve({ supported: true, keySystemAccess: new MediaKeySystemAccess(c.keySystemConfiguration.keySystem) }) };
          }
          Navigator.prototype.requestMediaKeySystemAccess = function (keySystem, configs) { return Promise.resolve(new MediaKeySystemAccess(keySystem)); };
          Object.assign(w, { MediaKeySession, MediaKeys, MediaKeySystemAccess, HTMLMediaElement, Navigator, navigator: new Navigator() });
          new Function('window', 'addEventListener', 'location', 'CustomEvent', 'const cra = window.__cra = {};' + \(isolated))(w, w.addEventListener, w.location, CustomEvent);
          new Function('window', 'dispatchEvent', 'CustomEvent', 'setTimeout', \(pageWorld))(w, w.dispatchEvent, CustomEvent, setTimeout);
          return w;
        }
        var top = makeWindow('https://watch.example.tv/film/42');
        var frame = makeWindow('https://watch.example.tv/player_frame.html', top);
        var failures = [];
        var wait = () => { top.__cra.drmFailNext().then(v => failures.push(v)); };
        var sessions = [];
        // A player: key system (asked for, or through Media Capabilities as Shaka Player 4 does), keys on
        // a <video> (unless attach is false), a session that asks for a licence.
        function play(w, { keySystem = 'com.widevine.alpha', attach = true, capabilities = false } = {}) {
          (capabilities
            ? w.navigator.mediaCapabilities.decodingInfo({ type: 'media-source', keySystemConfiguration: { keySystem } }).then(r => r.keySystemAccess)
            : w.navigator.requestMediaKeySystemAccess(keySystem, [{}]))
            .then(a => a.createMediaKeys())
            .then(keys => (attach ? new w.HTMLMediaElement().setMediaKeys(keys) : Promise.resolve()).then(() => keys))
            .then(keys => { const s = keys.createSession(); sessions.push(s); return s.generateRequest('cenc', new ArrayBuffer(8)); });
        }
        function answer(s, licence) { s.update(licence).catch(() => {}); }
        function statuses(s, ...all) { s.keyStatuses = new Map(all.map((x, i) => [i, x])); s.dispatchEvent({ type: 'keystatuseschange' }); }
        """)
        return context
    }

    @Test func aRefusedLicenceIsAFailure() throws {
        let p = try page()
        func text(_ js: String) -> String { p.evaluateScript(js).toString() }
        p.evaluateScript("wait(); play(top)")
        #expect(text("sessions.length") == "1" && text("failures.length") == "0")
        p.evaluateScript("answer(sessions[0], 'refused')")
        #expect(text("failures.join()") == "https://watch.example.tv/film/42")
        #expect(text("top.__cra.drmFailed") == "true")
        // The same session refused again counts once; the page's own call still sees the refusal.
        p.evaluateScript("wait(); var seen = ''; sessions[0].update('refused').catch(e => { seen = e.message; })")
        #expect(text("seen") == "refused" && text("failures.length") == "1" && text("top.__cra.drmFailedN") == "1")
        // A licence that arrives in time and works is no failure, and neither is its timer.
        p.evaluateScript("play(top)")
        p.evaluateScript("answer(sessions[1], 'good'); tick()")
        #expect(text("failures.length") == "1")
    }

    @Test func aLicenceRequestNoOneAnswersIsAFailure() throws {
        let p = try page()
        func text(_ js: String) -> String { p.evaluateScript(js).toString() }
        p.evaluateScript("wait(); play(top)")
        #expect(text("timers.length") == "1" && text("failures.length") == "0")
        p.evaluateScript("tick()")
        #expect(text("failures.join()") == "https://watch.example.tv/film/42")
        // A session the page closed before then was given up on, not refused.
        p.evaluateScript("wait(); play(top)")
        p.evaluateScript("sessions[1].close()")
        p.evaluateScript("tick()")
        #expect(text("failures.length") == "1")
    }

    /// Shaka Player 4 (and players built on it) gets its MediaKeySystemAccess from
    /// navigator.mediaCapabilities.decodingInfo, so the watch knows the keys by the access's own
    /// keySystem, not by the request that made it. Seen on a real Widevine licence Shaka's CDM refused.
    @Test func aPlayerThatFindsWidevineThroughMediaCapabilitiesCanFail() throws {
        let p = try page()
        func text(_ js: String) -> String { p.evaluateScript(js).toString() }
        p.evaluateScript("wait(); play(top, { capabilities: true })")
        #expect(text("sessions.length") == "1")
        p.evaluateScript("answer(sessions[0], 'refused')")
        #expect(text("failures.join()") == "https://watch.example.tv/film/42")
        // Another key system found the same way is still nothing.
        p.evaluateScript("wait(); play(top, { capabilities: true, keySystem: 'com.apple.fps.1_0' })")
        p.evaluateScript("answer(sessions[1], 'refused'); tick()")
        #expect(text("failures.length") == "1")
    }

    @Test func keysThatCantPlayAreAFailure() throws {
        let p = try page()
        func text(_ js: String) -> String { p.evaluateScript(js).toString() }
        p.evaluateScript("wait(); play(top)")
        p.evaluateScript("answer(sessions[0], 'good'); statuses(sessions[0], 'output-restricted', 'usable')")
        #expect(text("failures.length") == "0", "one key plays: the film plays, perhaps in SD")
        p.evaluateScript("statuses(sessions[0], 'output-restricted', 'internal-error')")
        #expect(text("failures.length") == "1")
    }

    /// Only playback fails. Asking for Widevine (what a fingerprinting script does), keys no
    /// element plays, or another key system tell nothing.
    @Test func onlyPlaybackCanFail() throws {
        let p = try page()
        func text(_ js: String) -> String { p.evaluateScript(js).toString() }
        p.evaluateScript("wait(); top.navigator.requestMediaKeySystemAccess('com.widevine.alpha', [{}])")
        #expect(text("top.__cra.drm") == "true" && text("failures.length") == "0")
        p.evaluateScript("play(top, { attach: false })")
        p.evaluateScript("answer(sessions[0], 'refused'); tick()")
        #expect(text("failures.length") == "0")
        p.evaluateScript("play(top, { keySystem: 'com.apple.fps.1_0' }); play(top, { keySystem: 'org.w3.clearkey' })")
        p.evaluateScript("answer(sessions[1], 'refused'); answer(sessions[2], 'refused'); tick()")
        #expect(text("failures.length") == "0" && text("top.__cra.drmFailed === true") == "false")
        // A test run watches Clear Key too, to fail on purpose.
        let test = try page(keySystems: ["com.widevine", "org.w3.clearkey"])
        test.evaluateScript("wait(); play(top, { keySystem: 'org.w3.clearkey' })")
        test.evaluateScript("answer(sessions[0], 'refused')")
        #expect(test.evaluateScript("failures.length").toString() == "1")
    }

    @Test func aPlayerFramesFailureIsItsPages() throws {
        let p = try page()
        func text(_ js: String) -> String { p.evaluateScript(js).toString() }
        p.evaluateScript("wait(); play(frame)")
        p.evaluateScript("answer(sessions[0], 'refused')")
        #expect(text("frame.__cra.drmFailed") == "true" && text("top.__cra.drmFailed") == "true")
        #expect(text("failures.join()") == "https://watch.example.tv/film/42", "the page's address, not the frame's")
        // The wrapped calls keep their arity.
        #expect(text("top.Navigator.prototype.requestMediaKeySystemAccess.length") == "2")
        #expect(text("top.MediaKeySession.prototype.update.length") == "1")
    }
    #endif
}
