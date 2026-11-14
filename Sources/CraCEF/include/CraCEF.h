// CraCEF: the Objective-C surface Swift uses to drive Chromium. Two engines implement it: CEF
// (CraCEF.mm) and Chrome's own framework (engine/chromium/cra/bridge, docs/chromium-engine.md).
// Everything here runs on the main thread.
#import <Cocoa/Cocoa.h>

// The classes are exported from Chrome's framework, which hides everything else.
#define CRA_EXPORT __attribute__((visibility("default")))
// Chrome's framework needs NSApp to be its BrowserCrApplication; CEF only needs an NSApplication.
#ifndef CRA_APPLICATION_SUPERCLASS
#define CRA_APPLICATION_SUPERCLASS NSApplication
#endif

NS_ASSUME_NONNULL_BEGIN

@class CraBrowser;

typedef NS_ENUM(NSInteger, CraDownloadState) {
    CraDownloadStateInProgress = 0,
    CraDownloadStateComplete = 1,
    CraDownloadStateCancelled = 2,
    CraDownloadStateInterrupted = 3,
};

/// What a download's menu asks of it (GitHub #272).
typedef NS_ENUM(NSInteger, CraDownloadControl) {
    CraDownloadControlPause = 0,
    CraDownloadControlResume = 1,
    CraDownloadControlCancel = 2,
};

/// Where a page's context menu opens a link that isn't for a tab.
typedef NS_ENUM(NSInteger, CraLinkWindow) {
    CraLinkWindowNew = 0,
    CraLinkWindowIncognito = 1,
    CraLinkWindowLittle = 2,
};

/// Chromium's own strings that Cra's page menus use (GitHub #276).
typedef NS_ENUM(NSInteger, CraChromiumString) {
    /// "Open Link in New &Tab"
    CraChromiumStringOpenLinkInNewTab = 0,
    /// Google Lens's "Search Image with $1"
    CraChromiumStringSearchLensForImage = 1,
    /// Chrome's own "&Search $1 for Image"
    CraChromiumStringSearchWebForImage = 2,
};

/// The page's media session as Chromium reports it (MediaSessionInfo's state, #411).
typedef NS_ENUM(NSInteger, CraMediaSessionState) {
    /// No media holds audio focus: nothing plays, or what played ended or left the page.
    CraMediaSessionStateInactive = 0,
    CraMediaSessionStateActive = 1,
    /// Playing, quieter while another app's sound has the focus for a moment.
    CraMediaSessionStateDucking = 2,
    /// Paused, still holding the focus.
    CraMediaSessionStateSuspended = 3,
};

CRA_EXPORT @interface CraDownloadInfo : NSObject
@property (nonatomic) uint32_t identifier;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, copy) NSString *suggestedName;
@property (nonatomic) int64_t receivedBytes;
@property (nonatomic) int64_t totalBytes;
@property (nonatomic) NSInteger percent;
@property (nonatomic) CraDownloadState state;
/// In progress but paused (Chromium's IsPaused); `state` stays in progress.
@property (nonatomic) BOOL paused;
@end

/// The connection of the page on screen (Chromium's SSL status of the visible navigation entry).
CRA_EXPORT @interface CraSSLStatus : NSObject
/// The page came over a connection with a certificate (https, whatever the certificate's errors).
@property (nonatomic) BOOL secureConnection;
/// net::CertStatus bits: the certificate's errors and notes.
@property (nonatomic) NSUInteger certStatus;
/// net::SSLStatus::ContentStatus bits: http content the page showed or ran.
@property (nonatomic) NSUInteger contentStatus;
/// The server's certificate, then its issuers, DER encoded; empty without a certificate.
@property (nonatomic, copy) NSArray<NSData *> *certificates;
@end

@protocol CraBrowserDelegate <NSObject>
- (void)browser:(CraBrowser *)browser didChangeTitle:(NSString *)title;
- (void)browser:(CraBrowser *)browser didChangeURL:(NSString *)url;
- (void)browser:(CraBrowser *)browser didChangeLoading:(BOOL)loading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
- (void)browser:(CraBrowser *)browser didChangeProgress:(double)progress;
- (void)browser:(CraBrowser *)browser didFinishLoadingURL:(NSString *)url title:(NSString *)title statusCode:(NSInteger)statusCode;
- (void)browser:(CraBrowser *)browser didLoadFavicon:(NSImage *)image forURL:(NSString *)iconURL;
- (void)browser:(CraBrowser *)browser didChangeStatusMessage:(NSString *)message;
/// The page's theme colour (meta theme-color or body background) as "#RRGGBB", or "" when unknown.
- (void)browser:(CraBrowser *)browser didReportThemeColor:(NSString *)hex;
- (void)browser:(CraBrowser *)browser didChangeFullscreen:(BOOL)fullscreen;
/// Cmd-click, middle-click and similar: open a plain new tab.
- (void)browser:(CraBrowser *)browser requestsNewTabWithURL:(NSString *)url inBackground:(BOOL)background;
/// window.open / target=_blank: return a popup host (a CraBrowser created with
/// a nil URL) so the popup keeps its opener relationship, or nil to block it.
- (nullable CraBrowser *)browser:(CraBrowser *)browser popupHostForURL:(NSString *)url inBackground:(BOOL)background;
/// Return a view to host DevTools in (Cra docks it inside the content card);
/// nil makes CEF open its own DevTools window.
- (nullable NSView *)devToolsHostViewForBrowser:(CraBrowser *)browser;
/// DevTools was created for docking (a host view was returned): `view.window`
/// is CEF's hidden Alloy window, to be attached as a child window.
- (void)browser:(CraBrowser *)browser didCreateDevToolsView:(NSView *)view;
/// The DevTools browser closed (either mode).
- (void)browserDidCloseDevTools:(CraBrowser *)browser;
/// Chrome-style hosting: the page's window exists (also for popups).
- (void)browser:(CraBrowser *)browser didCreateHostWindow:(NSWindow *)window;
/// Chrome's docked DevTools frontend placed the page: `bounds` are points with a
/// top-left origin inside the DevTools window's content view (setInspectedPageBounds).
- (void)browser:(CraBrowser *)browser devToolsPageBounds:(NSRect)bounds;
/// Chrome's DevTools frontend docked (YES) or undocked into its own window (NO).
- (void)browser:(CraBrowser *)browser devToolsDocked:(BOOL)docked;
/// Reserved shortcuts, before the page sees the key. Return YES to consume.
- (BOOL)browser:(CraBrowser *)browser handleKeyEvent:(NSEvent *)event;
/// Keys the page did not handle (Chrome gives the page first chance at
/// unreserved shortcuts like ⌘F). Return YES to consume.
- (BOOL)browser:(CraBrowser *)browser handleUnhandledKeyEvent:(NSEvent *)event;
- (void)browser:(CraBrowser *)browser didUpdateDownload:(CraDownloadInfo *)download;
/// Ask the user. `kinds` is a bitmask: 1 = camera, 2 = microphone,
/// 4 = location, 8 = notifications, 16 = a type CraCEF has no bit for, and from
/// 1 << 5 Chrome's other types (kPermissionKinds in CraCEF.mm, worded by CraCore's
/// PermissionPrompt).
- (void)browser:(CraBrowser *)browser requestsPermissionForOrigin:(NSString *)origin kinds:(NSUInteger)kinds completion:(void (^)(BOOL allowed))completion;
- (void)browserDidReceiveFocus:(CraBrowser *)browser;
- (void)browserDidClose:(CraBrowser *)browser;
@optional
/// The page's context menu: Open Link in New Window, Little Window or Incognito Window.
- (void)browser:(CraBrowser *)browser requestsWindowWithURL:(NSString *)url kind:(CraLinkWindow)kind;
/// The page's context menu: Open Link in Split View, a pane beside this page (#257). Without it
/// the menu has no such item (a Little Window's page).
- (void)browser:(CraBrowser *)browser requestsSplitPaneWithURL:(NSString *)url;
/// Chromium wants to download `url` for this page. `clickModifiers` (AppKit's flags) and
/// `clickAge` (seconds since) are the page's last click, or Return in it; `clickAge` is negative
/// when there was none. Return YES when that was an Option-click on a link, which Chromium makes
/// a download and Arc opens in Split View (#298): the download doesn't start, and the delegate
/// opens the pane once Chromium's call has returned.
- (BOOL)browser:(CraBrowser *)browser opensSplitForDownloadURL:(NSString *)url
  clickModifiers:(NSUInteger)clickModifiers clickAge:(NSTimeInterval)clickAge;
/// The page's context menu on an image: Capture Image… at `point` (page points from the top
/// left). Without it the menu has no such item.
- (void)browser:(CraBrowser *)browser requestsCaptureOfImageAt:(NSPoint)point;
/// A video of this page entered or left Chromium's Picture in Picture window
/// (whether the page, the user or Cra asked for it).
- (void)browser:(CraBrowser *)browser didChangePictureInPicture:(BOOL)active;
/// The video in the Picture in Picture window started or stopped playing.
- (void)browser:(CraBrowser *)browser didChangePictureInPicturePlayback:(BOOL)playing;
/// Where the video in the Picture in Picture window is, in seconds, and how long it is
/// (0 for a stream with no end). Sent as the video plays and after a seek.
- (void)browser:(CraBrowser *)browser didChangePictureInPictureTime:(double)position duration:(double)duration;
/// The colour the page paints behind its content (root/body background, else the
/// canvas colour of its color scheme), as "#RRGGBB"; "" when a new page starts loading
/// and has not reported one yet (show +[CraBrowser pageCanvasColor] then). The shell fills
/// the area under the page window with it, so a page lagging behind a resize shows no white edge.
- (void)browser:(CraBrowser *)browser didReportBackgroundColor:(NSString *)hex;
/// Find in page progress: `count` matches, `activeMatch` is the highlighted one
/// (1-based). Either is -1 while Chromium has no new value for it.
- (void)browser:(CraBrowser *)browser didFindMatches:(NSInteger)count activeMatch:(NSInteger)activeMatch;
/// The page started or stopped using the camera or microphone.
- (void)browser:(CraBrowser *)browser didChangeMediaCapture:(BOOL)capturing;
/// Chromium dropped the page's permission request before Cra answered it (the page navigated or
/// closed, or a newer request replaced it): its sheet should go, and its completion does nothing.
- (void)browserWithdrewPermissionRequest:(CraBrowser *)browser;
/// A page made with a saved history (-initWithFrame:…history:): `count` entries went in, or
/// `error` says why none did and the page loaded its address instead.
- (void)browser:(CraBrowser *)browser didRestoreHistoryEntries:(NSInteger)count error:(nullable NSString *)error;
/// The page started or stopped playing sound (see `isAudible`).
- (void)browser:(CraBrowser *)browser didChangeAudible:(BOOL)audible;
/// The page's media session changed (#411): its state, and whether Chrome's global media controls
/// offer it (`controllable`: media over 5 s or of unknown length, or a page media session with a
/// playbackState; never a ding alone or Web Audio). Only an engine whose `reportsMediaSession` is YES
/// sends it; the sidebar player follows it then instead of the audible state.
- (void)browser:(CraBrowser *)browser didChangeMediaSessionState:(CraMediaSessionState)state controllable:(BOOL)controllable
    NS_SWIFT_NAME(browser(_:didChangeMediaSessionState:controllable:));
/// The page's sound started or stopped as it happened, before the 2 s that `isAudible` and
/// `browser:didChangeAudible:` hold a quiet page audible.
- (void)browser:(CraBrowser *)browser didChangeSoundPlaying:(BOOL)playing;
/// Chrome's bars over the page changed (`infoBars`): "<extension> started debugging this browser" and the other
/// yes/no bars Chrome shows in a tab. Only the Chromium engine reports them; on CEF Chrome draws its own.
- (void)browser:(CraBrowser *)browser didChangeInfoBars:(NSArray<NSDictionary<NSString *, id> *> *)infoBars;
/// `hasCommittedLoad` changed: the main frame committed, or a new navigation started.
- (void)browser:(CraBrowser *)browser didChangeCommittedLoad:(BOOL)committed;
/// The page's main-frame load failed with a net error (ERR_ABORTED, a navigation cut off,
/// is left out): `url` is the address that failed.
- (void)browser:(CraBrowser *)browser didFailLoadingURL:(NSString *)url errorCode:(NSInteger)errorCode;
/// An extension asked to bring this page's tab to the front (chrome.tabs.update with
/// active: true; scripts/cef-patches/extension-tab-activate.patch), or with byPage the page
/// did (window.focus(), or clients.focus() from a notification click; page-activate.patch).
- (void)browserRequestsActivation:(CraBrowser *)browser byPage:(BOOL)byPage;
/// The page's translate state changed, as JSON (CraCore's PageTranslation; GitHub #310,
/// scripts/cef-patches/translate-ui.patch). Chromium shows no translate bubble of its own for
/// Cra's pages: Cra draws Arc's button, popover and toasts from this.
- (void)browser:(CraBrowser *)browser didChangeTranslateState:(NSString *)state;
/// The pop-ups Chromium's pop-up blocker holds back on the page changed: one was blocked, or the
/// list was cleared by a navigation (scripts/cef-patches/blocked-popups.patch). `ids` and `urls`
/// pair up, oldest first; both are empty when nothing is blocked (CraCore's BlockedPopups).
- (void)browser:(CraBrowser *)browser didChangeBlockedPopups:(NSArray<NSNumber *> *)ids urls:(NSArray<NSString *> *)urls;
/// Arc's Peek: a link the user clicked (`shiftClick` NO: before it navigates the page or
/// opens as a target=_blank tab) or Shift-clicked (YES, instead of a new window). Return
/// YES to show it in a Peek; the page then stays where it is.
- (BOOL)browser:(CraBrowser *)browser opensPeekForURL:(NSString *)url shiftClick:(BOOL)shiftClick newTab:(BOOL)newTab;
/// Arc's "Open Little Arc when clicking on links with ⌥⌘ held": a link the user clicked asks for Chromium's
/// split view or a background tab. `clickModifiers` (AppKit's flags) and `clickAge` (seconds, -1 when none)
/// are the page's last click or Return, as for a download. Return YES to show it in a Little Window; the page
/// then stays where it is.
- (BOOL)browser:(CraBrowser *)browser opensLittleWindowForURL:(NSString *)url
  clickModifiers:(NSUInteger)clickModifiers clickAge:(NSTimeInterval)clickAge;
/// A main-frame navigation (a link, a redirect, history, an address Cra loaded) before its request
/// goes out; `method` is its HTTP method. Return YES to cancel it here because Cra shows `url` in
/// another engine (ProtectedMediaSites: WebKit for DRM services). Called on the main thread from
/// inside Chromium: don't close the browser before returning.
- (BOOL)browser:(CraBrowser *)browser handsOffNavigationToURL:(NSString *)url method:(NSString *)method;
/// The DevTools frontend shows `panel` ("elements", "console", "network", …): on load, and
/// on every switch, from Cra or the frontend's own tab bar.
- (void)browser:(CraBrowser *)browser devToolsShowsPanel:(NSString *)panel;
@end

CRA_EXPORT @interface CraBrowser : NSObject
@property (nonatomic, weak, nullable) id<CraBrowserDelegate> delegate;
/// Embedded (Alloy) hosting: a plain NSView that owns the Chromium view. Put
/// it in your hierarchy and size it; Chromium follows.
@property (nonatomic, readonly) NSView *containerView;
/// Chrome-style hosting (see +[CraCEFRuntime setChromeHosting:]): the page
/// lives in its own frameless Chrome window, delivered through
/// -browser:didCreateHostWindow:. Attach it as a child window and size it.
@property (nonatomic, readonly, nullable) NSWindow *hostWindow;
@property (nonatomic, readonly, copy) NSString *currentURL;
@property (nonatomic, readonly, copy) NSString *currentTitle;
@property (nonatomic, readonly) BOOL isLoading;
/// NO from the start of a main-frame navigation until it commits (the server answered and the
/// new page began to load), YES after.
@property (nonatomic, readonly) BOOL hasCommittedLoad;
/// The address the main frame is navigating to, redirects followed (OnBeforeBrowse); what a
/// page still waiting for its answer is waiting for (GitHub #256). nil before the first.
@property (nonatomic, readonly, copy, nullable) NSString *navigatingURL;
/// Main-frame navigations started (not redirects): another one restarts a wait.
@property (nonatomic, readonly) NSInteger navigationStarts;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
@property (nonatomic, readonly) BOOL isCreated;
@property (nonatomic, readonly) BOOL isClosed;
/// YES once the page closed itself (window.close()) rather than through -close.
@property (nonatomic, readonly) BOOL closedByPage;
@property (nonatomic, readonly) BOOL hasDevTools;
/// Chromium's window for this page's DevTools frontend while they are open, wherever Cra put it
/// (docked over the page area, or a window of its own); nil when closed.
@property (nonatomic, readonly, nullable) NSWindow *devToolsWindow;
/// Anything you want to hang on the browser (Swift stores the tab id).
@property (nonatomic, strong, nullable) id userInfo;
/// Runs in the shared off-the-record profile (+[CraCEFRuntime endIncognitoSession]).
@property (nonatomic, readonly) BOOL isIncognito;
/// Windowless agent page. Shares a normal profile, never creates an AppKit window.
@property (nonatomic, readonly) BOOL isAgent;
- (instancetype)initAgentWithURL:(NSString *)url profilePath:(nullable NSString *)profilePath NS_SWIFT_NAME(init(agentURL:profilePath:));
/// Last native HTML drag payload from DevTools interception. Cleared by each MCP drag.
@property (nonatomic, copy, nullable) NSString *interceptedDragData;
/// DevTools protocol events of this browser's own session (method, params JSON), on the main
/// thread. Set while an MCP client works in the page; nil otherwise, so nothing is encoded.
@property (nonatomic, copy, nullable) void (^devToolsEventHandler)(NSString *method, NSString *params);
/// While set, a context menu the page asks for is cancelled instead of shown: an MCP client's
/// right-click reaches the page (contextmenu event) without a native menu over the user's screen.
@property (nonatomic) BOOL suppressesContextMenu;
/// Explicit download in an agent tab. Site-initiated downloads are blocked in agent tabs.
- (BOOL)startAgentDownload:(NSString *)url path:(NSString *)path update:(void (^)(CraDownloadInfo *))update;
- (void)cancelAgentDownload;
@property (nonatomic, readonly) BOOL agentDownloadReady;
/// The profile folder this page's cookies, logins and storage live in (a space's own
/// profile, under the cache root), or nil for the Default profile.
@property (nonatomic, readonly, copy, nullable) NSString *profilePath;

/// Pass a URL to create a browser now. Pass nil to create a popup host that
/// adopts the next popup CEF gives it (see -browser:popupHostForURL:...).
- (instancetype)initWithFrame:(NSRect)frame url:(nullable NSString *)url delegate:(nullable id<CraBrowserDelegate>)delegate;
- (instancetype)initWithFrame:(NSRect)frame url:(nullable NSString *)url delegate:(nullable id<CraBrowserDelegate>)delegate
                    incognito:(BOOL)incognito;
- (instancetype)initWithFrame:(NSRect)frame url:(nullable NSString *)url delegate:(nullable id<CraBrowserDelegate>)delegate
                    incognito:(BOOL)incognito profilePath:(nullable NSString *)profilePath;
/// An extension's side panel page (`url`). Chromium counts every page Cra hosts as a tab; this
/// one is marked as a side panel (Cra.extensionSidePanel, scripts/cef-patches) before it loads,
/// so that, as in Chrome, it has no tab: no `sender.tab` on its messages, `tabs.getCurrent()`
/// gives undefined, and `runtime.getContexts()` lists it as SIDE_PANEL (GitHub #265).
- (instancetype)initWithFrame:(NSRect)frame extensionSidePanelURL:(NSString *)url
                     delegate:(nullable id<CraBrowserDelegate>)delegate profilePath:(nullable NSString *)profilePath;
/// A page that opens with a saved back and forward list (GitHub #273): `history` is what
/// Cra.getHistory returned ({"history": base64, "index": n}). The page is made without an
/// address, the list goes in before anything loads, and the current entry loads; if the list
/// can't go in (an older engine, a damaged file) `url` loads instead.
- (instancetype)initWithFrame:(NSRect)frame url:(NSString *)url delegate:(nullable id<CraBrowserDelegate>)delegate
                    incognito:(BOOL)incognito profilePath:(nullable NSString *)profilePath
                      history:(nullable NSDictionary<NSString *, id> *)history;
/// A page made ahead for the next tab that needs one (SparePages): Chromium makes the page and its
/// window now, when nothing waits on it, with no address and no delegate; the window stays hidden and
/// extensions don't see it as a tab (Cra.setSpare, spare-pages.patch). -takeSpareWithURL:history:
/// gives it its address, after the caller has set the delegate.
- (instancetype)initSpareWithFrame:(NSRect)frame profilePath:(nullable NSString *)profilePath;
@property (nonatomic, readonly) BOOL isSpare;
/// A spare page becomes a tab's page: it loads `url`, or the saved back and forward list `history`
/// (as -initWithFrame:…history: takes it) with `url` as its current entry.
- (void)takeSpareWithURL:(NSString *)url history:(nullable NSDictionary<NSString *, id> *)history;

- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
/// Chrome's pop-up setting for the page's site: YES once pop-ups are always allowed there.
@property (nonatomic, readonly) BOOL popupsAllowed;
/// Always allows pop-ups on the page's site (Chrome's site setting), or goes back to blocking.
- (void)setPopupsAllowed:(BOOL)allowed;
- (void)reloadIgnoringCache;
- (void)stopLoading;
/// Leaves element fullscreen (a video), as Esc does.
- (void)exitFullscreen;
- (void)setFocused:(BOOL)focused;
/// Chrome's bars over the page, top first: `id` (NSNumber), `message`, `ok` and `cancel` (button titles, when the
/// bar has them), `link` (its link's title, when it has one) and `closeable` (an NSNumber: it has a ✕). Empty on
/// CEF, which draws Chrome's own.
@property (nonatomic, readonly) NSArray<NSDictionary<NSString *, id> *> *infoBars;
/// A press on a bar of `infoBars`: "ok", "cancel", "link" or "close".
- (void)infoBar:(NSInteger)identifier action:(NSString *)action;
- (void)showDevToolsInspectingPoint:(NSPoint)point;
- (void)showDevTools;
/// What the next -showDevTools asks of the frontend, as Chrome's DevToolsToggleAction does: a
/// panel to select ("console", "network", "elements"), or "inspect" for the element picker. Done
/// once the frontend is up (at once when DevTools are already open), then cleared.
@property (nonatomic, copy, nullable) NSString *devToolsAction;
/// Does devToolsAction in DevTools already open, without showing them again; a frontend
/// still loading does it once up.
- (void)applyDevToolsAction;
- (void)closeDevTools;
- (double)zoomLevel;
- (void)setZoomLevel:(double)level;
- (void)findText:(NSString *)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext;
- (void)stopFinding:(BOOL)clearSelection;
/// Mutes the page, also one Chromium hasn't made yet: it starts muted (#387).
- (void)setAudioMuted:(BOOL)muted;
/// Whether Chromium has the page muted (CefBrowserHost::IsAudioMuted), NO before it made it.
- (BOOL)isAudioMuted;
/// Pops the page's video out into Chromium's floating Picture in Picture
/// window. Manual requests toggle (a second call brings the video back).
/// `automatic` is the "leaving a video tab" case: only a playing video of some
/// size qualifies, and nothing happens when there is none.
- (void)requestPictureInPictureAutomatic:(BOOL)automatic NS_SWIFT_NAME(requestPictureInPicture(automatic:));
- (void)exitPictureInPicture;
/// Picture in Picture's close button: the video pauses and goes back to the page, as in Arc
/// and Chrome (back to tab and returning to the tab keep it playing).
- (void)closePictureInPicture;
/// YES while a video of this page is in the Picture in Picture window.
@property (nonatomic, readonly) BOOL isInPictureInPicture;
/// YES while that video is playing.
@property (nonatomic, readonly) BOOL isPictureInPicturePlaying;
/// The page is using the camera or microphone, as Chrome's tab recording indicator counts it.
@property (nonatomic, readonly) BOOL isCapturingMedia;
/// The page is playing sound, in any frame (Chromium's audible state). Like Chrome's tab
/// speaker it stays YES for 2 s after the page goes quiet. Muting the tab doesn't change it.
@property (nonatomic, readonly) BOOL isAudible;
/// The sound that last started or stopped is one Chrome's global media controls leave out
/// (Chromium's media session isn't controllable): a sound under 5 s, such as a notification
/// ding, or Web Audio alone. The sidebar player makes no card for it, as Arc (#411).
@property (nonatomic, readonly) BOOL hasUncontrollableSound;
/// The engine sends `browser:didChangeMediaSessionState:controllable:` (Chrome's framework does,
/// CEF and WebKit pages don't).
@property (nonatomic, readonly) BOOL reportsMediaSession;
/// Play/pause the video in the Picture in Picture window.
- (void)togglePictureInPicturePlayback;
/// Seek the video in the Picture in Picture window by `seconds` (negative = back).
- (void)skipPictureInPictureBy:(double)seconds NS_SWIFT_NAME(skipPictureInPicture(by:));
/// Seek the video in the Picture in Picture window to `seconds` from its start.
- (void)seekPictureInPictureTo:(double)seconds NS_SWIFT_NAME(seekPictureInPicture(to:));
- (void)print;
/// One of Chrome's own commands by its IDC name ("IDC_ROUTE_MEDIA" for Cast…, "IDC_TASK_MANAGER"),
/// where Chromium can run it for this page. NO when it can't.
- (BOOL)runChromeCommand:(NSString *)name NS_SWIFT_NAME(runChromeCommand(_:));
- (void)executeJavaScript:(NSString *)script;
/// Asks the page for its background colour again (-browser:didReportBackgroundColor:);
/// pages can switch themes without a load.
- (void)probeBackgroundColor;
/// What the page area shows before a page reports its background: Arc's black while
/// websites are dark, white while they are light.
@property (class, nonatomic, readonly) NSColor *pageCanvasColor;
/// Runs script in this browser's DevTools frontend, if open (debug aid behind cra://debug?devtoolsjs=).
- (void)executeJavaScript:(NSString *)script inDevTools:(BOOL)inDevTools;
/// Runtime.evaluate (`params` without a context) in the main frame's isolated world `world`,
/// where the isolated document start script runs.
- (void)evaluateInIsolatedWorld:(NSString *)world params:(NSString *)params
                     completion:(void (^)(NSString * _Nullable result, NSString * _Nullable error))completion;
/// Chrome DevTools Protocol call on this browser's own session (no DevTools window).
/// `params` is a JSON object string; the completion gets the result JSON or an error.
- (void)sendDevToolsMethod:(NSString *)method params:(NSString *)params
                completion:(void (^)(NSString * _Nullable result, NSString * _Nullable error))completion;
/// The page on screen's connection; nil before anything has committed.
- (nullable CraSSLStatus *)sslStatus;
- (void)notifyMoveOrResizeStarted;
/// Asynchronous. -browserDidClose: fires when Chromium is done.
- (void)close;
@end

CRA_EXPORT @interface CraCEFRuntime : NSObject
/// Call once, after NSApplication exists, before creating browsers.
/// Experiment: a Chrome-style (extension-capable) Views window; the handler gets its NSWindow.
+ (void)spikeChromeWindowWithURL:(NSString *)url handler:(void (^)(NSWindow *))handler;
/// Host pages as Chrome-style windows (Chrome extensions, Chrome's docked
/// DevTools) instead of embedded Alloy views. Set before any browser exists.
+ (void)setChromeHosting:(BOOL)enabled;
+ (BOOL)chromeHosting;
/// The "Open Link in New Tab" item at the top of a page's context menu: its title and whether it
/// opens its tab in the background. Read when a menu opens.
+ (void)setLinkMenuTitle:(NSString *)title opensInBackground:(BOOL)background;
/// One of Chromium's strings in the language Chromium runs in, as its resource bundle has it
/// (`$1` where a name goes, `&` before a mnemonic); nil before CEF is up.
+ (nullable NSString *)chromiumString:(CraChromiumString)string;
/// Gets the Google Lens item's title when an image's menu opens (main thread) and gives the title
/// of the image search item that replaces it, or nil to keep Chromium's item.
+ (void)setImageSearchTitle:(NSString *_Nullable (^)(NSString *lensTitle))block;
/// Run in every frame of every page browser before the page's own scripts (and once in the
/// document already loaded): `script` in the page's world, `isolatedScript` in the isolated
/// world named `world` (invisible to the page). Set before browsers are created.
+ (void)setDocumentStartScript:(NSString *)script isolatedScript:(NSString *)isolatedScript world:(NSString *)world;
/// Third-party ad and tracker blocking: subresource and subframe requests whose host
/// (or a parent domain) is on the blocked list are cancelled when they are third-party
/// to the tab's top-level page. Main-frame navigations always load. Takes effect for
/// the next request, any time, from any thread. Off until enabled.
+ (void)setContentBlockingEnabled:(BOOL)enabled;
+ (BOOL)contentBlockingEnabled;
/// Chrome's HTTPS-Only Mode ("Always use secure connections") in every profile:
/// http:// navigations are upgraded, and a site without HTTPS shows Chrome's warning
/// page before it loads. Profiles that load later get it too. Off until enabled.
+ (void)setHttpsOnlyModeEnabled:(BOOL)enabled;
/// Settings ▸ Privacy ▸ Fingerprinting protection in every profile, live in open pages: Cra's
/// Chromium noises canvas, WebGL and offline-audio readback and reports 8 cores, with a seed per
/// site, profile and launch. Profiles that load later get it too. Off until enabled.
+ (void)setFingerprintingProtectionEnabled:(BOOL)enabled;
/// Arc's View ▸ Appearance ("Websites, Easels, and Notes will use:"): 0 Automatic (the Mac's),
/// 1 Light, 2 Dark. Chrome's colour mode in every profile, which pages' prefers-color-scheme and
/// Chrome's own pages follow; profiles that load later get it too.
+ (void)setWebsiteAppearance:(NSInteger)mode;
@property (class, nonatomic, readonly) NSInteger websiteAppearance;
/// Chromium's secure DNS setting (chrome://settings/security), app-wide in Local State:
/// `dns_over_https.mode` and `dns_over_https.templates` as Chromium holds them now. nil
/// before Chromium is ready and once quitting starts.
+ (nullable NSString *)secureDNSMode;
+ (nullable NSString *)secureDNSTemplates;
/// Writes both, as chrome://settings/security does; Chromium's network service picks the
/// change up at once. NO when Chromium isn't ready, a policy sets them, or a write fails.
+ (BOOL)setSecureDNSMode:(NSString *)mode templates:(NSString *)templates;
/// A policy (DnsOverHttpsMode, DnsOverHttpsTemplates) sets secure DNS, so Settings can't.
+ (BOOL)secureDNSIsManaged;
/// Called on the main queue once Chromium is ready (at once if it already is) and after the
/// secure DNS setting changes.
+ (void)setSecureDNSChangeHandler:(nullable void (^)(void))handler;
/// Replaces the blocked list (bare domains; a domain also covers its subdomains).
+ (void)setBlockedDomains:(NSArray<NSString *> *)domains;
/// Reads and installs a list file off the main thread: one domain per line or
/// hosts-file lines ("0.0.0.0 example.com"), # comments. The completion gets the
/// domain count (0 when the file can't be read) on the main queue.
+ (void)loadBlockedDomainsFromFile:(NSString *)path completion:(nullable void (^)(NSInteger count))completion;
+ (NSInteger)blockedDomainCount;
/// The blocking decision for a request made by a page, for diagnostics and tests.
+ (BOOL)shouldBlockRequestURL:(NSString *)requestURL onPageURL:(NSString *)pageURL;
/// Unpacked extension folders to load with --load-extension, set before initializing, and
/// for each in the same order the profile folders that load it ("Default|Profile <id>", "*"
/// for every profile), comma-separated; nil when every one loads in every profile.
+ (void)setExtensionPaths:(NSArray<NSString *> *)paths profiles:(nullable NSString *)profiles;
/// `locale` is Chromium's application locale ("zh-CN"); nil leaves CEF's en-US.
+ (BOOL)initializeWithCachePath:(NSString *)cachePath
                 userAgentProduct:(NSString *)product
                          logPath:(NSString *)logPath
                           locale:(nullable NSString *)locale
                   useChromeStyle:(BOOL)useChromeStyle
                  useMockKeychain:(BOOL)useMockKeychain;
/// Runs the Chromium-integrated AppKit run loop. Returns after -quitMessageLoop.
+ (void)runMessageLoop;
/// Runs `block` once Chromium is up and before the app finishes launching: at once with CEF (initialize
/// starts Chromium), from inside -runMessageLoop with Chrome's framework (ChromeMain starts it there).
+ (void)whenReady:(void (^)(void))block;
+ (void)quitMessageLoop;
+ (void)shutdown;
/// Closes every browser, then quits the message loop once they are gone.
+ (void)closeAllBrowsersAndQuit;
+ (NSInteger)liveBrowserCount;
/// The last incognito window closed: the next incognito page starts a fresh
/// off-the-record profile (no cookies or storage carried over).
+ (void)endIncognitoSession;
/// YES when another Cra is running and was told about this launch (exit quietly): after initialize
/// fails with CEF, after -runMessageLoop returns with Chrome's framework.
+ (BOOL)anotherInstanceWasNotified;
/// Called in the running instance when another launch is handed over.
+ (void)setRelaunchHandler:(void (^)(NSArray<NSString *> *urls))handler;
/// An extension's chrome.tabs.create (scripts/cef-patches/extension-tabs-create.patch): the
/// handler gets the URL, the Chromium profile folder the extension runs in, whether the tab
/// opens behind, and the page Chromium offers it through (the extension's current window).
/// It returns the popup host (a CraBrowser made with a nil url) of the tab it opened, whose
/// page is then the tab Chromium made and the extension holds (GitHub #292), or nil to leave
/// the page to Chrome's own window and so to the stray page handler.
+ (void)setExtensionTabHandler:(CraBrowser * _Nullable (^)(NSString *url, NSString * _Nullable profile, BOOL background,
                                                          CraBrowser * _Nullable opener))handler;
/// Pages Chromium opens on its own (an extension's chrome.tabs.create when the extension tab
/// handler declines, windows.create, welcome pages after an extension loads). The handler gets
/// the URL to open as a Cra tab and the Chromium profile folder it came from
/// ("Default", "Profile <id>"; nil off the record); Chrome's own window for it is closed.
/// Popup-type windows (windows.create({type: "popup"})) stay Chrome's windows.
+ (void)setStrayPageHandler:(void (^)(NSString *url, NSString * _Nullable profile))handler;
/// Where a new page's (or DevTools') Chromium window is first shown, in screen coordinates, given
/// its size; an empty rect leaves it where Chromium made it, the top left corner of the primary
/// display (GitHub #354). Asked on the main thread, before the window shows.
+ (void)setPageWindowStartHandler:(NSRect (^)(NSSize size))handler;
/// A new tab or window a page asks for (target=_blank, window.open) at another app's address
/// (spotify:): the handler gets the page's browser, the address and whether a click asked, and
/// returns YES when it took it (Cra's "Open <app>?"); then no tab opens (GitHub #207). On the
/// main thread, before Peek and the delegate's popupHostForURL.
+ (void)setAppLinkHandler:(BOOL (^)(CraBrowser *browser, NSString *url, BOOL userGesture))handler;
/// The page's right-click View Page Source and View Frame Source: the handler gets the page's browser
/// and the address whose source to show, and opens it as Cra's View Source does (GitHub #348).
+ (void)setViewSourceHandler:(void (^)(CraBrowser *browser, NSString *url))handler;
/// Test hook: the next page context menu runs Chromium's command `name` (an IDC name, such as
/// "IDC_VIEW_SOURCE") as if it had been picked, instead of showing. NO for an unknown name.
+ (BOOL)runNextPageMenuCommand:(NSString *)name;
/// Where a page's download is saved (GitHub #190): the handler gets the browser's profile folder
/// (nil for Default and off the record) and the file name Chromium suggests, and calls `completion`
/// on the main thread with the full path to save to, or nil to cancel the download (a save panel
/// the user closed). Without a handler downloads go to ~/Downloads.
+ (void)setDownloadDestinationHandler:(void (^)(NSString * _Nullable profilePath, NSString *suggestedName,
                                                void (^completion)(NSString * _Nullable path)))handler;
/// Pauses, resumes or cancels a download still in progress, from its row's menu (GitHub #272); NO
/// when Chromium has no download in progress by that id. Its next update reports the change.
+ (BOOL)controlDownload:(uint32_t)identifier action:(CraDownloadControl)action;
/// Renderer trouble and failed loads, for Cra's performance recorder (GitHub #91): `kind` is
/// terminated, unresponsive, responsive or loadError; `detail` how it ended or the net error
/// code; `site` the host (nil for incognito, Cra's own pages or a closed tab). Never a URL.
/// On the main thread. Chrome's "Page Unresponsive" dialog still shows.
+ (void)setProcessEventHandler:(void (^)(NSString *kind, NSString *detail, NSString *_Nullable site))handler;
/// YES for a popup window an extension opened (kept by the stray page handling).
+ (BOOL)isExtensionWindow:(NSWindow *)window;
/// YES for the Chrome-style window hosting one of Cra's own browsers.
+ (BOOL)isPageWindow:(NSWindow *)window;
/// Lets one of Chromium's Picture in Picture windows show over another app's full-screen Space,
/// as Arc's non-activating PiP panel does (GitHub #206). Chromium only makes it join every desktop Space.
+ (void)floatOverFullScreenSpaces:(NSWindow *)window;
/// "shown=<n> away=<n> animated=<n>": the page and DevTools windows Chromium has shown, how many of
/// them it showed off every Cra window that was on screen, and how many macOS animates in and out
/// (GitHub #354), for cra://debug?pageWindows=.
@property (class, nonatomic, readonly) NSString *pageWindowsReadout;
+ (NSString *)chromiumVersion;
+ (NSString *)cefVersion;
/// YES when the browser-level DevTools pipe is up (it needs fds 3/4 free at start-up).
+ (BOOL)hasBrowserDevTools;
/// Browser-level DevTools protocol call (Target.*, Extensions.*) over the private pipe.
+ (void)sendBrowserDevToolsMethod:(NSString *)method params:(NSString *)params
                       completion:(void (^)(NSString * _Nullable result, NSString * _Nullable error))completion;
/// A GET made by the browser itself with a profile's cookies (nil is Default), as a
/// page of that profile would make it: how Arc's and Dia's live folders read github.com
/// with the user's own session. The completion gets the HTTP status (0 when the request
/// failed), the URL after redirects, the MIME type and the body as UTF-8, on the main queue.
+ (void)fetchURL:(NSString *)url headers:(nullable NSDictionary<NSString *, NSString *> *)headers
     profilePath:(nullable NSString *)profilePath
      completion:(void (^)(NSInteger status, NSString *finalURL, NSString *mimeType, NSString *body))completion;
+ (void)fetchPluginURL:(NSString *)url headers:(nullable NSDictionary<NSString *, NSString *> *)headers
          profilePath:(nullable NSString *)profilePath
           completion:(void (^)(NSInteger status, NSString *finalURL, NSString *mimeType, NSString *body))completion;
/// Same, inside an attached target's session (Target.attachToTarget with flatten).
+ (void)sendBrowserDevToolsMethod:(NSString *)method params:(NSString *)params sessionID:(nullable NSString *)sessionID
                       completion:(void (^)(NSString * _Nullable result, NSString * _Nullable error))completion;
/// Protocol events from the pipe: method, params JSON, and the session they belong to.
+ (void)setBrowserDevToolsEventHandler:(nullable void (^)(NSString *method, NSString *params, NSString * _Nullable sessionID))handler;
/// A profile's `extensions.settings` pref as Chromium holds it now (nil profilePath is
/// Default), as JSON. Chromium writes it to Preferences ~10 s after a change. nil until
/// that profile has loaded.
+ (nullable NSString *)extensionSettingsForProfile:(nullable NSString *)profilePath;
/// A profile's pref as Chromium holds it now (nil profilePath is Default), as JSON: how Cra reads
/// `default_search_provider_data.template_url_data`, the engine chrome://settings/searchEngines
/// made the default. nil until that profile has loaded.
+ (nullable NSString *)preference:(NSString *)name forProfile:(nullable NSString *)profilePath;
/// Sets a profile's pref to a JSON value, as chrome://settings would. NO when the profile hasn't
/// loaded, a policy holds the pref, or the value isn't one it takes.
+ (BOOL)setPreference:(NSString *)name json:(NSString *)json forProfile:(nullable NSString *)profilePath;
/// Puts a profile's pref back to Chromium's default (PrefService::ClearPref). NO when the profile hasn't
/// loaded, a policy holds the pref, or Chromium has no pref of that name.
+ (BOOL)resetPreference:(NSString *)name forProfile:(nullable NSString *)profilePath;
/// Whether a profile (nil is Default) has loaded in this session: 2 ready, 1 loading (its prefs are being
/// read), 0 not asked for, so nothing in this process has its Preferences file open.
+ (NSInteger)loadStateOfProfile:(nullable NSString *)profilePath;
/// Called on the main queue with a profile's path once it has loaded (not Default, which loads first).
+ (void)setProfileLoadedHandler:(nullable void (^)(NSString *profilePath))handler;
/// Called on the main queue after a loaded profile's `extensions.settings` changed: an
/// extension installed, enabled, disabled or removed.
+ (void)setExtensionSettingsChangeHandler:(nullable void (^)(void))handler;
@end

/// NSApplication subclass CEF requires (CefAppProtocol). Set as
/// NSPrincipalClass and created with +sharedApplication before anything else.
CRA_EXPORT @interface CraApplication : CRA_APPLICATION_SUPERCLASS
/// How many requests to bring Cra to the front, made while it was in the background, went
/// through (a background test copy counts them, then refuses them all).
@property (class, readonly) NSInteger backgroundActivations;
@end

NS_ASSUME_NONNULL_END
