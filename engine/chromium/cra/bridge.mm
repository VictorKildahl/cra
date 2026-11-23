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
#include "cra/fetch.h"
#include "cra/page_protocol.h"
#include "cra/permission_prompt.h"
#include "cra/profile_prefs.h"

#include <fcntl.h>
#include <objc/runtime.h>
#include <unistd.h>

#include <algorithm>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "base/no_destructor.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/version_info/version_info.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/grit/generated_resources.h"
#include "components/renderer_context_menu/render_view_context_menu_base.h"
#include "content/public/browser/context_menu_params.h"
#include "third_party/blink/public/mojom/context_menu/context_menu.mojom.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/menus/simple_menu_model.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/printing/print_view_manager_common.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/cra_engine_hooks.h"
#include "chrome/browser/cra_permission_hook.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/lifetime/application_lifetime_desktop.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/permissions/system/system_permission_settings.h"
#include "chrome/browser/tab_group_sync/tab_group_sync_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/keyboard_lock_controller.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/browser_window/public/browser_collection_observer.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/browser_window/public/global_browser_collection.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/unload_controller.h"
#include "components/saved_tab_groups/public/saved_tab_group.h"
#include "components/saved_tab_groups/public/saved_tab_group_tab.h"
#include "components/saved_tab_groups/public/tab_group_sync_service.h"
#include "components/saved_tab_groups/public/types.h"
#include "components/tab_groups/tab_group_color.h"
#include "components/tab_groups/tab_group_id.h"
#include "chrome/common/chrome_result_codes.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/media_player_id.h"
#include "content/public/browser/navigation_throttle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "ui/base/cocoa/secure_password_input.h"
#include "ui/base/page_transition_types.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/child_process_termination_info.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/render_process_host_observer.h"
#include "content/public/browser/site_instance.h"
#include "content/public/common/result_codes.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "components/blocked_content/popup_blocker_tab_helper.h"
#include "chrome/browser/ui/tabs/tab_muted_utils.h"
#include "chrome/browser/ui/tab_sharing/tab_sharing_infobar_delegate.h"
#include "chrome/browser/ui/views/tab_sharing/tab_capture_contents_border_helper.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/permissions/cra_permission_tabs.h"
#include "content/public/browser/cra_live_connection.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "components/zoom/zoom_controller.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_item_utils.h"
#include "extensions/browser/webstore_installer.h"
#include "content/public/browser/download_manager.h"
#include "content/public/browser/download_request_utils.h"
#include "components/download/public/common/download_url_parameters.h"
#include "base/functional/callback_helpers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
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
#include "ui/compositor/compositor.h"
#include "ui/views/widget/widget.h"
#include "chrome/browser/ui/browser_element_identifiers.h"
#include "chrome/browser/ui/interaction/browser_elements.h"
#include "ui/base/interaction/element_tracker.h"
#include "ui/views/view.h"
#include "ui/views/view_class_properties.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"
#include "url/origin.h"

extern "C" int CraEngineMain(int argc, const char** argv);

@interface CraBrowser ()
- (void)adoptContents:(content::WebContents*)contents;
/// The page's Boost colorize for its WebPreferences (#602), empty for none.
- (std::string)boostTintForPrefs;
- (void)contentsCreated:(content::WebContents*)contents;
- (void)pageStartedNavigation:(content::NavigationHandle*)handle;
- (void)pageFinishedNavigation:(content::NavigationHandle*)handle;
- (void)pageLoadingChanged;
- (void)pageProgress:(double)progress;
- (void)pageFinishedLoad;
- (void)pageTitleChanged;
- (void)pageAudible:(BOOL)audible;
- (void)pageMediaSession:(CraMediaSessionState)state controllable:(BOOL)controllable;
- (void)pageFocused;
- (void)pageDestroyed;
- (void)pageBackgroundColor;
- (void)applyPageCanvasTo:(content::RenderWidgetHostView*)view;
- (void)applyCanvasBaseTo:(content::WebContents*)contents;
- (void)applySpareCanvas;
- (void)refreshCanvasBase:(content::WebContents*)contents;
- (void)pageFirstPaint;
- (void)pageFavicon:(NSImage*)image url:(NSString*)url;
- (void)pageFindResult;
- (void)pagePictureInPicture:(BOOL)active;
- (void)pageProcessEvent:(NSString*)kind detail:(NSString*)detail url:(const GURL&)url;
- (void)pageCaptureChanged;
- (void)agentDownloadItem:(download::DownloadItem*)item;
- (bool)agentDownloadTakes:(download::DownloadItem*)item;
- (void)pageMediaPlaying:(BOOL)playing;
- (void)pageSoundPlaying:(BOOL)playing;
- (void)dropSpareContents;
- (void)pageInfoBarsChanged;
- (void)pageTabSharingChanged;
- (void)pagePictureInPictureTime;
@property(nonatomic) BOOL inPageFullscreen;
- (void)devToolsOpened:(BrowserWindowInterface*)devtools;
- (void)devToolsClosed:(BrowserWindowInterface*)devtools;
- (void)devToolsShowsPanel:(NSString*)panel;
- (void)devToolsFrontendDocked:(BOOL)docked;
- (void)devToolsFrontendPageBounds:(NSRect)bounds;
- (void)makeChromeActiveTab;
@end

// The window that holds a page's DevTools frontend for the app (-devToolsWindow): docked in a card it lends its
// view, undocked it is the DevTools window. Its title bar's close button closes DevTools, as Chrome's does.
@interface CraDevToolsHostWindow : NSWindow
@property(nonatomic, weak) CraBrowser* page;
@end

// A page's view: counted once for cra://debug?pageWindows= when it first shows in a window (a Cra window, the only
// kind it goes in, so never away).
@interface CraPageContainerView : NSView
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
void (^g_process_event_handler)(NSString*, NSString*, NSString* _Nullable) = nil;
void (^g_view_source_handler)(CraBrowser*, NSString*) = nil;
void (^g_relaunch_handler)(NSArray<NSString*>*) = nil;
NSString* _Nullable (^g_image_search_title)(NSString*) = nil;
// The "Open Link in New Tab" item: its title and whether its tab opens behind (LinkMenu, GitHub #276).
NSString* g_link_menu_title = @"Open Link in New Tab";
BOOL g_link_menu_background = YES;
// A test's command for the next page menu, run instead of showing it (-1: none).
int g_next_page_menu_command = -1;

// Cra's own page menu items (cra_engine_hooks.h's range).
constexpr int kMenuOpenLinkNewTab = cra::kCraMenuFirst;
constexpr int kMenuOpenLinkSplitView = cra::kCraMenuFirst + 1;
constexpr int kMenuOpenLinkLittleWindow = cra::kCraMenuFirst + 2;
constexpr int kMenuCaptureImage = cra::kCraMenuFirst + 3;
void (^g_download_destination_handler)(NSString* _Nullable, NSString*, void (^)(NSString* _Nullable)) = nil;
// Chrome windows an extension opened as popups (windows.create type popup), which stay Chrome's.
NSHashTable<NSWindow*>* g_extension_windows = nil;
// Set while the bridge makes one of its own hidden Browsers.
bool g_making_host = false;

// The profile folder's name ("Default", "Profile 1"), nil off the record: what the app's handlers take.
NSString* ProfileFolder(Profile* profile) {
  return profile->IsOffTheRecord() ? nil : base::SysUTF8ToNSString(profile->GetBaseName().AsUTF8Unsafe());
}

// The address each new page was opened for (DidOpenRequestedURL on its opener), until Cra adopts it: a page's
// own pop-up has no visible address before its navigation starts, and Cra matches it to a blocked one (#357).
std::map<content::WebContents*, GURL>& OpenedURLs() {
  static auto* urls = new std::map<content::WebContents*, GURL>();
  return *urls;
}
// The page each new page was opened from (DidOpenRequestedURL on it), until Cra adopts it: a ⌘-click's tab has no
// JavaScript opener, and Chrome's tab strip names the tab that was active then (a Little Window's page, say).
std::map<content::WebContents*, base::WeakPtr<content::WebContents>>& OpenedFrom() {
  static auto* sources = new std::map<content::WebContents*, base::WeakPtr<content::WebContents>>();
  return *sources;
}

// Every CraBrowser that has a page, by its page.
std::map<content::WebContents*, CraBrowser* __weak>& PagesByContents() {
  static auto* pages = new std::map<content::WebContents*, CraBrowser* __weak>();
  return *pages;
}
NSInteger g_live_browsers = 0;
// Pages made ahead for the next tab, outside any tab strip: they go before Chrome destroys their profile at quit,
// which CHECKs that no page of it is left (WebContentsOfBrowserContext).
NSHashTable<CraBrowser*>* SparePages() {
  static NSHashTable<CraBrowser*>* spares = [NSHashTable weakObjectsHashTable];
  return spares;
}
// Set while Cra adds a page of its own, so the tab strip observer leaves it alone.
bool g_adding_own_page = false;

CraBrowser* BrowserFor(content::WebContents* contents) {
  auto it = PagesByContents().find(contents);
  return it == PagesByContents().end() ? nil : it->second;
}

// The Boost colours of a page of Cra's, every colour it draws but its images (#602; cra_engine_hooks.h).
std::string BoostTint(content::WebContents* contents) {
  CraBrowser* page = BrowserFor(contents);
  return page ? [page boostTintForPrefs] : std::string();
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

// Whether pages see a dark Mac: View ▸ Appearance, or the Mac's own on Automatic.
BOOL PagesAreDark() {
  NSInteger mode = cra::WebsiteAppearance();
  return mode == 2 || (mode == 0 && [NSApp.effectiveAppearance
                                        bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua,
                                                                             NSAppearanceNameDarkAqua ]] ==
                                        NSAppearanceNameDarkAqua);
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
                     public find_in_page::FindResultObserver,
                     public infobars::InfoBarManager::Observer {
 public:
  PageObserver(content::WebContents* contents, CraBrowser* owner)
      : content::WebContentsObserver(contents), owner_(owner) {
    WatchInfoBars();
    WatchTabCapture();
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
    if (infobars_) {
      infobars_->RemoveObserver(this);
    }
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

  void DidOpenRequestedURL(content::WebContents* new_contents,
                           content::RenderFrameHost* source,
                           const GURL& url,
                           const content::Referrer& referrer,
                           WindowOpenDisposition disposition,
                           ui::PageTransition transition,
                           bool started_from_context_menu,
                           bool renderer_initiated) override {
    if (new_contents != web_contents()) {
      OpenedURLs()[new_contents] = url;
      OpenedFrom()[new_contents] = web_contents()->GetWeakPtr();
    }
  }
  // Chromium calls this for a Document Picture in Picture window too (documentPictureInPicture.requestWindow): a
  // page of the site's own, with its own player controls. Cra's Picture in Picture is the video's, as CEF reported
  // it, so only a video counts; its controls over a document window doubled the site's (GitHub #460).
  void MediaPictureInPictureChanged(bool) override {
    [owner_ pagePictureInPicture:web_contents()->HasPictureInPictureVideo()];
  }

  // "Aw, Snap!" and "Page Unresponsive", for Cra's performance recorder (GitHub #91).
  void PrimaryMainFrameRenderProcessGone(base::TerminationStatus status) override {
    // The page's next renderer (a tab slept by discarding, then shown again) starts on Arc's canvas too (#712).
    [owner_ applyCanvasBaseTo:web_contents()];
    const char* what = "unknown";
    switch (status) {
      case base::TERMINATION_STATUS_ABNORMAL_TERMINATION:
        what = "abnormal termination";
        break;
      case base::TERMINATION_STATUS_PROCESS_WAS_KILLED:
        what = "killed";
        break;
      case base::TERMINATION_STATUS_PROCESS_CRASHED:
        what = "crashed";
        break;
      case base::TERMINATION_STATUS_OOM:
        what = "out of memory";
        break;
      case base::TERMINATION_STATUS_LAUNCH_FAILED:
        what = "launch failed";
        break;
      default:
        break;
    }
    [owner_ pageProcessEvent:@"terminated" detail:@(what) url:GURL()];
  }
  void OnRendererUnresponsive(content::RenderProcessHost* host) override {
    [owner_ pageProcessEvent:@"unresponsive" detail:@"" url:GURL()];
  }
  void OnRendererResponsive(content::RenderProcessHost* host) override {
    [owner_ pageProcessEvent:@"responsive" detail:@"" url:GURL()];
  }
  void MediaStartedPlaying(const MediaPlayerInfo& info, const content::MediaPlayerId& id) override {
    [owner_ pageMediaPlaying:YES];
    if (info.has_audio && sounding_.insert(id).second && sounding_.size() == 1) {
      [owner_ pageSoundPlaying:YES];
    }
  }
  void MediaStoppedPlaying(const MediaPlayerInfo& info,
                           const content::MediaPlayerId& id,
                           WebContentsObserver::MediaStoppedReason reason) override {
    [owner_ pageMediaPlaying:NO];
    if (sounding_.erase(id) && sounding_.empty()) {
      [owner_ pageSoundPlaying:NO];
    }
  }
  void OnBackgroundColorChanged() override { [owner_ pageBackgroundColor]; }
  // A main frame's new view (a new page, or a site that moves to another process) shows Arc's canvas until its
  // first frame, not Chromium's white or Chrome's grey.
  void RenderFrameCreated(content::RenderFrameHost* frame) override {
    if (!frame->GetParent()) {
      [owner_ applyPageCanvasTo:frame->GetView()];
    }
  }
  void RenderFrameHostChanged(content::RenderFrameHost* old_host, content::RenderFrameHost* new_host) override {
    if (new_host && !new_host->GetParent()) {
      [owner_ applyPageCanvasTo:new_host->GetView()];
    }
  }
  void RenderViewReady() override { [owner_ applyPageCanvasTo:web_contents()->GetRenderWidgetHostView()]; }

  void DidStartNavigation(content::NavigationHandle* handle) override {
    WatchInfoBars();
    WatchTabCapture();
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
  void DidFirstVisuallyNonEmptyPaint() override { [owner_ pageFirstPaint]; }
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
  // Players playing sound now, for the immediate sound state (music notes).
  std::set<content::MediaPlayerId> sounding_;
  raw_ptr<infobars::InfoBarManager> infobars_ = nullptr;

 public:
  // Chrome's bars over the page (infobars::ContentInfoBarManager, made when the page becomes a tab): Cra shows them
  // itself; Chrome would draw them in its never-shown window.
  void WatchInfoBars() {
    if (infobars_) {
      return;
    }
    if (auto* manager = infobars::ContentInfoBarManager::FromWebContents(web_contents())) {
      manager->AddObserver(this);
      infobars_ = manager;
      if (!manager->infobars().empty()) {
        [owner_ pageInfoBarsChanged];
      }
    }
  }
  void OnInfoBarAdded(infobars::InfoBar* infobar) override { [owner_ pageInfoBarsChanged]; }
  void OnInfoBarRemoved(infobars::InfoBar* infobar, bool animate) override { [owner_ pageInfoBarsChanged]; }
  void OnInfoBarReplaced(infobars::InfoBar* old_infobar, infobars::InfoBar* new_infobar) override {
    [owner_ pageInfoBarsChanged];
  }
  void OnManagerWillBeDestroyed(infobars::InfoBarManager* manager) override {
    manager->RemoveObserver(this);
    infobars_ = nullptr;
  }

  // The tab a call shares (TabSharingUIViews tells the shared tab's TabCaptureContentsBorderHelper, which Chrome
  // makes with the tab's features): Arc rings it in yellow. Chrome's blue border would go in its never-shown window.
  // A page that moves to another Browser gets a new helper, so the subscription follows the current one.
  void WatchTabCapture() {
    auto* helper = TabCaptureContentsBorderHelper::FromWebContents(web_contents());
    uintptr_t id = reinterpret_cast<uintptr_t>(helper);
    if (!helper || id == capture_helper_) {
      return;
    }
    capture_helper_ = id;
    // Unretained: the subscription is this observer's, and ends with it.
    capture_subscription_ =
        helper->AddOnTabCaptureChangeCallback(base::BindRepeating(&PageObserver::TabCaptureChanged, base::Unretained(this)));
    if (helper->IsTabCapturing()) {
      [owner_ pageTabSharingChanged];
    }
  }
  void TabCaptureChanged(bool border_shown) { [owner_ pageTabSharingChanged]; }

 private:
  // The helper subscribed to, by address only: it belongs to the tab's features and may go first.
  uintptr_t capture_helper_ = 0;
  base::CallbackListSubscription capture_subscription_;
};

// A Browser's window that holds Cra's pages: never seen, never clicked, never captured, never key or main (keys
// would go to a window with nothing in it). Chrome still anchors bubbles to it (an extension's popup), which Cra's
// app finds as a child of a page window (ExtensionPopupCandidate) and frames under its own button.
// The windows MakeHostWindow made, and the unseen stray windows (StrayWindows); Chrome's window class answers NO for
// them (swapped once, as Cra's app does for CEF's page windows in EmbeddedPages: the window's own class may be a KVO
// subclass, so it isn't replaced).
NSHashTable<NSWindow*>* g_host_windows = nil;

// Where and how pages and Chrome's windows for them came on screen: cra://debug?pageWindows= (#354), as the CEF
// bridge counts them. On the engine a page is a view in a Cra window, and Chrome's only windows for pages are a
// profile's hidden window and a page's DevTools window: a window shown on a display brings that display to a
// desktop, so they start on the Cra window in use (g_page_window_start), without macOS's animation.
NSInteger g_page_windows_shown = 0;
NSInteger g_page_windows_away = 0;
NSInteger g_page_windows_animated = 0;
NSRect (^g_page_window_start)(NSSize) = nil;

// Whether one of Cra's windows fills the screen on the Space the user is looking at.
BOOL FullScreenWindowOnActiveSpace(NSWindow* except) {
  for (NSWindow* window in NSApp.windows) {
    if (window != except && window.visible && (window.styleMask & NSWindowStyleMaskFullScreen) && window.onActiveSpace) {
      return YES;
    }
  }
  return NO;
}

// An extension's own window (Bitwarden's vault unlock prompt, chrome.windows.create) that opens over a full-screen
// Cra joins that Space as a full-screen auxiliary, as the CEF bridge's did: as an ordinary window it opened on a
// desktop and macOS switched there. Only over a full-screen Cra: an auxiliary window can't go full screen itself.
void JoinFullScreenSpace(NSWindow* window) {
  NSWindowCollectionBehavior behavior = window.collectionBehavior;
  behavior &= ~(NSWindowCollectionBehaviorPrimary | NSWindowCollectionBehaviorFullScreenPrimary |
                NSWindowCollectionBehaviorFullScreenAllowsTiling | NSWindowCollectionBehaviorCanJoinAllSpaces);
  behavior |= NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorMoveToActiveSpace;
  window.collectionBehavior = behavior;
}

// A Chrome window Cra keeps out of sight (a profile's, a page's DevTools) never goes full screen itself. Made while a
// Cra window was full screen, macOS took it into full screen with it, and Chrome moved its tab strip and toolbar into
// windows of their own at the top of the screen, which the window's alpha doesn't reach: Chrome's whole top bar over
// the page (GitHub #472, #486). An auxiliary window still sits on Cra's full-screen Space, where Chrome anchors its
// bubbles (an extension's popup) to it.
void NeverFullScreen(NSWindow* window) {
  NSWindowCollectionBehavior behavior = window.collectionBehavior;
  behavior &= ~(NSWindowCollectionBehaviorPrimary | NSWindowCollectionBehaviorFullScreenPrimary |
                NSWindowCollectionBehaviorFullScreenAllowsTiling);
  behavior |= NSWindowCollectionBehaviorFullScreenAuxiliary;
  window.collectionBehavior = behavior;
}

void PlaceChromeWindow(NSWindow* window) {
  if (!window) {
    return;
  }
  NSRect frame = g_page_window_start ? g_page_window_start(window.frame.size) : NSZeroRect;
  if (!NSIsEmptyRect(frame)) {
    [window setFrame:frame display:NO];
  }
  window.animationBehavior = NSWindowAnimationBehaviorNone;
}

// A window of Chrome's for a page, where it is now: away when its centre is on no Cra window on screen.
void NoteChromeWindowShown(NSWindow* window) {
  if (!window) {
    return;
  }
  g_page_windows_shown++;
  if (window.animationBehavior != NSWindowAnimationBehaviorNone) {
    g_page_windows_animated++;
  }
  NSPoint centre = NSMakePoint(NSMidX(window.frame), NSMidY(window.frame));
  BOOL anyCraWindow = NO;
  for (NSWindow* w in NSApp.windows) {
    if (w == window || !w.isVisible || w.parentWindow || w.alphaValue == 0 || [g_host_windows containsObject:w]) {
      continue;
    }
    if (NSPointInRect(centre, w.frame)) {
      return;
    }
    anyCraWindow = YES;
  }
  if (anyCraWindow) {
    g_page_windows_away++;
  }
}

// A Chrome window nobody sees never becomes key or main: keys would go to a window with nothing in it on screen.
// Nor is it a row of the Window menu, which the Dock icon's menu lists too: it stays ordered in at alpha 0, titled
// after its active page, and one browser window showed there twice (scenario dock-menu-windows).
void NeverKeyOrMain(NSWindow* window) {
  if (!window) {
    return;
  }
  if (!g_host_windows) {
    g_host_windows = [NSHashTable weakObjectsHashTable];
  }
  // Once per class: a page's host and a page's DevTools window can be different kinds of Chrome window.
  static NSMutableSet<NSString*>* patched = [NSMutableSet set];
  Class cls = [window class];
  if (![patched containsObject:NSStringFromClass(cls)]) {
    [patched addObject:NSStringFromClass(cls)];
    for (NSString* name in @[ @"canBecomeKeyWindow", @"canBecomeMainWindow" ]) {
      SEL selector = NSSelectorFromString(name);
      Method method = class_getInstanceMethod(cls, selector);
      if (!method) {
        continue;
      }
      using BoolIMP = BOOL (*)(id, SEL);
      BoolIMP original = reinterpret_cast<BoolIMP>(method_getImplementation(method));
      method_setImplementation(method, imp_implementationWithBlock(^BOOL(id me) {
                                 return [g_host_windows containsObject:me] ? NO : original(me, selector);
                               }));
    }
  }
  [g_host_windows addObject:window];
  window.excludedFromWindowsMenu = YES;
}

void MakeHostWindow(NSWindow* window) {
  if (!window) {
    return;
  }
  PlaceChromeWindow(window);
  NoteChromeWindowShown(window);
  window.alphaValue = 0;
  window.ignoresMouseEvents = YES;
  window.sharingType = NSWindowSharingNone;
  NeverFullScreen(window);
  NeverKeyOrMain(window);
}

// The DevTools frontend of a page of Cra's: the panel it shows, on load and on every switch, so ⌥⌘J and Network
// tell a switch from a close (GitHub #138), as the CEF bridge's frontend hooks report it.
const char kDevToolsPanelScript[] =
    "(function(){if(window.__craPanel)return;window.__craPanel=1;"
    "function find(root,sel){var r=root.querySelector(sel);if(r)return r;var all=root.querySelectorAll('*');"
    "for(var i=0;i<all.length;i++){if(all[i].shadowRoot){var f=find(all[i].shadowRoot,sel);if(f)return f;}}return null;}"
    "var now=null,n=0,w=setInterval(function(){var e=find(document,'#tab-elements'),tabs=e&&e.parentNode;"
    "if(tabs){clearInterval(w);var report=function(){var t=tabs.querySelector('.tabbed-pane-header-tab.selected');"
    "var p=t&&t.id.indexOf('tab-')==0?t.id.slice(4):null;if(p&&p!==now){now=p;console.log('__cra_devtools_panel:'+p);}};"
    "report();new MutationObserver(report).observe(tabs,{attributes:true,subtree:true,attributeFilter:['class']});return;}"
    "if(++n>200)clearInterval(w);},150);})();";

// The frontend docked in Cra's card, as on CEF (Sources/CraCEF/CraCEF.mm, kCraDevToolsHooks): Chrome's DevTools window
// is never shown and stays undocked (patches/cra-devtools.patch), while the frontend loads with can_dock=true, so
// it draws the page's place, its splitter, its close button and its dock menu. Its embedder calls for docking come
// back here as console messages instead of going to Chrome: setIsDocked (acknowledged at once; Cra lays the window
// out), setInspectedPageBounds (where Cra puts the page) and closeWindow (the close button).
const char kDevToolsDockScript[] =
    "(function(){var h=window.InspectorFrontendHost;if(!h||h.__craDock)return;h.__craDock=1;"
    "if(!/[?&]can_dock=true/.test(location.search))return;"
    "h.closeWindow=function(){console.log('__cra_devtools_close');};"
    "var sent=false;"
    "h.setInspectedPageBounds=function(b){sent=true;try{console.log('__cra_devtools_bounds:'+JSON.stringify("
    "{x:b.x,y:b.y,width:b.width,height:b.height}));}catch(e){}};"
    "h.setIsDocked=function(d,cb){console.log('__cra_devtools_docked:'+(d?1:0));if(cb)setTimeout(function(){cb();},0);};"
    // The frontend may have laid out before these hooks: a resize makes a docked one send its placeholder again,
    // and one that stays silent is undocked.
    "window.dispatchEvent(new Event('resize'));"
    "requestAnimationFrame(function(){requestAnimationFrame(function(){setTimeout(function(){"
    "if(!sent)console.log('__cra_devtools_docked:0');},80);});});"
    "})();";

class DevToolsFrontendObserver : public content::WebContentsObserver {
 public:
  DevToolsFrontendObserver(content::WebContents* frontend, CraBrowser* page)
      : content::WebContentsObserver(frontend), page_(page) {
    Run();
  }

  void DidFinishLoad(content::RenderFrameHost* frame, const GURL& url) override {
    if (frame->IsInPrimaryMainFrame()) {
      Run();
    }
  }

  void OnDidAddMessageToConsole(content::RenderFrameHost* frame,
                                blink::mojom::ConsoleMessageLevel level,
                                const std::u16string& message,
                                int32_t line,
                                const std::u16string& source,
                                const std::optional<std::u16string>& stack) override {
    constexpr std::u16string_view kPanel = u"__cra_devtools_panel:";
    constexpr std::u16string_view kClose = u"__cra_devtools_close";
    constexpr std::u16string_view kDocked = u"__cra_devtools_docked:";
    constexpr std::u16string_view kBounds = u"__cra_devtools_bounds:";
    if (message.starts_with(kPanel) && message.size() > kPanel.size()) {
      [page_ devToolsShowsPanel:base::SysUTF16ToNSString(message.substr(kPanel.size()))];
    } else if (message == kClose) {
      // Later: closing destroys this observer's WebContents.
      CraBrowser* page = page_;
      dispatch_async(dispatch_get_main_queue(), ^{
        [page closeDevTools];
      });
    } else if (message.starts_with(kDocked) && message.size() > kDocked.size()) {
      [page_ devToolsFrontendDocked:message[kDocked.size()] == u'1'];
    } else if (message.starts_with(kBounds)) {
      NSData* data = [base::SysUTF16ToNSString(message.substr(kBounds.size())) dataUsingEncoding:NSUTF8StringEncoding];
      id d = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
      if ([d isKindOfClass:[NSDictionary class]]) {
        NSDictionary* b = d;
        [page_ devToolsFrontendPageBounds:NSMakeRect([b[@"x"] doubleValue], [b[@"y"] doubleValue],
                                                     [b[@"width"] doubleValue], [b[@"height"] doubleValue])];
      }
    }
  }

  void Execute(const std::u16string& script) {
    web_contents()->GetPrimaryMainFrame()->ExecuteJavaScriptForTests(script, base::NullCallback(), /*world_id=*/0);
  }

  void Run() {
    for (const char* script : {kDevToolsDockScript, kDevToolsPanelScript}) {
      web_contents()->GetPrimaryMainFrame()->ExecuteJavaScriptForTests(base::UTF8ToUTF16(std::string_view(script)),
                                                                       base::NullCallback(), /*world_id=*/0);
    }
  }

  CraBrowser* __weak page_;
};

// The hidden Browser that holds a profile's pages, and what arrives in it that Cra didn't put there: a
// page's popup or link opened in a new tab, which becomes a Cra tab through the opener's delegate.
class PageHost : public TabStripModelObserver {
 public:
  explicit PageHost(BrowserWindowInterface* browser) : browser_(browser) {
    // The blank page: the Browser stays open with no page of Cra's in it. Never navigated, so it has no renderer
    // process; about:blank took one of its own for as long as Cra ran.
    std::unique_ptr<content::WebContents> blank =
        content::WebContents::Create(content::WebContents::CreateParams(browser->GetProfile()));
    placeholder_ = blank.get();
    // Not a tab to extensions (chrome.tabs.query, chrome.windows.getAll), as a spare page isn't.
    placeholder_->SetUserData(content::CraSparePageKey(), std::make_unique<base::SupportsUserData::Data>());
    browser->GetTabStripModel()->AppendWebContents(std::move(blank), /*foreground=*/true);
    browser->GetTabStripModel()->AddObserver(this);
    MakeHostWindow(window());
    StopDrawing();
  }

  // The window is never seen, but on screen (a bubble Chrome anchors to it, an extension's popup, only shows over a
  // window that is), and its compositor drew for it: the display link that ticked in the GPU process at idle (20 tabs
  // idle: 95 wakeups a second against CEF's 46-50; 41 without, docs/speed.md). Chrome's macOS widgets set their
  // compositor's visibility only with the NotifyCompositorOf* features, off, so it stays hidden. The bubbles are
  // windows with compositors of their own.
  void StopDrawing() {
    NSWindow* hidden = window();
    views::Widget* widget = hidden ? views::Widget::GetWidgetForNativeWindow(gfx::NativeWindow(hidden)) : nullptr;
    if (ui::Compositor* compositor = widget ? widget->GetCompositor() : nullptr) {
      compositor->SetVisible(false);
    }
  }

  BrowserWindowInterface* browser() { return browser_; }

  NSWindow* window() {
    return browser_ ? browser_->GetWindow()->GetNativeWindow().GetNativeNSWindow() : nil;
  }

  // The window rides along with the Cra window of the page in use, as a child, so a bubble Chrome anchors to it
  // (an extension's popup) is found where Cra looks for it.
  void FollowWindow(NSWindow* cra) {
    NSWindow* hidden = window();
    if (!hidden || !cra || hidden.parentWindow == cra) {
      return;
    }
    [hidden.parentWindow removeChildWindow:hidden];
    [hidden setFrame:cra.frame display:NO];
    [cra addChildWindow:hidden ordered:NSWindowAbove];
    StopDrawing();
  }

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
    // Only a page that opened in front: a background one (an extension's tabs.create with active: false) leaves
    // Chrome's active tab on the page the user is on, which extensions read.
    if (!background) {
      KeepPlaceholderActive();
    }
    // A page's own pop-up has no visible address yet (renderer-initiated): the one it was opened for.
    GURL target = page->GetVisibleURL();
    if (auto opened = OpenedURLs().find(page.get()); opened != OpenedURLs().end()) {
      target = opened->second;
      OpenedURLs().erase(opened);
    } else if (content::NavigationEntry* pending = page->GetController().GetPendingEntry()) {
      target = pending->GetURL();
    }
    NSString* url = NS(target.spec());
    // The page the link was clicked in, which Chrome names after inserting the tab (DidOpenRequestedURL), beats
    // the tab strip's opener.
    if (auto clicked = OpenedFrom().find(page.get()); clicked != OpenedFrom().end()) {
      if (clicked->second) {
        opener = clicked->second;
      }
      OpenedFrom().erase(clicked);
    }
    CraBrowser* from = opener ? BrowserFor(opener.get()) : nil;
    // A page's DevTools: their own helper pages (the device toolbar's frame when undocked) never become tabs, as
    // Chrome never shows them either; a link they open (a source's URL) is a tab from the page they inspect.
    if (!from && opener) {
      if (DevToolsWindow* devtools = DevToolsWindow::AsDevToolsWindow(opener.get())) {
        if (target.SchemeIs("devtools") || target.is_empty() || target.IsAboutBlank()) {
          chrome::CloseWebContents(browser_, page.get(), false);
          // KeepPlaceholderActive made the blank page Chrome's active tab for it: the page is again.
          [BrowserFor(devtools->GetInspectedWebContents()) makeChromeActiveTab];
          return;
        }
        from = BrowserFor(devtools->GetInspectedWebContents());
      }
    }
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
  // A page's DevTools: their keys are the page's, as in Chrome, where the frontend sits in the page's window (⌥⌘I
  // closes them, ⌘L goes to the address). Chrome's DevTools window, which would get them otherwise, is never shown.
  if (!browser) {
    if (DevToolsWindow* devtools = DevToolsWindow::AsDevToolsWindow(contents)) {
      browser = BrowserFor(devtools->GetInspectedWebContents());
    }
  }
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

// The page used last in each profile (Chrome's active tab follows it): a download that no page of Cra's started
// (an extension's popup, side panel or service worker, GitHub #218) is listed with it.
std::map<content::BrowserContext*, CraBrowser* __weak>& LastPages() {
  static auto* pages = new std::map<content::BrowserContext*, CraBrowser* __weak>();
  return *pages;
}

// The page a download belongs to: the one that started it, else the profile's last page. None for a Web Store
// install's own CRX download, which is Chrome's (WebstoreInstaller sets its path, #203) and which Chrome's
// downloads never show: an imported extension's install, or the store page's Add to Chrome. Its source says so
// from the start; WebstoreInstaller attaches its approval only after Chrome has reported the item, so the
// approval alone let the first report through, and a failed install (an extension the store no longer has)
// stayed in Cra's downloads as a file named <id>_<number>.crx at every launch.
CraBrowser* DownloadPage(download::DownloadItem* item) {
  if (item->GetDownloadSource() == download::DownloadSource::EXTENSION_INSTALLER ||
      extensions::WebstoreInstaller::GetAssociatedApproval(*item)) {
    return nil;
  }
  if (CraBrowser* page = BrowserFor(content::DownloadItemUtils::GetWebContents(item))) {
    return page;
  }
  auto it = LastPages().find(content::DownloadItemUtils::GetBrowserContext(item));
  return it == LastPages().end() ? nil : it->second;
}

// A download's progress, for the page that started it (the CEF bridge's OnDownloadUpdated).
void ReportDownload(download::DownloadItem* item) {
  CraBrowser* browser = DownloadPage(item);
  if (!browser) {
    return;
  }
  if (browser.isAgent) {
    [browser agentDownloadItem:item];
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
  CraBrowser* browser = DownloadPage(item);
  // An agent page saves only what its agent asked for, where it asked.
  if (browser.isAgent) {
    std::move(done).Run([browser agentDownloadTakes:item] ? std::optional<base::FilePath>(suggested) : std::nullopt);
    return;
  }
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

// Whether a page of Cra's is in the window the user is in (cra_engine_hooks.h, g_page_window_active).
int PageWindowActive(content::WebContents* contents) {
  if (!BrowserFor(contents)) {
    return -1;
  }
  NSWindow* window = contents->GetNativeView().GetNativeNSView().window;
  return NSApp.isActive && window.isKeyWindow ? 1 : 0;
}

// Chrome's exclusive-access notice for a page (cra_engine_hooks.h, g_exclusive_access_notice). Chrome's types
// are CraExclusiveAccessNotice's values.
bool ExclusiveAccessNotice(content::WebContents* contents, int type, bool force_update) {
  CraBrowser* browser = contents ? BrowserFor(contents) : nil;
  if (!browser) {
    return false;
  }
  if ([browser.delegate respondsToSelector:@selector(browser:exclusiveAccessNotice:force:)]) {
    [browser.delegate browser:browser
        exclusiveAccessNotice:static_cast<CraExclusiveAccessNotice>(type)
                        force:force_update];
  }
  return true;
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
// page, to a listed domain. The page is the asking frame's; a frame's navigation has none, and then it is the
// navigation's top frame (up to engine -10 such frames were never blocked).
bool BlockRequest(const GURL& url, const content::GlobalRenderFrameHostId& frame, const url::Origin* top_frame) {
  if (!cra_blocker::Enabled().load(std::memory_order_relaxed)) {
    return false;
  }
  std::string page;
  if (content::RenderFrameHost* host = content::RenderFrameHost::FromID(frame)) {
    page = cra_blocker::WebHost(host->GetOutermostMainFrame()->GetLastCommittedURL().spec());
  } else if (top_frame && !top_frame->opaque()) {
    page = cra_blocker::WebHost(top_frame->GetURL().spec());
  } else {
    return false;
  }
  return cra_blocker::ShouldBlock(cra_blocker::WebHost(url.spec()), page);
}

// The pop-ups Chrome's blocker holds back on a page, oldest first (patches/blocked-popups.patch), for Cra's
// toolbar button.
void BlockedPopupsChanged(content::WebContents* contents) {
  CraBrowser* browser = BrowserFor(contents);
  auto* blocker = blocked_content::PopupBlockerTabHelper::FromWebContents(contents);
  if (!browser || !blocker || ![browser.delegate respondsToSelector:@selector(browser:didChangeBlockedPopups:urls:)]) {
    return;
  }
  NSMutableArray<NSNumber*>* ids = [NSMutableArray array];
  NSMutableArray<NSString*>* urls = [NSMutableArray array];
  for (const auto& [id, url] : blocker->GetBlockedPopupRequests()) {
    [ids addObject:@(id)];
    [urls addObject:NS(url.spec())];
  }
  [browser.delegate browser:browser didChangeBlockedPopups:ids urls:urls];
}

// The camera or microphone in use, as Chrome's tab recording indicator counts it.
class CaptureWatcher : public MediaStreamCaptureIndicator::Observer {
 public:
  void OnIsCapturingVideoChanged(content::WebContents* contents, bool capturing) override { Changed(contents); }
  void OnIsCapturingAudioChanged(content::WebContents* contents, bool capturing) override { Changed(contents); }

 private:
  void Changed(content::WebContents* contents) { [BrowserFor(contents) pageCaptureChanged]; }
};

CaptureWatcher& Captures() {
  static auto* captures = new CaptureWatcher();
  return *captures;
}

// No separator first, last or twice in a row (among the visible items).
void TidySeparators(ui::SimpleMenuModel* model) {
  bool separator_after = true;  // walking back from the end, which counts as one
  for (size_t i = model->GetItemCount(); i-- > 0;) {
    if (model->GetTypeAt(i) != ui::MenuModel::TYPE_SEPARATOR) {
      if (model->IsVisibleAt(i)) {
        separator_after = false;
      }
    } else if (separator_after) {
      model->RemoveItemAt(i);
    } else {
      separator_after = true;
    }
  }
  for (size_t i = 0; i < model->GetItemCount();) {
    if (model->GetTypeAt(i) == ui::MenuModel::TYPE_SEPARATOR) {
      model->RemoveItemAt(i);
    } else if (model->IsVisibleAt(i)) {
      break;
    } else {
      i++;
    }
  }
}

// Arc's page menus are Chrome's with a few changes (Arc 1.172; the CEF bridge's MakeArcMenu says which).
void BuildArcMenu(content::WebContents* contents, const content::ContextMenuParams& params, ui::SimpleMenuModel* model) {
  CraBrowser* page = BrowserFor(contents);
  if (!page) {
    return;
  }
  if (std::optional<size_t> new_tab = model->GetIndexOfCommandId(IDC_CONTENT_CONTEXT_OPENLINKNEWTAB)) {
    model->RemoveItemAt(*new_tab);
    model->InsertItemAt(*new_tab, kMenuOpenLinkNewTab, base::SysNSStringToUTF16(g_link_menu_title));
  }
  // Under New Window: Split View, then Little Window (Arc's order, #276); no Little Window from incognito.
  if (std::optional<size_t> new_window = model->GetIndexOfCommandId(IDC_CONTENT_CONTEXT_OPENLINKNEWWINDOW)) {
    size_t at = *new_window;
    if ([page.delegate respondsToSelector:@selector(browser:requestsSplitPaneWithURL:)]) {
      model->InsertItemAt(++at, kMenuOpenLinkSplitView, u"Open Link in Split View");
    }
    if (!page.isIncognito) {
      model->InsertItemAt(at + 1, kMenuOpenLinkLittleWindow, u"Open Link in Little Window");
    }
  }
  // Arc has no reading mode rows; Chrome's open its side panel in the page's hidden Chrome window (#563).
  for (int id : {IDC_CONTENT_CONTEXT_GENERATE_QR_CODE, IDC_CONTENT_CONTEXT_OPENLINKINPROFILE,
                 IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW, IDC_CONTENT_CONTEXT_OPENLINKBOOKMARKAPP,
                 IDC_CONTENT_CONTEXT_SEARCHLENSFORVIDEOFRAME, IDC_CONTENT_CONTEXT_SEARCHWEBFORVIDEOFRAME,
                 IDC_CONTENT_CONTEXT_OPEN_IN_READING_MODE, IDC_CONTENT_CONTEXT_LISTEN_TO_THIS_PAGE}) {
    while (std::optional<size_t> at = model->GetIndexOfCommandId(id)) {
      model->RemoveItemAt(*at);
    }
  }
  TidySeparators(model);
  // Translate sits with Save As…, Print… and Cast…: no separator before it.
  if (std::optional<size_t> translate = model->GetIndexOfCommandId(IDC_CONTENT_CONTEXT_TRANSLATE); translate && *translate > 0) {
    size_t before = *translate - 1;
    while (before > 0 && model->GetTypeAt(before) != ui::MenuModel::TYPE_SEPARATOR && !model->IsVisibleAt(before)) {
      before--;
    }
    if (model->GetTypeAt(before) == ui::MenuModel::TYPE_SEPARATOR) {
      model->RemoveItemAt(before);
    }
  }
  // Selected text: Search <engine> for "…" before Copy (not with a link).
  std::optional<size_t> search = model->GetIndexOfCommandId(IDC_CONTENT_CONTEXT_SEARCHWEBFOR);
  std::optional<size_t> copy = model->GetIndexOfCommandId(IDC_CONTENT_CONTEXT_COPY);
  if (params.link_url.is_empty() && !params.is_editable && search && copy && *search > *copy) {
    std::u16string label = model->GetLabelAt(*search);
    model->RemoveItemAt(*search);
    model->InsertItemAt(*copy, IDC_CONTENT_CONTEXT_SEARCHWEBFOR, label);
  }
  // "Search Image with Google" becomes Chrome's own "Search <engine> for Image" (CraCore's PageMenuLabels).
  if (std::optional<size_t> lens = model->GetIndexOfCommandId(IDC_CONTENT_CONTEXT_SEARCHLENSFORIMAGE);
      lens && g_image_search_title) {
    if (NSString* title = g_image_search_title(base::SysUTF16ToNSString(model->GetLabelAt(*lens)))) {
      model->RemoveItemAt(*lens);
      model->InsertItemAt(*lens, IDC_CONTENT_CONTEXT_SEARCHWEBFORIMAGE, base::SysNSStringToUTF16(title));
    }
  }
  if (std::optional<size_t> save_image = model->GetIndexOfCommandId(IDC_CONTENT_CONTEXT_SAVEIMAGEAS);
      save_image && params.media_type == blink::mojom::ContextMenuDataMediaType::kImage &&
      [page.delegate respondsToSelector:@selector(browser:requestsCaptureOfImageAt:)]) {
    model->InsertItemAt(*save_image + 1, kMenuCaptureImage, u"Capture Image…");
  }
  TidySeparators(model);
}

// The page menu's commands Cra runs: its own items, and Chrome's that would open Chrome windows or tabs.
bool PageMenuCommand(content::WebContents* contents, const content::ContextMenuParams& params, int command) {
  CraBrowser* page = BrowserFor(contents);
  if (!page) {
    return false;
  }
  id<CraBrowserDelegate> delegate = page.delegate;
  NSString* link = NS(params.link_url.spec());
  switch (command) {
    case kMenuOpenLinkNewTab:
      [delegate browser:page requestsNewTabWithURL:link inBackground:g_link_menu_background];
      return true;
    case kMenuOpenLinkSplitView:
      if ([delegate respondsToSelector:@selector(browser:requestsSplitPaneWithURL:)]) {
        [delegate browser:page requestsSplitPaneWithURL:link];
      }
      return true;
    case IDC_CONTENT_CONTEXT_OPENLINKNEWWINDOW:
    case IDC_CONTENT_CONTEXT_OPENLINKOFFTHERECORD:
    case kMenuOpenLinkLittleWindow: {
      if (![delegate respondsToSelector:@selector(browser:requestsWindowWithURL:kind:)]) {
        [delegate browser:page requestsNewTabWithURL:link inBackground:NO];
        return true;
      }
      CraLinkWindow kind = command == kMenuOpenLinkLittleWindow                 ? CraLinkWindowLittle
                           : command == IDC_CONTENT_CONTEXT_OPENLINKOFFTHERECORD ? CraLinkWindowIncognito
                                                                                 : CraLinkWindowNew;
      [delegate browser:page requestsWindowWithURL:link kind:kind];
      return true;
    }
    case kMenuCaptureImage:
      if ([delegate respondsToSelector:@selector(browser:requestsCaptureOfImageAt:)]) {
        [delegate browser:page requestsCaptureOfImageAt:NSMakePoint(params.x, params.y)];
      }
      return true;
    // View Page Source and View Frame Source go where ⌥⌘U goes, a view-source: tab in front (#348).
    case IDC_VIEW_SOURCE:
    case IDC_CONTENT_CONTEXT_VIEWFRAMESOURCE:
      if (!g_view_source_handler) {
        return false;
      }
      g_view_source_handler(page, NS(command == IDC_VIEW_SOURCE ? params.page_url.spec() : params.frame_url.spec()));
      return true;
    // Inspect: Cra's DevTools, docked in the card, on that element.
    case IDC_CONTENT_CONTEXT_INSPECTELEMENT:
      [page showDevToolsInspectingPoint:NSMakePoint(params.x, params.y)];
      return true;
    default:
      return false;
  }
}

// A test's command runs instead of the menu; an MCP client's right-click shows none.
bool PageMenuShow(content::WebContents* contents, RenderViewContextMenuBase* menu) {
  CraBrowser* page = BrowserFor(contents);
  if (!page) {
    return true;
  }
  if (g_next_page_menu_command >= 0) {
    int command = g_next_page_menu_command;
    g_next_page_menu_command = -1;
    NSLog(@"Cra page menu runs command %d", command);
    menu->ExecuteCommand(command, 0);
    return false;
  }
  return !page.suppressesContextMenu;
}

// Another launch handed its command line over: its URLs go to the app, as from CEF's OnAlreadyRunningAppRelaunch.
void Relaunch(const base::CommandLine& command_line) {
  NSMutableArray<NSString*>* urls = [NSMutableArray array];
  for (const auto& arg : command_line.GetArgs()) {
    NSString* text = base::SysUTF8ToNSString(arg);
    if ([text hasPrefix:@"http://"] || [text hasPrefix:@"https://"] || [text hasPrefix:@"cra://"] ||
        [text hasPrefix:@"file://"]) {
      [urls addObject:text];
    }
  }
  if (g_relaunch_handler) {
    g_relaunch_handler(urls);
  }
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

// A host Browser that is closing (Chrome closing its windows, an extension's windows.remove) takes no more pages.
bool IsClosing(BrowserWindowInterface* browser) {
  return !browser || browser->IsDeleteScheduled() || UnloadController::From(browser)->is_attempting_to_close_browser();
}

// The profile's host, or nullptr while Chrome shuts down. A page added to a host that was closing stayed in its tab
// strip when Chrome deleted it, after its window's features had gone: ExclusiveAccessManager::OnTabClosing on a null
// manager from ~Browser (0.1.44 crash reports). A closing host is left to close; a new one takes the page.
PageHost* HostFor(Profile* profile) {
  auto it = Hosts().find(profile);
  if (it != Hosts().end()) {
    if (!IsClosing(it->second->browser())) {
      return it->second;
    }
    Hosts().erase(it);
  }
  if (browser_shutdown::IsTryingToQuit() || browser_shutdown::HasShutdownStarted()) {
    return nullptr;
  }
  g_making_host = true;
  BrowserWindowInterface* browser = CreateBrowserWindow(BrowserWindowCreateParams(*profile, false));
  g_making_host = false;
  // Its WebViews attach no page (cra_hosted_page.h): a page Chrome puts in front here (a link opened in a new
  // tab) drew into this never-shown window from then on, and its Cra tab stayed blank (GitHub #469).
  if (views::Widget* widget = views::Widget::GetWidgetForNativeWindow(browser->GetWindow()->GetNativeWindow())) {
    widget->SetNativeWindowProperty(views::kCraPageHostWindow, widget);
  }
  auto* host = new PageHost(browser);
  Hosts()[profile] = host;
  return host;
}

// NativeWidgetMacNSWindow's switch for acting as a non-activating panel (Widget::SetActivationIndependence).
}  // namespace

@protocol CraActivationIndependentWindow
- (void)setActivationIndependence:(BOOL)independence;
@end

namespace {

// Chromium makes a Picture in Picture window (a video's, or Document PiP's) an ordinary window that
// joins every desktop Space, so it went missing over another app's full-screen Space (GitHub #206).
// Only a non-activating panel joins that Space (#186); Arc's PiP is one (an NSPanel, AXSystemDialog).
// This is Chromium's own recipe for such windows (Glic's floating panel, the screen-share picker):
// activation independence, which makes NativeWidgetMacNSWindow answer _isNonactivatingPanel, and
// SetCanAppearInExistingFullscreenSpaces' collection behaviour.
void FloatOverFullScreenSpaces(NSWindow* window) {
    if (!window) return;
    if ([window respondsToSelector:@selector(setActivationIndependence:)]) {
        [(id<CraActivationIndependentWindow>)window setActivationIndependence:YES];
        // It also turns canHide off; Chrome's PiP has always hidden with the app (⌘H), so it still does.
        window.canHide = YES;
    }
    // Chromium also makes every top-level window `.managed` (Document PiP is one), and a managed
    // window stays off another app's full-screen Space whatever else it says.
    NSWindowCollectionBehavior behavior = window.collectionBehavior;
    behavior &= ~(NSWindowCollectionBehaviorPrimary | NSWindowCollectionBehaviorFullScreenPrimary
                  | NSWindowCollectionBehaviorManaged);
    behavior |= NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    window.collectionBehavior = behavior;
    // Shown while a full-screen Space is in front (Document PiP, or a video's from a tab left for it),
    // the window only moves onto that Space once it is ordered again.
    if (window.isVisible) [window orderFrontRegardless];
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
// Cra tab through the app's stray page handler and the window closes. One with only a blank page (an extension's
// windows.create({url: "about:blank"}), to fill later) has nothing to adopt and stays, unseen, so the extension's
// window id keeps working (GitHub #578). A popup one (windows.create type popup) stays Chrome's window, as in Arc.
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
      // has put it in. Never key either, as a page's host window: Chrome activates the frontend's window when the
      // frontend takes focus (a click in it), and Cra's window, where the frontend is, lost the keys. Chromium then
      // dropped mouse moves (no splitter cursor, no hover) and the next click only made Cra's window key again.
      MakeHostWindow(window);
      Later(base::BindOnce(&StrayWindows::TakeDevTools, base::Unretained(this), browser->GetWeakPtr()));
      return;
    }
    // Document Picture in Picture (a call's window, TYPE_FLOATING since Chrome 158): over full-screen Spaces too,
    // as Arc's (GitHub #206).
    if (browser->GetType() == BrowserWindowInterface::TYPE_FLOATING) {
      FloatOverFullScreenSpaces(window);
      return;
    }
    if (browser->GetType() != BrowserWindowInterface::TYPE_NORMAL) {
      if (window) {
        if (FullScreenWindowOnActiveSpace(window)) {
          JoinFullScreenSpace(window);
        }
        if (!g_extension_windows) {
          g_extension_windows = [NSHashTable weakObjectsHashTable];
        }
        [g_extension_windows addObject:window];
      }
      return;
    }
    // Never seen, and never a reason to leave a full-screen Space (GitHub #38).
    window.alphaValue = 0;
    window.ignoresMouseEvents = YES;
    window.collectionBehavior = (window.collectionBehavior & ~NSWindowCollectionBehaviorFullScreenPrimary) |
                                NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorMoveToActiveSpace;
    // Nor key or main: windows.create shows it with makeKeyAndOrderFront, and one that stays (nothing to adopt)
    // would keep the keys from Cra's own window.
    NeverKeyOrMain(window);
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
      [g_host_windows removeObject:window];
      window.excludedFromWindowsMenu = NO;
      window.sharingType = NSWindowSharingReadOnly;
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
    bool blank_only = true;
    for (int i = 0; i < tabs->count(); ++i) {
      std::string url = tabs->GetWebContentsAt(i)->GetVisibleURL().spec();
      // A blank page: what an extension's windows.create({url: "about:blank"}) starts with, to fill it later.
      if (url.empty() || url == url::kAboutBlankURL) {
        continue;
      }
      blank_only = false;
      // Chrome's own empty tab (after a Web Store install): nobody asked for it.
      if (base::StartsWith(url, "chrome://newtab") || base::StartsWith(url, "chrome://new-tab-page")) {
        continue;
      }
      if (g_stray_page_handler) {
        g_stray_page_handler(NS(url), profile);
      }
    }
    tabs->RemoveObserver(this);
    // Only blank pages: the window stays, unseen, for the extension that made it, as the CEF bridge kept it (GitHub
    // #578). Closed, the id windows.create gave back named no window: windows.get, tabs.query and tabs.create on it
    // all failed, and windows.getAll never listed it.
    if (blank_only && tabs->count() > 0) {
      return;
    }
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

// Chrome closes its windows at quit: the hidden ones leave Cra's windows first.
void DetachHostWindows() {
  for (auto& [profile, host] : Hosts()) {
    NSWindow* hidden = host->window();
    [hidden.parentWindow removeChildWindow:hidden];
  }
}

void DropSparePages() {
  for (CraBrowser* spare in SparePages().allObjects) {
    [spare dropSpareContents];
  }
  [SparePages() removeAllObjects];
}

void StopBridge() {
  g_quitting = true;
  DropSparePages();
  DetachHostWindows();
  MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator()->RemoveObserver(&Captures());
}

// MARK: Links Cra opens its own way

// The last click (left mouse-up) or Return in any window, for the link Chromium opens a moment after it: where it
// landed and the keys held (the CEF bridge's CraNoteLastPress). Set in -[CraApplication sendEvent:].
NSWindow* __weak g_last_press_window = nil;
// The page that took the focus last (pageFocused).
CraBrowser* __weak g_last_focused_page = nil;
NSView* __weak g_last_press_view = nil;
NSEventModifierFlags g_last_press_modifiers = 0;
NSTimeInterval g_last_press_time = -1;
BOOL (^g_app_link_handler)(CraBrowser*, NSString*, BOOL) = nil;

void NoteLastPress(NSEvent* event) {
  BOOL click = event.type == NSEventTypeLeftMouseUp;
  BOOL enter = event.type == NSEventTypeKeyDown && (event.keyCode == 36 || event.keyCode == 76);  // Return, Enter
  if (!click && !enter) {
    return;
  }
  NSWindow* window = event.window;
  NSView* view = nil;
  if (click) {
    NSView* root = window.contentView.superview ?: window.contentView;
    view = [root hitTest:event.locationInWindow];
  } else if ([window.firstResponder isKindOfClass:[NSView class]]) {
    view = static_cast<NSView*>(window.firstResponder);
  }
  g_last_press_window = window;
  g_last_press_view = view;
  g_last_press_modifiers = event.modifierFlags;
  g_last_press_time = event.timestamp;
}

// The page's last click (or Return): the keys it was made with and its age in seconds, or -1 when the last one
// wasn't in this page. Split panes share a window; the first pane to ask takes the click.
NSTimeInterval LastPressInPage(CraBrowser* page, NSEventModifierFlags* modifiers) {
  NSView* view = g_last_press_view;
  BOOL in_page = view && [view isDescendantOf:page.containerView];
  *modifiers = in_page ? g_last_press_modifiers : 0;
  return in_page && g_last_press_time >= 0 ? NSProcessInfo.processInfo.systemUptime - g_last_press_time : -1;
}

// ⌥⌘-click opens the link in a Little Window (Arc's, Settings ▸ Links): Chromium reports it as its split view
// click (or a ⌘-click, a background tab), so the keys are the click's own (LittleWindowTrigger decides).
bool OpensLittleWindow(CraBrowser* page, NSString* url, WindowOpenDisposition disposition, bool user_gesture) {
  if (!user_gesture ||
      (disposition != WindowOpenDisposition::kNewSplitView &&
       disposition != WindowOpenDisposition::kNewBackgroundTab) ||
      ![page.delegate respondsToSelector:@selector(browser:opensLittleWindowForURL:clickModifiers:clickAge:)]) {
    return false;
  }
  NSEventModifierFlags modifiers = 0;
  NSTimeInterval age = LastPressInPage(page, &modifiers);
  if (![page.delegate browser:page opensLittleWindowForURL:url clickModifiers:modifiers clickAge:age]) {
    return false;
  }
  g_last_press_time = -1;  // one click, one window
  return true;
}

// Chromium's split view click: a pane beside this page, as an Option-click opens (#298).
bool OpensSplitPane(CraBrowser* page, NSString* url, WindowOpenDisposition disposition, bool user_gesture) {
  if (!user_gesture || disposition != WindowOpenDisposition::kNewSplitView ||
      ![page.delegate respondsToSelector:@selector(browser:requestsSplitPaneWithURL:)]) {
    return false;
  }
  NSString* scheme = [NSURL URLWithString:url].scheme.lowercaseString;
  if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
    return false;
  }
  __weak CraBrowser* weak = page;
  dispatch_async(dispatch_get_main_queue(), ^{
    CraBrowser* b = weak;
    if (b) {
      [b.delegate browser:b requestsSplitPaneWithURL:url];
    }
  });
  return true;
}

// patches/cra-links.patch: a link a page of Cra's opens elsewhere than its own tab, in the CEF bridge's order
// (OnBeforePopup): another app's address, a Little Window, a split pane, then a Peek for a clicked target=_blank
// link (Shift-click: Chrome's new window). window.open with features (a sign-in pop-up) stays a pop-up.
bool LinkOpen(content::WebContents* source, const GURL& gurl, WindowOpenDisposition disposition, bool user_gesture) {
  CraBrowser* page = BrowserFor(source);
  if (!page || g_quitting) {
    return false;
  }
  NSString* url = NS(gurl.spec());
  if (g_app_link_handler && g_app_link_handler(page, url, user_gesture)) {
    return true;
  }
  if (OpensLittleWindow(page, url, disposition, user_gesture) || OpensSplitPane(page, url, disposition, user_gesture)) {
    return true;
  }
  bool peek_kind = disposition == WindowOpenDisposition::kNewForegroundTab ||
                   disposition == WindowOpenDisposition::kNewWindow;
  return user_gesture && peek_kind &&
         [page.delegate respondsToSelector:@selector(browser:opensPeekForURL:shiftClick:newTab:)] &&
         [page.delegate browser:page
                opensPeekForURL:url
                     shiftClick:disposition == WindowOpenDisposition::kNewWindow
                         newTab:disposition == WindowOpenDisposition::kNewForegroundTab];
}

// Another app's address, or Cra's cra-boost:, from a page of Cra's: Cra's app asks about it (AppLinkPrompt). cra:
// is Cra's own scripting scheme, which a page never drives.
bool ExternalProtocol(content::WebContents* contents, const GURL& url, bool user_gesture) {
  CraBrowser* page = BrowserFor(contents);
  if (!page) {
    return false;
  }
  if (url.SchemeIs("cra")) {
    return true;
  }
  return g_app_link_handler && g_app_link_handler(page, NS(url.spec()), user_gesture);
}

// A page of Cra's own navigation, before its request goes out (the CEF bridge's OnBeforeBrowse): a clicked link
// that opens in a Peek, or a page Cra shows in its WebKit engine (ProtectedMediaSites: a sign-in's one-time code
// isn't spent here).
class CraNavigationThrottle : public content::NavigationThrottle {
 public:
  explicit CraNavigationThrottle(content::NavigationThrottleRegistry& registry)
      : content::NavigationThrottle(registry) {}

  ThrottleCheckResult WillStartRequest() override {
    content::NavigationHandle* handle = navigation_handle();
    if (!handle->IsInPrimaryMainFrame()) {
      return PROCEED;
    }
    CraBrowser* page = BrowserFor(handle->GetWebContents());
    if (!page) {
      return PROCEED;
    }
    NSString* url = NS(handle->GetURL().spec());
    ui::PageTransition transition = handle->GetPageTransition();
    // Not a new page's first load (a ⌘-clicked link's background tab, a pop-up): only a page's own link.
    if (handle->HasUserGesture() && handle->IsRendererInitiated() &&
        !handle->GetWebContents()->GetController().IsInitialNavigation() &&
        ui::PageTransitionCoreTypeIs(transition, ui::PAGE_TRANSITION_LINK) &&
        !(transition & ui::PAGE_TRANSITION_FORWARD_BACK) &&
        [page.delegate respondsToSelector:@selector(browser:opensPeekForURL:shiftClick:newTab:)] &&
        [page.delegate browser:page opensPeekForURL:url shiftClick:NO newTab:NO]) {
      return CANCEL_AND_IGNORE;
    }
    if ([page.delegate respondsToSelector:@selector(browser:handsOffNavigationToURL:method:)] &&
        [page.delegate browser:page handsOffNavigationToURL:url method:handle->IsPost() ? @"POST" : @"GET"]) {
      return CANCEL_AND_IGNORE;
    }
    return PROCEED;
  }

  const char* GetNameForLogging() override { return "CraNavigationThrottle"; }
};

void AddNavigationThrottles(content::NavigationThrottleRegistry& registry) {
  if (BrowserFor(registry.GetNavigationHandle().GetWebContents())) {
    registry.AddThrottle(std::make_unique<CraNavigationThrottle>(registry));
  }
}

// Chromium makes an Option-clicked link a download of it; Arc opens it in Split View (#298). The click that asked
// is the last one in this page, a moment ago.
bool DownloadIntercept(content::WebContents* contents, const GURL& url) {
  CraBrowser* page = BrowserFor(contents);
  if (!page || ![page.delegate respondsToSelector:@selector(browser:opensSplitForDownloadURL:clickModifiers:clickAge:)]) {
    return false;
  }
  NSEventModifierFlags modifiers = 0;
  NSTimeInterval age = LastPressInPage(page, &modifiers);
  if (![page.delegate browser:page opensSplitForDownloadURL:NS(url.spec()) clickModifiers:modifiers clickAge:age]) {
    return false;
  }
  g_last_press_time = -1;  // one click, one pane
  return true;
}

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
  g_page_window_active = &PageWindowActive;
  g_exclusive_access_notice = &ExclusiveAccessNotice;
  g_block_request = &BlockRequest;
  g_boost_tint = &BoostTint;
  g_page_menu_built = &BuildArcMenu;
  g_page_menu_command = &PageMenuCommand;
  g_page_menu_show = &PageMenuShow;
  g_relaunch = &Relaunch;
  g_link_open = &LinkOpen;
  g_external_protocol = &ExternalProtocol;
  g_navigation_throttles = &AddNavigationThrottles;
  g_download_intercept = &DownloadIntercept;
  // Cra's app holds a request from a tab behind until its tab shows (BrowserManager, PermissionAsk), as on CEF.
  permissions::cra::g_asks_from_any_tab = [](content::WebContents* contents) { return BrowserFor(contents) != nil; };
  MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator()->AddObserver(&Captures());
  blocked_content::PopupBlockerTabHelper::SetCraListChangedCallback(base::BindRepeating(&BlockedPopupsChanged));
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

// Scenarios' way to what Chrome does to the bridge's hidden pieces (Tests/Scenarios/engine-*.scenario).
bool HandleDebugMethod(content::WebContents* contents,
                       const std::string& method,
                       const base::DictValue* params,
                       base::DictValue* result,
                       std::string* error) {
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  if (method == "Cra.debugCloseHost") {
    // Chrome closes the hidden Browser that holds the profile's pages, as it does its other windows. With
    // addPage, a page goes to the profile's host the moment Chrome has closed that Browser and scheduled its
    // deletion, as the bridge's next page would.
    auto it = Hosts().find(profile);
    if (it == Hosts().end() || !it->second->browser()) {
      *error = "no host for this profile";
      return true;
    }
    BrowserWindowInterface* browser = it->second->browser();
    if (params && params->FindBool("addPage").value_or(false)) {
      static base::NoDestructor<std::vector<base::CallbackListSubscription>> subscriptions;
      subscriptions->push_back(browser->RegisterBrowserDidClose(base::BindRepeating(
          [](Profile* profile, BrowserWindowInterface* closed) {
            PageHost* host = HostFor(profile);
            if (!host) {
              LOG(WARNING) << "Cra: debug page after host closed: no host";
              return;
            }
            LOG(WARNING) << "Cra: debug page after host closed: "
                         << (host->browser() == closed ? "the closed host" : "a new host");
            g_adding_own_page = true;
            host->browser()->GetTabStripModel()->AppendWebContents(
                content::WebContents::Create(content::WebContents::CreateParams(profile)), /*foreground=*/false);
            g_adding_own_page = false;
          },
          profile)));
    }
    // On the next turn: closing takes the page this call came from with it, and its reply is still on the way.
    Later(base::BindOnce(
        [](base::WeakPtr<BrowserWindowInterface> browser) {
          if (browser) {
            chrome::CloseWindow(browser.get());
          }
        },
        browser->GetWeakPtr()));
    result->Set("closing", true);
    return true;
  }
  if (method == "Cra.debugSystemPermission") {
    // macOS's answer for camera, microphone or location, as Chrome reads it (denied: true or false; no denied:
    // macOS's own again). A page's <geolocation> or <usermedia> element then takes Chrome's System Settings step.
    const std::string* type = params ? params->FindString("type") : nullptr;
    ContentSettingsType types[2] = {ContentSettingsType::DEFAULT, ContentSettingsType::DEFAULT};
    if (type && *type == "geolocation") {
      types[0] = ContentSettingsType::GEOLOCATION;
      types[1] = ContentSettingsType::GEOLOCATION_WITH_OPTIONS;
    } else if (type && *type == "camera") {
      types[0] = ContentSettingsType::MEDIASTREAM_CAMERA;
    } else if (type && *type == "microphone") {
      types[0] = ContentSettingsType::MEDIASTREAM_MIC;
    } else {
      *error = "type is geolocation, camera or microphone";
      return true;
    }
    static base::NoDestructor<
        std::map<ContentSettingsType, std::unique_ptr<system_permission_settings::ScopedSettingsForTesting>>>
        overrides;
    std::optional<bool> denied = params->FindBool("denied");
    for (ContentSettingsType t : types) {
      if (t == ContentSettingsType::DEFAULT) {
        continue;
      }
      overrides->erase(t);
      if (denied) {
        (*overrides)[t] = std::make_unique<system_permission_settings::ScopedSettingsForTesting>(t, *denied);
      }
    }
    result->Set("denied", denied ? base::Value(*denied) : base::Value());
    return true;
  }
  if (method == "Cra.debugConnectClosedTabGroup") {
    // Session restore asks to connect a restored window's tab group (ProcessSavedGroup), and the window is
    // gone by then: Cra closes the Chrome windows it didn't make.
    tab_groups::TabGroupSyncService* service = tab_groups::TabGroupSyncServiceFactory::GetForProfile(profile);
    if (!service) {
      *error = "no tab group sync service";
      return true;
    }
    tab_groups::SavedTabGroup group(u"Cra scenario", tab_groups::TabGroupColorId::kBlue, {});
    group.AddTabLocally(tab_groups::SavedTabGroupTab(GURL("https://example.com/"), u"Example", group.saved_guid(),
                                                     /*position=*/0));
    base::Uuid sync_id = group.saved_guid();
    service->AddGroup(std::move(group));
    service->ConnectLocalTabGroup(sync_id, tab_groups::TabGroupId::GenerateNew(),
                                  tab_groups::OpeningSource::kConnectOnSessionRestore);
    result->Set("connected", true);
    return true;
  }
  return false;
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
  // The page's empty document draws in Arc's canvas colour until it first draws something of its own (#712).
  BOOL _canvasBase;
  raw_ptr<content::WebContents> _contents;
  std::unique_ptr<PageObserver> _observer;
  std::unique_ptr<DevToolsFrontendObserver> _devToolsFrontend;
  // The page's media session is one Chrome's global media controls offer (#411).
  BOOL _mediaSessionControllable;
  // While a video of the page is in Picture in Picture: its time for the window's scrubber, twice a second.
  NSTimer* _pictureInPictureClock;
  // -loadURL: counted the navigation it starts; Chrome's start of it isn't counted again.
  BOOL _startCounted;
  // The page's DevTools protocol session, made on the first -sendDevToolsMethod:.
  std::unique_ptr<cra::PageSession> _session;
  NSString* _pendingURL;
  BOOL _waitingForPopup;
  BOOL _audioMuted;
  // A Boost's colorize, Arc's 6 comma-separated numbers; empty for none (#602).
  std::string _boostTint;
  // The app's find session (AskOnPage.FindRequest): every result Chrome reports is tagged with it. Nil
  // after -stopFinding:, so a late result of a stopped search reaches nobody.
  NSUUID* _findGeneration;
  BOOL _findQuote;
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
  // The frontend's view, wherever the app put it (its window, or a card while docked).
  NSView* __weak _devToolsFrontendView;
  // An agent page (MCP) renders while never on screen, as the CEF bridge's windowless page did.
  base::ScopedClosureRunner _agentCapture;
  // The download the agent asked for (startAgentDownload:…); anything else the site starts is cancelled.
  BOOL _agentDownloadActive;
  BOOL _agentDownloadCancelled;
  GURL _agentDownloadURL;
  base::FilePath _agentDownloadPath;
  uint32_t _agentDownloadID;
  std::set<uint32_t> _agentFinishedDownloads;
  void (^_agentDownloadUpdate)(CraDownloadInfo*);
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
  // An incognito page keeps its profile's folder: it loads in that profile's off-the-record one, as each
  // Chrome profile has its own incognito (GitHub #620). Without one it is Default's, as before.
  _profilePath = [profilePath copy];
  _container = [[CraPageContainerView alloc] initWithFrame:frame];
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
  // Quitting: Chrome is tearing down (its profile manager may be gone); the page is never made, as with CEF.
  if (g_quitting || !g_browser_process || !g_browser_process->profile_manager()) {
    return self;
  }
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

// Whether the app wants this page to start hidden: a tab opened behind the page in front (#552).
- (BOOL)startsHidden {
  return [_delegate respondsToSelector:@selector(browserStartsHidden:)] && [_delegate browserStartsHidden:self];
}

- (void)createPageInProfile:(Profile*)profile {
  // Quitting: Chrome is closing every Browser, and the app may still ask for a page as tabs lose theirs.
  if (_isClosed || g_quitting) {
    return;
  }
  if (_isIncognito) {
    profile = profile->GetPrimaryOTRProfile(/*create_if_needed=*/true);
  }
  // Until a page is first shown, Chromium keeps the visibility it was made with, whatever Cra's container
  // does. A tab opened behind the page in front starts hidden, so its video waits until it is shown (#552);
  // every other page starts shown. A spare is made shown: the tab that takes it asks (takeSpareWithURL:).
  content::WebContents::CreateParams params(profile);
  params.initially_hidden = !_isSpare && [self startsHidden];
  if (_isSpare) {
    // Made now, while nothing waits on it; it goes in a tab strip when a tab takes it (takeSpareWithURL:).
    _spareProfile = profile;
    _spareContents = content::WebContents::Create(params);
    [self applySpareCanvas];
    [SparePages() addObject:self];
    // Made: a tab can take it (SparePages.take), as the CEF bridge reports a spare once its browser exists.
    _isCreated = YES;
    return;
  }
  std::unique_ptr<content::WebContents> made = content::WebContents::Create(params);
  [self applyCanvasBaseTo:made.get()];
  if (_sidePanel) {
    extensions::SetViewType(made.get(), extensions::mojom::ViewType::kExtensionSidePanel);
  }
  [self insertContents:std::move(made) profile:profile];
}

// A page the bridge made itself goes in its profile's tab strip (Chrome's tab helpers attach there), then
// loads: its saved history (GitHub #273), else its address.
- (void)insertContents:(std::unique_ptr<content::WebContents>)made profile:(Profile*)profile {
  PageHost* host = HostFor(profile);
  if (!host) {
    return;  // Chrome is shutting down: the page goes with it.
  }
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
    // Told a moment later, as the CEF bridge does: this can run while the page is still being made, before the
    // app knows which tab it is.
    NSString* failure = count > 0 ? nil : (error.empty() ? @"nothing restored" : NS(error));
    __weak CraBrowser* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      CraBrowser* page = weakSelf;
      if (page && [page.delegate respondsToSelector:@selector(browser:didRestoreHistoryEntries:error:)]) {
        [page.delegate browser:page didRestoreHistoryEntries:count error:failure];
      }
    });
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
  host->FollowWindow(_container.window);
  if (!_isAgent) {
    LastPages()[_contents->GetBrowserContext()] = self;
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
  if (_audioMuted || _isAgent) {
    // As the user's mute (the tab's speaker): Chrome's sound setting leaves it on across navigations.
    SetTabAudioMuted(contents, true, TabMutedReason::kAudioIndicator, std::string());
  }
  if (_isAgent) {
    _agentCapture = contents->IncrementCapturerCount(gfx::Size(1280, 800), /*stay_hidden=*/false,
                                                     /*stay_awake=*/true, /*is_activity=*/false);
  }
  // What the page did before Cra watched it (its first load starts inside AddAndReturnTabAt).
  [self pageAddressChanged];
  [self pageLoadingChanged];
  NSView* page = contents->GetNativeView().GetNativeNSView();
  [page removeFromSuperview];
  page.frame = _container.bounds;
  page.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [_container addSubview:page];
  // A page made hidden (a background tab: a ⌘-click, a restored tab) gets a hidden view from Chrome
  // (WebContentsViewMac::CreateView), and Chrome's view host unhides it when it attaches the page. Cra's
  // pages never attach there (cra_hosted_page.h), so Cra unhides it: the page is shown and hidden with
  // Cra's container. Left hidden, such a tab stayed black whenever it was shown (0.1.44).
  page.hidden = NO;
  [self applyPageCanvasTo:contents->GetRenderWidgetHostView()];
  [self installDocumentStartScripts];
  __weak CraBrowser* weakSelf = self;
  cra::WatchMediaSession(contents, ^(NSInteger state, bool controllable) {
    [weakSelf pageMediaSession:(CraMediaSessionState)state controllable:controllable];
  });
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
  if (_startCounted) {
    _startCounted = NO;  // -loadURL: counted it before Chrome ended the load it replaces
  } else {
    ++_navigationStarts;
  }
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

// A page being torn down (~WebContentsImpl) ends its unfinished navigation from FrameTree::Shutdown, after its view's
// widget let go of the page (DetachDelegate). That is no finished navigation and no end of loading for the tab: the
// app took it for a page that had loaded, and the toolbar's colour (#629) took a screenshot of it, which ended in
// VisibleTimeRequestTrigger::TakeRequest on the page that was gone (crash-page-closed-while-loading). Nothing about
// such a page reaches the app; browserDidClose follows.
- (void)pageFinishedNavigation:(content::NavigationHandle*)handle {
  if (_contents && _contents->IsBeingDestroyed()) {
    return;
  }
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
  if (error != net::OK && error != net::ERR_ABORTED) {
    [self pageProcessEvent:@"loadError" detail:[NSString stringWithFormat:@"%d", error] url:handle->GetURL()];
    if ([_delegate respondsToSelector:@selector(browser:didFailLoadingURL:errorCode:)]) {
      [_delegate browser:self didFailLoadingURL:NS(handle->GetURL().spec()) errorCode:error];
    }
  }
  [self pageLoadingChanged];
}

- (void)pageLoadingChanged {
  if (!_contents || _contents->IsBeingDestroyed()) {
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

// The media session as Chrome's global media controls follow it (#411): the sidebar player's card does too.
- (void)pageMediaSession:(CraMediaSessionState)state controllable:(BOOL)controllable {
  _mediaSessionControllable = controllable;
  if ([_delegate respondsToSelector:@selector(browser:didChangeMediaSessionState:controllable:)]) {
    [_delegate browser:self didChangeMediaSessionState:state controllable:controllable];
  }
}

- (BOOL)reportsMediaSession {
  return YES;
}

// A sound with no controllable session behind it: a ding, or Web Audio, which never joins one.
- (BOOL)hasUncontrollableSound {
  return !_mediaSessionControllable;
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
  [_pictureInPictureClock invalidate];
  _pictureInPictureClock = nil;
  if (active && [_delegate respondsToSelector:@selector(browser:didChangePictureInPictureTime:duration:)]) {
    __weak CraBrowser* weakSelf = self;
    _pictureInPictureClock = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                             repeats:YES
                                                               block:^(NSTimer* timer) {
                                                                 [weakSelf pagePictureInPictureTime];
                                                               }];
    [self pagePictureInPictureTime];
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

// The Picture in Picture video's time, from the page's media session (the CEF bridge's script sent "time:").
- (void)pagePictureInPictureTime {
  double position = 0;
  double duration = 0;
  if (_contents && _isInPictureInPicture && cra::MediaPositionNow(_contents, &position, &duration) &&
      [_delegate respondsToSelector:@selector(browser:didChangePictureInPictureTime:duration:)]) {
    [_delegate browser:self didChangePictureInPictureTime:position duration:duration];
  }
}

// Chrome's bars changed: told once the manager is done changing (a bar's press removes it from inside the call).
// A call's tab sharing bars come and go with it, so the sharing state is told too.
- (void)pageInfoBarsChanged {
  __weak CraBrowser* weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    CraBrowser* page = weakSelf;
    if (page && [page.delegate respondsToSelector:@selector(browser:didChangeInfoBars:)]) {
      [page.delegate browser:page didChangeInfoBars:page.infoBars];
    }
  });
  [self pageTabSharingChanged];
}

// Told once Chrome is done changing: TabSharingUIViews swaps every tab's bar while it switches the shared tab.
- (void)pageTabSharingChanged {
  __weak CraBrowser* weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    CraBrowser* page = weakSelf;
    if (page && [page.delegate respondsToSelector:@selector(browserDidChangeTabSharing:)]) {
      [page.delegate browserDidChangeTabSharing:page];
    }
  });
}

- (BOOL)isBeingShared {
  auto* helper = _contents ? TabCaptureContentsBorderHelper::FromWebContents(_contents) : nullptr;
  return helper && helper->IsTabCapturing();
}

// The page's tab sharing bar, when its "Share this tab instead" button is there and enabled. TabSharingUIViews puts
// one on every tab a call could switch to (same profile, not the shared tab, not blocked by policy).
static TabSharingInfoBarDelegate* ShareInsteadBar(content::WebContents* contents) {
  auto* manager = contents ? infobars::ContentInfoBarManager::FromWebContents(contents) : nullptr;
  if (!manager) {
    return nullptr;
  }
  for (infobars::InfoBar* bar : manager->infobars()) {
    infobars::InfoBarDelegate* delegate = bar->delegate();
    if (!delegate || delegate->GetIdentifier() != infobars::InfoBarDelegate::TAB_SHARING_INFOBAR_DELEGATE) {
      continue;
    }
    auto* sharing = static_cast<TabSharingInfoBarDelegate*>(delegate);
    if ((sharing->GetButtons() & TabSharingInfoBarDelegate::kShareThisTabInstead) &&
        sharing->IsButtonEnabled(TabSharingInfoBarDelegate::kShareThisTabInstead)) {
      return sharing;
    }
  }
  return nullptr;
}

- (BOOL)canShareInstead {
  return ShareInsteadBar(_contents) != nullptr;
}

- (BOOL)shareInstead {
  TabSharingInfoBarDelegate* bar = ShareInsteadBar(_contents);
  if (!bar) {
    return NO;
  }
  bar->ShareThisTabInstead();  // Chrome's button: TabSharingUIViews::StartSharing, then new bars on every tab.
  return YES;
}

- (NSArray<NSDictionary<NSString*, id>*>*)infoBars {
  NSMutableArray<NSDictionary<NSString*, id>*>* out = [NSMutableArray array];
  auto* manager = _contents ? infobars::ContentInfoBarManager::FromWebContents(_contents) : nullptr;
  if (!manager) {
    return out;
  }
  for (infobars::InfoBar* bar : manager->infobars()) {
    infobars::InfoBarDelegate* delegate = bar->delegate();
    ConfirmInfoBarDelegate* confirm = delegate ? delegate->AsConfirmInfoBarDelegate() : nullptr;
    if (!confirm) {
      continue;  // Translate's bar and the like: Cra has its own UI for them.
    }
    NSMutableDictionary<NSString*, id>* entry = [@{
      @"id" : @(reinterpret_cast<intptr_t>(bar)),
      @"message" : base::SysUTF16ToNSString(confirm->GetMessageText()),
      @"closeable" : @(delegate->IsCloseable()),
    } mutableCopy];
    int buttons = confirm->GetButtons();
    if (buttons & ConfirmInfoBarDelegate::BUTTON_OK) {
      entry[@"ok"] = base::SysUTF16ToNSString(confirm->GetButtonLabel(ConfirmInfoBarDelegate::BUTTON_OK));
    }
    if (buttons & ConfirmInfoBarDelegate::BUTTON_CANCEL) {
      entry[@"cancel"] = base::SysUTF16ToNSString(confirm->GetButtonLabel(ConfirmInfoBarDelegate::BUTTON_CANCEL));
    }
    if (std::u16string link = delegate->GetLinkText(); !link.empty()) {
      entry[@"link"] = base::SysUTF16ToNSString(link);
    }
    [out addObject:entry];
  }
  return out;
}

- (void)infoBar:(NSInteger)identifier action:(NSString*)action {
  auto* manager = _contents ? infobars::ContentInfoBarManager::FromWebContents(_contents) : nullptr;
  if (!manager) {
    return;
  }
  for (infobars::InfoBar* bar : manager->infobars()) {
    if (reinterpret_cast<intptr_t>(bar) != identifier) {
      continue;
    }
    infobars::InfoBarDelegate* delegate = bar->delegate();
    ConfirmInfoBarDelegate* confirm = delegate ? delegate->AsConfirmInfoBarDelegate() : nullptr;
    bool remove = false;
    if ([action isEqualToString:@"ok"]) {
      remove = confirm && confirm->Accept();
    } else if ([action isEqualToString:@"cancel"]) {
      remove = confirm && confirm->Cancel();
    } else if ([action isEqualToString:@"link"]) {
      remove = delegate && delegate->LinkClicked(WindowOpenDisposition::kNewForegroundTab);
    } else if ([action isEqualToString:@"close"] && delegate) {
      delegate->InfoBarDismissed();
      remove = true;
    }
    if (remove) {
      bar->RemoveSelf();
    }
    return;
  }
}

- (void)devToolsShowsPanel:(NSString*)panel {
  if ([_delegate respondsToSelector:@selector(browser:devToolsShowsPanel:)]) {
    [_delegate browser:self devToolsShowsPanel:panel];
  }
}

// Chrome quits: a spare page never taken goes before its profile does.
- (void)dropSpareContents {
  _spareContents.reset();
  _spareProfile = nullptr;
}

// Sound starting or stopping as it happens, before the 2 s Chrome's audible state holds (music notes).
- (void)pageSoundPlaying:(BOOL)playing {
  if ([_delegate respondsToSelector:@selector(browser:didChangeSoundPlaying:)]) {
    [_delegate browser:self didChangeSoundPlaying:playing];
  }
}

// Only the host, and none for incognito or Cra's own pages: the recorder's log can be shared.
- (void)pageProcessEvent:(NSString*)kind detail:(NSString*)detail url:(const GURL&)url {
  if (!g_process_event_handler) {
    return;
  }
  GURL page = url.is_empty() && _contents ? _contents->GetLastCommittedURL() : url;
  NSString* site = !_isIncognito && page.SchemeIsHTTPOrHTTPS() && !page.host().empty() ? NS(std::string(page.host()))
                                                                                       : nil;
  g_process_event_handler(kind, detail, site);
}

- (BOOL)isCapturingMedia {
  return _contents &&
         MediaCaptureDevicesDispatcher::GetInstance()->GetMediaStreamCaptureIndicator()->IsCapturingUserMedia(_contents);
}

- (void)pageCaptureChanged {
  if ([_delegate respondsToSelector:@selector(browser:didChangeMediaCapture:)]) {
    [_delegate browser:self didChangeMediaCapture:self.isCapturingMedia];
  }
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
  SEL selector = @selector(browser:didFindMatches:activeMatch:generation:quote:identifier:finalUpdate:);
  // The session is read here, as the result arrives: a later search never lends it its tag. Chrome's
  // find helper drops replies to any request but its current one.
  NSUUID* generation = _findGeneration;
  if (!find || !generation || ![_delegate respondsToSelector:selector]) {
    return;
  }
  const find_in_page::FindNotificationDetails& result = find->find_result();
  [_delegate browser:self
      didFindMatches:result.number_of_matches()
         activeMatch:result.active_match_ordinal()
          generation:generation
               quote:_findQuote
          identifier:result.request_id()
         finalUpdate:result.final_update()];
}

// The page took focus: a click into it, or its window became key again. It becomes Chrome's active tab too, as
// Cra's own focusing makes it: Chrome opens a page's file picker only for its Browser's active tab
// (WebContentsImpl::RunFileChooser asks IsContentsActive) and closes one whose page stops being it. A click back
// into a page from a Little Window's, or from another window's, left Chrome's active tab on that other page, and
// every upload button (X's media button) did nothing. Only in the key window: the page the user is in.
// Once Chrome is done with what it was doing: focus also comes back in the middle of a tab strip change. An
// extension popup's Settings (#626, #631) opens the options page as a tab; Chrome closes the popup while that
// tab goes in, Cra's window becomes key again, its page takes focus, and activating it there hit TabStripModel's
// reentrancy CHECK. Only for the page focused last: an earlier one, made Chrome's active tab after another took the
// focus, takes it back, and that one's turn takes it back again (two pages traded focus hundreds of times a second).
// (Not the view's HasFocus: the window's key state reaches it later, and a page just focused read as not.)
- (void)pageFocused {
  cra::g_last_focused_page = self;
  CraBrowser* __weak weakSelf = self;
  Later(base::BindOnce(^{
    CraBrowser* page = weakSelf;
    if (!page || !page->_contents || page != cra::g_last_focused_page) {
      return;
    }
    if (page->_container.window.isKeyWindow) {
      [page makeChromeActiveTab];
    }
    [page->_delegate browserDidReceiveFocus:page];
  }));
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
  [_pictureInPictureClock invalidate];
  _pictureInPictureClock = nil;
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
  // A new navigation, counted before Chrome ends the load still under way (which tells the app the page stopped
  // loading) and then starts this one: the app sees the new navigation's number first, as the CEF bridge has it.
  ++_navigationStarts;
  _startCounted = YES;
  _contents->GetController().LoadURLWithParams(params);
  if (_startCounted) {
    // Chrome started nothing (or not yet): the count stays as it was.
    _startCounted = NO;
    --_navigationStarts;
  }
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

- (void)setBoostTint:(NSString*)tint {
  std::string value = base::SysNSStringToUTF8(tint ?: @"");
  if (value == _boostTint) {
    return;
  }
  _boostTint = value;
  // Chrome asks again (OverrideWebPreferences → g_boost_tint) and the page repaints; a page made later
  // gets it as it's made.
  if (_contents) {
    _contents->OnWebPreferencesChanged();
  }
}

- (std::string)boostTintForPrefs {
  return _boostTint;
}

- (void)setAudioMuted:(BOOL)muted {
  _audioMuted = muted;
  if (_contents) {
    // As the user's mute (the tab's speaker): Chrome's sound setting would otherwise undo it on the next
    // navigation (SoundContentSettingObserver).
    SetTabAudioMuted(_contents, muted, TabMutedReason::kAudioIndicator, std::string());
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
  if (_isAgent) {
    [self cancelAgentDownload];
  }
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
  // page alive. Deleting the page closes its DevTools too. It is deleted on the next turn, as CEF's close
  // was: close can come from inside the page's own callbacks (a hidden page that answers from its
  // navigation, and its owner closes it), and Chrome stops when a page is deleted while it tells its
  // observers something (~WebContentsImpl, 0.1.44 crash reports).
  Later(base::BindOnce(
      [](base::WeakPtr<content::WebContents> contents) {
        if (!contents) {
          return;
        }
        if (PageHost* host = HostOf(contents.get())) {
          TabStripModel* tabs = host->browser()->GetTabStripModel();
          const int index = tabs->GetIndexOfWebContents(contents.get());
          if (index != TabStripModel::kNoTab) {
            tabs->DetachAndDeleteWebContentsAt(index);
          }
        }
      },
      _contents->GetWeakPtr()));
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
    // A background tab's spare is hidden before it loads, as a page made hidden is (#552). Chromium ignores a
    // hidden container until a page is first shown, so it is told directly; showing the tab shows it.
    if ([self startsHidden]) {
      _spareContents->WasHidden();
    }
    [self insertContents:std::move(_spareContents) profile:profile];
  }
  // Taken before its profile loaded: createPageInProfile: makes it as a tab's page.
}
#pragma mark Agent downloads

- (BOOL)startAgentDownload:(NSString*)url path:(NSString*)path update:(void (^)(CraDownloadInfo*))update {
  GURL target(UTF8(url));
  if (!_isAgent || !_contents || _isClosed || _agentDownloadActive || !target.is_valid()) {
    return NO;
  }
  _agentDownloadActive = YES;
  _agentDownloadCancelled = NO;
  _agentDownloadURL = target;
  _agentDownloadPath = base::FilePath(UTF8(path));
  if (_agentDownloadID) {
    _agentFinishedDownloads.insert(_agentDownloadID);
  }
  _agentDownloadID = 0;
  _agentDownloadUpdate = [update copy];
  std::unique_ptr<download::DownloadUrlParameters> params = content::DownloadRequestUtils::CreateDownloadForWebContentsMainFrame(
      _contents, target, MISSING_TRAFFIC_ANNOTATION);
  params->set_file_path(_agentDownloadPath);
  params->set_prompt(false);
  _contents->GetBrowserContext()->GetDownloadManager()->DownloadUrl(std::move(params));
  return YES;
}

- (BOOL)agentDownloadReady {
  return !_agentDownloadActive;
}

- (void)cancelAgentDownload {
  if (_isClosed) {
    return;
  }
  _agentDownloadCancelled = YES;
  if (_agentDownloadID) {
    cra::ControlDownload(_agentDownloadID, cra::DownloadControl::kCancel);
  }
}

// Whether a download in this agent page is the one its agent asked for (the rest are cancelled).
- (bool)agentDownloadTakes:(download::DownloadItem*)item {
  return !_agentFinishedDownloads.count(item->GetId()) && !_agentDownloadCancelled && _agentDownloadActive &&
         item->GetOriginalUrl() == _agentDownloadURL && (!_agentDownloadID || _agentDownloadID == item->GetId());
}

- (void)agentDownloadItem:(download::DownloadItem*)item {
  if (_agentFinishedDownloads.count(item->GetId())) {
    return;
  }
  if (![self agentDownloadTakes:item] && !(_agentDownloadID && _agentDownloadID == item->GetId())) {
    if (item->GetState() == download::DownloadItem::IN_PROGRESS) {
      item->Cancel(/*user_cancel=*/false);
    }
    return;
  }
  _agentDownloadID = item->GetId();
  constexpr int64_t kMax = 64 * 1024 * 1024;
  if (item->GetState() == download::DownloadItem::IN_PROGRESS &&
      (_agentDownloadCancelled || item->GetReceivedBytes() > kMax || item->GetTotalBytes() > kMax)) {
    _agentDownloadCancelled = YES;
    item->Cancel(/*user_cancel=*/false);
  }
  CraDownloadInfo* info = [[CraDownloadInfo alloc] init];
  info.identifier = item->GetId();
  info.url = NS(item->GetURL().spec());
  info.fullPath = NS(item->GetFullPath().value());
  info.suggestedName = NS(item->GetSuggestedFilename());
  info.receivedBytes = item->GetReceivedBytes();
  info.totalBytes = item->GetTotalBytes();
  info.percent = item->PercentComplete();
  if (item->GetState() == download::DownloadItem::COMPLETE && !_agentDownloadCancelled) {
    info.state = CraDownloadStateComplete;
  } else if (item->GetState() == download::DownloadItem::CANCELLED || _agentDownloadCancelled) {
    info.state = CraDownloadStateCancelled;
  } else if (item->GetState() == download::DownloadItem::INTERRUPTED) {
    info.state = CraDownloadStateInterrupted;
  } else {
    info.state = CraDownloadStateInProgress;
  }
  if (_agentDownloadUpdate) {
    _agentDownloadUpdate(info);
  }
  if (info.state != CraDownloadStateInProgress) {
    _agentDownloadActive = NO;
    _agentDownloadUpdate = nil;
  }
}
// Chrome keys the setting by the page that opens the pop-up.
- (BOOL)popupsAllowed {
  if (!_contents) {
    return NO;
  }
  GURL url = _contents->GetLastCommittedURL();
  auto* settings = HostContentSettingsMapFactory::GetForProfile(_contents->GetBrowserContext());
  return settings && settings->GetContentSetting(url, url, ContentSettingsType::POPUPS) == CONTENT_SETTING_ALLOW;
}

- (void)setPopupsAllowed:(BOOL)allowed {
  if (!_contents) {
    return;
  }
  GURL url = _contents->GetLastCommittedURL();
  auto* settings = HostContentSettingsMapFactory::GetForProfile(_contents->GetBrowserContext());
  if (settings && url.is_valid()) {
    settings->SetContentSettingDefaultScope(url, url, ContentSettingsType::POPUPS,
                                            allowed ? CONTENT_SETTING_ALLOW : CONTENT_SETTING_DEFAULT);
  }
}
- (void)exitFullscreen {
  if (_contents) {
    _contents->ExitFullscreen(/*will_cause_resize=*/true);
  }
}
// The page holds the keyboard with Esc in it: Chrome's KeyboardLockController of the Browser that holds the page.
- (BOOL)holdsEscapeKey {
  if (!_contents) {
    return NO;
  }
  auto it = Hosts().find(Profile::FromBrowserContext(_contents->GetBrowserContext()));
  if (it == Hosts().end() || IsClosing(it->second->browser())) {
    return NO;
  }
  ExclusiveAccessManager* manager = ExclusiveAccessManager::From(it->second->browser());
  KeyboardLockController* lock = manager ? manager->keyboard_lock_controller() : nullptr;
  return lock && lock->exclusive_access_tab() == _contents && lock->RequiresPressAndHoldEscToExit();
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
  _devToolsFrontend = std::make_unique<DevToolsFrontendObserver>(frontend, self);
  frontend->SetUserData(views::CraHostedPageKey(), std::make_unique<base::SupportsUserData::Data>());
  if (!_devToolsHost) {
    _devToolsHost = [[CraDevToolsHostWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                                             styleMask:NSWindowStyleMaskBorderless
                                                               backing:NSBackingStoreBuffered
                                                                 defer:NO];
    _devToolsHost.releasedWhenClosed = NO;
    static_cast<CraDevToolsHostWindow*>(_devToolsHost).page = self;
    _devToolsHost.contentView.autoresizesSubviews = YES;
  }
  NSView* view = frontend->GetNativeView().GetNativeNSView();
  [view removeFromSuperview];
  _devToolsFrontendView = view;
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
  _devToolsFrontend.reset();
  _hasDevTools = NO;
  // Out of the card it was docked in, if the app had it there.
  [_devToolsFrontendView removeFromSuperview];
  _devToolsFrontendView = nil;
  [_devToolsHost.parentWindow removeChildWindow:_devToolsHost];
  [_devToolsHost orderOut:nil];
  [_delegate browserDidCloseDevTools:self];
}

- (NSWindow*)devToolsWindow {
  return _hasDevTools ? _devToolsHost : nil;
}

// The frontend's dock calls (kDevToolsDockScript): docked on a side, or undocked into a window of its own.
- (void)devToolsFrontendDocked:(BOOL)docked {
  if (_hasDevTools && [_delegate respondsToSelector:@selector(browser:devToolsDocked:)]) {
    [_delegate browser:self devToolsDocked:docked];
  }
}

// Where the docked frontend left room for the page, in points from its top left.
- (void)devToolsFrontendPageBounds:(NSRect)bounds {
  if (_hasDevTools && [_delegate respondsToSelector:@selector(browser:devToolsPageBounds:)]) {
    [_delegate browser:self devToolsPageBounds:bounds];
  }
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
- (void)findText:(NSString*)text
         forward:(BOOL)forward
       matchCase:(BOOL)matchCase
        findNext:(BOOL)findNext
      generation:(NSUUID*)generation
           quote:(BOOL)quote {
  auto* find = _contents ? find_in_page::FindTabHelper::FromWebContents(_contents) : nullptr;
  if (!find) {
    return;
  }
  // Within one session Chrome's find helper tells a new search from the next match itself. A new
  // session stops the old one first, so the same text again (A, B, A) is a fresh search with its own
  // request, and the old one's replies are dropped.
  if (![_findGeneration isEqual:generation] || _findQuote != quote) {
    _findGeneration = nil;
    find->StopFinding(find_in_page::SelectionAction::kKeep);
    _findGeneration = generation;
    _findQuote = quote;
  }
  find->StartFinding(base::SysNSStringToUTF16(text), forward, matchCase, /*find_match=*/true);
}
- (void)stopFinding:(BOOL)clearSelection {
  _findGeneration = nil;
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
// One of Chrome's commands by its IDC name, run for this page by its Browser (Chrome's active tab follows it).
- (BOOL)runChromeCommand:(NSString*)name {
  static NSDictionary<NSString*, NSNumber*>* const commands = @{
    @"IDC_TASK_MANAGER" : @(IDC_TASK_MANAGER),
    @"IDC_ROUTE_MEDIA" : @(IDC_ROUTE_MEDIA),
  };
  NSNumber* command = commands[name];
  PageHost* host = _contents ? HostOf(_contents) : nullptr;
  if (!command || !host || !chrome::IsCommandEnabled(host->browser(), command.intValue)) {
    return NO;
  }
  [self makeChromeActiveTab];
  return chrome::ExecuteCommand(host->browser(), command.intValue);
}
- (void)probeBackgroundColor {
  if (_contents) {
    [self pageBackgroundColor];
  }
}// Arc's black while websites are dark, white while they are light.
+ (NSColor*)pageCanvasColor {
  return PagesAreDark() ? NSColor.blackColor : NSColor.whiteColor;
}
// Until a page's renderer sends its first frame, Chromium's compositor fills the view with the view's own colour:
// white unless the browser sets one. Chrome sets its theme's (ContentsWebView, which leaves Cra's pages alone:
// cra-hosted-pages.patch); Cra sets Arc's canvas, so a Peek or a new tab of a dark site doesn't flash white (X,
// 22 Nov). Only the colour before a frame: a page that paints nothing still paints white, as in Arc.
- (void)applyPageCanvasTo:(content::RenderWidgetHostView*)view {
  if (view) {
    view->SetBackgroundColor(PagesAreDark() ? SK_ColorBLACK : SK_ColorWHITE);
  }
}
// A new page draws its empty document before its first page commits, and that frame stays on screen until the page
// paints: white for a second and more on a dark site that draws late (#712), for a tab woken from sleep whether it
// takes a spare page (drawn before any tab took it), makes a page and restores its history, or reloads in place
// after a discard (its renderer gone: PrimaryMainFrameRenderProcessGone). The empty document
// draws in Arc's canvas instead; the page goes back to Chromium's white base once it draws
// (pageFirstPaint), so a page with no background of its own still paints white, as in Arc.
- (void)applyCanvasBaseTo:(content::WebContents*)contents {
  if (!contents) {
    return;
  }
  contents->SetPageBaseBackgroundColor(PagesAreDark() ? SK_ColorBLACK : SK_ColorWHITE);
  [self applyPageCanvasTo:contents->GetRenderWidgetHostView()];
  _canvasBase = YES;
}
- (void)applySpareCanvas {
  [self applyCanvasBaseTo:_spareContents.get()];
}
// The page drew something of its own: Chromium's base again, so a page with no background of its own paints white,
// as in Arc. Not at commit: a page restored from its history (a tab woken without a spare) drew its first frame on
// the cleared base, white, before its own colours came (#712).
- (void)pageFirstPaint {
  if (_canvasBase && _contents && !_contents->IsBeingDestroyed()) {
    _canvasBase = NO;
    _contents->SetPageBaseBackgroundColor(std::nullopt);
    [self applyPageCanvasTo:_contents->GetRenderWidgetHostView()];
  }
}
// View ▸ Appearance while a page still waits for its first paint.
- (void)refreshCanvasBase:(content::WebContents*)contents {
  if (_canvasBase) {
    [self applyCanvasBaseTo:contents];
  }
}
- (void)executeJavaScript:(NSString*)script inDevTools:(BOOL)inDevTools {
  if (!inDevTools) {
    [self executeJavaScript:script];
  } else if (_devToolsFrontend) {
    // The frontend (cra://debug?devtoolsjs=, the undocked window's title bar inset).
    _devToolsFrontend->Execute(base::SysNSStringToUTF16(script));
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
  // Page.captureScreenshot and the others act on the page's view, which a page being torn down no longer has
  // (crash-page-closed-while-loading).
  if (_contents->IsBeingDestroyed()) {
    completion(nil, @"page closing");
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
  [self evaluateInIsolatedWorld:world
                         params:params
                      ifCurrent:^BOOL {
                        return YES;
                      }
                     completion:completion];
}

// The caller's check runs again before each step and right before the script is sent: Ask on Page
// drops an evaluation whose page or question changed while the frame and world were looked up.
- (void)evaluateInIsolatedWorld:(NSString*)world
                         params:(NSString*)params
                      ifCurrent:(BOOL (^)(void))ifCurrent
                     completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
  if (!ifCurrent()) {
    completion(nil, @"retired evaluation");
    return;
  }
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
                  if (!strong || !ifCurrent()) {
                    completion(nil, @"retired evaluation");
                    return;
                  }
                  if (![frameID isKindOfClass:NSString.class]) {
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
                                    if (!again || !ifCurrent()) {
                                      completion(nil, @"retired evaluation");
                                      return;
                                    }
                                    if (![context isKindOfClass:NSNumber.class] ||
                                        ![evaluate isKindOfClass:NSMutableDictionary.class]) {
                                      completion(nil, madeError ?: @"no isolated world");
                                      return;
                                    }
                                    evaluate[@"contextId"] = context;
                                    NSData* json = [NSJSONSerialization dataWithJSONObject:evaluate options:0 error:nil];
                                    if (!ifCurrent()) {
                                      completion(nil, @"retired evaluation");
                                      return;
                                    }
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

namespace {

// Scenarios only (crash-extensions-renderer-reused-on-exit): a renderer host that starts its next process from inside
// the notice that its last one ended, before the extensions system has heard of the end. Chrome's
// RendererStartupHelper then still holds the old process's entry when the new one is created (and so sends it
// nothing), drops the entry when its turn in the notice comes, and finds the new process untracked once it launches:
// CHECK(GetRenderer(host) != nullptr || ...) in OnRenderProcessLaunched, two Cra crash reports (0.1.52, 0.1.54).
// Chromium handles this on Android and ChromeOS only (renderer-startup-reused-process.patch does it on the Mac).
// The helper's observer goes in when it registers a process, so the first end (the helper first, then this) puts
// this one ahead of it for the second.
class RendererReuseOnExit : public content::RenderProcessHostObserver {
 public:
  // A hidden page of its own gives it a renderer host through the public API (SiteInstance's
  // GetOrCreateProcessForTesting is CHECK_IS_TEST in a shipping build).
  explicit RendererReuseOnExit(Profile* profile)
      : contents_(content::WebContents::Create(content::WebContents::CreateParams(
            profile, content::SiteInstance::CreateForURL(profile, GURL("http://renderer-reuse.invalid/"))))) {
    host_ = contents_->GetPrimaryMainFrame()->GetProcess();
    host_->IncrementPendingReuseRefCount();
    host_->AddObserver(this);
    if (!host_->IsInitializedAndNotDead()) {
      host_->Init();
    } else if (host_->IsReady()) {
      RenderProcessReady(host_);
    }
  }

  void RenderProcessReady(content::RenderProcessHost* host) override {
    if (step_ == 0 || step_ == 2) {
      LOG(WARNING) << "Cra: renderer reuse: ends process " << step_ / 2 + 1;
      ++step_;
      host->Shutdown(content::RESULT_CODE_KILLED);
    } else if (step_ == 4) {
      LOG(WARNING) << "Cra: renderer reuse: the process started in the exit notice is running";
      step_ = 5;
      Later(base::BindOnce(&RendererReuseOnExit::Finish, base::Unretained(this)));
    }
  }

  void RenderProcessExited(content::RenderProcessHost* host, const content::ChildProcessTerminationInfo&) override {
    if (step_ == 1) {
      // The extensions system heard first; its next registration comes after this observer.
      step_ = 2;
      Later(base::BindOnce([](content::RenderProcessHost* host) { host->Init(); }, base::Unretained(host)));
    } else if (step_ == 3) {
      LOG(WARNING) << "Cra: renderer reuse: starts the next process inside the exit notice";
      step_ = 4;
      host->Init();
    }
  }

  void RenderProcessHostDestroyed(content::RenderProcessHost* host) override {
    host_ = nullptr;
    if (step_ != 5) {  // otherwise Finish, already posted, deletes it
      // Not the page from inside its own process host's teardown.
      base::SingleThreadTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, std::move(contents_));
      delete this;
    }
  }

 private:
  void Finish() {
    if (host_) {
      host_->RemoveObserver(this);
      host_->DecrementPendingReuseRefCount();
    }
    delete this;
  }

  std::unique_ptr<content::WebContents> contents_;
  raw_ptr<content::RenderProcessHost> host_ = nullptr;
  int step_ = 0;
};

}  // namespace

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
  // Feature lists given on the command line (scripts/perf/bench.sh's BENCH_ARGS) join Cra's: Chromium reads
  // one --enable-features and one --disable-features, and a feature in both stays enabled.
  std::vector<std::string> givenEnabled, givenDisabled;
  auto takeList = [](const std::string& arg, const char* prefix, std::vector<std::string>* into) {
    if (arg.rfind(prefix, 0) != 0) {
      return false;
    }
    for (const std::string& name : base::SplitString(arg.substr(strlen(prefix)), ",", base::TRIM_WHITESPACE,
                                                     base::SPLIT_WANT_NONEMPTY)) {
      into->push_back(name);
    }
    return true;
  };
  for (NSString* arg in given) {
    std::string a = UTF8(arg);
    if (takeList(a, "--enable-features=", &givenEnabled) || takeList(a, "--disable-features=", &givenDisabled)) {
      continue;
    }
    args.push_back(a);
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
      "ScalableFrameEviction,OptimizationHints,PreloadingHeuristicsMLModel,HistoryEmbeddings,Glic,LensOverlay,"
      // Chrome 158 makes the "v10" key (the Keychain item's) unavailable outside Chrome's own data folder and
      // encrypts with a "v11" key instead. Every cookie and password Cra on CEF saved is v10, and a cookie that
      // won't decrypt takes its whole site down with it: everyone signed out at the first engine launch. The
      // item is Cra's own ("Cra Safe Storage"), so there is no other app's data to protect from.
      "KeychainKeyProviderUserDataDirProtection,"
      // Chrome unloads a profile once its last Chrome window closes. Cra's pages and spares live outside Chrome's
      // windows, so a profile whose hidden host closed went with pages still in it: ~WebContentsOfBrowserContext
      // from ProfileDestroyer::Timeout (0.1.44 crash reports). Cra's profiles stay loaded until it quits.
      "DestroyProfileOnBrowserClose,"
      // Chrome's code sign clone: at quit it starts a cleanup helper from Versions/<old>/Helpers, and Sparkle,
      // waiting on that quit, replaces the bundle. When the update moves Chrome's version (158 → 159 in 0.1.52)
      // the folder is gone, so the helper dies at dlopen, the framework bundle CHECK or ICU: 127 "Cra Helper"
      // crash reports, 20–22 Nov 2026, each leaving a whole-app clone in $TMPDIR/../X. Chrome's own updater keeps
      // old version folders; Sparkle installs after Cra quits, so Cra doesn't need the clone's protection.
      "MacAppCodeSignClone";
  // CraEngineMain adds AperitifHelpers to this one.
  std::vector<std::string> enabled = {"ForceWebRequestProxyForTest", "WebContentsDiscard", "InfiniteTabsFreezing",
                                      "VideoPipForceTrustedForMediaPlaybackForTesting", "HideDelegatedFrameHostMac"};
  std::erase_if(enabled, [&](const std::string& name) { return std::ranges::contains(givenDisabled, name); });
  enabled.insert(enabled.end(), givenEnabled.begin(), givenEnabled.end());
  for (const std::string& name : givenDisabled) {
    disabled += "," + name;
  }
  args.push_back("--enable-features=" + base::JoinString(enabled, ","));
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
  // Safe Browsing's list updates need a Google API key, which Chrome reads from the environment in an
  // unbranded build (google_apis); one already set there wins, for testing (docs/release.md).
  if (NSString* key = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CraGoogleAPIKey"]; key.length) {
    setenv("GOOGLE_API_KEY", key.UTF8String, 0);
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
  cra::DropSparePages();
  cra::StopProfilePrefs();
  cra::DetachHostWindows();
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

+ (BOOL)supportsSparePages {
  return YES;
}

#pragma mark Not yet

+ (void)spikeChromeWindowWithURL:(NSString*)url handler:(void (^)(NSWindow*))handler {
}
+ (void)setLinkMenuTitle:(NSString*)title opensInBackground:(BOOL)background {
  g_link_menu_title = [title copy];
  g_link_menu_background = background;
}
// One of Chromium's strings in the language it runs in ($1 where a name goes, & before a mnemonic).
+ (NSString*)chromiumString:(CraChromiumString)string {
  if (!g_ready) {
    return nil;
  }
  if (string == CraChromiumStringSearchWebForImage) {
    // Chrome 159 dropped "Search $1 for Image" (IDS_CONTENT_CONTEXT_SEARCHWEBFORIMAGE) and its translations: Chrome
    // labels every image search with the Lens string now. Arc's English label stays; in another language Cra
    // keeps Chrome's own label (nil).
    return base::StartsWith(g_browser_process->GetApplicationLocale(), "en") ? @"&Search $1 for Image" : nil;
  }
  int ids = string == CraChromiumStringOpenLinkInNewTab ? IDS_CONTENT_CONTEXT_OPENLINKNEWTAB
                                                        : IDS_CONTENT_CONTEXT_SEARCHLENSFORIMAGE;
  return base::SysUTF16ToNSString(l10n_util::GetStringUTF16(ids));
}
+ (void)setImageSearchTitle:(NSString* _Nullable (^)(NSString*))block {
  g_image_search_title = [block copy];
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
// The last incognito window closed: the off-the-record profile's Browser closes, so Chrome destroys the profile
// and the next incognito page starts a fresh one.
+ (void)endIncognitoSession {
  for (auto& [profile, host] : Hosts()) {
    if (profile->IsOffTheRecord() && host->browser()) {
      host->browser()->GetWindow()->Close();
    }
  }
}
+ (void)setRelaunchHandler:(void (^)(NSArray<NSString*>*))handler {
  g_relaunch_handler = [handler copy];
}
+ (void)setExtensionTabHandler:(CraBrowser* _Nullable (^)(NSString*, NSString* _Nullable, BOOL,
                                                          CraBrowser* _Nullable))handler {
  g_extension_tab_handler = [handler copy];
}
+ (void)setStrayPageHandler:(void (^)(NSString*, NSString* _Nullable))handler {
  g_stray_page_handler = [handler copy];
}
+ (void)setPageWindowStartHandler:(NSRect (^)(NSSize))handler {
  g_page_window_start = [handler copy];
}
+ (void)setAppLinkHandler:(BOOL (^)(CraBrowser*, NSString*, BOOL))handler {
  cra::g_app_link_handler = [handler copy];
}
+ (void)setViewSourceHandler:(void (^)(CraBrowser*, NSString*))handler {
  g_view_source_handler = [handler copy];
}
// Test hook: the commands scenarios run by name.
+ (BOOL)runNextPageMenuCommand:(NSString*)name {
  static NSDictionary<NSString*, NSNumber*>* const commands = @{
    @"IDC_CONTENT_CONTEXT_OPENLINKNEWTAB" : @(kMenuOpenLinkNewTab),
    @"IDC_VIEW_SOURCE" : @(IDC_VIEW_SOURCE),
    @"IDC_CONTENT_CONTEXT_VIEWFRAMESOURCE" : @(IDC_CONTENT_CONTEXT_VIEWFRAMESOURCE),
    @"IDC_CONTENT_CONTEXT_INSPECTELEMENT" : @(IDC_CONTENT_CONTEXT_INSPECTELEMENT),
    @"IDC_CONTENT_CONTEXT_OPENLINKNEWWINDOW" : @(IDC_CONTENT_CONTEXT_OPENLINKNEWWINDOW),
    @"IDC_CONTENT_CONTEXT_OPENLINKOFFTHERECORD" : @(IDC_CONTENT_CONTEXT_OPENLINKOFFTHERECORD),
    @"IDC_CONTENT_CONTEXT_COPYLINKLOCATION" : @(IDC_CONTENT_CONTEXT_COPYLINKLOCATION),
  };
  NSNumber* command = commands[name];
  g_next_page_menu_command = command ? command.intValue : -1;
  return command != nil;
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
  g_process_event_handler = [handler copy];
}
+ (BOOL)isExtensionWindow:(NSWindow*)window {
  return [g_extension_windows containsObject:window];
}
// The hidden window of a profile's Browser (it hosts Chrome's bubbles for Cra's pages).
+ (BOOL)isPageWindow:(NSWindow*)window {
  for (auto& [profile, host] : Hosts()) {
    if (host->window() == window) {
      return YES;
    }
  }
  return NO;
}
+ (void)floatOverFullScreenSpaces:(NSWindow*)window {
  FloatOverFullScreenSpaces(window);
}
// A focused password field's lock on macOS Secure Input (secure-input-active-app.patch turns the
// system's on only while Cra is the active app).
+ (BOOL)holdsSecureInput {
  return ui::ScopedPasswordInputEnabler::IsPasswordInputEnabled();
}
+ (NSString*)pageWindowsReadout {
  return [NSString stringWithFormat:@"shown=%ld away=%ld animated=%ld", (long)g_page_windows_shown,
                                    (long)g_page_windows_away, (long)g_page_windows_animated];
}
// The view Chrome's Settings find as the page's browser window (kBrowserViewElementId), in a profile's hidden Browser.
views::View* PageHostBrowserView(BrowserWindowInterface* browser) {
  views::Widget* widget =
      views::Widget::GetWidgetForNativeWindow(browser->GetWindow()->GetNativeWindow());
  std::vector<views::View*> queue = {widget ? widget->GetRootView() : nullptr};
  while (!queue.empty()) {
    views::View* view = queue.back();
    queue.pop_back();
    if (!view) {
      continue;
    }
    if (view->GetProperty(views::kElementIdentifierKey) == kBrowserViewElementId) {
      return view;
    }
    for (views::View* child : view->children()) {
      queue.push_back(child);
    }
  }
  return nullptr;
}
// "element=<0|1> shown=<0|1>" per profile's hidden Browser: whether Chrome finds its browser element, which its
// Settings CHECKed for (Clear browsing data's Cancel crashed Cra 0.1.50 without it), for cra://debug?hostBrowserView=.
+ (NSString*)pageHostBrowserViewReadout {
  NSMutableArray<NSString*>* hosts = [NSMutableArray array];
  for (auto& [profile, host] : Hosts()) {
    BrowserWindowInterface* browser = host->browser();
    if (!browser) {
      continue;
    }
    ui::TrackedElement* element = ui::ElementTracker::GetElementTracker()->GetUniqueElement(
        kBrowserViewElementId, BrowserElements::From(browser)->GetContext());
    views::View* view = PageHostBrowserView(browser);
    [hosts addObject:[NSString stringWithFormat:@"element=%d shown=%d", element ? 1 : 0,
                                                (view && view->GetVisible()) ? 1 : 0]];
  }
  return hosts.count ? [hosts componentsJoinedByString:@"; "] : @"no host";
}
// Scenarios only: every hidden Browser's view out of sight, so Chrome finds no browser element for its pages, the
// state a Mac was in when Clear browsing data's Cancel crashed (crash-clear-browsing-data-cancel).
+ (void)setPageHostBrowserViewsHidden:(BOOL)hidden {
  for (auto& [profile, host] : Hosts()) {
    if (views::View* view = host->browser() ? PageHostBrowserView(host->browser()) : nullptr) {
      view->SetVisible(!hidden);
    }
  }
}
// Scenarios only: a renderer process started inside the notice that the one before it ended
// (crash-extensions-renderer-reused-on-exit, RendererReuseOnExit above). Its steps go to Chrome's log.
+ (void)reuseRendererInsideExitNotice {
  if (Hosts().empty()) {
    LOG(WARNING) << "Cra: renderer reuse: no profile";
    return;
  }
  new RendererReuseOnExit(Hosts().begin()->first);
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
  [self fetchURL:url headers:headers profilePath:profilePath restricted:NO completion:completion];
}
+ (void)fetchPluginURL:(NSString*)url
               headers:(NSDictionary<NSString*, NSString*>*)headers
           profilePath:(NSString*)profilePath
            completion:(void (^)(NSInteger, NSString*, NSString*, NSString*))completion {
  [self fetchURL:url headers:headers profilePath:profilePath restricted:YES completion:completion];
}
// The profile loads first if it hasn't, as a page's does.
+ (void)fetchURL:(NSString*)url
         headers:(NSDictionary<NSString*, NSString*>*)headers
     profilePath:(NSString*)profilePath
      restricted:(BOOL)restricted
      completion:(void (^)(NSInteger, NSString*, NSString*, NSString*))completion {
  GURL target(UTF8(url));
  if (!g_ready || g_quitting || !target.is_valid()) {
    completion(0, url, @"", @"");
    return;
  }
  void (^done)(NSInteger, NSString*, NSString*, NSString*) = [completion copy];
  NSDictionary* sent = [headers copy];
  base::FilePath dir = ProfileDir(profilePath);
  ProfileManager* profiles = g_browser_process->profile_manager();
  if (Profile* profile = profiles->GetProfileByPath(dir)) {
    cra::Fetch(profile, target, sent, restricted, done);
    return;
  }
  LoadingProfiles().insert(dir);
  profiles->CreateProfileAsync(dir, base::BindOnce(^(Profile* loaded) {
                                 LoadingProfiles().erase(dir);
                                 if (!loaded || g_quitting) {
                                   done(0, url, @"", @"");
                                   return;
                                 }
                                 cra::Fetch(loaded, target, sent, restricted, done);
                               }));
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
  for (const auto& [contents, page] : PagesByContents()) {
    [page applyPageCanvasTo:contents->GetRenderWidgetHostView()];
    [page refreshCanvasBase:contents];
  }
  for (CraBrowser* spare in SparePages().allObjects) {
    [spare applySpareCanvas];
  }
}
+ (NSInteger)websiteAppearance {
  return cra::WebsiteAppearance();
}
+ (void)setWebsiteAppearanceChangeHandler:(void (^)(NSInteger))handler {
  cra::SetWebsiteAppearanceHandler(handler);
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

namespace {

// AppKit raises "-_newFirstResponderAfterResigning is not a valid message outside of a responder's implementation
// of -resignFirstResponder" when a text field in a popover or panel gives up focus while another window takes the
// key window: the crash-report question's sheet, a page window, the space icon popover (0.1.53 crash reports,
// crash-first-responder-after-resigning). Other Mac apps get it logged; with Chrome's NSApplicationCrashOnExceptions
// (content/app/mac_init.mm) AppKit's event loop throws it on after -reportException: and Cra quit. It's caught where
// it's raised: the method answers nil (no new first responder) and the focus change goes on. Every other exception
// still reaches Chrome's handling.
void DropFirstResponderAfterResigningException() {
  SEL sel = NSSelectorFromString(@"_newFirstResponderAfterResigning");
  Method method = class_getInstanceMethod([NSWindow class], sel);
  if (!method || strcmp(method_getTypeEncoding(method), "@16@0:8") != 0) {
    return;
  }
  auto original = reinterpret_cast<id (*)(id, SEL)>(method_getImplementation(method));
  method_setImplementation(method, imp_implementationWithBlock(^id(NSWindow* window) {
    @try {
      return original(window, sel);
    } @catch (NSException* exception) {
      if (![exception.name isEqualToString:NSInternalInconsistencyException]) {
        @throw;
      }
      NSLog(@"Cra: AppKit exception dropped: %@", exception.reason);
      return nil;
    }
  }));
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
  DropFirstResponderAfterResigningException();
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
  cra::NoteLastPress(event);
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

@implementation CraDevToolsHostWindow
// Undocked it is a titled window the frontend's keys go to; docked, the app takes its view into a card.
- (BOOL)canBecomeKeyWindow {
  return YES;
}
- (BOOL)canBecomeMainWindow {
  return (self.styleMask & NSWindowStyleMaskTitled) != 0;
}
// The close button and ⌘W on the undocked window close DevTools; the window stays for the next time.
- (void)performClose:(id)sender {
  [self.page closeDevTools];
}
@end

@implementation CraPageContainerView {
  BOOL _counted;
}
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  if (!_counted && self.window) {
    _counted = YES;
    g_page_windows_shown++;
  }
}
@end
