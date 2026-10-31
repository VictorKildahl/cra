import Foundation

/// Scripts that run in every page before its own (CraCEFRuntime.setDocumentStartScript), so Cra
/// can read what the page itself doesn't expose. Almost all of it runs in an isolated world the
/// page can't see (Chrome extensions' content scripts work the same way); `window.__cra` exists
/// only there:
///
/// - `typed`: fields the user typed into (trusted input events only, so values a framework sets
///   don't count), with the URL they were typed on. Tab sleeping keeps such a page awake.
/// - `volume`: the sidebar player's volume drawer; media that starts playing later gets it too.
/// - `send(action)` / `handlers`: the page's media session handlers (YouTube, Spotify…), so the
///   player can skip tracks. `setActionHandler` can't be called from outside and its handlers
///   live in the page's world, so a small wrapper there keeps them in a closure and answers an
///   event whose name is random per launch: nothing in the page's world names Cra.
enum PageScript {
    static let world = "cra"
    private static let channel = "c" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

    /// The page's world: only the media session wrapper.
    static let mainWorld = """
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
      cra.send = action => dispatchEvent(new CustomEvent('\(channel)', { detail: action }));
      cra.query = () => (cra.send('?'), cra.handlers);
    })();
    """
}
