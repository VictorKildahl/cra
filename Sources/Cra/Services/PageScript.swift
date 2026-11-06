import Foundation

/// Scripts that run in every page before its own (CraCEFRuntime.setDocumentStartScript), so Cra
/// can read what the page itself doesn't expose. Almost all of it runs in an isolated world the
/// page can't see (Chrome extensions' content scripts work the same way); `window.__cra` exists
/// only there:
///
/// - `typed`: fields the user typed into (trusted input events only, so values a framework sets
///   don't count), with the URL they were typed on. Tab sleeping keeps such a page awake.
/// - `volume`: the sidebar player's volume drawer; media that starts playing later gets it too.
/// - `send(action)` / `handlers`: a WebKit page's media session handlers (YouTube, Spotify…), so
///   the player can skip tracks. `setActionHandler` can't be called from outside and its handlers
///   live in the page's world, so a small wrapper there (`mediaSessionWrapper`) keeps them in a
///   closure and answers an event whose name is random per launch: nothing in the page's world
///   names Cra. Chromium pages don't get it: Chromium routes their handlers itself
///   (`Cra.mediaSession`, like Arc), which also finds a handler the page registered before a
///   wrapper could be in place (the first page of a new tab).
/// - `drm`: the page asked for Widevine (navigator.requestMediaKeySystemAccess): the Site Control
///   Center then offers to play the site in Safari's engine (docs/protected-media.md). A wrapper in
///   the page's world tells this world through the same per-launch event name.
/// - `lt`: the top frame's long tasks (50 ms or more) for the performance recorder (GitHub #91):
///   a count, the total and the last 100 durations, which Cra reads and resets for the visible
///   tab every few seconds. No attribution, no addresses; the observer only runs when a long
///   task happens, so it never polls or wakes a background tab.
enum PageScript {
    static let world = "cra"
    private static let channel = "c" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

    /// The page's world in WebKit: the media session wrapper.
    static let mediaSessionWrapper = """
    (() => {
      const proto = window.MediaSession?.prototype, set = proto?.setActionHandler;
      if (!set) return;
      const handlers = {};
      Object.defineProperty(proto, 'setActionHandler', { configurable: true, writable: true,
        value: { setActionHandler(action, handler) {
          if (handler) handlers[action] = handler; else delete handlers[action];
          return set.call(this, action, handler);
        } }.setActionHandler });
      addEventListener('\(channel)', e => {
        if (e.detail === '?') return dispatchEvent(new CustomEvent('\(channel)r', { detail: Object.keys(handlers).join(',') }));
        try { handlers[e.detail]?.({ action: e.detail }); } catch {}
      });
    })();
    """

    /// The page's world, in both engines: the Widevine request wrapper.
    static let mainWorld = """
    (() => {
      const proto = window.Navigator?.prototype, request = proto?.requestMediaKeySystemAccess;
      if (!request) return;
      Object.defineProperty(proto, 'requestMediaKeySystemAccess', { configurable: true, writable: true,
        value: { requestMediaKeySystemAccess(keySystem, configs) {
          if (String(keySystem).startsWith('com.widevine')) dispatchEvent(new CustomEvent('\(channel)d'));
          return request.call(this, keySystem, configs);
        } }.requestMediaKeySystemAccess });
    })();
    """

    /// Cra's isolated world.
    static let isolatedWorld = """
    (() => {
      if (window.__cra) return;
      const cra = window.__cra = { typed: new Map(), volume: 1, handlers: [] };
      addEventListener('play', e => { if (cra.volume < 1 && e.target instanceof HTMLMediaElement) e.target.volume = cra.volume; }, true);
      addEventListener('input', e => {
        const t = e.isTrusted && e.composedPath()[0];
        if (t instanceof Element) cra.typed.set(t, location.href);
      }, true);
      addEventListener('\(channel)r', e => { cra.handlers = String(e.detail || '').split(',').filter(Boolean); });
      addEventListener('\(channel)d', () => { cra.drm = true; });
      cra.send = action => dispatchEvent(new CustomEvent('\(channel)', { detail: action }));
      cra.query = () => (cra.send('?'), cra.handlers);
      if (window.top === window) try {
        const lt = cra.lt = { n: 0, t: 0, d: [] };
        new PerformanceObserver(list => {
          for (const e of list.getEntries()) { lt.n++; lt.t += e.duration; if (lt.d.length < 100) lt.d.push(Math.round(e.duration)); }
        }).observe({ type: 'longtask' });
        const lf = cra.lf = { n: 0, max: 0 };
        new PerformanceObserver(list => {
          for (const e of list.getEntries()) { lf.n++; if (e.duration > lf.max) lf.max = Math.round(e.duration); }
        }).observe({ type: 'long-animation-frame' });
      } catch {}
    })();
    """
}
