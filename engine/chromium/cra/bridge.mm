// The bridge on Chrome's own framework: Sources/CraCEF/include/CraCEF.h (copied here as cra/CraCEF.h by
// engine/chromium/apply.sh), the same surface Cra's Swift app drives on CEF. docs/chromium-engine.md has
// the plan; step 3 fills this in method by method.
//
// Shape: one hidden Chrome Browser per profile holds that profile's pages as tabs, behind a blank first tab
// that keeps the Browser open when Cra has no page in it. Each of Cra's pages carries views::CraHostedPageKey,
// so Chrome's (never shown) window never attaches its view (patches/cra-hosted-pages.patch); Cra puts it in
// its own windows (containerView), and Chrome's active tab follows the page Cra focuses.
//
// What isn't done yet does nothing and returns an empty answer. Each such method says "Not yet".

// CraCEF.h's properties are synthesized as the CEF bridge has them; Chrome's own code spells it out.
#pragma clang diagnostic ignored "-Wobjc-missing-property-synthesis"

#define CRA_APPLICATION_SUPERCLASS BrowserCrApplication
#import "chrome/browser/chrome_browser_application_mac.h"
#import "cra/CraCEF.h"

#include "cra/bridge.h"
#include "cra/CraContentBlocker.h"
#include "cra/downloads.h"
#include "cra/page_protocol.h"
#include "cra/permission_prompt.h"
#include "cra/profile_prefs.h"

#include <fcntl.h>
#include <unistd.h>

#include <map>
#include <set>
#include <string>
#include <vector>

#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/version_info/version_info.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/printing/print_view_manager_common.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/cra_engine_hooks.h"
#include "chrome/browser/cra_permission_hook.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/lifetime/application_lifetime_desktop.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/browser_window/public/browser_collection_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
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
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "components/zoom/zoom_controller.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/ssl_status.h"
#include "net/cert/x509_certificate.h"
#include "net/cert/x509_util.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/gfx/image/image.h"
#include "components/input/native_web_keyboard_event.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "net/base/net_errors.h"
#include "ui/base/base_window.h"
#include "extensions/browser/view_type_utils.h"
#include "extensions/common/mojom/view_type.mojom.h"
#include "ui/views/controls/webview/cra_hosted_page.h"
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
- (void)pageThemeColor;
- (void)pageBackgroundColor;
- (void)pageFavicon:(NSImage*)image url:(NSString*)url;
- (void)pageFindResult;
- (void)pagePictureInPicture:(BOOL)active;
- (void)pageMediaPlaying:(BOOL)playing;
@property(nonatomic) BOOL inPageFullscreen;
- (void)devToolsOpened:(BrowserWindowInterface*)devtools;
- (void)devToolsClosed:(BrowserWindowInterface*)devtools;
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
// Page.addScriptToEvaluateOnNewDocument params every page gets once it exists (setDocumentStartScript:…).
NSArray<NSString*>* g_document_start_params = nil;
NSString* g_extension_profiles = nil;
int g_exit_code = 0;
bool g_ready = false;
bool g_quitting = false;
NSMutableArray<void (^)(void)>* g_ready_blocks = nil;
// Chrome quits once nothing keeps it alive; in Chrome AppController does, which Cra's app replaces. Held from
// start-up to Cra's quit.
ScopedKeepAlive* g_keep_alive = nullptr;

// The app's handlers (CraCEF.h says what each is for).
CraBrowser* _Nullable (^g_extension_tab_handler)(NSString*, NSString* _Nullable, BOOL, CraBrowser* _Nullable) = nil;
void (^g_stray_page_handler)(NSString*, NSString* _Nullable) = nil;
void (^g_download_destination_handler)(NSString* _Nullable, NSString*, void (^)(NSString* _Nullable)) = nil;
// Chrome windows an extension opened as popups (windows.create type popup), which stay Chrome's.
NSHashTable<NSWindow*>* g_extension_windows = nil;
// Set while the bridge makes one of its own hidden Browsers.
bool g_making_host = false;

// The profile folder's name ("Default", "Profile 1"), nil off the record: what the app's handlers take.
NSString* ProfileFolder(Profile* profile) {
  return profile->IsOffTheRecord() ? nil : base::SysUTF8ToNSString(profile->GetBaseName().AsUTF8Unsafe());
}

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

// The CEF bridge's Picture in Picture script (Sources/CraCEF/CraCEF.mm says what it picks). Its `send` reported
// to the CEF bridge; Chrome reports the same through the page observer, so it gets a no-op.
NSString* PictureInPictureScript(BOOL automatic, int x, int y) {
    return [NSString stringWithFormat:
        @"(function(send){var auto=%d,x=%d,y=%d;try{"
        "if(document.pictureInPictureElement){if(!auto){document.exitPictureInPicture().catch(function(){});}return;}"
        "var area=function(v){var r=v.getBoundingClientRect();return r.width*r.height;};"
        "var c=Array.prototype.slice.call(document.querySelectorAll('video')).filter(function(v){return !v.disablePictureInPicture&&v.readyState>=1&&v.videoWidth>0;});"
        "if(auto){c=c.filter(function(v){return !v.paused&&!v.ended&&!v.muted&&v.volume>0&&area(v)>=20000;});}"
        "if(!c.length){send('pip:none');return;}"
        "var v=null;"
        "if(x>=0){v=c.filter(function(e){var r=e.getBoundingClientRect();return x>=r.left&&x<=r.right&&y>=r.top&&y<=r.bottom;}).sort(function(a,b){return area(a)-area(b);})[0]||null;}"
        "if(!v){c.sort(function(a,b){return ((b.paused?0:1)-(a.paused?0:1))||(area(b)-area(a));});v=c[0];}"
        "var go=function(){v.requestPictureInPicture().then(function(){send('pip:ok');}).catch(function(e){send('pip:err '+e.name+': '+e.message);});};"
        "send('pip:want');"
        "var n=0;var t=setInterval(function(){if((navigator.userActivation&&navigator.userActivation.isActive)||++n>20){clearInterval(t);go();}},50);"
        "}catch(e){send('pip:err '+e);}})", automatic ? 1 : 0, x, y];
}


// Runs `script` in every frame of the page (embedded players live in iframes), with a user gesture when asked
// (a page's requestPictureInPicture and play() need one).
void RunInFrames(content::WebContents* contents, NSString* script, bool gesture) {
  std::u16string js = base::SysNSStringToUTF16(script);
  contents->GetPrimaryMainFrame()->ForEachRenderFrameHost([&](content::RenderFrameHost* frame) {
    if (!frame->IsRenderFrameLive()) {
      return;
    }
    if (gesture) {
      frame->ExecuteJavaScriptWithUserGestureForTests(js, base::NullCallback(), /*world_id=*/0);
    } else {
      frame->ExecuteJavaScriptForTests(js, base::NullCallback(), /*world_id=*/0);
    }
  });
}

// "#RRGGBB", or "" for no colour.
NSString* Hex(std::optional<SkColor> color) {
  if (!color) {
    return @"";
  }
  return [NSString stringWithFormat:@"#%02X%02X%02X", SkColorGetR(*color), SkColorGetG(*color), SkColorGetB(*color)];
}

// A page of Cra's tells its CraBrowser what happens to it: the page itself, its favicon and its find results.
class PageObserver : public content::WebContentsObserver,
                     public favicon::FaviconDriverObserver,
                     public find_in_page::FindResultObserver {
 public:
  PageObserver(content::WebContents* contents, CraBrowser* owner)
      : content::WebContentsObserver(contents), owner_(owner) {
    if (auto* favicons = favicon::ContentFaviconDriver::FromWebContents(contents)) {
      favicons->AddObserver(this);
      favicons_ = favicons;
    }
    if (auto* find = find_in_page::FindTabHelper::FromWebContents(contents)) {
      find->AddObserver(this);
      find_ = find;
    }
  }

  ~PageObserver() override {
    if (favicons_) {
      favicons_->RemoveObserver(this);
    }
    if (find_) {
      find_->RemoveObserver(this);
    }
  }

  // favicon::FaviconDriverObserver:
  void OnFaviconUpdated(favicon::FaviconDriver* driver,
                        NotificationIconType type,
                        const GURL& icon_url,
                        bool icon_url_changed,
                        const gfx::Image& image) override {
    if (type == NON_TOUCH_16_DIP && !image.IsEmpty()) {
      [owner_ pageFavicon:image.ToNSImage() url:base::SysUTF8ToNSString(icon_url.spec())];
    }
  }

  // find_in_page::FindResultObserver:
  void OnFindResultAvailable(content::WebContents* contents) override { [owner_ pageFindResult]; }
  void OnFindTabHelperDestroyed(find_in_page::FindTabHelper* helper) override { find_ = nullptr; }

  void DidChangeThemeColor() override { [owner_ pageThemeColor]; }
  void MediaPictureInPictureChanged(bool active) override { [owner_ pagePictureInPicture:active]; }
  void MediaStartedPlaying(const MediaPlayerInfo& info, const content::MediaPlayerId& id) override {
    [owner_ pageMediaPlaying:YES];
  }
  void MediaStoppedPlaying(const MediaPlayerInfo& info,
                           const content::MediaPlayerId& id,
                           WebContentsObserver::MediaStoppedReason reason) override {
    [owner_ pageMediaPlaying:NO];
  }
  void OnBackgroundColorChanged() override { [owner_ pageBackgroundColor]; }

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
  raw_ptr<favicon::ContentFaviconDriver> favicons_ = nullptr;
  raw_ptr<find_in_page::FindTabHelper> find_ = nullptr;
};

// The hidden Browser that holds a profile's pages, and what arrives in it that Cra didn't put there: a
// page's popup or link opened in a new tab, which becomes a Cra tab through the opener's delegate.
class PageHost : public TabStripModelObserver {
 public:
  explicit PageHost(BrowserWindowInterface* browser) : browser_(browser) {
    // The blank page: the Browser stays open with no page of Cra's in it.
    chrome::AddTabAt(browser, GURL(url::kAboutBlankURL), -1, true);
    placeholder_ = browser->GetTabStripModel()->GetActiveWebContents();
    browser->GetTabStripModel()->AddObserver(this);
  }

  BrowserWindowInterface* browser() { return browser_; }

  // Makes the blank page the active one, so a popup that opened in front leaves Chrome's window before Cra
  // marks it as its own and takes its view.
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
      // The page in front before this one came: an extension's tab opens beside it (its "current window").
      content::WebContents* before = selection.old_contents;
      Later(base::BindOnce(&PageHost::Adopt, base::Unretained(this), page->GetWeakPtr(),
                           opener ? opener->GetWeakPtr() : base::WeakPtr<content::WebContents>(),
                           before ? before->GetWeakPtr() : base::WeakPtr<content::WebContents>(), background));
    }
  }

  void OnTabStripModelDestroyed(TabStripModel* model) override;

 private:
  void Adopt(base::WeakPtr<content::WebContents> page,
             base::WeakPtr<content::WebContents> opener,
             base::WeakPtr<content::WebContents> before,
             bool background) {
    if (!page) {
      return;
    }
    KeepPlaceholderActive();
    NSString* url = NS(page->GetVisibleURL().spec());
    CraBrowser* from = opener ? BrowserFor(opener.get()) : nil;
    CraBrowser* host = nil;
    if (from && [from.delegate respondsToSelector:@selector(browser:popupHostForURL:inBackground:)]) {
      host = [from.delegate browser:from popupHostForURL:url inBackground:background];
    } else if (!from && g_extension_tab_handler) {
      // No page of Cra's opened it: an extension's chrome.tabs.create. Cra opens it as one of its tabs, and the
      // extension keeps this page (its tab id) (GitHub #292).
      Profile* profile = Profile::FromBrowserContext(page->GetBrowserContext());
      host = g_extension_tab_handler(url, ProfileFolder(profile), background, before ? BrowserFor(before.get()) : nil);
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

// The page's tab in its host Browser, or nullptr.
PageHost* HostOf(content::WebContents* contents) {
  for (auto& [profile, host] : Hosts()) {
    if (host->browser() && host->browser()->GetTabStripModel()->GetIndexOfWebContents(contents) != TabStripModel::kNoTab) {
      return host;
    }
  }
  return nullptr;
}

void PageActivation(content::WebContents* contents, bool by_page) {
  CraBrowser* browser = BrowserFor(contents);
  if ([browser.delegate respondsToSelector:@selector(browserRequestsActivation:byPage:)]) {
    [browser.delegate browserRequestsActivation:browser byPage:by_page];
  }
}

// Keys in Cra's pages (patches/cra-keys.patch), as CEF's OnPreKeyEvent and OnKeyEvent gave them: Cra's
// reserved shortcuts before the page, the rest after it; what both leave goes to the menu bar (⌘C, ⌘V, ⌘Z are
// Edit menu items sent to the page).
int KeyEvent(content::WebContents* contents, const input::NativeWebKeyboardEvent& event, bool unhandled) {
  CraBrowser* browser = BrowserFor(contents);
  if (!browser) {
    return -1;
  }
  NSEvent* key = event.os_event.Get();
  // Modifier-only presses arrive as flagsChanged.
  if (!key || key.type != NSEventTypeKeyDown || event.GetType() != blink::WebInputEvent::Type::kRawKeyDown) {
    return 0;
  }
  if (!unhandled) {
    return [browser.delegate browser:browser handleKeyEvent:key] ? 1 : 0;
  }
  if ([browser.delegate browser:browser handleUnhandledKeyEvent:key]) {
    return 1;
  }
  return [NSApp.mainMenu performKeyEquivalent:key] ? 1 : 0;
}

// A download's progress, for the page that started it (the CEF bridge's OnDownloadUpdated).
void ReportDownload(download::DownloadItem* item) {
  CraBrowser* browser = BrowserFor(content::DownloadItemUtils::GetWebContents(item));
  if (!browser) {
    return;
  }
  CraDownloadInfo* info = [[CraDownloadInfo alloc] init];
  info.identifier = item->GetId();
  info.paused = item->IsPaused();
  info.url = NS(item->GetURL().spec());
  info.fullPath = NS(item->GetTargetFilePath().value());
  info.suggestedName = NS(item->GetFileNameToReportUser().value());
  info.receivedBytes = item->GetReceivedBytes();
  info.totalBytes = item->GetTotalBytes();
  info.percent = item->PercentComplete();
  switch (item->GetState()) {
    case download::DownloadItem::COMPLETE:
      info.state = CraDownloadStateComplete;
      break;
    case download::DownloadItem::CANCELLED:
      info.state = CraDownloadStateCancelled;
      break;
    case download::DownloadItem::INTERRUPTED:
      info.state = CraDownloadStateInterrupted;
      break;
    default:
      info.state = CraDownloadStateInProgress;
  }
  [browser.delegate browser:browser didUpdateDownload:info];
}

// Where a download goes (patches/cra-downloads.patch): the app's handler, with the page's profile folder (nil
// for Default and off the record) and the name Chrome suggests; without one, where Chrome suggests.
void DownloadPath(download::DownloadItem* item,
                  const base::FilePath& suggested,
                  base::OnceCallback<void(std::optional<base::FilePath>)> done) {
  if (!g_download_destination_handler) {
    std::move(done).Run(suggested);
    return;
  }
  CraBrowser* browser = BrowserFor(content::DownloadItemUtils::GetWebContents(item));
  NSString* profile = browser && !browser.isIncognito ? browser.profilePath : nil;
  NSString* name = NS(suggested.BaseName().value());
  __block base::OnceCallback<void(std::optional<base::FilePath>)> answer = std::move(done);
  g_download_destination_handler(profile, name.length ? name : @"download", ^(NSString* path) {
    if (answer) {
      std::move(answer).Run(path.length ? std::optional<base::FilePath>(base::FilePath(UTF8(path))) : std::nullopt);
    }
  });
}

// A page's permission request (patches/cra-permissions.patch): the app asks, as from the CEF bridge's
// OnShowPermissionPrompt. nullptr for a page that isn't Cra's.
std::unique_ptr<permissions::PermissionPrompt> MakeCraPrompt(content::WebContents* contents,
                                                             permissions::PermissionPrompt::Delegate* delegate) {
  CraBrowser* browser = BrowserFor(contents);
  if (!browser) {
    return nullptr;
  }
  CraBrowser* __weak weak = browser;
  return cra::MakePermissionPrompt(
      delegate,
      ^(NSString* origin, NSUInteger kinds, void (^answer)(BOOL)) {
        CraBrowser* page = weak;
        if (page) {
          [page.delegate browser:page requestsPermissionForOrigin:origin kinds:kinds completion:answer];
        }
      },
      ^{
        CraBrowser* page = weak;
        if ([page.delegate respondsToSelector:@selector(browserWithdrewPermissionRequest:)]) {
          [page.delegate browserWithdrewPermissionRequest:page];
        }
      });
}

// Element fullscreen (patches/cra-fullscreen-status.patch): Cra's window shows it, as from CEF's
// OnFullscreenModeChange; the page then lays out at its new size.
bool PageFullscreen(content::WebContents* contents, bool enter) {
  CraBrowser* browser = BrowserFor(contents);
  if (!browser) {
    return false;
  }
  if (browser.inPageFullscreen == enter) {
    return true;
  }
  browser.inPageFullscreen = enter;
  [browser.delegate browser:browser didChangeFullscreen:enter];
  if (content::RenderWidgetHostView* view = contents->GetRenderWidgetHostView()) {
    view->GetRenderWidgetHost()->SynchronizeVisualProperties();
  }
  return true;
}

int PageIsFullscreen(const content::WebContents* contents) {
  CraBrowser* browser = BrowserFor(const_cast<content::WebContents*>(contents));
  return browser ? (browser.inPageFullscreen ? 1 : 0) : -1;
}

// The link under the pointer, for Cra's status line ("" when none).
bool TargetURL(content::WebContents* contents, const GURL& url) {
  CraBrowser* browser = BrowserFor(contents);
  if (!browser) {
    return false;
  }
  [browser.delegate browser:browser didChangeStatusMessage:url.is_empty() ? @"" : NS(url.spec())];
  return true;
}

// Cra's ad and tracker blocking (patches/cra-content-blocking.patch): a request third-party to its top-level
// page, to a listed domain.
bool BlockRequest(const GURL& url, const content::GlobalRenderFrameHostId& frame) {
  if (!cra_blocker::Enabled().load(std::memory_order_relaxed)) {
    return false;
  }
  content::RenderFrameHost* host = content::RenderFrameHost::FromID(frame);
  if (!host) {
    return false;
  }
  std::string page = cra_blocker::WebHost(host->GetOutermostMainFrame()->GetLastCommittedURL().spec());
  return cra_blocker::ShouldBlock(cra_blocker::WebHost(url.spec()), page);
}

bool IsCraPage(const content::WebContents* contents) {
  return BrowserFor(const_cast<content::WebContents*>(contents)) != nil;
}

// Cra's translate UI (patches/translate-ui.patch): false for a page that isn't Cra's.
bool TranslateState(content::WebContents* contents, const std::string& state) {
  CraBrowser* browser = BrowserFor(contents);
  if (!browser) {
    return false;
  }
  if ([browser.delegate respondsToSelector:@selector(browser:didChangeTranslateState:)]) {
    [browser.delegate browser:browser didChangeTranslateState:NS(state)];
  }
  return true;
}

PageHost* HostFor(Profile* profile) {
  auto it = Hosts().find(profile);
  if (it != Hosts().end()) {
    return it->second;
  }
  g_making_host = true;
  BrowserWindowInterface* browser = CreateBrowserWindow(BrowserWindowCreateParams(*profile, false));
  g_making_host = false;
  auto* host = new PageHost(browser);
  Hosts()[profile] = host;
  return host;
}

bool IsHost(BrowserWindowInterface* browser) {
  for (auto& [profile, host] : Hosts()) {
    if (host->browser() == browser) {
      return true;
    }
  }
  return false;
}

// Chrome windows Cra didn't make (the CEF bridge's stray page handling): a normal one, which Chrome opens for an
// extension's windows.create or a welcome page after an extension loads, is never shown; its page becomes a
// Cra tab through the app's stray page handler and the window closes. A popup one (windows.create type
// popup) stays Chrome's window, as in Arc.
class StrayWindows : public BrowserCollectionObserver, public TabStripModelObserver {
 public:
  void Start() { observation_.Observe(GlobalBrowserCollection::GetInstance()); }

  void OnBrowserCreated(BrowserWindowInterface* browser) override {
    if (g_making_host || IsHost(browser)) {
      return;
    }
    NSWindow* window = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
    if (browser->GetType() == BrowserWindowInterface::TYPE_DEVTOOLS) {
      // A page of Cra's DevTools (patches/cra-devtools.patch): never shown; Cra takes its frontend once Chrome
      // has put it in.
      window.alphaValue = 0;
      window.ignoresMouseEvents = YES;
      Later(base::BindOnce(&StrayWindows::TakeDevTools, base::Unretained(this), browser->GetWeakPtr()));
      return;
    }
    if (browser->GetType() != BrowserWindowInterface::TYPE_NORMAL) {
      if (window) {
        if (!g_extension_windows) {
          g_extension_windows = [NSHashTable weakObjectsHashTable];
        }
        [g_extension_windows addObject:window];
      }
      return;
    }
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    browser->GetTabStripModel()->AddObserver(this);
    Later(base::BindOnce(&StrayWindows::TakePages, base::Unretained(this), browser->GetWeakPtr()));
  }

  void OnTabStripModelChanged(TabStripModel* model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override {}

  void OnBrowserClosed(BrowserWindowInterface* browser) override {
    auto it = devtools_.find(browser);
    if (it == devtools_.end()) {
      return;
    }
    CraBrowser* page = it->second;
    devtools_.erase(it);
    [page devToolsClosed:browser];
  }

 private:
  void TakeDevTools(base::WeakPtr<BrowserWindowInterface> browser) {
    if (!browser) {
      return;
    }
    DevToolsWindow* devtools = DevToolsWindow::AsDevToolsWindow(browser.get());
    CraBrowser* page = devtools ? BrowserFor(devtools->GetInspectedWebContents()) : nil;
    if (!page) {
      // Not a page of Cra's (an extension's background page, say): Chrome's own DevTools window.
      NSWindow* window = browser->GetWindow()->GetNativeWindow().GetNativeNSWindow();
      window.alphaValue = 1;
      window.ignoresMouseEvents = NO;
      return;
    }
    devtools_[browser.get()] = page;
    [page devToolsOpened:browser.get()];
  }

  std::map<BrowserWindowInterface*, CraBrowser* __weak> devtools_;

  // Once Chrome has put the window's pages in (they start loading as they go in).
  void TakePages(base::WeakPtr<BrowserWindowInterface> browser) {
    if (!browser) {
      return;
    }
    TabStripModel* tabs = browser->GetTabStripModel();
    NSString* profile = ProfileFolder(browser->GetProfile());
    for (int i = 0; i < tabs->count(); ++i) {
      std::string url = tabs->GetWebContentsAt(i)->GetVisibleURL().spec();
      // Chrome's own empty tab (after a Web Store install): nobody asked for it.
      if (url.empty() || url == url::kAboutBlankURL || base::StartsWith(url, "chrome://newtab") ||
          base::StartsWith(url, "chrome://new-tab-page")) {
        continue;
      }
      if (g_stray_page_handler) {
        g_stray_page_handler(NS(url), profile);
      }
    }
    tabs->RemoveObserver(this);
    browser->GetWindow()->Close();
  }

  base::ScopedObservation<GlobalBrowserCollection, BrowserCollectionObserver> observation_{this};
};

StrayWindows& Strays() {
  static auto* strays = new StrayWindows();
  return *strays;
}

// Profiles asked for that haven't loaded yet.
std::set<base::FilePath>& LoadingProfiles() {
  static auto* loading = new std::set<base::FilePath>();
  return *loading;
}

base::FilePath ProfileDir(NSString* profilePath) {
  ProfileManager* profiles = g_browser_process->profile_manager();
  return profilePath.length ? base::FilePath(UTF8(profilePath)) : profiles->user_data_dir().AppendASCII("Default");
}

// AuthServerAllowlist as an MDM sets it for Chrome or Edge (e.g. "*.example.com"), which Cra's own bundle id
// doesn't get; CRA_AUTH_SERVER_ALLOWLIST overrides it for machines without such a profile.
NSString* ManagedAuthServerAllowlist() {
  NSString* env = NSProcessInfo.processInfo.environment[@"CRA_AUTH_SERVER_ALLOWLIST"];
  if (env.length) {
    return env;
  }
  for (NSString* domain in @[ @"com.google.Chrome", @"com.microsoft.Edge" ]) {
    for (NSString* key in @[ @"AuthServerAllowlist", @"AuthServerWhitelist" ]) {
      id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain));
      if ([value isKindOfClass:NSString.class] && [value length]) {
        return value;
      }
    }
  }
  return nil;
}

// MARK: Browser-level DevTools pipe
//
// With --remote-debugging-pipe Chrome reads protocol messages from fd 3 and writes replies to fd 4,
// NUL-terminated. Chrome runs in this process, so Cra holds the other ends: a trusted client with no port open
// to anyone else (the CEF bridge's, as it was).
int g_cdp_write_fd = -1;
dispatch_source_t g_cdp_read_source;
NSMutableData* g_cdp_buffer = nil;
NSMutableDictionary<NSNumber*, void (^)(NSString*, NSString*)>* g_cdp_pending = nil;
int g_cdp_next_id = 0;
void (^g_cdp_event_handler)(NSString*, NSString*, NSString*) = nil;

NSString* JSONString(id object) {
  return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:object ?: @{} options:0 error:nil]
                               encoding:NSUTF8StringEncoding];
}

void CDPDeliver(NSData* chunk) {
  NSDictionary* message = [NSJSONSerialization JSONObjectWithData:chunk options:0 error:nil];
  if (![message isKindOfClass:NSDictionary.class]) {
    return;
  }
  NSNumber* key = [message[@"id"] isKindOfClass:NSNumber.class] ? message[@"id"] : nil;
  if (!key) {
    if (g_cdp_event_handler && [message[@"method"] isKindOfClass:NSString.class]) {
      g_cdp_event_handler(message[@"method"], JSONString(message[@"params"]), message[@"sessionId"]);
    }
    return;
  }
  void (^done)(NSString*, NSString*) = g_cdp_pending[key];
  [g_cdp_pending removeObjectForKey:key];
  if (!done) {
    return;
  }
  NSString* json = JSONString(message[@"error"] ?: message[@"result"]);
  message[@"error"] ? done(nil, json) : done(json, nil);
}

// Makes the pipe pair on fds 3 and 4. False (and no pipe) when either is in use.
bool CDPPipeSetUp() {
  if (g_cdp_write_fd >= 0) {
    return true;
  }
  if (fcntl(3, F_GETFD) != -1 || fcntl(4, F_GETFD) != -1) {
    return false;
  }
  int to_chrome[2];
  int from_chrome[2];
  if (pipe(to_chrome) != 0) {
    return false;
  }
  if (pipe(from_chrome) != 0) {
    close(to_chrome[0]);
    close(to_chrome[1]);
    return false;
  }
  // Every end above 10 first: pipe() itself may have handed out 3 or 4.
  int our_write = fcntl(to_chrome[1], F_DUPFD_CLOEXEC, 10);
  int our_read = fcntl(from_chrome[0], F_DUPFD_CLOEXEC, 10);
  int chrome_read = fcntl(to_chrome[0], F_DUPFD, 10);
  int chrome_write = fcntl(from_chrome[1], F_DUPFD, 10);
  for (int fd : {to_chrome[0], to_chrome[1], from_chrome[0], from_chrome[1]}) {
    close(fd);
  }
  dup2(chrome_read, 3);
  dup2(chrome_write, 4);
  close(chrome_read);
  close(chrome_write);
  g_cdp_write_fd = our_write;
  g_cdp_buffer = [NSMutableData data];
  g_cdp_pending = [NSMutableDictionary dictionary];
  g_cdp_read_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, our_read, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(g_cdp_read_source, ^{
    char buffer[65536];
    ssize_t n = read(our_read, buffer, sizeof buffer);
    if (n <= 0) {
      dispatch_source_cancel(g_cdp_read_source);
      return;
    }
    [g_cdp_buffer appendBytes:buffer length:static_cast<NSUInteger>(n)];
    for (;;) {
      NSRange nul = [g_cdp_buffer rangeOfData:[NSData dataWithBytes:"" length:1]
                                      options:0
                                        range:NSMakeRange(0, g_cdp_buffer.length)];
      if (nul.location == NSNotFound) {
        break;
      }
      CDPDeliver([g_cdp_buffer subdataWithRange:NSMakeRange(0, nul.location)]);
      [g_cdp_buffer replaceBytesInRange:NSMakeRange(0, nul.location + 1) withBytes:NULL length:0];
    }
  });
  dispatch_resume(g_cdp_read_source);
  return true;
}

}  // namespace

namespace cra {

void RunReadyBlocks() {
  g_page_activation = &PageActivation;
  g_translate_state = &TranslateState;
  g_key_event = &KeyEvent;
  g_download_path = &DownloadPath;
  g_permission_prompt = &MakeCraPrompt;
  g_page_fullscreen = &PageFullscreen;
  g_page_is_fullscreen = &PageIsFullscreen;
  g_target_url = &TargetURL;
  g_is_cra_page = &IsCraPage;
  g_block_request = &BlockRequest;
  StartDownloads(&ReportDownload);
  Strays().Start();
  StartProfilePrefs();
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
  // The page's DevTools protocol session, made on the first -sendDevToolsMethod:.
  std::unique_ptr<cra::PageSession> _session;
  NSString* _pendingURL;
  BOOL _waitingForPopup;
  BOOL _audioMuted;
  BOOL _closeRequested;
  BOOL _pendingFocus;
  // The saved back and forward list the page opens with (GitHub #273), until it has gone in.
  NSDictionary<NSString*, id>* _pendingHistory;
  // An extension's side panel page (initWithFrame:extensionSidePanelURL:…).
  BOOL _sidePanel;
  // A spare page's contents, made ahead and kept out of the tab strip (so out of extensions' sight) until a tab
  // takes it.
  std::unique_ptr<content::WebContents> _spareContents;
  raw_ptr<Profile> _spareProfile;
  // The page's DevTools: Chrome's DevTools window (never shown) and the window Cra docks, which holds the
  // frontend's view.
  base::WeakPtr<BrowserWindowInterface> _devToolsBrowser;
  NSWindow* _devToolsHost;
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
  // Marked as a side panel before it loads, so it has no tab for extensions (GitHub #265).
  _sidePanel = YES;
  return [self initWithFrame:frame url:url delegate:delegate incognito:NO profilePath:profilePath history:nil];
}

- (instancetype)initSpareWithFrame:(NSRect)frame profilePath:(NSString*)profilePath {
  _isSpare = YES;
  return [self initWithFrame:frame url:@"" delegate:nil incognito:NO profilePath:profilePath history:nil];
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
  _delegate = delegate;
  _pendingHistory = url && !incognito && [history[@"history"] isKindOfClass:NSString.class] ? [history copy] : nil;
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
    LoadingProfiles().insert(dir);
    profiles->CreateProfileAsync(dir, base::BindOnce(^(Profile* loaded) {
                                   LoadingProfiles().erase(dir);
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
  if (_isSpare) {
    // Made now, while nothing waits on it; it goes in a tab strip when a tab takes it (takeSpareWithURL:).
    _spareProfile = profile;
    _spareContents = content::WebContents::Create(content::WebContents::CreateParams(profile));
    return;
  }
  std::unique_ptr<content::WebContents> made = content::WebContents::Create(content::WebContents::CreateParams(profile));
  if (_sidePanel) {
    extensions::SetViewType(made.get(), extensions::mojom::ViewType::kExtensionSidePanel);
  }
  [self insertContents:std::move(made) profile:profile];
}

// A page the bridge made itself goes in its profile's tab strip (Chrome's tab helpers attach there), then
// loads: its saved history (GitHub #273), else its address.
- (void)insertContents:(std::unique_ptr<content::WebContents>)made profile:(Profile*)profile {
  PageHost* host = HostFor(profile);
  content::WebContents* contents = made.get();
  g_adding_own_page = true;
  host->browser()->GetTabStripModel()->AppendWebContents(std::move(made), /*foreground=*/false);
  g_adding_own_page = false;
  [self contentsCreated:contents];
  if (_pendingHistory) {
    NSDictionary* history = _pendingHistory;
    _pendingHistory = nil;
    std::string error;
    int count = cra::RestorePageHistory(contents, UTF8(history[@"history"]), [history[@"index"] intValue], &error);
    if ([_delegate respondsToSelector:@selector(browser:didRestoreHistoryEntries:error:)]) {
      [_delegate browser:self
          didRestoreHistoryEntries:count
                             error:count > 0 ? nil : (error.empty() ? @"nothing restored" : NS(error))];
    }
    if (count > 0) {
      _pendingURL = nil;
      return;
    }
  }
  NSString* url = _pendingURL;
  _pendingURL = nil;
  if (url.length) {
    [self loadURL:url];
  }
}

- (void)adoptContents:(content::WebContents*)contents {
  _waitingForPopup = NO;
  [self contentsCreated:contents];
  [self pageLoadingChanged];
  [self pageTitleChanged];
}

// Chrome's active tab follows the page Cra focuses, so extensions see the tab the user is on. A page Cra hosts
// is never attached to Chrome's window (cra_hosted_page.h), so this moves nothing.
- (void)makeChromeActiveTab {
  PageHost* host = _contents ? HostOf(_contents) : nullptr;
  if (!host) {
    return;
  }
  TabStripModel* tabs = host->browser()->GetTabStripModel();
  int index = tabs->GetIndexOfWebContents(_contents);
  if (index != TabStripModel::kNoTab && tabs->active_index() != index) {
    tabs->ActivateTabAt(index);
  }
}

// Cra's scripts in every frame before the page's own (PageScript.swift), as the CEF bridge installed them: the
// page agent runs new-document scripts only while its domain is enabled. Protocol messages run in order, so
// they are in before the page's first load.
- (void)installDocumentStartScripts {
  if (!g_document_start_params.count) {
    return;
  }
  [self sendDevToolsMethod:@"Page.enable" params:@"{}" completion:^(NSString*, NSString*) {}];
  for (NSString* params in g_document_start_params) {
    [self sendDevToolsMethod:@"Page.addScriptToEvaluateOnNewDocument"
                      params:params
                  completion:^(NSString*, NSString* error) {
                    if (error) {
                      NSLog(@"Cra: document start script not installed: %@", error);
                    }
                  }];
  }
}

- (void)contentsCreated:(content::WebContents*)contents {
  _contents = contents;
  contents->SetUserData(views::CraHostedPageKey(), std::make_unique<base::SupportsUserData::Data>());
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
  [self installDocumentStartScripts];
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
  // A new page: its colour isn't known until it reports one (CraBrowser.pageCanvasColor shows meanwhile).
  if ([_delegate respondsToSelector:@selector(browser:didReportBackgroundColor:)]) {
    [_delegate browser:self didReportBackgroundColor:@""];
  }
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

- (void)pagePictureInPicture:(BOOL)active {
  if (_isInPictureInPicture == active) {
    return;
  }
  _isInPictureInPicture = active;
  if (!active) {
    _isPictureInPicturePlaying = NO;
  } else {
    _isPictureInPicturePlaying = _contents->IsCurrentlyAudible() || _isAudible;
  }
  if ([_delegate respondsToSelector:@selector(browser:didChangePictureInPicture:)]) {
    [_delegate browser:self didChangePictureInPicture:active];
  }
}

- (void)pageMediaPlaying:(BOOL)playing {
  if (!_isInPictureInPicture || _isPictureInPicturePlaying == playing) {
    return;
  }
  _isPictureInPicturePlaying = playing;
  if ([_delegate respondsToSelector:@selector(browser:didChangePictureInPicturePlayback:)]) {
    [_delegate browser:self didChangePictureInPicturePlayback:playing];
  }
}

- (void)pageThemeColor {
  [_delegate browser:self didReportThemeColor:Hex(_contents->GetThemeColor())];
}

- (void)pageBackgroundColor {
  if ([_delegate respondsToSelector:@selector(browser:didReportBackgroundColor:)]) {
    [_delegate browser:self didReportBackgroundColor:Hex(_contents->GetBackgroundColor())];
  }
}

- (void)pageFavicon:(NSImage*)image url:(NSString*)url {
  [_delegate browser:self didLoadFavicon:image forURL:url];
}

- (void)pageFindResult {
  auto* find = find_in_page::FindTabHelper::FromWebContents(_contents);
  if (!find || ![_delegate respondsToSelector:@selector(browser:didFindMatches:activeMatch:)]) {
    return;
  }
  const find_in_page::FindNotificationDetails& result = find->find_result();
  [_delegate browser:self didFindMatches:result.number_of_matches() activeMatch:result.active_match_ordinal()];
}

- (void)pageFocused {
  [_delegate browserDidReceiveFocus:self];
}

- (void)pageDestroyed {
  _closedByPage = !_closeRequested && !g_quitting;
  _session.reset();
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
  [self makeChromeActiveTab];
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
    _spareContents.reset();
    [self didClose];
    return;
  }
  // A forced close, as CEF's CloseBrowser(true): no "Leave site?" (beforeunload), which would keep a closed tab's
  // page alive. Deleting the page closes its DevTools too.
  if (PageHost* host = HostOf(_contents)) {
    TabStripModel* tabs = host->browser()->GetTabStripModel();
    tabs->DetachAndDeleteWebContentsAt(tabs->GetIndexOfWebContents(_contents));
  }
}

#pragma mark Not yet

- (void)takeSpareWithURL:(NSString*)url history:(NSDictionary<NSString*, id>*)history {
  if (!_isSpare) {
    return;
  }
  _isSpare = NO;
  _currentURL = [url copy];
  _pendingURL = [url copy];
  _pendingHistory = [history[@"history"] isKindOfClass:NSString.class] ? [history copy] : nil;
  if (_spareContents && _spareProfile && !g_quitting) {
    Profile* profile = _spareProfile;
    _spareProfile = nullptr;
    [self insertContents:std::move(_spareContents) profile:profile];
  }
  // Taken before its profile loaded: createPageInProfile: makes it as a tab's page.
}
- (BOOL)startAgentDownload:(NSString*)url path:(NSString*)path update:(void (^)(CraDownloadInfo*))update {
  return NO;
}
- (void)cancelAgentDownload {
}
- (void)setPopupsAllowed:(BOOL)allowed {
}
- (void)exitFullscreen {
  if (_contents) {
    _contents->ExitFullscreen(/*will_cause_resize=*/true);
  }
}
#pragma mark DevTools

// What Chrome's DevTools open on: the action the app set (DevToolsToggle), as Chrome's DevToolsToggleAction.
- (DevToolsToggleAction)toggleAction {
  NSString* action = self.devToolsAction;
  self.devToolsAction = nil;
  if ([action isEqualToString:@"console"]) {
    return DevToolsToggleAction::ShowConsolePanel();
  }
  if ([action isEqualToString:@"elements"]) {
    return DevToolsToggleAction::ShowElementsPanel();
  }
  if ([action isEqualToString:@"inspect"]) {
    return DevToolsToggleAction::Inspect();
  }
  return DevToolsToggleAction::Show();
}

- (void)showDevTools {
  if (!_contents) {
    return;
  }
  // The app gives the area DevTools dock in; Cra's window for them goes there once Chrome has made them.
  [_delegate devToolsHostViewForBrowser:self];
  DevToolsWindow::OpenDevToolsWindow(_contents, [self toggleAction], DevToolsOpenedByAction::kUnknown);
}

- (void)showDevToolsInspectingPoint:(NSPoint)point {
  if (!_contents) {
    return;
  }
  if (!DevToolsWindow::GetInstanceForInspectedWebContents(_contents)) {
    [_delegate devToolsHostViewForBrowser:self];
  }
  DevToolsWindow::InspectElement(_contents->GetPrimaryMainFrame(), static_cast<int>(point.x),
                                 static_cast<int>(point.y));
}

- (void)applyDevToolsAction {
  if (_contents && DevToolsWindow::GetInstanceForInspectedWebContents(_contents)) {
    DevToolsWindow::OpenDevToolsWindow(_contents, [self toggleAction], DevToolsOpenedByAction::kUnknown);
  }
}

- (void)closeDevTools {
  if (_devToolsBrowser) {
    _devToolsBrowser->GetWindow()->Close();
  }
}

// Chrome made the page's DevTools window: its frontend moves into a borderless window of Cra's, which the app
// docks in the page's card (as the CEF bridge's hidden window was).
- (void)devToolsOpened:(BrowserWindowInterface*)devtools {
  DevToolsWindow* window = DevToolsWindow::AsDevToolsWindow(devtools);
  content::WebContents* frontend = window ? window->GetDevToolsWebContents().get() : nullptr;
  if (!frontend) {
    return;
  }
  _devToolsBrowser = devtools->GetWeakPtr();
  frontend->SetUserData(views::CraHostedPageKey(), std::make_unique<base::SupportsUserData::Data>());
  if (!_devToolsHost) {
    _devToolsHost = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                                styleMask:NSWindowStyleMaskBorderless
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    _devToolsHost.releasedWhenClosed = NO;
    _devToolsHost.contentView.autoresizesSubviews = YES;
  }
  NSView* view = frontend->GetNativeView().GetNativeNSView();
  [view removeFromSuperview];
  view.frame = _devToolsHost.contentView.bounds;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [_devToolsHost.contentView addSubview:view];
  _hasDevTools = YES;
  [_delegate browser:self didCreateDevToolsView:_devToolsHost.contentView];
  if ([_delegate respondsToSelector:@selector(browser:devToolsDocked:)]) {
    [_delegate browser:self devToolsDocked:YES];
  }
}

- (void)devToolsClosed:(BrowserWindowInterface*)devtools {
  _devToolsBrowser = nullptr;
  _hasDevTools = NO;
  [_devToolsHost.parentWindow removeChildWindow:_devToolsHost];
  [_devToolsHost orderOut:nil];
  [_delegate browserDidCloseDevTools:self];
}

- (NSWindow*)devToolsWindow {
  return _hasDevTools ? _devToolsHost : nil;
}
- (double)zoomLevel {
  auto* zoom = _contents ? zoom::ZoomController::FromWebContents(_contents) : nullptr;
  return zoom ? zoom->GetZoomLevel() : 0;
}
- (void)setZoomLevel:(double)level {
  if (auto* zoom = _contents ? zoom::ZoomController::FromWebContents(_contents) : nullptr) {
    zoom->SetZoomLevel(level);
  }
}
- (void)findText:(NSString*)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext {
  // Chrome's find helper tells a new search from the next match of the same one itself.
  if (auto* find = _contents ? find_in_page::FindTabHelper::FromWebContents(_contents) : nullptr) {
    find->StartFinding(base::SysNSStringToUTF16(text), forward, matchCase, /*find_match=*/true);
  }
}
- (void)stopFinding:(BOOL)clearSelection {
  if (auto* find = _contents ? find_in_page::FindTabHelper::FromWebContents(_contents) : nullptr) {
    find->StopFinding(clearSelection ? find_in_page::SelectionAction::kClear : find_in_page::SelectionAction::kKeep);
  }
}
#pragma mark Picture in Picture

- (void)requestPictureInPictureAutomatic:(BOOL)automatic {
  if (!_contents) {
    return;
  }
  if (_isInPictureInPicture) {
    if (!automatic) {
      [self exitPictureInPicture];
    }
    return;
  }
  // Leaving a tab takes only a video that plays aloud: a quiet page gets nothing, not even the gesture, which
  // would let it open pop-ups for a few seconds (GitHub #357).
  if (automatic && !_isAudible) {
    return;
  }
  NSString* script = [NSString stringWithFormat:@"%@(function(){})", PictureInPictureScript(automatic, -1, -1)];
  RunInFrames(_contents, script, /*gesture=*/true);
}

- (void)exitPictureInPicture {
  if (_contents) {
    RunInFrames(_contents, @"if(document.pictureInPictureElement){document.exitPictureInPicture().catch(function(){});}",
                false);
  }
}

// The window's close button: the video pauses and goes back to the page, as in Arc and Chrome.
- (void)closePictureInPicture {
  if (_contents) {
    RunInFrames(_contents,
                @"(function(){var v=document.pictureInPictureElement;if(!v)return;v.pause();"
                @"document.exitPictureInPicture().catch(function(){});})();",
                false);
  }
}

- (void)togglePictureInPicturePlayback {
  if (_contents) {
    RunInFrames(_contents,
                @"(function(){var v=document.pictureInPictureElement;if(!v)return;"
                @"if(v.paused||v.ended){v.play().catch(function(){});}else{v.pause();}})();",
                true);
  }
}

- (void)skipPictureInPictureBy:(double)seconds {
  if (_contents) {
    RunInFrames(_contents,
                [NSString stringWithFormat:@"(function(){var v=document.pictureInPictureElement;if(!v)return;"
                                           @"var t=v.currentTime+(%f);if(isFinite(v.duration))t=Math.min(t,v.duration);"
                                           @"v.currentTime=Math.max(0,t);})();",
                                           seconds],
                false);
  }
}

- (void)seekPictureInPictureTo:(double)seconds {
  if (_contents) {
    RunInFrames(_contents,
                [NSString stringWithFormat:@"(function(){var v=document.pictureInPictureElement;"
                                           @"if(!v||!isFinite(v.duration))return;"
                                           @"v.currentTime=Math.max(0,Math.min(%f,v.duration));})();",
                                           seconds],
                false);
  }
}

// The system print dialog, as CEF's Print: Chrome's print preview would hang off its never-shown window.
- (void)print {
  if (_contents) {
    printing::StartPrint(_contents, /*print_preview_disabled=*/true, /*has_selection=*/false);
  }
}
- (BOOL)runChromeCommand:(NSString*)name {
  return NO;
}
- (void)probeBackgroundColor {
  if (_contents) {
    [self pageBackgroundColor];
  }
}
// Arc's black while websites are dark, white while they are light.
+ (NSColor*)pageCanvasColor {
  NSInteger mode = cra::WebsiteAppearance();
  BOOL dark = mode == 2 || (mode == 0 && [NSApp.effectiveAppearance
                                             bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua,
                                                                                  NSAppearanceNameDarkAqua ]] ==
                                             NSAppearanceNameDarkAqua);
  return dark ? NSColor.blackColor : NSColor.whiteColor;
}
- (void)executeJavaScript:(NSString*)script inDevTools:(BOOL)inDevTools {
  if (!inDevTools) {
    [self executeJavaScript:script];
  }
}
#pragma mark DevTools protocol

- (void)sendDevToolsMethod:(NSString*)method
                    params:(NSString*)params
                completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  if (!_contents) {
    completion(nil, @"no browser");
    return;
  }
  if (!_session) {
    CraBrowser* __weak weakSelf = self;
    _session = std::make_unique<cra::PageSession>(_contents, ^(NSString* event, NSString* eventParams) {
      [weakSelf protocolEvent:event params:eventParams];
    });
  }
  _session->Send(UTF8(method), UTF8(params), completion);
}

// As the CEF bridge: an MCP drag's payload (Input.dragIntercepted) is kept for the drag; the client's own
// events go to devToolsEventHandler while one is set.
- (void)protocolEvent:(NSString*)method params:(NSString*)params {
  if (![method isEqualToString:@"Input.dragIntercepted"]) {
    if (self.devToolsEventHandler && params.length <= 262144) {
      self.devToolsEventHandler(method, params);
    }
    return;
  }
  if (params.length > 65536) {
    self.interceptedDragData = @"{\"oversized\":true}";
    return;
  }
  NSDictionary* payload = [NSJSONSerialization JSONObjectWithData:[params dataUsingEncoding:NSUTF8StringEncoding]
                                                          options:0
                                                            error:nil];
  NSDictionary* drag = [payload isKindOfClass:NSDictionary.class] ? payload[@"data"] : nil;
  if (![drag isKindOfClass:NSDictionary.class]) {
    return;
  }
  NSData* encoded = [NSJSONSerialization dataWithJSONObject:drag options:0 error:nil];
  self.interceptedDragData = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
}

// Runtime.evaluate in the main frame's isolated world `world`, as the CEF bridge does it.
- (void)evaluateInIsolatedWorld:(NSString*)world
                         params:(NSString*)params
                     completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  CraBrowser* __weak weakSelf = self;
  id (^parse)(NSString*) = ^id(NSString* json) {
    return json ? [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                                  options:0
                                                    error:nil]
                : nil;
  };
  [self sendDevToolsMethod:@"Page.getFrameTree"
                    params:@"{}"
                completion:^(NSString* tree, NSString* error) {
                  NSString* frameID = [parse(tree) valueForKeyPath:@"frameTree.frame.id"];
                  CraBrowser* strong = weakSelf;
                  if (!strong || ![frameID isKindOfClass:NSString.class]) {
                    completion(nil, error ?: @"no frame");
                    return;
                  }
                  NSData* body = [NSJSONSerialization dataWithJSONObject:@{@"frameId" : frameID, @"worldName" : world}
                                                                 options:0
                                                                   error:nil];
                  [strong sendDevToolsMethod:@"Page.createIsolatedWorld"
                                      params:[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding]
                                  completion:^(NSString* made, NSString* madeError) {
                                    NSNumber* context = [parse(made) valueForKey:@"executionContextId"];
                                    NSMutableDictionary* evaluate = [parse(params) mutableCopy];
                                    CraBrowser* again = weakSelf;
                                    if (!again || ![context isKindOfClass:NSNumber.class] ||
                                        ![evaluate isKindOfClass:NSMutableDictionary.class]) {
                                      completion(nil, madeError ?: @"no isolated world");
                                      return;
                                    }
                                    evaluate[@"contextId"] = context;
                                    NSData* json = [NSJSONSerialization dataWithJSONObject:evaluate options:0 error:nil];
                                    [again sendDevToolsMethod:@"Runtime.evaluate"
                                                       params:[[NSString alloc] initWithData:json
                                                                                    encoding:NSUTF8StringEncoding]
                                                   completion:completion];
                                  }];
                }];
}
- (CraSSLStatus*)sslStatus {
  content::NavigationEntry* entry = _contents ? _contents->GetController().GetLastCommittedEntry() : nullptr;
  if (!entry || entry->IsInitialEntry()) {
    return nil;
  }
  const content::SSLStatus& ssl = entry->GetSSL();
  CraSSLStatus* status = [[CraSSLStatus alloc] init];
  status.secureConnection = ssl.certificate != nullptr;
  status.certStatus = ssl.cert_status;
  status.contentStatus = static_cast<NSUInteger>(ssl.content_status);
  NSMutableArray<NSData*>* certificates = [NSMutableArray array];
  if (ssl.certificate) {
    auto add = [&](const CRYPTO_BUFFER* buffer) {
      base::span<const uint8_t> der = net::x509_util::CryptoBufferAsSpan(buffer);
      [certificates addObject:[NSData dataWithBytes:der.data() length:der.size()]];
    };
    add(ssl.certificate->cert_buffer());
    for (const auto& intermediate : ssl.certificate->intermediate_buffers()) {
      add(intermediate.get());
    }
  }
  status.certificates = certificates;
  return status;
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
  // The CEF bridge's switches (OnBeforeCommandLineProcessing), which say why each is there.
  args.push_back("--user-data-dir=" + UTF8(g_cache_path));
  args.push_back("--no-first-run");
  args.push_back("--no-default-browser-check");
  args.push_back("--no-startup-window");
  args.push_back("--disable-session-crashed-bubble");
  args.push_back("--hide-crash-restore-bubble");
  args.push_back("--profile-directory=Default");
  args.push_back("--autoplay-policy=document-user-activation-required");
  // --remote-debugging-pipe turns on navigator.webdriver in pages, and Google sign-in then refuses; Chrome
  // copies this switch to every renderer.
  args.push_back("--disable-blink-features=AutomationControlled");
  std::string disabled =
      "WebRtcHideLocalIpsWithMdns,WebUIOmniboxPopup,WebUIOmniboxAimPopup,AutofillAiWalletPrivatePasses,"
      "ScalableFrameEviction,OptimizationHints,PreloadingHeuristicsMLModel,HistoryEmbeddings,Glic,LensOverlay";
  // CraEngineMain adds AperitifHelpers to this one.
  args.push_back("--enable-features=ForceWebRequestProxyForTest,WebContentsDiscard,InfiniteTabsFreezing,"
                 "VideoPipForceTrustedForMediaPlaybackForTesting,HideDelegatedFrameHostMac");
  if (NSString* allowlist = ManagedAuthServerAllowlist()) {
    args.push_back("--auth-server-allowlist=" + UTF8(allowlist));
  }
  // The browser-level DevTools protocol over a private pipe: the trusted client Chrome requires for
  // Extensions.triggerAction (toolbar extension buttons).
  if (CDPPipeSetUp()) {
    args.push_back("--remote-debugging-pipe");
    args.push_back("--enable-unsafe-extension-debugging");
  }
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
    disabled += ",DisableLoadExtensionCommandLineSwitch";
    // Which profiles load each (extension-profiles.patch).
    if (g_extension_profiles.length) {
      args.push_back("--cra-load-extension-profiles=" + UTF8(g_extension_profiles));
    }
  }
  args.push_back("--disable-features=" + disabled);
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
  cra::StopProfilePrefs();
  delete g_keep_alive;
  g_keep_alive = nullptr;
  // Chrome keeps running while a --remote-debugging-pipe client is attached: hang up.
  if (g_cdp_write_fd >= 0) {
    close(g_cdp_write_fd);
    g_cdp_write_fd = -1;
  }
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
  g_extension_paths = [paths copy];
  g_extension_profiles = [profiles copy];
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
  NSMutableArray<NSString*>* all = [NSMutableArray array];
  for (NSDictionary* params in @[
         @{@"source" : script ?: @"", @"runImmediately" : @YES},
         @{@"source" : isolatedScript ?: @"", @"worldName" : world ?: @"", @"runImmediately" : @YES}
       ]) {
    if (![params[@"source"] length]) {
      continue;
    }
    NSData* json = [NSJSONSerialization dataWithJSONObject:params options:0 error:nil];
    if (json) {
      [all addObject:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    }
  }
  g_document_start_params = all;
}
+ (void)setContentBlockingEnabled:(BOOL)enabled {
  cra_blocker::Enabled().store(enabled);
}
+ (BOOL)contentBlockingEnabled {
  return cra_blocker::Enabled().load();
}

+ (void)setBlockedDomains:(NSArray<NSString*>*)domains {
  auto* set = new cra_blocker::DomainSet();
  for (NSString* domain in domains) {
    cra_blocker::AddListLine(*set, domain.UTF8String ?: "");
  }
  cra_blocker::Publish(set);
}
+ (void)loadBlockedDomainsFromFile:(NSString*)path completion:(void (^)(NSInteger))completion {
  void (^done)(NSInteger) = [completion copy];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSData* data = [NSData dataWithContentsOfFile:path];
    NSInteger count = 0;
    if (data) {
      cra_blocker::DomainSet* set =
          cra_blocker::ParseList(std::string_view(static_cast<const char*>(data.bytes), data.length));
      count = static_cast<NSInteger>(set->size());
      cra_blocker::Publish(set);
    }
    if (done) {
      dispatch_async(dispatch_get_main_queue(), ^{
        done(count);
      });
    }
  });
}
+ (NSInteger)blockedDomainCount {
  return static_cast<NSInteger>(cra_blocker::Count());
}
+ (BOOL)shouldBlockRequestURL:(NSString*)requestURL onPageURL:(NSString*)pageURL {
  return cra_blocker::ShouldBlock(cra_blocker::WebHost(requestURL.UTF8String ?: ""),
                                  cra_blocker::WebHost(pageURL.UTF8String ?: ""));
}
+ (void)endIncognitoSession {
}
+ (void)setRelaunchHandler:(void (^)(NSArray<NSString*>*))handler {
}
+ (void)setExtensionTabHandler:(CraBrowser* _Nullable (^)(NSString*, NSString* _Nullable, BOOL,
                                                          CraBrowser* _Nullable))handler {
  g_extension_tab_handler = [handler copy];
}
+ (void)setStrayPageHandler:(void (^)(NSString*, NSString* _Nullable))handler {
  g_stray_page_handler = [handler copy];
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
  g_download_destination_handler = [handler copy];
}
+ (BOOL)controlDownload:(uint32_t)identifier action:(CraDownloadControl)action {
  cra::DownloadControl control = action == CraDownloadControlPause    ? cra::DownloadControl::kPause
                                 : action == CraDownloadControlResume ? cra::DownloadControl::kResume
                                                                      : cra::DownloadControl::kCancel;
  return cra::ControlDownload(identifier, control);
}
+ (void)setProcessEventHandler:(void (^)(NSString*, NSString*, NSString* _Nullable))handler {
}
+ (BOOL)isExtensionWindow:(NSWindow*)window {
  return [g_extension_windows containsObject:window];
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
  return g_cdp_write_fd >= 0;
}
+ (void)sendBrowserDevToolsMethod:(NSString*)method
                           params:(NSString*)params
                       completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  [self sendBrowserDevToolsMethod:method params:params sessionID:nil completion:completion];
}
+ (void)sendBrowserDevToolsMethod:(NSString*)method
                           params:(NSString*)params
                        sessionID:(NSString*)sessionID
                       completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  if (g_cdp_write_fd < 0) {
    completion(nil, @"no DevTools pipe");
    return;
  }
  int message_id = ++g_cdp_next_id;
  g_cdp_pending[@(message_id)] = [completion copy];
  NSString* session = sessionID.length ? [NSString stringWithFormat:@",\"sessionId\":\"%@\"", sessionID] : @"";
  NSString* message = [NSString stringWithFormat:@"{\"id\":%d,\"method\":\"%@\",\"params\":%@%@}", message_id, method,
                                                 params.length ? params : @"{}", session];
  NSMutableData* data = [[message dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
  [data appendBytes:"" length:1];
  const char* bytes = static_cast<const char*>(data.bytes);
  for (size_t sent = 0; sent < data.length;) {
    ssize_t n = write(g_cdp_write_fd, bytes + sent, data.length - sent);
    if (n <= 0) {
      [g_cdp_pending removeObjectForKey:@(message_id)];
      completion(nil, @"pipe write failed");
      return;
    }
    sent += static_cast<size_t>(n);
  }
}
+ (void)setBrowserDevToolsEventHandler:(void (^)(NSString*, NSString*, NSString* _Nullable))handler {
  g_cdp_event_handler = [handler copy];
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
+ (NSInteger)loadStateOfProfile:(NSString*)profilePath {
  if (!g_ready || g_quitting) {
    return 0;
  }
  base::FilePath dir = ProfileDir(profilePath);
  if (g_browser_process->profile_manager()->GetProfileByPath(dir)) {
    return 2;
  }
  return LoadingProfiles().count(dir) ? 1 : 0;
}

#pragma mark Preferences

// A loaded profile (nil path: Default), or nullptr: these never load one.
+ (Profile*)loadedProfile:(NSString*)profilePath {
  if (!g_ready || g_quitting) {
    return nullptr;
  }
  return g_browser_process->profile_manager()->GetProfileByPath(ProfileDir(profilePath));
}
+ (void)setHttpsOnlyModeEnabled:(BOOL)enabled {
  cra::SetHttpsOnly(enabled);
}
+ (void)setFingerprintingProtectionEnabled:(BOOL)enabled {
  cra::SetFingerprintingProtection(enabled);
}
+ (void)setWebsiteAppearance:(NSInteger)mode {
  cra::SetWebsiteAppearance(mode);
}
+ (NSInteger)websiteAppearance {
  return cra::WebsiteAppearance();
}
+ (NSString*)secureDNSMode {
  return g_quitting ? nil : cra::SecureDNSPreference("dns_over_https.mode");
}
+ (NSString*)secureDNSTemplates {
  return g_quitting ? nil : cra::SecureDNSPreference("dns_over_https.templates");
}
+ (BOOL)setSecureDNSMode:(NSString*)mode templates:(NSString*)templates {
  return !g_quitting && cra::SetSecureDNS(mode, templates);
}
+ (BOOL)secureDNSIsManaged {
  return cra::SecureDNSIsManaged();
}
+ (void)setSecureDNSChangeHandler:(void (^)(void))handler {
  cra::SetSecureDNSHandler(handler);
}
+ (NSString*)extensionSettingsForProfile:(NSString*)profilePath {
  return cra::PreferenceJSON([self loadedProfile:profilePath], @"extensions.settings");
}
+ (NSString*)preference:(NSString*)name forProfile:(NSString*)profilePath {
  return cra::PreferenceJSON([self loadedProfile:profilePath], name);
}
+ (BOOL)setPreference:(NSString*)name json:(NSString*)json forProfile:(NSString*)profilePath {
  return cra::SetPreferenceJSON([self loadedProfile:profilePath], name, json);
}
+ (BOOL)resetPreference:(NSString*)name forProfile:(NSString*)profilePath {
  return cra::ResetPreference([self loadedProfile:profilePath], name);
}
+ (void)setProfileLoadedHandler:(void (^)(NSString*))handler {
  cra::SetProfileLoadedHandler(handler);
}
+ (void)setExtensionSettingsChangeHandler:(void (^)(void))handler {
  cra::SetExtensionSettingsHandler(handler);
}

@end

#pragma mark - CraApplication

namespace {

// A background test copy (CRA_TEST_BACKGROUND, HitchMonitor.swift) never takes the front: Chrome activates the
// app whenever it shows one of its windows.
BOOL CraTestBackground() {
  static BOOL background = [NSProcessInfo.processInfo.environment[@"CRA_TEST_BACKGROUND"] isEqualToString:@"1"];
  return background;
}
// Requests to come to the front made while Cra was in the background that went through, counted before a
// background test copy refuses them all (cra://debug?activations=).
NSInteger g_background_activations = 0;

// A page's view, wherever Cra shows it.
BOOL CraIsInPageView(NSView* view) {
  for (NSView* v = view; v; v = v.superview) {
    if ([NSStringFromClass([v class]) isEqualToString:@"WebContentsViewCocoa"]) {
      return YES;
    }
  }
  return NO;
}

// Whether a key is a shortcut that Chromium keeps from pages because it is enabled in System
// Settings ▸ Keyboard ▸ Shortcuts (EventIsReservedBySystem, content/browser/cocoa/
// system_hotkey_map.mm): ⌘Space set to switch input sources (#174), ⌘` for the next window.
// macOS acts on these inside -[NSApplication sendEvent:]. Same set as Chromium's map: the
// enabled "standard" entries of com.apple.symbolichotkeys, without 80 and 82, plus ⌘` and ⇧⌘`
// for 27 when the user hasn't changed it. Read live (a few µs) so a changed setting applies.
BOOL CraIsSystemHotKey(NSEvent* event) {
    const NSEventModifierFlags relevant =
        NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;
    NSEventModifierFlags mods = event.modifierFlags & relevant;
    NSDictionary* stored = CFBridgingRelease(
        CFPreferencesCopyAppValue(CFSTR("AppleSymbolicHotKeys"), CFSTR("com.apple.symbolichotkeys")));
    NSMutableDictionary* hotKeys = [@{@"27": @{@"enabled": @YES,
                                              @"value": @{@"type": @"standard", @"parameters": @[@96, @50, @(NSEventModifierFlagCommand)]}}}
                                       mutableCopy];
    if ([stored isKindOfClass:[NSDictionary class]]) [hotKeys addEntriesFromDictionary:stored];
    [hotKeys removeObjectsForKeys:@[@"80", @"82"]];
    for (NSString* identifier in hotKeys) {
        NSDictionary* hotKey = hotKeys[identifier];
        if (![hotKey isKindOfClass:[NSDictionary class]] || ![hotKey[@"enabled"] respondsToSelector:@selector(boolValue)] ||
            ![hotKey[@"enabled"] boolValue])
            continue;
        NSDictionary* value = hotKey[@"value"];
        if (![value isKindOfClass:[NSDictionary class]] || ![value[@"type"] isEqual:@"standard"]) continue;
        NSArray* parameters = value[@"parameters"];
        if (![parameters isKindOfClass:[NSArray class]] || parameters.count != 3 ||
            ![parameters[1] isKindOfClass:[NSNumber class]] || ![parameters[2] isKindOfClass:[NSNumber class]])
            continue;
        if ([parameters[1] unsignedShortValue] != event.keyCode) continue;
        NSEventModifierFlags hotKeyMods = [parameters[2] unsignedIntegerValue] & relevant;
        if (hotKeyMods == mods) return YES;
        if ([identifier isEqualToString:@"27"] && hotKeyMods == (mods & ~NSEventModifierFlagShift)) return YES;
    }
    return NO;
}

}  // namespace

@implementation CraApplication {
  NSHashTable<NSEvent*>* _forwardedKeyEvents;
}

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
  return g_background_activations;
}

- (BOOL)allowsActivation {
  if (!self.isActive) {
    g_background_activations++;
  }
  return !CraTestBackground();
}

- (void)activateIgnoringOtherApps:(BOOL)flag {
  if ([self allowsActivation]) {
    [super activateIgnoringOtherApps:flag];
  }
}

- (void)activate {
  if ([self allowsActivation]) {
    [super activate];
  }
}

// Chrome's rule: when a page has focus, ⌘-shortcuts go to the page first and reach the menu bar only if the page
// leaves them alone (⌘F in Google Docs, ⌘← in a text field). Cra's window isn't Chrome's, whose command
// dispatcher does this, so the key goes to the page's view here; the page's keys come back through Cra's key
// hook (KeyEvent). Enabled macOS shortcuts (CraIsSystemHotKey) take the normal path, as in Chrome and Arc.
- (void)sendEvent:(NSEvent*)event {
  if ([_forwardedKeyEvents containsObject:event]) {
    [_forwardedKeyEvents removeObject:event];
    [super sendEvent:event];
    return;
  }
  if (event.type == NSEventTypeKeyDown && (event.modifierFlags & NSEventModifierFlagCommand) &&
      !CraIsSystemHotKey(event)) {
    NSWindow* key = self.keyWindow;
    NSResponder* responder = key.firstResponder;
    if ([responder isKindOfClass:[NSView class]] && CraIsInPageView(static_cast<NSView*>(responder))) {
      if (!_forwardedKeyEvents) {
        _forwardedKeyEvents = [NSHashTable weakObjectsHashTable];
      }
      [_forwardedKeyEvents addObject:event];
      [key sendEvent:event];
      return;
    }
  }
  [super sendEvent:event];
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
