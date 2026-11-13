// The bridge on Chrome's own framework: Sources/CraCEF/include/CraCEF.h (copied here as cra/CraCEF.h by
// engine/chromium/apply.sh), the same surface Cra's Swift app drives on CEF. docs/chromium-engine.md has
// the plan; step 3 fills this in method by method.
//
// Shape: one hidden Chrome Browser per profile holds that profile's pages as tabs. Its first tab is a
// blank page that stays the active one, so Chrome's (never shown) window never takes a page's view; every
// page of Cra's is a background tab whose view Cra puts in its own windows (containerView).
//
// What isn't done yet does nothing and returns an empty answer. Each such method says "Not yet".

// CraCEF.h's properties are synthesized as the CEF bridge has them; Chrome's own code spells it out.
#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

#define CRA_APPLICATION_SUPERCLASS BrowserCrApplication
#import "chrome/browser/chrome_browser_application_mac.h"
#import "cra/CraCEF.h"

#include "cra/bridge.h"

#include <map>
#include <string>
#include <vector>

#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/version_info/version_info.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/cra_engine_hooks.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/lifetime/application_lifetime_desktop.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/common/chrome_result_codes.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "net/base/net_errors.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

extern "C" int CraEngineMain(int argc, const char** argv);

@interface CraBrowser ()
- (void)adoptContents:(content::WebContents*)contents;
- (void)contentsCreated:(content::WebContents*)contents;
- (void)pageStartedNavigation:(content::NavigationHandle*)handle;
- (void)pageFinishedNavigation:(content::NavigationHandle*)handle;
- (void)pageLoadingChanged;
- (void)pageProgress:(double)progress;
- (void)pageFinishedLoad;
- (void)pageTitleChanged;
- (void)pageAudible:(BOOL)audible;
- (void)pageFocused;
- (void)pageDestroyed;
@end

namespace {

NSString* NS(const std::string& s) {
  return base::SysUTF8ToNSString(s);
}

std::string UTF8(NSString* s) {
  return s ? base::SysNSStringToUTF8(s) : std::string();
}

// Start-up, as initialize… left it for runMessageLoop.
NSString* g_cache_path = nil;
NSString* g_log_path = nil;
NSString* g_locale = nil;
BOOL g_mock_keychain = NO;
NSArray<NSString*>* g_extension_paths = nil;
int g_exit_code = 0;
bool g_ready = false;
bool g_quitting = false;
NSMutableArray<void (^)(void)>* g_ready_blocks = nil;
// Chrome quits once nothing keeps it alive; in Chrome AppController does, which Cra's app replaces. Held from
// start-up to Cra's quit.
ScopedKeepAlive* g_keep_alive = nullptr;

// Every CraBrowser that has a page, by its page.
std::map<content::WebContents*, CraBrowser* __weak>& PagesByContents() {
  static auto* pages = new std::map<content::WebContents*, CraBrowser* __weak>();
  return *pages;
}
NSInteger g_live_browsers = 0;
// Set while Cra adds a page of its own, so the tab strip observer leaves it alone.
bool g_adding_own_page = false;

CraBrowser* BrowserFor(content::WebContents* contents) {
  auto it = PagesByContents().find(contents);
  return it == PagesByContents().end() ? nil : it->second;
}

void Later(base::OnceClosure task) {
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(FROM_HERE, std::move(task));
}

// A page of Cra's tells its CraBrowser what happens to it.
class PageObserver : public content::WebContentsObserver {
 public:
  PageObserver(content::WebContents* contents, CraBrowser* owner)
      : content::WebContentsObserver(contents), owner_(owner) {}

  void DidStartNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame() && !handle->IsSameDocument()) {
      [owner_ pageStartedNavigation:handle];
    }
  }
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    if (handle->IsInPrimaryMainFrame()) {
      [owner_ pageFinishedNavigation:handle];
    }
  }
  void DidStartLoading() override { [owner_ pageLoadingChanged]; }
  void DidStopLoading() override { [owner_ pageLoadingChanged]; }
  void LoadProgressChanged(double progress) override { [owner_ pageProgress:progress]; }
  void DidFinishLoad(content::RenderFrameHost* frame, const GURL& url) override {
    if (frame->IsInPrimaryMainFrame()) {
      [owner_ pageFinishedLoad];
    }
  }
  void TitleWasSet(content::NavigationEntry* entry) override { [owner_ pageTitleChanged]; }
  void OnAudioStateChanged(bool audible) override { [owner_ pageAudible:audible]; }
  void OnWebContentsFocused(content::RenderWidgetHost* widget) override { [owner_ pageFocused]; }
  void WebContentsDestroyed() override { [owner_ pageDestroyed]; }

 private:
  CraBrowser* __weak owner_;
};

// The hidden Browser that holds a profile's pages, and what arrives in it that Cra didn't put there: a
// page's popup or link opened in a new tab, which becomes a Cra tab through the opener's delegate.
class PageHost : public TabStripModelObserver {
 public:
  explicit PageHost(BrowserWindowInterface* browser) : browser_(browser) {
    // The blank page that stays active, so Chrome never puts one of Cra's pages in its own window.
    chrome::AddTabAt(browser, GURL(url::kAboutBlankURL), -1, true);
    placeholder_ = browser->GetTabStripModel()->GetActiveWebContents();
    browser->GetTabStripModel()->AddObserver(this);
  }

  BrowserWindowInterface* browser() { return browser_; }

  // Makes the blank page the active one again (a popup that opened in front took its place).
  void KeepPlaceholderActive() {
    TabStripModel* tabs = browser_->GetTabStripModel();
    int index = tabs->GetIndexOfWebContents(placeholder_);
    if (index != TabStripModel::kNoTab && tabs->active_index() != index) {
      tabs->ActivateTabAt(index);
    }
  }

  void OnTabStripModelChanged(TabStripModel* model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override {
    if (change.type() != TabStripModelChange::kInserted || g_adding_own_page) {
      return;
    }
    for (const auto& inserted : change.GetInsert()->contents) {
      content::WebContents* page = inserted.contents;
      if (page == placeholder_ || BrowserFor(page)) {
        continue;
      }
      // The page that opened it: the frame for window.open, else the tab strip's opener (a link opened
      // in a new tab).
      content::WebContents* opener = nullptr;
      if (content::RenderFrameHost* frame = page->GetOpener()) {
        opener = content::WebContents::FromRenderFrameHost(frame);
      }
      if (!opener) {
        if (tabs::TabInterface* tab = model->GetOpenerOfTabAt(inserted.index)) {
          opener = tab->GetContents();
        }
      }
      bool background = model->GetActiveWebContents() != page;
      Later(base::BindOnce(&PageHost::Adopt, base::Unretained(this), page->GetWeakPtr(),
                           opener ? opener->GetWeakPtr() : base::WeakPtr<content::WebContents>(), background));
    }
  }

  void OnTabStripModelDestroyed(TabStripModel* model) override;

 private:
  void Adopt(base::WeakPtr<content::WebContents> page, base::WeakPtr<content::WebContents> opener, bool background) {
    if (!page) {
      return;
    }
    KeepPlaceholderActive();
    CraBrowser* from = opener ? BrowserFor(opener.get()) : nil;
    CraBrowser* host = nil;
    if (from && [from.delegate respondsToSelector:@selector(browser:popupHostForURL:inBackground:)]) {
      host = [from.delegate browser:from popupHostForURL:NS(page->GetVisibleURL().spec()) inBackground:background];
    }
    if (!host) {
      // Not Cra's to show (blocked, or no page of Cra's opened it): it goes.
      chrome::CloseWebContents(browser_, page.get(), false);
      return;
    }
    [host adoptContents:page.get()];
  }

  raw_ptr<BrowserWindowInterface> browser_;
  raw_ptr<content::WebContents> placeholder_ = nullptr;
};

std::map<Profile*, PageHost*>& Hosts() {
  static auto* hosts = new std::map<Profile*, PageHost*>();
  return *hosts;
}

// The Browser closed (Chrome quits): its profile gets a new one if a page asks again. The host itself stays
// (it is still in the model's observer list while this runs); a few bytes, once per Browser.
void PageHost::OnTabStripModelDestroyed(TabStripModel* model) {
  for (auto it = Hosts().begin(); it != Hosts().end(); ++it) {
    if (it->second == this) {
      Hosts().erase(it);
      break;
    }
  }
  browser_ = nullptr;
  placeholder_ = nullptr;
}

PageHost* HostFor(Profile* profile) {
  auto it = Hosts().find(profile);
  if (it != Hosts().end()) {
    return it->second;
  }
  BrowserWindowInterface* browser = CreateBrowserWindow(BrowserWindowCreateParams(*profile, false));
  auto* host = new PageHost(browser);
  Hosts()[profile] = host;
  return host;
}

base::FilePath ProfileDir(NSString* profilePath) {
  ProfileManager* profiles = g_browser_process->profile_manager();
  return profilePath.length ? base::FilePath(UTF8(profilePath)) : profiles->user_data_dir().AppendASCII("Default");
}

}  // namespace

namespace cra {

void RunReadyBlocks() {
  g_keep_alive = new ScopedKeepAlive(KeepAliveOrigin::APP_CONTROLLER, KeepAliveRestartOption::DISABLED);
  g_ready = true;
  NSArray<void (^)(void)>* blocks = g_ready_blocks;
  g_ready_blocks = nil;
  for (void (^block)(void) in blocks) {
    block();
  }
}

}  // namespace cra

#pragma mark - Data classes

@implementation CraDownloadInfo
@end

@implementation CraSSLStatus
@end

#pragma mark - CraBrowser

@implementation CraBrowser {
  NSView* _container;
  raw_ptr<content::WebContents> _contents;
  std::unique_ptr<PageObserver> _observer;
  NSString* _pendingURL;
  BOOL _waitingForPopup;
  BOOL _audioMuted;
  BOOL _closeRequested;
  BOOL _pendingFocus;
}

- (instancetype)initWithFrame:(NSRect)frame url:(NSString*)url delegate:(id<CraBrowserDelegate>)delegate {
  return [self initWithFrame:frame url:url delegate:delegate incognito:NO profilePath:nil history:nil];
}

- (instancetype)initWithFrame:(NSRect)frame
                          url:(NSString*)url
                     delegate:(id<CraBrowserDelegate>)delegate
                    incognito:(BOOL)incognito {
  return [self initWithFrame:frame url:url delegate:delegate incognito:incognito profilePath:nil history:nil];
}

- (instancetype)initWithFrame:(NSRect)frame
                          url:(NSString*)url
                     delegate:(id<CraBrowserDelegate>)delegate
                    incognito:(BOOL)incognito
                  profilePath:(NSString*)profilePath {
  return [self initWithFrame:frame url:url delegate:delegate incognito:incognito profilePath:profilePath history:nil];
}

- (instancetype)initAgentWithURL:(NSString*)url profilePath:(NSString*)profilePath {
  self = [self initWithFrame:NSMakeRect(0, 0, 1280, 800) url:url delegate:nil incognito:NO profilePath:profilePath history:nil];
  _isAgent = YES;
  return self;
}

- (instancetype)initWithFrame:(NSRect)frame
        extensionSidePanelURL:(NSString*)url
                     delegate:(id<CraBrowserDelegate>)delegate
                  profilePath:(NSString*)profilePath {
  // Not yet: marked as a side panel, so extensions don't see it as a tab.
  return [self initWithFrame:frame url:url delegate:delegate incognito:NO profilePath:profilePath history:nil];
}

- (instancetype)initSpareWithFrame:(NSRect)frame profilePath:(NSString*)profilePath {
  self = [self initWithFrame:frame url:@"" delegate:nil incognito:NO profilePath:profilePath history:nil];
  _isSpare = YES;
  return self;
}

- (instancetype)initWithFrame:(NSRect)frame
                          url:(NSString*)url
                     delegate:(id<CraBrowserDelegate>)delegate
                    incognito:(BOOL)incognito
                  profilePath:(NSString*)profilePath
                      history:(NSDictionary<NSString*, id>*)history {
  self = [super init];
  if (!self) {
    return nil;
  }
  // Not yet: `history` (the saved back and forward list) is left out; the page loads `url`.
  _delegate = delegate;
  _isIncognito = incognito;
  _profilePath = incognito ? nil : [profilePath copy];
  _container = [[NSView alloc] initWithFrame:frame];
  _container.wantsLayer = YES;
  _container.autoresizesSubviews = YES;
  // The address it was asked for, until the page reports its own (as CEF does).
  _currentURL = url ?: @"";
  _currentTitle = @"";
  ++g_live_browsers;
  if (!url) {
    // A popup host: the next popup its opener's delegate hands it (adoptContents:).
    _waitingForPopup = YES;
    return self;
  }
  _pendingURL = [url copy];
  ProfileManager* profiles = g_browser_process->profile_manager();
  base::FilePath dir = ProfileDir(_profilePath);
  if (Profile* profile = profiles->GetProfileByPath(dir)) {
    [self createPageInProfile:profile];
  } else {
    CraBrowser* __weak weakSelf = self;
    profiles->CreateProfileAsync(dir, base::BindOnce(^(Profile* loaded) {
                                   if (loaded) {
                                     [weakSelf createPageInProfile:loaded];
                                   }
                                 }));
  }
  return self;
}

- (void)createPageInProfile:(Profile*)profile {
  // Quitting: Chrome is closing every Browser, and the app may still ask for a page as tabs lose theirs.
  if (_isClosed || g_quitting) {
    return;
  }
  if (_isIncognito) {
    profile = profile->GetPrimaryOTRProfile(/*create_if_needed=*/true);
  }
  PageHost* host = HostFor(profile);
  GURL url(_pendingURL.length ? UTF8(_pendingURL) : std::string(url::kAboutBlankURL));
  g_adding_own_page = true;
  content::WebContents* contents = chrome::AddAndReturnTabAt(host->browser(), url, -1, /*foreground=*/false);
  g_adding_own_page = false;
  host->KeepPlaceholderActive();
  _pendingURL = nil;
  [self contentsCreated:contents];
}

- (void)adoptContents:(content::WebContents*)contents {
  _waitingForPopup = NO;
  [self contentsCreated:contents];
  [self pageLoadingChanged];
  [self pageTitleChanged];
}

- (void)contentsCreated:(content::WebContents*)contents {
  _contents = contents;
  _observer = std::make_unique<PageObserver>(contents, self);
  PagesByContents()[contents] = self;
  _isCreated = YES;
  if (_audioMuted) {
    contents->SetAudioMuted(true);
  }
  // What the page did before Cra watched it (its first load starts inside AddAndReturnTabAt).
  [self pageAddressChanged];
  [self pageLoadingChanged];
  NSView* page = contents->GetNativeView().GetNativeNSView();
  [page removeFromSuperview];
  page.frame = _container.bounds;
  page.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [_container addSubview:page];
  if (_pendingFocus) {
    _pendingFocus = NO;
    [self setFocused:YES];
  }
}

- (NSView*)containerView {
  return _container;
}

- (NSWindow*)hostWindow {
  return nil;
}

#pragma mark Page events

- (void)pageStartedNavigation:(content::NavigationHandle*)handle {
  _hasCommittedLoad = NO;
  _navigatingURL = NS(handle->GetURL().spec());
  ++_navigationStarts;
  if ([_delegate respondsToSelector:@selector(browser:didChangeCommittedLoad:)]) {
    [_delegate browser:self didChangeCommittedLoad:NO];
  }
  [self pageAddressChanged];
}

// The address the page shows (Chrome's visible URL: a typed address as its load starts), as CEF's
// OnAddressChange reports it.
- (void)pageAddressChanged {
  if (!_contents) {
    return;
  }
  GURL visible = _contents->GetVisibleURL();
  if (visible.is_empty()) {
    return;
  }
  NSString* url = NS(visible.spec());
  if (![url isEqualToString:_currentURL]) {
    _currentURL = url;
    [_delegate browser:self didChangeURL:url];
  }
}

- (void)pageFinishedNavigation:(content::NavigationHandle*)handle {
  if (handle->HasCommitted()) {
    if (!handle->IsSameDocument() && !_hasCommittedLoad) {
      _hasCommittedLoad = YES;
      if ([_delegate respondsToSelector:@selector(browser:didChangeCommittedLoad:)]) {
        [_delegate browser:self didChangeCommittedLoad:YES];
      }
    }
  }
  [self pageAddressChanged];
  int error = handle->GetNetErrorCode();
  if (error != net::OK && error != net::ERR_ABORTED &&
      [_delegate respondsToSelector:@selector(browser:didFailLoadingURL:errorCode:)]) {
    [_delegate browser:self didFailLoadingURL:NS(handle->GetURL().spec()) errorCode:error];
  }
  [self pageLoadingChanged];
}

- (void)pageLoadingChanged {
  if (!_contents) {
    return;
  }
  content::NavigationController& history = _contents->GetController();
  if (_contents->IsLoading() && !_isLoading) {
    _hasCommittedLoad = NO;
  }
  _isLoading = _contents->IsLoading();
  _canGoBack = history.CanGoBack();
  _canGoForward = history.CanGoForward();
  [_delegate browser:self didChangeLoading:_isLoading canGoBack:_canGoBack canGoForward:_canGoForward];
}

- (void)pageProgress:(double)progress {
  [_delegate browser:self didChangeProgress:progress];
}

- (void)pageFinishedLoad {
  content::NavigationEntry* entry = _contents->GetController().GetLastCommittedEntry();
  [_delegate browser:self
      didFinishLoadingURL:NS(_contents->GetLastCommittedURL().spec())
                    title:_currentTitle
               statusCode:entry ? entry->GetHttpStatusCode() : 0];
}

- (void)pageTitleChanged {
  if (!_contents) {
    return;
  }
  NSString* title = base::SysUTF16ToNSString(_contents->GetTitle());
  if (![title isEqualToString:_currentTitle]) {
    _currentTitle = title;
    [_delegate browser:self didChangeTitle:title];
  }
}

- (void)pageAudible:(BOOL)audible {
  _isAudible = audible;
  if ([_delegate respondsToSelector:@selector(browser:didChangeAudible:)]) {
    [_delegate browser:self didChangeAudible:audible];
  }
}

- (void)pageFocused {
  [_delegate browserDidReceiveFocus:self];
}

- (void)pageDestroyed {
  _closedByPage = !_closeRequested && !g_quitting;
  PagesByContents().erase(_contents.get());
  _observer.reset();
  _contents = nullptr;
  [self didClose];
}

- (void)didClose {
  if (_isClosed) {
    return;
  }
  _isClosed = YES;
  --g_live_browsers;
  [_delegate browserDidClose:self];
}

#pragma mark Navigation

- (void)loadURL:(NSString*)url {
  if (!_contents) {
    _pendingURL = [url copy];
    return;
  }
  content::NavigationController::LoadURLParams params{GURL(UTF8(url))};
  params.transition_type = ui::PAGE_TRANSITION_TYPED;
  _contents->GetController().LoadURLWithParams(params);
}

- (void)goBack {
  if (_contents && _contents->GetController().CanGoBack()) {
    _contents->GetController().GoBack();
  }
}

- (void)goForward {
  if (_contents && _contents->GetController().CanGoForward()) {
    _contents->GetController().GoForward();
  }
}

- (void)reload {
  if (_contents) {
    _contents->GetController().Reload(content::ReloadType::NORMAL, true);
  }
}

- (void)reloadIgnoringCache {
  if (_contents) {
    _contents->GetController().Reload(content::ReloadType::BYPASSING_CACHE, true);
  }
}

- (void)stopLoading {
  if (_contents) {
    _contents->Stop();
  }
}

// As CEF's SetFocus: the page's window becomes key (so a command bar panel that was key closes), then the
// page takes the keys. A page not made yet takes them once it is.
- (void)setFocused:(BOOL)focused {
  if (!focused) {
    return;
  }
  if (!_contents) {
    _pendingFocus = YES;
    return;
  }
  NSWindow* window = _container.window;
  if (window && !window.isKeyWindow && window.canBecomeKeyWindow) {
    [window makeKeyWindow];
  }
  _contents->Focus();
}

- (void)setAudioMuted:(BOOL)muted {
  _audioMuted = muted;
  if (_contents) {
    _contents->SetAudioMuted(muted);
  }
}

- (BOOL)isAudioMuted {
  return _contents && _contents->IsAudioMuted();
}

- (void)executeJavaScript:(NSString*)script {
  // Not yet: Cra's own world for its scripts. ExecuteJavaScript only runs on chrome:// pages; this one has
  // no such limit (Chrome's name for it says tests).
  if (_contents) {
    _contents->GetPrimaryMainFrame()->ExecuteJavaScriptForTests(base::SysNSStringToUTF16(script), base::NullCallback(),
                                                                /*world_id=*/0);
  }
}

- (void)close {
  if (_isClosed) {
    return;
  }
  _closeRequested = YES;
  if (!_contents) {
    [self didClose];
    return;
  }
  for (auto& [profile, host] : Hosts()) {
    TabStripModel* tabs = host->browser()->GetTabStripModel();
    if (tabs->GetIndexOfWebContents(_contents) != TabStripModel::kNoTab) {
      chrome::CloseWebContents(host->browser(), _contents, /*add_to_history=*/false);
      return;
    }
  }
}

#pragma mark Not yet

- (void)takeSpareWithURL:(NSString*)url history:(NSDictionary<NSString*, id>*)history {
  _isSpare = NO;
  [self loadURL:url];
}
- (BOOL)startAgentDownload:(NSString*)url path:(NSString*)path update:(void (^)(CraDownloadInfo*))update {
  return NO;
}
- (void)cancelAgentDownload {
}
- (void)setPopupsAllowed:(BOOL)allowed {
}
- (void)exitFullscreen {
}
- (void)showDevToolsInspectingPoint:(NSPoint)point {
}
- (void)showDevTools {
}
- (void)applyDevToolsAction {
}
- (void)closeDevTools {
}
- (double)zoomLevel {
  return 0;
}
- (void)setZoomLevel:(double)level {
}
- (void)findText:(NSString*)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext {
}
- (void)stopFinding:(BOOL)clearSelection {
}
- (void)requestPictureInPictureAutomatic:(BOOL)automatic {
}
- (void)exitPictureInPicture {
}
- (void)closePictureInPicture {
}
- (void)togglePictureInPicturePlayback {
}
- (void)skipPictureInPictureBy:(double)seconds {
}
- (void)seekPictureInPictureTo:(double)seconds {
}
- (void)print {
}
- (BOOL)runChromeCommand:(NSString*)name {
  return NO;
}
- (void)probeBackgroundColor {
}
+ (NSColor*)pageCanvasColor {
  return NSColor.whiteColor;
}
- (void)executeJavaScript:(NSString*)script inDevTools:(BOOL)inDevTools {
  if (!inDevTools) {
    [self executeJavaScript:script];
  }
}
- (void)evaluateInIsolatedWorld:(NSString*)world
                         params:(NSString*)params
                     completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  completion(nil, @"not yet on Chrome's framework");
}
- (void)sendDevToolsMethod:(NSString*)method
                    params:(NSString*)params
                completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  completion(nil, @"not yet on Chrome's framework");
}
- (CraSSLStatus*)sslStatus {
  return nil;
}
- (void)notifyMoveOrResizeStarted {
}

@end

#pragma mark - CraCEFRuntime

@implementation CraCEFRuntime

+ (BOOL)initializeWithCachePath:(NSString*)cachePath
               userAgentProduct:(NSString*)product
                        logPath:(NSString*)logPath
                         locale:(NSString*)locale
                 useChromeStyle:(BOOL)useChromeStyle
                useMockKeychain:(BOOL)useMockKeychain {
  // Chrome starts inside runMessageLoop (ChromeMain runs from start to quit); this keeps what it needs.
  g_cache_path = [cachePath copy];
  g_log_path = [logPath copy];
  g_locale = [locale copy];
  g_mock_keychain = useMockKeychain;
  return YES;
}

+ (void)whenReady:(void (^)(void))block {
  if (g_ready) {
    block();
    return;
  }
  if (!g_ready_blocks) {
    g_ready_blocks = [NSMutableArray array];
  }
  [g_ready_blocks addObject:[block copy]];
}

+ (void)runMessageLoop {
  NSArray<NSString*>* given = NSProcessInfo.processInfo.arguments;
  std::vector<std::string> args;
  for (NSString* arg in given) {
    args.push_back(UTF8(arg));
  }
  args.push_back("--user-data-dir=" + UTF8(g_cache_path));
  args.push_back("--no-first-run");
  args.push_back("--no-default-browser-check");
  args.push_back("--no-startup-window");
  if (g_locale.length) {
    args.push_back("--lang=" + UTF8(g_locale));
  }
  if (g_log_path.length) {
    args.push_back("--enable-logging");
    args.push_back("--log-file=" + UTF8(g_log_path));
    args.push_back("--log-level=1");
  }
  if (g_mock_keychain) {
    args.push_back("--use-mock-keychain");
  }
  if (g_extension_paths.count) {
    args.push_back("--load-extension=" + UTF8([g_extension_paths componentsJoinedByString:@","]));
    args.push_back("--disable-features=DisableLoadExtensionCommandLineSwitch");
  }
  std::vector<const char*> argv;
  for (const std::string& arg : args) {
    argv.push_back(arg.c_str());
  }
  // Cra made NSApp, its delegate and its menus: Chrome keeps them (cra_engine_hooks.h).
  cra::g_embedder_owns_app = NSApp.delegate != nil;
  g_exit_code = CraEngineMain(static_cast<int>(argv.size()), argv.data());
}

+ (void)quitMessageLoop {
  [self closeAllBrowsersAndQuit];
}

+ (void)shutdown {
  // ChromeMain shut Chromium down before runMessageLoop returned.
}

+ (void)closeAllBrowsersAndQuit {
  if (g_quitting) {
    return;
  }
  g_quitting = true;
  delete g_keep_alive;
  g_keep_alive = nullptr;
  // What Chrome's AppController does for Cmd-Q. (chrome::AttemptExit would send -terminate: back here.)
  chrome::CloseAllBrowsersAndQuit();
}

+ (NSInteger)liveBrowserCount {
  return g_live_browsers;
}

+ (BOOL)anotherInstanceWasNotified {
  return g_exit_code == CHROME_RESULT_CODE_NORMAL_EXIT_PROCESS_NOTIFIED;
}

+ (NSString*)chromiumVersion {
  return NS(std::string(version_info::GetVersionNumber()));
}

+ (NSString*)cefVersion {
  return @"";
}

+ (void)setExtensionPaths:(NSArray<NSString*>*)paths profiles:(NSString*)profiles {
  // Not yet: `profiles` (which profiles load each extension); every profile loads all of them.
  g_extension_paths = [paths copy];
}

+ (void)setChromeHosting:(BOOL)enabled {
  // Pages are always views Cra hosts (containerView); Chrome's windows never show.
}

+ (BOOL)chromeHosting {
  return NO;
}

#pragma mark Not yet

+ (void)spikeChromeWindowWithURL:(NSString*)url handler:(void (^)(NSWindow*))handler {
}
+ (void)setLinkMenuTitle:(NSString*)title opensInBackground:(BOOL)background {
}
+ (NSString*)chromiumString:(CraChromiumString)string {
  return nil;
}
+ (void)setImageSearchTitle:(NSString* _Nullable (^)(NSString*))block {
}
+ (void)setDocumentStartScript:(NSString*)script isolatedScript:(NSString*)isolatedScript world:(NSString*)world {
}
+ (void)setContentBlockingEnabled:(BOOL)enabled {
}
+ (BOOL)contentBlockingEnabled {
  return NO;
}
+ (void)setHttpsOnlyModeEnabled:(BOOL)enabled {
}
+ (void)setFingerprintingProtectionEnabled:(BOOL)enabled {
}
+ (void)setWebsiteAppearance:(NSInteger)mode {
}
+ (NSInteger)websiteAppearance {
  return 0;
}
+ (NSString*)secureDNSMode {
  return nil;
}
+ (NSString*)secureDNSTemplates {
  return nil;
}
+ (BOOL)setSecureDNSMode:(NSString*)mode templates:(NSString*)templates {
  return NO;
}
+ (BOOL)secureDNSIsManaged {
  return NO;
}
+ (void)setSecureDNSChangeHandler:(void (^)(void))handler {
}
+ (void)setBlockedDomains:(NSArray<NSString*>*)domains {
}
+ (void)loadBlockedDomainsFromFile:(NSString*)path completion:(void (^)(NSInteger))completion {
  if (completion) {
    completion(0);
  }
}
+ (NSInteger)blockedDomainCount {
  return 0;
}
+ (BOOL)shouldBlockRequestURL:(NSString*)requestURL onPageURL:(NSString*)pageURL {
  return NO;
}
+ (void)endIncognitoSession {
}
+ (void)setRelaunchHandler:(void (^)(NSArray<NSString*>*))handler {
}
+ (void)setExtensionTabHandler:(CraBrowser* _Nullable (^)(NSString*, NSString* _Nullable, BOOL,
                                                          CraBrowser* _Nullable))handler {
}
+ (void)setStrayPageHandler:(void (^)(NSString*, NSString* _Nullable))handler {
}
+ (void)setPageWindowStartHandler:(NSRect (^)(NSSize))handler {
}
+ (void)setAppLinkHandler:(BOOL (^)(CraBrowser*, NSString*, BOOL))handler {
}
+ (void)setViewSourceHandler:(void (^)(CraBrowser*, NSString*))handler {
}
+ (BOOL)runNextPageMenuCommand:(NSString*)name {
  return NO;
}
+ (void)setDownloadDestinationHandler:(void (^)(NSString* _Nullable, NSString*, void (^)(NSString* _Nullable)))handler {
}
+ (BOOL)controlDownload:(uint32_t)identifier action:(CraDownloadControl)action {
  return NO;
}
+ (void)setProcessEventHandler:(void (^)(NSString*, NSString*, NSString* _Nullable))handler {
}
+ (BOOL)isExtensionWindow:(NSWindow*)window {
  return NO;
}
+ (BOOL)isPageWindow:(NSWindow*)window {
  return NO;
}
+ (void)floatOverFullScreenSpaces:(NSWindow*)window {
}
+ (NSString*)pageWindowsReadout {
  return @"shown=0 away=0 animated=0";
}
+ (BOOL)hasBrowserDevTools {
  return NO;
}
+ (void)sendBrowserDevToolsMethod:(NSString*)method
                           params:(NSString*)params
                       completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  completion(nil, @"not yet on Chrome's framework");
}
+ (void)sendBrowserDevToolsMethod:(NSString*)method
                           params:(NSString*)params
                        sessionID:(NSString*)sessionID
                       completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  completion(nil, @"not yet on Chrome's framework");
}
+ (void)setBrowserDevToolsEventHandler:(void (^)(NSString*, NSString*, NSString* _Nullable))handler {
}
+ (void)fetchURL:(NSString*)url
         headers:(NSDictionary<NSString*, NSString*>*)headers
     profilePath:(NSString*)profilePath
      completion:(void (^)(NSInteger, NSString*, NSString*, NSString*))completion {
  completion(0, url, @"", @"");
}
+ (void)fetchPluginURL:(NSString*)url
               headers:(NSDictionary<NSString*, NSString*>*)headers
           profilePath:(NSString*)profilePath
            completion:(void (^)(NSInteger, NSString*, NSString*, NSString*))completion {
  completion(0, url, @"", @"");
}
+ (NSString*)extensionSettingsForProfile:(NSString*)profilePath {
  return nil;
}
+ (NSString*)preference:(NSString*)name forProfile:(NSString*)profilePath {
  return nil;
}
+ (BOOL)setPreference:(NSString*)name json:(NSString*)json forProfile:(NSString*)profilePath {
  return NO;
}
+ (BOOL)resetPreference:(NSString*)name forProfile:(NSString*)profilePath {
  return NO;
}
+ (NSInteger)loadStateOfProfile:(NSString*)profilePath {
  if (!g_ready) {
    return 0;
  }
  Profile* profile = g_browser_process->profile_manager()->GetProfileByPath(ProfileDir(profilePath));
  return profile ? 2 : 0;
}
+ (void)setProfileLoadedHandler:(void (^)(NSString*))handler {
}
+ (void)setExtensionSettingsChangeHandler:(void (^)(void))handler {
}

@end

#pragma mark - CraApplication

@implementation CraApplication

// Cra's app makes NSApp (this class) before ChromeMain, and +[BrowserCrApplication initialize] reads the
// process's command line (cocoa_l10n_util::ApplyForcedRTL): an empty one until CraEngineMain hands Chrome
// the real one. Only in the browser process; a helper's ChromeMain reads its own (--type=...).
+ (void)load {
  for (NSString* arg in NSProcessInfo.processInfo.arguments) {
    if ([arg hasPrefix:@"--type="]) {
      return;
    }
  }
  if (!base::CommandLine::InitializedForCurrentProcess()) {
    base::CommandLine::Init(0, nullptr);
  }
}

+ (NSInteger)backgroundActivations {
  return 0;
}

// Cmd-Q, the Dock, logout: give Cra's delegate a say, then Chrome's own exit closes every page and
// returns from ChromeMain (runMessageLoop). Chrome's BrowserCrApplication would ask its AppController,
// which Cra's app doesn't have.
- (void)terminate:(id)sender {
  id<NSApplicationDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(applicationShouldTerminate:)] &&
      [delegate applicationShouldTerminate:self] == NSTerminateCancel) {
    return;
  }
  [CraCEFRuntime closeAllBrowsersAndQuit];
}

- (void)cancelTerminate:(id)sender {
  g_quitting = false;
  if (!g_keep_alive) {
    g_keep_alive = new ScopedKeepAlive(KeepAliveOrigin::APP_CONTROLLER, KeepAliveRestartOption::DISABLED);
  }
}

@end
