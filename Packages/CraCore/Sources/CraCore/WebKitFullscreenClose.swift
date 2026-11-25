import Foundation

/// What a closing WebKit tab (a protected-media service's, ProtectedMediaSites) does with its page's own full
/// screen. Closed while WebKit was still taking the video into full screen, WebKit's full-screen window
/// controller went away with that entry pending, and WebKit stopped Cra on its own trap
/// (crash-webkit-tab-closed-entering-fullscreen). So the page's view stays where it is until WebKit has
/// finished: in full screen it is asked to leave, and it goes once WebKit says it is out.
public enum WebKitFullscreenClose: Equatable, Sendable {
    /// Not in full screen: close any Picture in Picture and take the view down now.
    case removeNow
    /// In full screen: ask WebKit to leave, and take the view down once it is out.
    case leave
    /// WebKit is on its way in or out: wait for it.
    case wait

    /// WKWebView.FullscreenState, without WebKit.
    public enum State: Equatable, Sendable { case out, entering, inFullscreen, exiting }

    public init(_ state: State) {
        switch state {
        case .out: self = .removeNow
        case .inFullscreen: self = .leave
        case .entering, .exiting: self = .wait
        }
    }

    /// The longest a closed tab's view waits for WebKit (its animations take under a second); after that it
    /// goes anyway, so a WebKit that never answers can't keep a closed page alive.
    public static let longestWait: TimeInterval = 5
}
