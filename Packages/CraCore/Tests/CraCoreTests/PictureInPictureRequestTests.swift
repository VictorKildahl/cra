import Testing
import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif
@testable import CraCore

/// Cra's own ask for Picture in Picture on a page whose player said no (`disablePictureInPicture`):
/// Netflix's does, so its video never opened (WebKit pages, GitHub #585).
@Suite struct PictureInPictureRequestTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/585"))
    func optedOutVideoIsTakenOnWebKitOnly() {
        // Safari's Enter Picture in Picture takes it too, and WebKit opens it.
        #expect(PictureInPictureRequest.takesOptedOutVideo(engine: .webKit))
        // Chromium answers such a request with InvalidStateError, so it isn't made.
        #expect(!PictureInPictureRequest.takesOptedOutVideo(engine: .chromium))
    }

    @Test func answersAsThePageGaveThem() {
        #expect(PictureInPictureRequest.Answer("ok") == .entered)
        #expect(PictureInPictureRequest.Answer("video") == .video)
        #expect(PictureInPictureRequest.Answer("none") == PictureInPictureRequest.Answer.none)
        #expect(PictureInPictureRequest.Answer(nil) == .lost)
        #expect(PictureInPictureRequest.Answer("NotAllowedError: denied") == .refused("NotAllowedError: denied"))
    }

    @Test func stepsAfterAnAnswer() {
        #expect(PictureInPictureRequest.step(after: .entered) == .done)
        // Only a page with a video is asked as a user gesture (#357).
        #expect(PictureInPictureRequest.step(after: .video) == .request)
        // A player in an iframe: the engine's request in every frame.
        #expect(PictureInPictureRequest.step(after: .none) == .frames)
        #expect(PictureInPictureRequest.step(after: .lost) == .frames)
        #expect(PictureInPictureRequest.step(after: .refused("NotAllowedError: denied")) == .report("NotAllowedError: denied"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/585"))
    func anAskThatOpensNothingSaysWhy() {
        // The user's ask on Netflix did nothing and the log had no line of it.
        #expect(PictureInPictureRequest.logLine(.none, automatic: false) == "has no video for Picture in Picture")
        #expect(PictureInPictureRequest.logLine(.lost, automatic: false) == "did not answer the Picture in Picture request")
        #expect(PictureInPictureRequest.logLine(.refused("InvalidStateError: no"), automatic: true) == "refuses Picture in Picture: InvalidStateError: no")
        // Leaving a tab without a video is every tab switch: nothing to say.
        #expect(PictureInPictureRequest.logLine(.none, automatic: true) == nil)
        #expect(PictureInPictureRequest.logLine(.lost, automatic: true) == nil)
        #expect(PictureInPictureRequest.logLine(.entered, automatic: false) == nil)
        #expect(PictureInPictureRequest.logLine(.video, automatic: false) == nil)
    }

    #if canImport(JavaScriptCore)
    /// A page with these videos (JavaScript object literals), and what `script` answers there.
    /// `asked` then holds what each video was asked: "std" (requestPictureInPicture) or "webkit"
    /// (webkitSetPresentationMode).
    private func run(_ script: String, videos: String, inPictureInPicture: Bool = false) -> (answer: String, asked: String) {
        let context = JSContext()!
        context.evaluateScript("""
        var asked = [], answer = 'pending';
        const video = o => Object.assign({
          disablePictureInPicture: false, readyState: 4, paused: false, ended: false, muted: false, volume: 1, videoWidth: 1920,
          width: 1280, height: 720, refuses: null, webkit: true,
          getBoundingClientRect() { return { width: this.width, height: this.height }; },
          requestPictureInPicture() {
            asked.push('std:' + this.name);
            return this.refuses ? Promise.reject({ name: this.refuses, message: 'no' }) : Promise.resolve({});
          },
          webkitSupportsPresentationMode(mode) { return this.webkit && mode === 'picture-in-picture'; },
          webkitSetPresentationMode(mode) { asked.push('webkit:' + this.name + ':' + mode); },
        }, o);
        const videos = (\(videos)).map(video);
        var document = { pictureInPictureElement: \(inPictureInPicture ? "videos[0]" : "null"), querySelectorAll: () => videos };
        """)
        context.evaluateScript("Promise.resolve(\(script)).then(v => { answer = v; });")
        return (context.evaluateScript("answer").toString(), context.evaluateScript("asked.join()").toString())
    }

    /// Netflix's video: playing aloud, full size, made with `disablePictureInPicture`.
    private let netflix = "[{ name: 'film', disablePictureInPicture: true }]"

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/585"))
    func optedOutVideoIsFoundAndAskedOnAWebKitPage() {
        let look = PictureInPictureRequest.script(engine: .webKit, automatic: false, request: false)
        #expect(run(look, videos: netflix) == ("video", ""))
        let ask = PictureInPictureRequest.script(engine: .webKit, automatic: false, request: true)
        #expect(run(ask, videos: netflix) == ("ok", "std:film"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/585"))
    func aWebKitThatRefusesAnOptedOutVideoIsAskedItsOwnWay() {
        // The standard request held to the attribute: WebKit's presentation mode, as Safari's menu.
        let ask = PictureInPictureRequest.script(engine: .webKit, automatic: false, request: true)
        #expect(run(ask, videos: "[{ name: 'film', disablePictureInPicture: true, refuses: 'InvalidStateError' }]")
                == ("ok", "std:film,webkit:film:picture-in-picture"))
        // A video the page didn't opt out keeps its refusal: that is another matter (no gesture, no track).
        #expect(run(ask, videos: "[{ name: 'film', refuses: 'NotAllowedError' }]") == ("NotAllowedError: no", "std:film"))
        // No presentation mode to fall back on: the refusal stands.
        #expect(run(ask, videos: "[{ name: 'film', disablePictureInPicture: true, refuses: 'InvalidStateError', webkit: false }]")
                == ("InvalidStateError: no", "std:film"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/585"))
    func leavingAWebKitTabTakesAnOptedOutVideo() {
        // Netflix's film, playing aloud as its tab is left: out it goes, as any other video.
        #expect(run(PictureInPictureRequest.script(engine: .webKit, automatic: true, request: false), videos: netflix) == ("video", ""))
        #expect(run(PictureInPictureRequest.script(engine: .webKit, automatic: true, request: true), videos: netflix) == ("ok", "std:film"))
        // Still only one that plays aloud: a muted preview stays in its page.
        #expect(run(PictureInPictureRequest.script(engine: .webKit, automatic: true, request: false),
                    videos: "[{ name: 'preview', disablePictureInPicture: true, muted: true }]") == ("none", ""))
    }

    @Test func optedOutVideoIsLeftAloneOnAChromiumPage() {
        // Chromium would refuse it, so it isn't a video to ask.
        for automatic in [false, true] {
            for request in [false, true] {
                #expect(run(PictureInPictureRequest.script(engine: .chromium, automatic: automatic, request: request), videos: netflix) == ("none", ""))
            }
        }
    }

    @Test func picksThePlayingThenTheLargestVideo() {
        for engine in [PictureInPictureRequest.Engine.chromium, .webKit] {
            let ask = PictureInPictureRequest.script(engine: engine, automatic: false, request: true)
            let videos = "[{ name: 'paused', paused: true, width: 1920, height: 1080 }, { name: 'small', width: 320, height: 180 }, { name: 'large' }]"
            #expect(run(ask, videos: videos) == ("ok", "std:large"), "\(engine)")
            #expect(run(ask, videos: "[{ name: 'unloaded', readyState: 0 }]") == ("none", ""), "\(engine)")
            #expect(run(ask, videos: "[]") == ("none", ""), "\(engine)")
            // Already out: nothing is asked again.
            #expect(run(ask, videos: "[{ name: 'film' }]", inPictureInPicture: true) == ("ok", ""), "\(engine)")
        }
    }

    @Test func leavingATabTakesOnlyAVideoPlayingAloud() {
        for engine in [PictureInPictureRequest.Engine.chromium, .webKit] {
            let look = PictureInPictureRequest.script(engine: engine, automatic: true, request: false)
            #expect(run(look, videos: "[{ name: 'film' }]") == ("video", ""), "\(engine)")
            for quiet in ["muted: true", "volume: 0", "paused: true", "ended: true", "videoWidth: 0", "width: 160, height: 90"] {
                #expect(run(look, videos: "[{ name: 'preview', \(quiet) }]") == ("none", ""), "\(engine) \(quiet)")
            }
        }
    }
    #endif
}
