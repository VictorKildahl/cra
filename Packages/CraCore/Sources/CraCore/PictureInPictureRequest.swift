import Foundation

/// Cra's own ask for Picture in Picture: View ▸ Picture in Picture, the sidebar player's button and
/// leaving a video tab. The ask runs in the page: it picks the page's video and requests it.
public enum PictureInPictureRequest {
    /// The engine the page runs in. They treat a video's `disablePictureInPicture` differently.
    public enum Engine: Equatable, Sendable { case chromium, webKit }

    /// Whether the ask takes a video its page made with `disablePictureInPicture`.
    ///
    /// Netflix's player makes its video that way (`disablePictureInPicture` defaults to true in
    /// its player script, cadmium-playercore 6.0065), so Cra found no video there and did
    /// nothing. WebKit doesn't hold a request to the attribute: on macOS 27 both
    /// `requestPictureInPicture()` and `webkitSetPresentationMode` open such a video, which is
    /// how Safari's own Enter Picture in Picture takes Netflix's. Arc's player works on Netflix
    /// too; its `arc::WebContents::MediaSession::PiPController` suggests it asks Chromium's media
    /// session, not the page (read from the class's name, not traced).
    ///
    /// - A WebKit page: taken, for the user's ask (View ▸ Picture in Picture, the sidebar
    ///   player's button) and as its tab is left, like any other video. The Site Control Center
    ///   still turns leaving-the-tab off for a site.
    /// - A Chromium page: never. Chromium answers a request for such a video with
    ///   InvalidStateError, so Cra doesn't ask.
    public static func takesOptedOutVideo(engine: Engine) -> Bool {
        engine == .webKit
    }

    /// The expression that looks for the page's video and, with `request`, asks it for Picture
    /// in Picture. It answers "ok" (the video is in Picture in Picture), "video" (there is one to
    /// ask; a look only), "none", or the page's refusal as "<Name>: <message>".
    ///
    /// The video: the one playing, then the largest. Leaving a tab (`automatic`) takes only a
    /// video that plays aloud at some size: muted ones are hover previews and GIF-like loops.
    ///
    /// A WebKit that does refuse an opted-out video is asked again through WebKit's own
    /// presentation mode, the call Safari's menu ends in.
    public static func script(engine: Engine, automatic: Bool, request: Bool) -> String {
        let optedOut = takesOptedOutVideo(engine: engine)
        let refused = optedOut
            ? """
            e => {
                if (v.disablePictureInPicture && v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('picture-in-picture')) {
                  v.webkitSetPresentationMode('picture-in-picture');
                  return 'ok';
                }
                return e.name + ': ' + e.message;
              }
            """
            : "e => e.name + ': ' + e.message"
        return """
        ((auto, request) => {
          if (document.pictureInPictureElement) return 'ok';
          const area = v => { const r = v.getBoundingClientRect(); return r.width * r.height; };
          const v = [...document.querySelectorAll('video')].filter(v => (\(optedOut) || !v.disablePictureInPicture) && v.readyState >= 1)
            .filter(v => !auto || (!v.paused && !v.ended && !v.muted && v.volume > 0 && v.videoWidth > 0 && area(v) >= 20000))
            .sort((a, b) => ((b.paused ? 0 : 1) - (a.paused ? 0 : 1)) || (area(b) - area(a)))[0];
          if (!v) return 'none';
          return request ? v.requestPictureInPicture().then(() => 'ok', \(refused)) : 'video';
        })(\(automatic), \(request))
        """
    }

    /// What the page answered to `script`.
    public enum Answer: Equatable, Sendable {
        /// The video is in Picture in Picture.
        case entered
        /// The page has a video to ask (a look).
        case video
        /// No video of the page's own that can be asked: none at all, or a player in a frame.
        case none
        /// The answer never came (the page went away, or its script failed).
        case lost
        /// The page said no, in its own words ("NotAllowedError: …").
        case refused(String)

        public init(_ value: String?) {
            switch value {
            case nil: self = .lost
            case "ok": self = .entered
            case "video": self = .video
            case "none": self = .none
            case let words?: self = .refused(words)
            }
        }
    }

    /// What Cra does with the page's answer.
    public enum Step: Equatable, Sendable {
        /// Nothing more: the video is out.
        case done
        /// The page has a video: ask it, as a user gesture.
        case request
        /// The engine's request in every frame, for a player in an iframe. A WebKit page has no
        /// such request, so there the ask ends, and an ask of the user's is logged.
        case frames
        /// The page said no: logged.
        case report(String)
    }

    public static func step(after answer: Answer) -> Step {
        switch answer {
        case .entered: .done
        case .video: .request
        case .none, .lost: .frames
        case .refused(let words): .report(words)
        }
    }

    /// The log's line (after "tab <id> ") for an ask that opened nothing, nil when there is
    /// nothing to say: leaving a tab without a video is every tab switch.
    public static func logLine(_ answer: Answer, automatic: Bool) -> String? {
        switch answer {
        case .entered, .video: nil
        case .none: automatic ? nil : "has no video for Picture in Picture"
        case .lost: automatic ? nil : "did not answer the Picture in Picture request"
        case .refused(let words): "refuses Picture in Picture: \(words)"
        }
    }
}
