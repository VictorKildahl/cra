// Objective-C++ bridge between Swift and CEF. See include/CraCEF.h.
#import "CraCEF.h"

#include "include/views/cef_browser_view.h"
#include "include/views/cef_browser_view_delegate.h"
#include "include/views/cef_window.h"
#include "include/views/cef_window_delegate.h"
#include <crt_externs.h>
#include <atomic>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_command_ids.h"
#include "include/cef_command_line.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_display_handler.h"
#include "include/cef_download_handler.h"
#include "include/cef_find_handler.h"
#include "include/cef_focus_handler.h"
#include "include/cef_keyboard_handler.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_parser.h"
#include "include/cef_permission_handler.h"
#include "include/cef_request_context.h"
#include "include/cef_request_handler.h"
#include "include/cef_resource_request_handler.h"
#include "include/cef_urlrequest.h"
#include "include/cef_version.h"
#include "CraContentBlocker.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

// MARK: - Globals

static CefScopedLibraryLoader* g_libraryLoader = nullptr;
static CefRefPtr<CefRequestContext> g_incognitoContext;
/// Arc's Profiles: one request context per profile folder (spaces that share a profile share it).
static std::map<std::string, CefRefPtr<CefRequestContext>> g_profileContexts;
/// Profiles that finished loading, and browsers waiting for theirs: a Chrome-style
/// browser view can't be made in a profile still loading from disk (CEF returns null).
static NSMutableSet<NSString*>* g_readyProfiles = nil;
static NSMutableDictionary<NSString*, NSMutableArray<CraBrowser*>*>* g_waitingForProfile = nil;
static std::atomic<bool> g_contextInitialized{false};
static std::atomic<int> g_liveBrowsers{0};
static bool g_quitting = false;
static bool g_useChromeStyle = false;
static bool g_useMockKeychain = false;
/// Resolved by Swift from the chosen profile, including environment-free dev launches.
static NSString* g_extensionsDirectory = nil;
static BOOL g_chromeHosting = NO;
static NSMutableArray<CraBrowser*>* g_pendingCreation = nil;
static void (^g_relaunchHandler)(NSArray<NSString*>*) = nil;
static BOOL g_alreadyRunning = NO;
static NSHashTable<CraBrowser*>* g_allBrowsers = nil;
/// Closed tabs whose page stays alive until its downloads end (see -[CraBrowser close]).
static NSMutableSet<CraBrowser*>* g_parkedBrowsers = nil;
static void (^g_strayPageHandler)(NSString*) = nil;

static NSString* NSStringFromCef(const CefString& s) {
    std::string utf8 = s.ToString();
    NSString* r = [[NSString alloc] initWithBytes:utf8.data() length:utf8.size() encoding:NSUTF8StringEncoding];
    return r ?: @"";
}

static CefString CefStringFromNS(NSString* s) {
    return CefString(std::string(s.UTF8String ?: ""));
}

/// Page context menus shown by Cra (RunContextMenu) instead of Chrome.
static BOOL g_ownContextMenus = NO;

/// The command picked from a context menu Cra shows; -1 while none is.
@interface CraMenuPick : NSObject
@property (nonatomic) int commandID;
- (void)choose:(NSMenuItem*)item;
@end

@implementation CraMenuPick
- (instancetype)init {
    if ((self = [super init])) _commandID = -1;
    return self;
}
- (void)choose:(NSMenuItem*)item { self.commandID = (int)item.tag; }
@end

/// Chrome's labels mark mnemonics with "&" ("&&" is a literal ampersand).
static NSString* CraMenuLabel(CefRefPtr<CefMenuModel> model, size_t i) {
    NSString* s = NSStringFromCef(model->GetLabelAt(i));
    s = [s stringByReplacingOccurrencesOfString:@"&&" withString:@"\u0001"];
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@""];
    return [s stringByReplacingOccurrencesOfString:@"\u0001" withString:@"&"];
}

static NSMenu* CraMenuFromModel(CefRefPtr<CefMenuModel> model, CraMenuPick* pick) {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
    menu.autoenablesItems = NO;
    for (size_t i = 0; i < model->GetCount(); i++) {
        cef_menu_item_type_t type = model->GetTypeAt(i);
        if (type == MENUITEMTYPE_SEPARATOR) {
            if (menu.numberOfItems > 0 && !menu.itemArray.lastObject.isSeparatorItem) [menu addItem:[NSMenuItem separatorItem]];
            continue;
        }
        if (type == MENUITEMTYPE_NONE) continue;
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:CraMenuLabel(model, i) action:nil keyEquivalent:@""];
        if (type == MENUITEMTYPE_SUBMENU) {
            item.submenu = CraMenuFromModel(model->GetSubMenuAt(i), pick);
        } else {
            item.action = @selector(choose:);
            item.target = pick;
            item.tag = model->GetCommandIdAt(i);
            if (model->IsCheckedAt(i)) item.state = NSControlStateValueOn;
        }
        item.enabled = model->IsEnabledAt(i);
        item.hidden = !model->IsVisibleAt(i);
        [menu addItem:item];
    }
    while (menu.itemArray.lastObject.isSeparatorItem) [menu removeItem:menu.itemArray.lastObject];
    return menu;
}

enum CraMenuCommand {
    kMenuOpenLinkInNewTab = MENU_ID_USER_FIRST + 1,
    kMenuOpenLinkInBackgroundTab,
    kMenuCopyLink,
    kMenuInspectElement,
    kMenuOpenImageInNewTab,
    kMenuCopyImageURL,
    kMenuPictureInPicture,
};

// MARK: - Downloads

@implementation CraDownloadInfo
@end

// MARK: - CraBrowser private interface

class CraClient;

// Live CraClient instances. The bridge is built without RTTI, so a popup's client
// (which can also be a DevToolsClient) is checked against this set before casting.
#include <set>
static std::set<const void*>& CraClientRegistry() { static std::set<const void*> s; return s; }
static CraClient* AsCraClient(CefClient* c) {
    return c && CraClientRegistry().count(static_cast<const void*>(c)) ? reinterpret_cast<CraClient*>(c) : nullptr;
}

@interface CraBrowser ()
@property (nonatomic, strong) NSView* containerView;
@property (nonatomic, copy) NSString* currentURL;
@property (nonatomic, copy) NSString* currentTitle;
@property (nonatomic) BOOL isLoading;
@property (nonatomic) BOOL canGoBack;
@property (nonatomic) BOOL canGoForward;
@property (nonatomic) BOOL isCreated;
@property (nonatomic) BOOL isClosed;
@property (nonatomic) BOOL closeRequested;
@property (nonatomic) BOOL closedByPage;
@property (nonatomic) BOOL isInPictureInPicture;
@property (nonatomic) BOOL isPictureInPicturePlaying;
@property (nonatomic) BOOL isCapturingMedia;
- (void)requestPictureInPictureInFrame:(CefRefPtr<CefFrame>)frame automatic:(BOOL)automatic x:(int)x y:(int)y;
- (void)adoptBrowser:(CefRefPtr<CefBrowser>)browser;
- (void)devToolsBrowserCreated:(CefRefPtr<CefBrowser>)browser;
- (void)devToolsBrowserClosed;
- (void)browserClosed;
- (void)downloadUpdated:(CraDownloadInfo*)download;
- (CefRefPtr<CefBrowser>)cefBrowser;
- (CefRefPtr<CefClient>)cefClient;
- (void)createNow;
- (CefRefPtr<CefRequestContext>)requestContext;
- (void)hostWindowCreated:(NSWindow*)window;
- (void)hostPopupBrowserView:(CefRefPtr<CefBrowserView>)view;
@property (nonatomic, strong, nullable) NSWindow* hostWindow;
/// The page's background as last reported by kBackgroundProbe (ARGB, white until then).
@property (nonatomic) cef_color_t pageBackgroundColor;
@end

// MARK: - CEF app

// Browsers Chromium creates through its own UI rather than through Cra: an
// extension's chrome.tabs.create / chrome.windows.create, or the welcome page an
// extension opens once it is installed. CEF gives them GetDefaultClient(); without
// one they appear in a stock Chrome window with a tab strip. Cra takes the URL as
// one of its own tabs and closes Chrome's browser before it is shown.
//
// Popup-type windows (windows.create({type: "popup"}): 1Password's detached window,
// sign-in and approval windows) stay what the extension asked for, like Arc's
// BrowserType.popup: the extension keeps its window id, can resize or close it and
// checks windows.getCurrent().type. Chrome gives tabbed windows a full-size content
// view under a transparent title bar (BrowserNativeWidgetMac::PopulateCreateWindowParams)
// and popups a plain titled window, which is how they are told apart here.
static NSHashTable<NSWindow*>* g_extensionWindows = nil;

class StrayBrowserClient : public CefClient, public CefLifeSpanHandler, public CefRequestHandler {
public:
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override { windows_.erase(browser->GetIdentifier()); }

    void CloseWindows() {
        for (auto& entry : windows_) entry.second->GetHost()->CloseBrowser(true);
    }

    bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request,
                        bool user_gesture, bool is_redirect) override {
        if (!g_strayPageHandler || !frame->IsMain() || windows_.count(browser->GetIdentifier())) return false;
        // Chrome's window exists by the first navigation (not yet in OnAfterCreated).
        NSWindow* window = ((__bridge NSView*)browser->GetHost()->GetWindowHandle()).window;
        if (window && !(window.styleMask & NSWindowStyleMaskFullSizeContentView)) {
            windows_[browser->GetIdentifier()] = browser;
            if (!g_extensionWindows) g_extensionWindows = [NSHashTable weakObjectsHashTable];
            [g_extensionWindows addObject:window];
            return false;
        }
        [window orderOut:nil];
        NSString* url = NSStringFromCef(request->GetURL());
        if (url.length == 0 || [url isEqualToString:@"about:blank"]) return false;
        // Chrome's own empty tab (the window it opens to show "extension added" after a
        // Web Store install): nobody asked for it, so it is closed, not turned into a tab.
        if ([url hasPrefix:@"chrome://newtab"] || [url hasPrefix:@"chrome://new-tab-page"]) {
            browser->GetHost()->CloseBrowser(true);
            return true;
        }
        void (^handler)(NSString*) = g_strayPageHandler;
        dispatch_async(dispatch_get_main_queue(), ^{ handler(url); });
        browser->GetHost()->CloseBrowser(true);
        return true;
    }

private:
    std::map<int, CefRefPtr<CefBrowser>> windows_;
    IMPLEMENT_REFCOUNTING(StrayBrowserClient);
};
static CefRefPtr<StrayBrowserClient> g_strayClient;

// MARK: - Browser-level DevTools pipe

// With --remote-debugging-pipe Chromium reads protocol messages from fd 3 and
// writes replies to fd 4, NUL-terminated. CEF runs the browser in this process,
// so Cra holds the other ends: a trusted client with no port open to anyone else.
static int g_cdpWriteFD = -1;
static dispatch_source_t g_cdpReadSource;
static NSMutableData* g_cdpBuffer;
static NSMutableDictionary<NSNumber*, void (^)(NSString*, NSString*)>* g_cdpPending;
static int g_cdpNextID;
static void (^g_cdpEventHandler)(NSString*, NSString*, NSString*);

static NSString* CraJSONString(id object) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:object ?: @{} options:0 error:nil]
                                 encoding:NSUTF8StringEncoding];
}

static void CraCDPPipeDeliver(NSData* chunk) {
    NSDictionary* msg = [NSJSONSerialization JSONObjectWithData:chunk options:0 error:nil];
    NSNumber* key = [msg[@"id"] isKindOfClass:NSNumber.class] ? msg[@"id"] : nil;
    if (!key) {
        if (g_cdpEventHandler && [msg[@"method"] isKindOfClass:NSString.class])
            g_cdpEventHandler(msg[@"method"], CraJSONString(msg[@"params"]), msg[@"sessionId"]);
        return;
    }
    void (^done)(NSString*, NSString*) = g_cdpPending[key];
    [g_cdpPending removeObjectForKey:key];
    if (!done) return;
    NSString* json = CraJSONString(msg[@"error"] ?: msg[@"result"]);
    msg[@"error"] ? done(nil, json) : done(json, nil);
}

/// Creates the pipe pair on fds 3/4. NO (and no pipe) when either fd is already in use.
static bool CraCDPPipeSetUp() {
    if (g_cdpWriteFD >= 0) return true;
    if (fcntl(3, F_GETFD) != -1 || fcntl(4, F_GETFD) != -1) return false;
    int toChrome[2], fromChrome[2];
    if (pipe(toChrome) != 0) return false;
    if (pipe(fromChrome) != 0) { close(toChrome[0]); close(toChrome[1]); return false; }
    // Park every end above 10 first: pipe() itself may have handed out 3 or 4.
    int ourWrite = fcntl(toChrome[1], F_DUPFD_CLOEXEC, 10), ourRead = fcntl(fromChrome[0], F_DUPFD_CLOEXEC, 10);
    int chromeRead = fcntl(toChrome[0], F_DUPFD, 10), chromeWrite = fcntl(fromChrome[1], F_DUPFD, 10);
    for (int fd : {toChrome[0], toChrome[1], fromChrome[0], fromChrome[1]}) close(fd);
    dup2(chromeRead, 3);
    dup2(chromeWrite, 4);
    close(chromeRead);
    close(chromeWrite);
    g_cdpWriteFD = ourWrite;
    g_cdpBuffer = [NSMutableData data];
    g_cdpPending = [NSMutableDictionary dictionary];
    g_cdpReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, ourRead, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(g_cdpReadSource, ^{
        char buf[65536];
        ssize_t n = read(ourRead, buf, sizeof buf);
        if (n <= 0) { dispatch_source_cancel(g_cdpReadSource); return; }
        [g_cdpBuffer appendBytes:buf length:(NSUInteger)n];
        for (;;) {
            NSRange nul = [g_cdpBuffer rangeOfData:[NSData dataWithBytes:"" length:1] options:0
                                             range:NSMakeRange(0, g_cdpBuffer.length)];
            if (nul.location == NSNotFound) break;
            CraCDPPipeDeliver([g_cdpBuffer subdataWithRange:NSMakeRange(0, nul.location)]);
            [g_cdpBuffer replaceBytesInRange:NSMakeRange(0, nul.location + 1) withBytes:NULL length:0];
        }
    });
    dispatch_resume(g_cdpReadSource);
    return true;
}

// Chrome keeps running while a --remote-debugging-pipe client is attached, so
// CefQuitMessageLoop alone never returns from the run loop (Cmd-Q hung). Hanging
// up the pipe lets Chrome shut down; it exits cleanly ("exit_type": "Normal").
static void CraQuitMessageLoop() {
    if (g_cdpWriteFD >= 0) {
        close(g_cdpWriteFD);
        g_cdpWriteFD = -1;
    }
    CefQuitMessageLoop();
}

// AuthServerAllowlist as an MDM sets it for Chrome or Edge (e.g. "*.example.com").
// CRA_AUTH_SERVER_ALLOWLIST overrides it for machines without such a profile.
static NSString* ManagedAuthServerAllowlist() {
    NSString* env = NSProcessInfo.processInfo.environment[@"CRA_AUTH_SERVER_ALLOWLIST"];
    if (env.length) return env;
    for (NSString* domain in @[@"com.google.Chrome", @"com.microsoft.Edge"]) {
        for (NSString* key in @[@"AuthServerAllowlist", @"AuthServerWhitelist"]) {
            id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                                   (__bridge CFStringRef)domain));
            if ([value isKindOfClass:NSString.class] && [value length]) return value;
        }
    }
    return nil;
}

/// Before any page loads: with mDNS off, the default policy would hand pages
/// the real local IP. Pages get the public address STUN reports and nothing else.
static void ApplyWebRTCPolicy(CefRefPtr<CefRequestContext> context) {
    CefRefPtr<CefValue> policy = CefValue::Create();
    policy->SetString("default_public_interface_only");
    CefString error;
    if (!context->SetPreference("webrtc.ip_handling_policy", policy, error)) {
        NSLog(@"CraCEF: webrtc.ip_handling_policy: %s", error.ToString().c_str());
    }
}

/// Cra shows downloads itself, the way Arc does (ADK hands Arc the download and Arc's own UI
/// shows it; Chrome's toolbar UI never appears). Chrome's download bubble ("Recent download
/// history") still pops up when a download finishes: with no toolbar to anchor to it is an
/// invisible window over the page that swallows the next click. This is Chrome's "Show
/// downloads when they're done" setting.
static void HideDownloadBubble(CefRefPtr<CefRequestContext> context) {
    CefRefPtr<CefValue> off = CefValue::Create();
    off->SetBool(false);
    CefString error;
    if (!context->SetPreference("download_bubble.partial_view_enabled", off, error)) {
        NSLog(@"CraCEF: download_bubble.partial_view_enabled: %s", error.ToString().c_str());
    }
}

static bool g_httpsOnly = false;
static bool g_incognitoReady = false;

/// Chrome's "Always use secure connections" (Settings ▸ Privacy in Cra).
static void ApplyHttpsOnly(CefRefPtr<CefRequestContext> context) {
    CefRefPtr<CefValue> value = CefValue::Create();
    value->SetBool(g_httpsOnly);
    CefString error;
    if (!context->SetPreference("https_only_mode_enabled", value, error)) {
        NSLog(@"CraCEF: https_only_mode_enabled: %s", error.ToString().c_str());
    }
}

static void ApplyProfilePreferences(CefRefPtr<CefRequestContext> context) {
    ApplyWebRTCPolicy(context);
    HideDownloadBubble(context);
    ApplyHttpsOnly(context);
}

/// Profiles other than the global Default one get the same preferences once they load,
/// then create the browsers that waited for them.
class ProfileContextHandler : public CefRequestContextHandler {
public:
    explicit ProfileContextHandler(NSString* path = nil) : path_([path copy]) {}
    void OnRequestContextInitialized(CefRefPtr<CefRequestContext> context) override {
        ApplyProfilePreferences(context);
        if (!path_) { g_incognitoReady = true; return; }
        if (!g_readyProfiles) g_readyProfiles = [NSMutableSet set];
        [g_readyProfiles addObject:path_];
        NSArray<CraBrowser*>* waiting = [g_waitingForProfile[path_] copy];
        [g_waitingForProfile removeObjectForKey:path_];
        for (CraBrowser* b in waiting) [b createNow];
    }
private:
    NSString* path_;
    IMPLEMENT_REFCOUNTING(ProfileContextHandler);
};

/// Incognito windows share one off-the-record profile (an empty cache path keeps
/// cookies, storage and cache in memory) until the last of them closes.
static CefRefPtr<CefRequestContext> IncognitoContext() {
    if (!g_incognitoContext) g_incognitoContext = CefRequestContext::CreateContext(CefRequestContextSettings(), new ProfileContextHandler());
    return g_incognitoContext;
}

/// A space's own profile: cookies, logins, storage and cache in a folder next to
/// Default (it must sit under root_cache_path). nil is the global Default profile.
static CefRefPtr<CefRequestContext> ProfileContext(NSString* path) {
    if (!path.length) return nullptr;
    std::string key = path.UTF8String;
    auto it = g_profileContexts.find(key);
    if (it != g_profileContexts.end()) return it->second;
    CefRequestContextSettings settings;
    CefString(&settings.cache_path) = CefStringFromNS(path);
    settings.persist_session_cookies = true;
    CefRefPtr<CefRequestContext> context = CefRequestContext::CreateContext(settings, new ProfileContextHandler(path));
    g_profileContexts[key] = context;
    return context;
}

/// Loads the profile if needed. NO means `browser` waits and is created once it has loaded.
static BOOL ProfileReady(NSString* path, CraBrowser* browser) {
    if (!path.length) return YES;
    ProfileContext(path);
    if ([g_readyProfiles containsObject:path]) return YES;
    if (!g_waitingForProfile) g_waitingForProfile = [NSMutableDictionary dictionary];
    if (!g_waitingForProfile[path]) g_waitingForProfile[path] = [NSMutableArray array];
    if (![g_waitingForProfile[path] containsObject:browser]) [g_waitingForProfile[path] addObject:browser];
    return NO;
}

class CraApp : public CefApp, public CefBrowserProcessHandler {
public:
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

    CefRefPtr<CefClient> GetDefaultClient() override {
        if (!g_strayClient) g_strayClient = new StrayBrowserClient();
        return g_strayClient;
    }

    void OnBeforeCommandLineProcessing(const CefString& process_type,
                                       CefRefPtr<CefCommandLine> command_line) override {
        if (!process_type.empty()) return;
        // Cookies and passwords are encrypted with the secret in the "Cra Safe Storage"
        // Keychain item (SafeStorage.swift). Only unsigned dev builds on a profile that
        // never used it keep the mock keychain, whose secret is a public constant: the
        // Keychain would ask for the login password after every rebuild.
        if (g_useMockKeychain) command_line->AppendSwitch("use-mock-keychain");
        // Chrome-style windows are ours; Chrome must not restore or reopen them.
        command_line->AppendSwitch("no-startup-window");
        command_line->AppendSwitch("disable-session-crashed-bubble");
        command_line->AppendSwitch("hide-crash-restore-bubble");
        command_line->AppendSwitch("no-first-run");
        // Unpacked Chrome extensions (Chrome-style browsers only): one folder per extension.
        if (process_type.empty()) {
            // Use the same resolved data root as AppPaths/ExtensionStore, never an
            // independent production fallback when CraDev is opened from Finder.
            NSString* dir = g_extensionsDirectory;
            NSMutableArray<NSString*>* paths = [NSMutableArray array];
            for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
                NSString* p = [dir stringByAppendingPathComponent:name];
                if ([[NSFileManager defaultManager] fileExistsAtPath:[p stringByAppendingPathComponent:@"manifest.json"]]) [paths addObject:p];
            }
            if (paths.count) command_line->AppendSwitchWithValue("load-extension", CefStringFromNS([paths componentsJoinedByString:@","]));
        }
        command_line->AppendSwitchWithValue("autoplay-policy", "document-user-activation-required");
        // WebRTC hides this Mac's local IP behind a random .local name announced over
        // mDNS, and macOS asks for Local Network access the first time any page (an
        // ad script will do) opens a peer connection. Cra offers no local address at
        // all instead (webrtc.ip_handling_policy, set in OnContextInitialized), so
        // there is nothing to announce and the mDNS responder can stay off.
        std::string disabled = command_line->GetSwitchValue("disable-features");
        command_line->AppendSwitchWithValue("disable-features",
            (disabled.empty() ? "" : disabled + ",") + "WebRtcHideLocalIpsWithMdns");
        // Kerberos/NTLM single sign-on (ADFS /adfs/ls/wia and the like). Chromium only sends
        // the OS ticket to allowlisted hosts, and IT sets that list as a Chrome or Edge policy,
        // which CEF never reads. Without it those logins fail with ERR_INVALID_AUTH_CREDENTIALS.
        if (NSString* allowlist = ManagedAuthServerAllowlist()) {
            command_line->AppendSwitchWithValue("auth-server-allowlist", CefStringFromNS(allowlist));
        }
        // Browser-level DevTools protocol over a private pipe (fd 3/4, no port): the trusted
        // client Chrome requires for Extensions.triggerAction (toolbar extension buttons).
        if (CraCDPPipeSetUp()) {
            command_line->AppendSwitch("remote-debugging-pipe");
            command_line->AppendSwitch("enable-unsafe-extension-debugging");
        }
    }

    // Chromium copies --remote-debugging-pipe to renderers, where it turns on
    // navigator.webdriver ("automation controlled"). Google sign-in then refuses
    // with "This browser or app may not be secure". The copy happens after this
    // hook, so removing the switch here does nothing; switch the feature off.
    void OnBeforeChildProcessLaunch(CefRefPtr<CefCommandLine> command_line) override {
        if (command_line->GetSwitchValue("type") == "renderer") {
            command_line->AppendSwitchWithValue("disable-blink-features", "AutomationControlled");
        }
    }

    // Another Cra process started (LaunchServices, `open -n`). Chromium's
    // process singleton hands its command line to us. Without this CEF opens
    // a stock Chrome-style window.
    bool OnAlreadyRunningAppRelaunch(CefRefPtr<CefCommandLine> command_line,
                                     const CefString& current_directory) override {
        CEF_REQUIRE_UI_THREAD();
        std::vector<CefString> args;
        command_line->GetArguments(args);
        NSMutableArray<NSString*>* urls = [NSMutableArray array];
        for (const auto& a : args) {
            NSString* str = NSStringFromCef(a);
            if ([str hasPrefix:@"http://"] || [str hasPrefix:@"https://"] || [str hasPrefix:@"cra://"] || [str hasPrefix:@"file://"]) {
                [urls addObject:str];
            }
        }
        if (g_relaunchHandler) g_relaunchHandler(urls);
        return true;
    }

    void OnContextInitialized() override {
        CEF_REQUIRE_UI_THREAD();
        ApplyProfilePreferences(CefRequestContext::GetGlobalContext());
        g_contextInitialized = true;
        NSArray<CraBrowser*>* pending = [g_pendingCreation copy];
        [g_pendingCreation removeAllObjects];
        for (CraBrowser* b in pending) {
            [b createNow];
        }
    }

private:
    IMPLEMENT_REFCOUNTING(CraApp);
};

// MARK: - Favicon download

class FaviconCallback : public CefDownloadImageCallback {
public:
    explicit FaviconCallback(CraBrowser* owner) : owner_(owner) {}

    void OnDownloadImageFinished(const CefString& image_url, int http_status_code,
                                 CefRefPtr<CefImage> image) override {
        CraBrowser* owner = owner_;
        if (!owner || !image || image->IsEmpty()) return;
        int w = 0, h = 0;
        CefRefPtr<CefBinaryValue> png = image->GetAsPNG(2.0f, true, w, h);
        if (!png || png->GetSize() == 0) png = image->GetAsPNG(1.0f, true, w, h);
        if (!png || png->GetSize() == 0) return;
        size_t n = png->GetSize();
        std::vector<uint8_t> bytes(n);
        png->GetData(bytes.data(), n, 0);
        NSData* data = [NSData dataWithBytes:bytes.data() length:n];
        NSImage* img = [[NSImage alloc] initWithData:data];
        if (!img) return;
        [owner.delegate browser:owner didLoadFavicon:img forURL:NSStringFromCef(image_url)];
    }

private:
    __weak CraBrowser* owner_;
    IMPLEMENT_REFCOUNTING(FaviconCallback);
};

// MARK: - Browser fetch

typedef void (^CraFetchCompletion)(NSInteger, NSString*, NSString*, NSString*);

/// Collects a CefURLRequest's body. Requests made on the UI thread call back on it.
class FetchClient : public CefURLRequestClient {
public:
    explicit FetchClient(CraFetchCompletion completion) : completion_([completion copy]) {}

    void OnDownloadData(CefRefPtr<CefURLRequest> request, const void* data, size_t length) override {
        body_.append(static_cast<const char*>(data), length);
    }
    void OnRequestComplete(CefRefPtr<CefURLRequest> request) override {
        CefRefPtr<CefResponse> response = request->GetResponse();
        bool ok = request->GetRequestStatus() == UR_SUCCESS && response;
        NSInteger status = ok ? response->GetStatus() : 0;
        NSString* finalURL = response ? NSStringFromCef(response->GetURL()) : @"";
        if (!finalURL.length) finalURL = NSStringFromCef(request->GetRequest()->GetURL());
        NSString* mime = response ? NSStringFromCef(response->GetMimeType()) : @"";
        NSString* body = [[NSString alloc] initWithBytes:body_.data() length:body_.size() encoding:NSUTF8StringEncoding] ?: @"";
        CraFetchCompletion done = completion_;
        completion_ = nil;
        CefRefPtr<CefURLRequest> finished = request;
        dispatch_async(dispatch_get_main_queue(), ^{
            InFlight().erase(finished);
            if (done) done(status, finalURL, mime, body);
        });
    }
    /// Requests stay referenced until they complete.
    static std::set<CefRefPtr<CefURLRequest>>& InFlight() { static std::set<CefRefPtr<CefURLRequest>> s; return s; }
    void OnUploadProgress(CefRefPtr<CefURLRequest> request, int64_t current, int64_t total) override {}
    void OnDownloadProgress(CefRefPtr<CefURLRequest> request, int64_t current, int64_t total) override {}
    bool GetAuthCredentials(bool isProxy, const CefString& host, int port, const CefString& realm, const CefString& scheme,
                            CefRefPtr<CefAuthCallback> callback) override { return false; }

private:
    CraFetchCompletion completion_;
    std::string body_;
    IMPLEMENT_REFCOUNTING(FetchClient);
};

// MARK: - DevTools client

// Diagnostic log for the DevTools life cycle: `defaults write dk.kildahl.cra devToolsLog -bool YES`,
// then read $TMPDIR/cra-devtools.log.
static void CraDevToolsLog(NSString* fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void CraDevToolsLog(NSString* fmt, ...) {
    static BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"devToolsLog"];
    if (!enabled) return;
    va_list ap;
    va_start(ap, fmt);
    NSString* s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cra-devtools.log"];
    NSString* line = [NSString stringWithFormat:@"%.3f %@\n", [NSDate date].timeIntervalSince1970, s];
    FILE* f = fopen(path.fileSystemRepresentation, "a");
    if (f) { fputs(line.UTF8String, f); fclose(f); }
}

// Chrome's DevTools the way Arc (plain Chromium) shows it: the frontend runs with
// can_dock=true, draws the dock/page split and the device toolbar itself, and tells
// the embedder where the page goes (InspectorFrontendHost.setInspectedPageBounds).
// CEF opens Chrome-style DevTools as an undockable popup, so the popup is reloaded
// once with can_dock=true and the frontend's embedder calls are mirrored to the
// shell as console messages; the shell then lays the page window over the
// placeholder exactly like Chrome's BrowserView does.
static const char kCraDevToolsHooks[] =
    "(function(){var h=window.InspectorFrontendHost;if(!h||h.__cra)return;h.__cra=1;"
    "function find(root,sel){var r=root.querySelector(sel);if(r)return r;var all=root.querySelectorAll('*');"
    "for(var i=0;i<all.length;i++){if(all[i].shadowRoot){var f=find(all[i].shadowRoot,sel);if(f)return f;}}return null;}"
    "function make(){var b=document.createElement('button');b.id='cra-close';b.title='Close DevTools';b.setAttribute('aria-label','Close DevTools');"
    "b.style.cssText='all:unset;box-sizing:border-box;cursor:pointer;width:26px;height:26px;margin:0 2px;display:inline-flex;align-items:center;justify-content:center;border-radius:4px;color:var(--icon-default,#9aa0a6)';"
    "b.innerHTML='<svg width=\"14\" height=\"14\" viewBox=\"0 0 14 14\"><path d=\"M2 2l10 10M12 2L2 12\" stroke=\"currentColor\" stroke-width=\"1.6\" stroke-linecap=\"round\" fill=\"none\"/></svg>';"
    "b.onmouseenter=function(){b.style.background='var(--sys-color-state-hover-on-subtle,rgba(128,128,128,.25))';};"
    "b.onmouseleave=function(){b.style.background='';};b.onclick=function(){console.log('__cra_devtools_close');};return b;}"
    "var timer=null;"
    "function installClose(){if(timer)return;var n=0;timer=setInterval(function(){"
    "if(find(document,'#cra-close')){clearInterval(timer);timer=null;return;}"
    "var bar=find(document,'.tabbed-pane-right-toolbar');"
    "if(bar&&bar.parentNode){var b=make();b.style.alignSelf='center';b.style.margin='0 4px 0 2px';b.style.order='9999';bar.parentNode.appendChild(b);clearInterval(timer);timer=null;return;}"
    "if(++n>60){clearInterval(timer);timer=null;var f=make();f.style.position='fixed';f.style.top='1px';f.style.right='4px';f.style.zIndex='2147483647';document.body.appendChild(f);}},150);}"
    "function removeClose(){if(timer){clearInterval(timer);timer=null;}var b=find(document,'#cra-close');if(b)b.remove();}"
    "h.closeWindow=function(){console.log('__cra_devtools_close');};"
    "if(!/[?&]can_dock=/.test(location.search)){installClose();return;}"
    "var sent=false;"
    "h.setInspectedPageBounds=function(b){sent=true;try{console.log('__cra_devtools_bounds:'+JSON.stringify({x:b.x,y:b.y,width:b.width,height:b.height}));}catch(e){}};"
    // Chrome never hears about docking: the shell owns the layout. The frontend only
    // needs its acknowledgement (DockController waits for it before relayout). Docked, the
    // frontend shows its own close button; undocked, the window's title bar has one.
    "h.setIsDocked=function(d,cb){console.log('__cra_devtools_docked:'+(d?1:0));removeClose();"
    "if(cb)setTimeout(function(){cb();},0);};"
    // Docked frontends re-send the placeholder on resize; an undocked one stays silent.
    "window.dispatchEvent(new Event('resize'));"
    "requestAnimationFrame(function(){requestAnimationFrame(function(){setTimeout(function(){if(!sent)console.log('__cra_devtools_docked:0');},80);});});"
    "})();";

class DevToolsClient : public CefClient, public CefLifeSpanHandler, public CefLoadHandler, public CefDisplayHandler,
                       public CefRequestHandler {
public:
    DevToolsClient(NSRect frame, CraBrowser* owner, NSView* host) : frame_(frame), owner_(owner), host_(host) {}
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }

    bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request,
                        bool user_gesture, bool is_redirect) override {
        if (frame->IsMain()) CraDevToolsLog(@"OnBeforeBrowse %s", request->GetURL().ToString().c_str());
        return false;
    }
    // The frontend's own helper pages (device_mode_emulation_frame.html when undocked)
    // would become stray CEF windows; Chrome never shows them either.
    bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int popup_id,
                       const CefString& target_url, const CefString& target_frame_name,
                       WindowOpenDisposition target_disposition, bool user_gesture,
                       const CefPopupFeatures& popupFeatures, CefWindowInfo& windowInfo,
                       CefRefPtr<CefClient>& client, CefBrowserSettings& settings,
                       CefRefPtr<CefDictionaryValue>& extra_info, bool* no_javascript_access) override {
        std::string url = target_url.ToString();
        CraDevToolsLog(@"DevTools popup %s", url.c_str());
        if (url.rfind("devtools://", 0) == 0 || url.empty() || url == "about:blank") return true;
        if (CraBrowser* o = owner_) [o.delegate browser:o requestsNewTabWithURL:[NSString stringWithUTF8String:url.c_str()] inBackground:NO];
        return true;
    }
    void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType transition_type) override {
        if (frame->IsMain()) CraDevToolsLog(@"OnLoadStart %s", frame->GetURL().ToString().c_str());
    }
    void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int httpStatusCode) override {
        if (!frame->IsMain()) return;
        CraDevToolsLog(@"OnLoadEnd %s", frame->GetURL().ToString().c_str());
        if (host_) Prepare(browser, frame);
    }

    // Docked mode: make a Chrome-style frontend dockable (one reload), then hook it.
    // Alloy frontends (can_dock=false, no close button) only get the close button.
    void Prepare(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame) {
        std::string url = frame->GetURL().ToString();
        if (url.rfind("devtools://", 0) != 0) return;
        // Only the main frontend; helper pages it opens (device_mode_emulation_frame.html
        // when undocked) must not report dock state or page bounds.
        if (url.find("/devtools_app.html") == std::string::npos && url.find("/inspector.html") == std::string::npos) return;
        if (browser->GetHost()->HasView() && url.find("can_dock=") == std::string::npos && !reloaded_) {
            reloaded_ = true;
            std::string docked = url + (url.find('?') == std::string::npos ? "?" : "&") + "can_dock=true";
            CraDevToolsLog(@"reloading as dockable: %s", docked.c_str());
            frame->LoadURL(docked);
            return;
        }
        frame->ExecuteJavaScript(kCraDevToolsHooks, frame->GetURL(), 0);
    }

    bool OnConsoleMessage(CefRefPtr<CefBrowser> browser, cef_log_severity_t level, const CefString& message,
                          const CefString& source, int line) override {
        static const std::string kClose = "__cra_devtools_close";
        static const std::string kBounds = "__cra_devtools_bounds:";
        static const std::string kDocked = "__cra_devtools_docked:";
        std::string m = message.ToString();
        if (m == kClose) {
            if (CraBrowser* o = owner_) [o closeDevTools];
            return true;
        }
        if (m.rfind(kBounds, 0) == 0) {
            NSData* data = [[NSString stringWithUTF8String:m.c_str() + kBounds.size()] dataUsingEncoding:NSUTF8StringEncoding];
            id d = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if ([d isKindOfClass:[NSDictionary class]]) {
                NSRect r = NSMakeRect([d[@"x"] doubleValue], [d[@"y"] doubleValue], [d[@"width"] doubleValue], [d[@"height"] doubleValue]);
                CraDevToolsLog(@"bounds %@", NSStringFromRect(r));
                if (CraBrowser* o = owner_) [o.delegate browser:o devToolsPageBounds:r];
            }
            return true;
        }
        if (m.rfind("__cra_dbg:", 0) == 0) { CraDevToolsLog(@"%s", m.c_str()); return true; }
        if (m.rfind(kDocked, 0) == 0) {
            BOOL docked = m.size() > kDocked.size() && m[kDocked.size()] == '1';
            CraDevToolsLog(@"docked=%d", docked);
            if (CraBrowser* o = owner_) [o.delegate browser:o devToolsDocked:docked];
            return true;
        }
        return false;
    }
    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        g_liveBrowsers++;
        if (CraBrowser* o = owner_) [o devToolsBrowserCreated:browser];
        NSView* view = (__bridge NSView*)browser->GetHost()->GetWindowHandle();
        if (host_) {
            if (browser->GetHost()->HasView()) {
                // Chrome-style (Views) DevTools: CraDevToolsWindowDelegate reports the
                // window once it exists. The frontend may already be loaded by now.
                CefRefPtr<CefFrame> main = browser->GetMainFrame();
                CraDevToolsLog(@"OnAfterCreated (Views) url=%s loading=%d", main ? main->GetURL().ToString().c_str() : "",
                               browser->IsLoading());
                if (main && !browser->IsLoading()) Prepare(browser, main);
                return;
            }
            // Alloy: CEF owns a hidden window; the shell attaches it as a child window
            // over the dock area. (A child *browser* for DevTools trips a CHECK in CEF
            // 154, and re-parenting the view is unsafe because CEF closes `view.window`
            // when DevTools closes.)
            if (CraBrowser* o = owner_) [o.delegate browser:o didCreateDevToolsView:view];
            return;
        }
        // CEF sizes its own DevTools window with a default; put it where we want it.
        NSWindow* w = view.window;
        if (w && frame_.size.width > 0) {
            [w setFrame:frame_ display:YES];
            [w makeKeyAndOrderFront:nil];
        }
    }
    bool DoClose(CefRefPtr<CefBrowser> browser) override { return false; }
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        g_liveBrowsers--;
        CraDevToolsLog(@"OnBeforeClose");
        if (CraBrowser* o = owner_) { [o devToolsBrowserClosed]; [o.delegate browserDidCloseDevTools:o]; }
        if (g_quitting && g_liveBrowsers <= 0) CraQuitMessageLoop();
    }
private:
    NSRect frame_;
    __weak CraBrowser* owner_;
    NSView* host_;
    bool reloaded_ = false;
    IMPLEMENT_REFCOUNTING(DevToolsClient);
};

// "rgb(r, g, b)" / "rgba(r, g, b, a)" from getComputedStyle as "#RRGGBB"; "" when
// unparsable or mostly transparent.
static NSString* HexFromCSSColor(const std::string& css) {
    int r = 0, g = 0, b = 0; float a = 1;
    if (sscanf(css.c_str(), "rgba(%d, %d, %d, %f)", &r, &g, &b, &a) == 4 || sscanf(css.c_str(), "rgb(%d, %d, %d)", &r, &g, &b) == 3) {
        if (a > 0.5f) return [NSString stringWithFormat:@"#%02X%02X%02X", r, g, b];
    }
    return @"";
}

// What the page paints behind its content: the root's background, else the body's
// (CSS propagates it to the canvas), else the canvas colour of the page's color
// scheme. Answers through OnConsoleMessage ("__cra_bg:"); installed once per
// document, re-run on load, after late stylesheets and when the OS appearance flips.
static const char kBackgroundProbe[] =
    "(function(){if(!window.__craBg){window.__craBg=function(){try{"
    "var bg=function(e){var c=e?getComputedStyle(e).backgroundColor:'';return c&&c!=='transparent'&&c!=='rgba(0, 0, 0, 0)'?c:'';};"
    "var c=bg(document.documentElement)||bg(document.body);"
    "if(!c){var d=document.createElement('div');d.style.color='Canvas';document.documentElement.appendChild(d);c=getComputedStyle(d).color;d.remove();}"
    "console.log('__cra_bg:'+c);}catch(e){}};"
    "matchMedia('(prefers-color-scheme: dark)').addEventListener('change',function(){setTimeout(window.__craBg,50);});"
    "setTimeout(window.__craBg,1500);}"
    "window.__craBg();})();";

// MARK: - Content blocking and app links

// Cancels third-party requests to listed ad and tracker domains (CraContentBlocker.h).
// Runs on the IO thread; stateless, the list and the switch are global atomics.
//
// Also lets links with a scheme Chromium can't load (macappstore:, mailto:, zoommtg:,
// slack:, …) reach the app registered for it. CEF only asks a resource request handler,
// so without this every such link failed with ERR_UNKNOWN_URL_SCHEME. Allowing it hands
// the link to Chrome's ExternalProtocolHandler, which blocks dangerous schemes and asks
// "Open <app>?" with "Always allow" like Chrome and Arc.
class CraContentBlockingHandler : public CefResourceRequestHandler {
public:
    ReturnValue OnBeforeResourceLoad(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                                     CefRefPtr<CefRequest> request, CefRefPtr<CefCallback> callback) override {
        if (!cra_blocker::Enabled().load(std::memory_order_relaxed)) return RV_CONTINUE;
        if (!browser || request->GetResourceType() == RT_MAIN_FRAME) return RV_CONTINUE;
        CefRefPtr<CefFrame> top = browser->GetMainFrame();  // the tab's top-level page
        if (!top) return RV_CONTINUE;
        std::string pageHost = cra_blocker::WebHost(top->GetURL().ToString());
        std::string requestHost = cra_blocker::WebHost(request->GetURL().ToString());
        return cra_blocker::ShouldBlock(requestHost, pageHost) ? RV_CANCEL : RV_CONTINUE;
    }

    void OnProtocolExecution(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request,
                             bool& allow_os_execution) override {
        // cra:// is Cra's own scripting scheme; a page must not drive it.
        std::string url = request->GetURL().ToString();
        allow_os_execution = url.compare(0, 4, "cra:") != 0;
    }

private:
    IMPLEMENT_REFCOUNTING(CraContentBlockingHandler);
};

// MARK: - Browser client

class CraClient : public CefClient,
                  public CefLifeSpanHandler,
                  public CefLoadHandler,
                  public CefDisplayHandler,
                  public CefRequestHandler,
                  public CefContextMenuHandler,
                  public CefKeyboardHandler,
                  public CefDownloadHandler,
                  public CefFocusHandler,
                  public CefPermissionHandler,
                  public CefFindHandler {
public:
    CraBrowser* owner() { return owner_; }
    explicit CraClient(CraBrowser* owner) : owner_(owner) { CraClientRegistry().insert(static_cast<const void*>(static_cast<CefClient*>(this))); }
    ~CraClient() override { CraClientRegistry().erase(static_cast<const void*>(static_cast<CefClient*>(this))); }

    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
    CefRefPtr<CefFocusHandler> GetFocusHandler() override { return this; }
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
    CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }

    // Life span -----------------------------------------------------------

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        g_liveBrowsers++;
        if (CraBrowser* o = owner_) [o adoptBrowser:browser];
    }

    bool DoClose(CefRefPtr<CefBrowser> browser) override { return false; }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        CEF_REQUIRE_UI_THREAD();
        g_liveBrowsers--;
        if (CraBrowser* o = owner_) [o browserClosed];
        if (g_quitting && g_liveBrowsers <= 0) CraQuitMessageLoop();
    }

    void OnBeforeDevToolsPopup(CefRefPtr<CefBrowser> browser, CefWindowInfo& windowInfo, CefRefPtr<CefClient>& client,
                               CefBrowserSettings& settings, CefRefPtr<CefDictionaryValue>& extra_info,
                               bool* use_default_window) override {
        CraBrowser* o = owner_;
        if (!o) return;
        client = new DevToolsClient(NSZeroRect, o, o.containerView);
        *use_default_window = false;
    }

    bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int popup_id,
                       const CefString& target_url, const CefString& target_frame_name,
                       WindowOpenDisposition target_disposition, bool user_gesture,
                       const CefPopupFeatures& popupFeatures, CefWindowInfo& windowInfo,
                       CefRefPtr<CefClient>& client, CefBrowserSettings& settings,
                       CefRefPtr<CefDictionaryValue>& extra_info, bool* no_javascript_access) override {
        CEF_REQUIRE_UI_THREAD();
        CraBrowser* o = owner_;
        if (!o || !o.delegate) return true;
        BOOL background = (target_disposition == CEF_WOD_NEW_BACKGROUND_TAB);
        CraBrowser* host = [o.delegate browser:o popupHostForURL:NSStringFromCef(target_url) inBackground:background];
        if (!host) return true;  // blocked
        client = [host cefClient];
        if (g_chromeHosting) return false;  // Views path: CraChromeViewDelegate hosts the popup view
        NSView* view = host.containerView;
        NSRect b = view.bounds;
        windowInfo.SetAsChild((__bridge void*)view, CefRect(0, 0, (int)b.size.width, (int)b.size.height));
        if (g_useChromeStyle) windowInfo.runtime_style = CEF_RUNTIME_STYLE_CHROME;
        return false;  // allow, CEF creates it into our view with the opener kept
    }

    // Load ----------------------------------------------------------------

    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading, bool canGoBack,
                              bool canGoForward) override {
        CraBrowser* o = owner_;
        if (!o) return;
        o.isLoading = isLoading;
        o.canGoBack = canGoBack;
        o.canGoForward = canGoForward;
        [o.delegate browser:o didChangeLoading:isLoading canGoBack:canGoBack canGoForward:canGoForward];
    }

    void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType transition_type) override {
        // The last page's colour must not show under the next one while it loads.
        CraBrowser* o = owner_;
        if (!o || !frame->IsMain()) return;
        o.pageBackgroundColor = CefColorSetARGB(255, 255, 255, 255);
        if (CefRefPtr<CefBrowserView> view = CefBrowserView::GetForBrowser(browser)) view->SetBackgroundColor(o.pageBackgroundColor);
    }

    void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int httpStatusCode) override {
        // Every frame reports Picture in Picture changes (the events don't bubble, hence capture).
        frame->ExecuteJavaScript(
            "(function(){if(window.__craPip)return;window.__craPip=1;"
            "var cur=null;function playing(v){console.log('__cra_pip:play'+(v.paused||v.ended?0:1));}"
            "function watch(v){cur=v;playing(v);v.addEventListener('play',function(){if(cur===v)playing(v);});"
            "v.addEventListener('pause',function(){if(cur===v)playing(v);});v.addEventListener('ended',function(){if(cur===v)playing(v);});}"
            "document.addEventListener('enterpictureinpicture',function(e){console.log('__cra_pip:1');watch(e.target);},true);"
            "document.addEventListener('leavepictureinpicture',function(){cur=null;console.log('__cra_pip:0');},true);"
            "if(document.pictureInPictureElement){console.log('__cra_pip:1');watch(document.pictureInPictureElement);}})();",
            frame->GetURL(), 0);
        if (!frame->IsMain()) return;
        CraBrowser* o = owner_;
        if (!o) return;
        [o.delegate browser:o didFinishLoadingURL:NSStringFromCef(frame->GetURL()) title:o.currentTitle
                 statusCode:httpStatusCode];
        // Ask the page for its theme colour; the answer comes back through OnConsoleMessage.
        frame->ExecuteJavaScript(
            "(function(){function probe(){try{var c='';var ms=document.querySelectorAll('meta[name=\"theme-color\"]');"
            "for(var i=0;i<ms.length;i++){if(!ms[i].getAttribute('media')){c=ms[i].getAttribute('content')||'';if(c)break;}}"
            "if(!c&&document.body){var b=getComputedStyle(document.body).backgroundColor;if(b&&b!=='rgba(0, 0, 0, 0)'&&b!=='transparent'){c=b;}}"
            "if(!c){var h=getComputedStyle(document.documentElement).backgroundColor;if(h&&h!=='rgba(0, 0, 0, 0)'&&h!=='transparent'){c=h;}}"
            "if(!c){c='rgb(255, 255, 255)';}"
            "var d=document.createElement('div');d.style.color=c;document.body.appendChild(d);"
            "var rgb=getComputedStyle(d).color;d.remove();console.log('__cra_theme:'+rgb);}catch(e){}}"
            "probe();setTimeout(probe,1500);})();",
            frame->GetURL(), 0);
        frame->ExecuteJavaScript(kBackgroundProbe, frame->GetURL(), 0);
    }

    bool OnConsoleMessage(CefRefPtr<CefBrowser> browser, cef_log_severity_t level, const CefString& message,
                          const CefString& source, int line) override {
        std::string m = message.ToString();
        if (m.compare(0, 10, "__cra_pip:") == 0) {
            CraBrowser* o = owner_;
            if (!o) return true;
            std::string v = m.substr(10);
            if (v == "1" || v == "0") {
                BOOL active = (v == "1");
                if (o.isInPictureInPicture != active) {
                    o.isInPictureInPicture = active;
                    if (!active) o.isPictureInPicturePlaying = NO;
                    if ([o.delegate respondsToSelector:@selector(browser:didChangePictureInPicture:)])
                        [o.delegate browser:o didChangePictureInPicture:active];
                }
            } else if (v == "play1" || v == "play0") {
                BOOL playing = (v == "play1");
                o.isPictureInPicturePlaying = playing;
                if ([o.delegate respondsToSelector:@selector(browser:didChangePictureInPicturePlayback:)])
                    [o.delegate browser:o didChangePictureInPicturePlayback:playing];
            } else if (v.compare(0, 3, "err") == 0) {
                NSLog(@"CraCEF: Picture in Picture %s", v.c_str());
            }
            return true;
        }
        const std::string bgPrefix = "__cra_bg:";
        if (m.compare(0, bgPrefix.size(), bgPrefix) == 0) {
            CraBrowser* o = owner_;
            NSString* hex = HexFromCSSColor(m.substr(bgPrefix.size()));
            if (o && hex.length) {
                // Under the page (CraChromeViewDelegate::OnThemeChanged).
                o.pageBackgroundColor = 0xFF000000 | (cef_color_t)strtoul(hex.UTF8String + 1, nullptr, 16);
                if (CefRefPtr<CefBrowserView> view = CefBrowserView::GetForBrowser(browser))
                    view->SetBackgroundColor(o.pageBackgroundColor);
            }
            if (o && hex.length && [o.delegate respondsToSelector:@selector(browser:didReportBackgroundColor:)])
                [o.delegate browser:o didReportBackgroundColor:hex];
            return true;
        }
        const std::string prefix = "__cra_theme:";
        if (m.compare(0, prefix.size(), prefix) != 0) return false;
        CraBrowser* o = owner_;
        if (!o) return true;
        std::string rgb = m.substr(prefix.size());  // "rgb(r, g, b)", "rgba(…)" or "none"
        NSString* hex = rgb == "none" ? @"none" : HexFromCSSColor(rgb);
        [o.delegate browser:o didReportThemeColor:hex];
        return true;  // keep it out of the console
    }

    void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, ErrorCode errorCode,
                     const CefString& errorText, const CefString& failedUrl) override {
        if ((int)errorCode == -3 /* ERR_ABORTED */ || !frame->IsMain()) return;
        // Chrome-style pages get Chrome's own error page: Reload retries the site and it
        // reloads by itself when the network returns. Ours, a data: URL loaded on top,
        // made Reload reload the error and added a history entry.
        if (browser->GetHost()->GetRuntimeStyle() == CEF_RUNTIME_STYLE_CHROME) return;
        // Chrome fails a navigation that hits an auth challenge with this error, commits a
        // blank page and asks for the password over it. Our page would replace both.
        if ((int)errorCode == -338 /* ERR_INVALID_AUTH_CREDENTIALS */) return;
        std::string url = failedUrl.ToString();
        std::string err = errorText.ToString();
        std::string html =
            "<!doctype html><html><head><meta charset=utf-8><title>Can’t reach this page</title>"
            "<style>html{background:#f5f5f7;color:#1d1d1f;font:15px -apple-system,system-ui}"
            "@media(prefers-color-scheme:dark){html{background:#1c1c1e;color:#f5f5f7}}"
            "body{display:flex;min-height:90vh;align-items:center;justify-content:center;margin:0}"
            "main{max-width:420px;padding:32px}h1{font-size:22px;margin:0 0 8px}p{opacity:.7;margin:0 0 6px}"
            "code{font:13px ui-monospace,Menlo;opacity:.6;word-break:break-all}</style></head><body><main>"
            "<h1>Cra can’t reach this page</h1><p>" + err + " (" + std::to_string((int)errorCode) + ")</p>"
            "<code>" + url + "</code></main></body></html>";
        CefString encoded = CefBase64Encode(html.data(), html.size());
        frame->LoadURL("data:text/html;base64," + encoded.ToString());
    }

    // Display -------------------------------------------------------------

    void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& url) override {
        if (!frame->IsMain()) return;
        CraBrowser* o = owner_;
        if (!o) return;
        o.currentURL = NSStringFromCef(url);
        [o.delegate browser:o didChangeURL:o.currentURL];
    }

    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override {
        CraBrowser* o = owner_;
        if (!o) return;
        o.currentTitle = NSStringFromCef(title);
        [o.delegate browser:o didChangeTitle:o.currentTitle];
    }

    // Arc's recording indicator ("This tab is using your camera or microphone").
    void OnMediaAccessChange(CefRefPtr<CefBrowser> browser, bool has_video_access, bool has_audio_access) override {
        CraBrowser* o = owner_;
        if (!o) return;
        BOOL capturing = has_video_access || has_audio_access;
        if (capturing == o.isCapturingMedia) return;
        o.isCapturingMedia = capturing;
        if ([o.delegate respondsToSelector:@selector(browser:didChangeMediaCapture:)])
            [o.delegate browser:o didChangeMediaCapture:capturing];
    }

    void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString>& icon_urls) override {
        CraBrowser* o = owner_;
        if (!o || icon_urls.empty()) return;
        // Prefer PNG/ICO-looking URLs over SVG, which CEF can't decode.
        CefString chosen = icon_urls.front();
        for (const auto& u : icon_urls) {
            std::string s = u.ToString();
            if (s.find(".svg") == std::string::npos) { chosen = u; break; }
        }
        std::string chosenStr = chosen.ToString();
        if (chosenStr == last_icon_url_) return;
        last_icon_url_ = chosenStr;
        browser->GetHost()->DownloadImage(chosen, true, 64, false, new FaviconCallback(o));
    }

    void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) override {
        if (CraBrowser* o = owner_) [o.delegate browser:o didChangeFullscreen:fullscreen];
    }

    void OnStatusMessage(CefRefPtr<CefBrowser> browser, const CefString& value) override {
        if (CraBrowser* o = owner_) [o.delegate browser:o didChangeStatusMessage:NSStringFromCef(value)];
    }

    // Find ------------------------------------------------------------------

    void OnFindResult(CefRefPtr<CefBrowser> browser, int identifier, int count, const CefRect& selectionRect,
                      int activeMatchOrdinal, bool finalUpdate) override {
        CraBrowser* o = owner_;
        if (o && [o.delegate respondsToSelector:@selector(browser:didFindMatches:activeMatch:)])
            [o.delegate browser:o didFindMatches:count activeMatch:activeMatchOrdinal];
    }

    void OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) override {
        if (CraBrowser* o = owner_) [o.delegate browser:o didChangeProgress:progress];
    }

    // Request -------------------------------------------------------------

    // Content blocking and app links (IO thread). Top-level navigations and downloads always
    // load; navigations always get the handler so app links work with blocking off.
    CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(
        CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request, bool is_navigation,
        bool is_download, const CefString& request_initiator, bool& disable_default_handling) override {
        if (is_download) return nullptr;
        if (!is_navigation && !cra_blocker::Enabled().load(std::memory_order_relaxed)) return nullptr;
        return blocker_;
    }

    bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString& target_url,
                          WindowOpenDisposition target_disposition, bool user_gesture) override {
        CraBrowser* o = owner_;
        if (!o) return false;
        BOOL background = (target_disposition == CEF_WOD_NEW_BACKGROUND_TAB);
        [o.delegate browser:o requestsNewTabWithURL:NSStringFromCef(target_url) inBackground:background];
        return true;
    }

    // Context menu --------------------------------------------------------

    // Embedded pages (EmbeddedPages.swift): Chrome shows the menu through the views widget that
    // owns the page's view, found through the view's window, which is now Cra's: it showed
    // nothing. Cra shows the menu itself and hands the pick back.
    bool RunContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefContextMenuParams> params, CefRefPtr<CefMenuModel> model,
                        CefRefPtr<CefRunContextMenuCallback> callback) override {
        if (!g_ownContextMenus || model->GetCount() == 0) return false;
        CraMenuPick* pick = [CraMenuPick new];
        NSMenu* menu = CraMenuFromModel(model, pick);
        NSPoint at = [NSEvent mouseLocation];
        CefRefPtr<CefRunContextMenuCallback> done = callback;
        dispatch_async(dispatch_get_main_queue(), ^{
            [menu popUpMenuPositioningItem:nil atLocation:at inView:nil];
            if (pick.commandID >= 0) done->Continue(pick.commandID, EVENTFLAG_NONE);
            else done->Cancel();
        });
        return true;
    }

    void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                             CefRefPtr<CefContextMenuParams> params, CefRefPtr<CefMenuModel> model) override {
        size_t index = 0;
        if (!params->GetLinkUrl().empty()) {
            model->InsertItemAt(index++, kMenuOpenLinkInNewTab, "Open Link in New Tab");
            model->InsertItemAt(index++, kMenuOpenLinkInBackgroundTab, "Open Link in Background Tab");
            model->InsertItemAt(index++, kMenuCopyLink, "Copy Link");
            model->InsertSeparatorAt(index++);
        }
        if ((params->GetTypeFlags() & CM_TYPEFLAG_MEDIA) && !params->GetSourceUrl().empty()) {
            model->InsertItemAt(index++, kMenuOpenImageInNewTab, "Open Image in New Tab");
            model->InsertItemAt(index++, kMenuCopyImageURL, "Copy Image Address");
            model->InsertSeparatorAt(index++);
        }
        // Chrome-style menus already carry Chrome's own "Picture in picture" item.
        if (params->GetMediaType() == CM_MEDIATYPE_VIDEO && (params->GetMediaStateFlags() & CM_MEDIAFLAG_CAN_PICTURE_IN_PICTURE) &&
            model->GetIndexOf(IDC_CONTENT_CONTEXT_PICTUREINPICTURE) < 0) {
            bool inPiP = params->GetMediaStateFlags() & CM_MEDIAFLAG_PICTURE_IN_PICTURE;
            model->InsertItemAt(index++, kMenuPictureInPicture, inPiP ? "Exit Picture in Picture" : "Picture in Picture");
            model->InsertSeparatorAt(index++);
        }
        if (model->GetCount() > 0) model->AddSeparator();
        model->AddItem(kMenuInspectElement, "Inspect Element");
    }

    bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                              CefRefPtr<CefContextMenuParams> params, int command_id,
                              EventFlags event_flags) override {
        CraBrowser* o = owner_;
        if (!o) return false;
        switch (command_id) {
            case kMenuOpenLinkInNewTab:
                [o.delegate browser:o requestsNewTabWithURL:NSStringFromCef(params->GetLinkUrl()) inBackground:NO];
                return true;
            case kMenuOpenLinkInBackgroundTab:
                [o.delegate browser:o requestsNewTabWithURL:NSStringFromCef(params->GetLinkUrl()) inBackground:YES];
                return true;
            case kMenuOpenImageInNewTab:
                [o.delegate browser:o requestsNewTabWithURL:NSStringFromCef(params->GetSourceUrl()) inBackground:NO];
                return true;
            case kMenuCopyLink:
            case kMenuCopyImageURL: {
                NSString* s = NSStringFromCef(command_id == kMenuCopyLink ? params->GetUnfilteredLinkUrl()
                                                                           : params->GetSourceUrl());
                NSPasteboard* pb = [NSPasteboard generalPasteboard];
                [pb clearContents];
                [pb setString:s forType:NSPasteboardTypeString];
                return true;
            }
            case kMenuInspectElement:
                [o showDevToolsInspectingPoint:NSMakePoint(params->GetXCoord(), params->GetYCoord())];
                return true;
            case kMenuPictureInPicture:
                [o requestPictureInPictureInFrame:frame automatic:NO x:params->GetXCoord() y:params->GetYCoord()];
                return true;
            default:
                return false;
        }
    }

    // Keyboard ------------------------------------------------------------

    bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser, const CefKeyEvent& event, CefEventHandle os_event,
                       bool* is_keyboard_shortcut) override {
        if (event.type != KEYEVENT_RAWKEYDOWN || !os_event) return false;
        CraBrowser* o = owner_;
        if (!o) return false;
        NSEvent* e = (__bridge NSEvent*)os_event;
        if (e.type != NSEventTypeKeyDown) return false;  // modifier-only presses arrive as flagsChanged
        return [o.delegate browser:o handleKeyEvent:e] ? true : false;
    }

    bool OnKeyEvent(CefRefPtr<CefBrowser> browser, const CefKeyEvent& event, CefEventHandle os_event) override {
        if (event.type != KEYEVENT_RAWKEYDOWN || !os_event) return false;
        CraBrowser* o = owner_;
        if (!o) return false;
        NSEvent* e = (__bridge NSEvent*)os_event;
        if (e.type != NSEventTypeKeyDown) return false;
        return [o.delegate browser:o handleUnhandledKeyEvent:e] ? true : false;
    }

    // Downloads -----------------------------------------------------------

    bool OnBeforeDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> download_item,
                          const CefString& suggested_name, CefRefPtr<CefBeforeDownloadCallback> callback) override {
        NSString* name = NSStringFromCef(suggested_name);
        if (name.length == 0) name = @"download";
        NSString* dir = [NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES) firstObject];
        NSString* path = [dir stringByAppendingPathComponent:name];
        NSFileManager* fm = [NSFileManager defaultManager];
        NSString* base = [name stringByDeletingPathExtension];
        NSString* ext = [name pathExtension];
        int n = 1;
        while ([fm fileExistsAtPath:path]) {
            NSString* candidate = ext.length ? [NSString stringWithFormat:@"%@ (%d).%@", base, n, ext]
                                             : [NSString stringWithFormat:@"%@ (%d)", base, n];
            path = [dir stringByAppendingPathComponent:candidate];
            n++;
        }
        callback->Continue(CefStringFromNS(path), false);
        return true;
    }

    void OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                           CefRefPtr<CefDownloadItemCallback> callback) override {
        CraBrowser* o = owner_;
        if (!o) return;
        CraDownloadInfo* info = [CraDownloadInfo new];
        info.identifier = item->GetId();
        info.url = NSStringFromCef(item->GetURL());
        info.fullPath = NSStringFromCef(item->GetFullPath());
        info.suggestedName = NSStringFromCef(item->GetSuggestedFileName());
        info.receivedBytes = item->GetReceivedBytes();
        info.totalBytes = item->GetTotalBytes();
        info.percent = item->GetPercentComplete();
        if (item->IsComplete()) info.state = CraDownloadStateComplete;
        else if (item->IsCanceled()) info.state = CraDownloadStateCancelled;
        else if (item->IsInterrupted()) info.state = CraDownloadStateInterrupted;
        else info.state = CraDownloadStateInProgress;
        [o downloadUpdated:info];
    }

    // Focus ---------------------------------------------------------------

    void OnGotFocus(CefRefPtr<CefBrowser> browser) override {
        if (CraBrowser* o = owner_) [o.delegate browserDidReceiveFocus:o];
    }

    // Permissions ---------------------------------------------------------

    bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                                        const CefString& requesting_origin, uint32_t requested_permissions,
                                        CefRefPtr<CefMediaAccessCallback> callback) override {
        CraBrowser* o = owner_;
        if (!o || !o.delegate) return false;
        // Chrome-style pages use Chrome's permission flow: camera and microphone come back
        // through OnShowPermissionPrompt and Chrome remembers the answer per site (answered
        // here, every getUserMedia asked again). Screen sharing goes to Chrome's own picker:
        // tabs, windows or a screen, with "Also share tab audio".
        if (browser->GetHost()->GetRuntimeStyle() == CEF_RUNTIME_STYLE_CHROME) return false;
        NSUInteger kinds = 0;
        if (requested_permissions & (CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE | CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE)) kinds |= 1;
        if (requested_permissions & (CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE)) kinds |= 2;
        CefRefPtr<CefMediaAccessCallback> cb = callback;
        uint32_t requested = requested_permissions;
        [o.delegate browser:o requestsPermissionForOrigin:NSStringFromCef(requesting_origin) kinds:kinds
                 completion:^(BOOL allowed) {
            cb->Continue(allowed ? requested : CEF_MEDIA_PERMISSION_NONE);
        }];
        return true;
    }

    bool OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser, uint64_t prompt_id,
                                const CefString& requesting_origin, uint32_t requested_permissions,
                                CefRefPtr<CefPermissionPromptCallback> callback) override {
        CraBrowser* o = owner_;
        if (!o || !o.delegate) return false;
        NSUInteger kinds = 0;
        if (requested_permissions & (CEF_PERMISSION_TYPE_CAMERA_STREAM | CEF_PERMISSION_TYPE_CAMERA_PAN_TILT_ZOOM)) kinds |= 1;
        if (requested_permissions & CEF_PERMISSION_TYPE_MIC_STREAM) kinds |= 2;
        if (requested_permissions & CEF_PERMISSION_TYPE_GEOLOCATION) kinds |= 4;
        if (requested_permissions & CEF_PERMISSION_TYPE_NOTIFICATIONS) kinds |= 8;
        if (kinds == 0) kinds = 16;
        CefRefPtr<CefPermissionPromptCallback> cb = callback;
        [o.delegate browser:o requestsPermissionForOrigin:NSStringFromCef(requesting_origin) kinds:kinds
                 completion:^(BOOL allowed) {
            cb->Continue(allowed ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY);
        }];
        return true;
    }

private:
    __weak CraBrowser* owner_;
    std::string last_icon_url_;
    CefRefPtr<CefResourceRequestHandler> blocker_ = new CraContentBlockingHandler();
    IMPLEMENT_REFCOUNTING(CraClient);
};

// MARK: - CraBrowser

// MARK: - Chrome-style hosting (Views). One frameless Chrome window per page; the
// shell attaches it as a child window over the content card.

class CraDevToolsWindowDelegate : public CefWindowDelegate {
public:
    CraDevToolsWindowDelegate(CraBrowser* owner, CefRefPtr<CefBrowserView> view) : owner_(owner), view_(view) {}
    void OnWindowCreated(CefRefPtr<CefWindow> window) override {
        window->AddChildView(view_);
        window->Show();
        NSView* v = (__bridge NSView*)window->GetWindowHandle();
        if (CraBrowser* o = owner_) [o.delegate browser:o didCreateDevToolsView:v];
    }
    bool IsFrameless(CefRefPtr<CefWindow> window) override { return true; }
    bool WithStandardWindowButtons(CefRefPtr<CefWindow> window) override { return false; }
    // Docked, the shell sizes it; a resizable window's edge zone (a few points outside
    // its frame) would swallow drags meant for the frontend's splitter. Undocking makes
    // it resizable again (MainWindowController.detachDevToolsWindow).
    bool CanResize(CefRefPtr<CefWindow> window) override { return false; }
    cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
    CefRect GetInitialBounds(CefRefPtr<CefWindow> window) override { return CefRect(0, 0, 10, 10); }
private:
    __weak CraBrowser* owner_;
    CefRefPtr<CefBrowserView> view_;
    IMPLEMENT_REFCOUNTING(CraDevToolsWindowDelegate);
};

class CraChromeViewDelegate : public CefBrowserViewDelegate {
public:
    explicit CraChromeViewDelegate(CraBrowser* owner, bool devtools = false) : owner_(owner), devtools_(devtools) {}
    // Pages carry Chrome's toolbar, hidden (CraChromeWindowDelegate): extension popups need
    // its extensions container as their anchor, and Extensions.triggerAction crashes without
    // one. CRA_NO_CHROME_TOOLBAR=1 turns it off (toolbar extension buttons then do nothing).
    ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView> browser_view) override {
        return devtools_ || getenv("CRA_NO_CHROME_TOOLBAR") ? CEF_CTT_NONE : CEF_CTT_NORMAL;
    }
    cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
    // CEF hides Chrome's web contents background, which makes the first page of each renderer
    // transparent (chromiumembedded/cef#3891): a page with no background of its own showed this
    // view's dark-mode fill (#1F1F1F) until a reload gave it a renderer CEF paints white. The
    // view takes the page's own colour instead; CEF resets it on every theme change.
    void OnThemeChanged(CefRefPtr<CefView> view) override {
        CraBrowser* o = owner_;
        if (!devtools_) view->SetBackgroundColor(o ? o.pageBackgroundColor : CefColorSetARGB(255, 255, 255, 255));
    }
    CefRefPtr<CefBrowserViewDelegate> GetDelegateForPopupBrowserView(CefRefPtr<CefBrowserView> browser_view,
                                                                     const CefBrowserSettings& settings,
                                                                     CefRefPtr<CefClient> client, bool is_devtools) override {
        if (is_devtools) return new CraChromeViewDelegate(owner_, true);
        CraClient* cc = AsCraClient(client.get());
        return new CraChromeViewDelegate(cc ? cc->owner() : nil);
    }
    bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView> browser_view, CefRefPtr<CefBrowserView> popup_browser_view,
                                   bool is_devtools) override {
        if (is_devtools) {
            // Chrome's DevTools for a Chrome-style page: host it in a frameless
            // window of ours; the shell docks it beside the page like before.
            CraBrowser* o = owner_;
            if (!o) return false;
            CefWindow::CreateTopLevelWindow(new CraDevToolsWindowDelegate(o, popup_browser_view));
            return true;
        }
        CefRefPtr<CefBrowser> b = popup_browser_view->GetBrowser();
        CraClient* cc = b ? AsCraClient(b->GetHost()->GetClient().get()) : nullptr;
        if (!cc) CraDevToolsLog(@"popup with a non-page client (url %s): CEF default window", b ? b->GetMainFrame()->GetURL().ToString().c_str() : "");
        CraBrowser* host = cc ? cc->owner() : nil;
        if (!host) return false;
        [host hostPopupBrowserView:popup_browser_view];
        return true;
    }
private:
    __weak CraBrowser* owner_;
    bool devtools_;
    IMPLEMENT_REFCOUNTING(CraChromeViewDelegate);
};

class CraChromeWindowDelegate : public CefWindowDelegate {
public:
    CraChromeWindowDelegate(CraBrowser* owner, CefRefPtr<CefBrowserView> view) : owner_(owner), view_(view) {}
    void OnWindowCreated(CefRefPtr<CefWindow> window) override {
        window->AddChildView(view_);
        if (CefRefPtr<CefView> toolbar = view_->GetChromeToolbar()) toolbar->SetVisible(false);
        window->Show();
        NSView* v = (__bridge NSView*)window->GetWindowHandle();
        if (CraBrowser* o = owner_) [o hostWindowCreated:v.window];
    }
    bool IsFrameless(CefRefPtr<CefWindow> window) override { return true; }
    bool WithStandardWindowButtons(CefRefPtr<CefWindow> window) override { return false; }
    // The shell sizes page windows; a resizable one grabs drags just outside its edge
    // (the DevTools splitter, the sidebar edge) and resizes itself instead.
    bool CanResize(CefRefPtr<CefWindow> window) override { return false; }
    cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
    CefRect GetInitialBounds(CefRefPtr<CefWindow> window) override { return CefRect(0, 0, 10, 10); }
private:
    __weak CraBrowser* owner_;
    CefRefPtr<CefBrowserView> view_;
    IMPLEMENT_REFCOUNTING(CraChromeWindowDelegate);
};

/// Routes DevTools protocol results back to the completion blocks of
/// -sendDevToolsMethod: (one observer per browser, registered on first use).
class CraDevToolsObserver : public CefDevToolsMessageObserver {
   public:
    NSMutableDictionary<NSNumber*, void (^)(NSString*, NSString*)>* pending = [NSMutableDictionary dictionary];
    void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int message_id, bool success, const void* result,
                                size_t result_size) override {
        NSString* json = [[NSString alloc] initWithBytes:result length:result_size encoding:NSUTF8StringEncoding] ?: @"";
        NSNumber* key = @(message_id);
        // Capture the table, not `this`: the tab can close before this block runs, and
        // CraBrowser's dealloc then frees the observer (read freed memory, crashed 29 Oct).
        NSMutableDictionary<NSNumber*, void (^)(NSString*, NSString*)>* table = pending;
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^done)(NSString*, NSString*) = table[key];
            [table removeObjectForKey:key];
            if (done) success ? done(json, nil) : done(nil, json);
        });
    }
    IMPLEMENT_REFCOUNTING(CraDevToolsObserver);
};

@implementation CraBrowser {
    CefRefPtr<CraDevToolsObserver> _cdpObserver;
    CefRefPtr<CefRegistration> _cdpRegistration;
    int _cdpNextID;
    CefRefPtr<CefBrowser> _devToolsBrowser;
    CefRefPtr<CefBrowser> _browser;
    CefRefPtr<CraClient> _client;
    NSString* _pendingURL;
    BOOL _pendingFocus;
    BOOL _isPopupHost;
    NSMutableSet<NSNumber*>* _activeDownloads;
    BOOL _parked;
}

- (instancetype)initWithFrame:(NSRect)frame url:(NSString*)url delegate:(id<CraBrowserDelegate>)delegate {
    return [self initWithFrame:frame url:url delegate:delegate incognito:NO];
}

- (instancetype)initWithFrame:(NSRect)frame url:(NSString*)url delegate:(id<CraBrowserDelegate>)delegate incognito:(BOOL)incognito {
    return [self initWithFrame:frame url:url delegate:delegate incognito:incognito profilePath:nil];
}

- (instancetype)initWithFrame:(NSRect)frame url:(NSString*)url delegate:(id<CraBrowserDelegate>)delegate
                    incognito:(BOOL)incognito profilePath:(NSString*)profilePath {
    self = [super init];
    if (!self) return nil;
    _delegate = delegate;
    _isIncognito = incognito;
    _profilePath = incognito ? nil : [profilePath copy];
    _pageBackgroundColor = CefColorSetARGB(255, 255, 255, 255);
    _currentURL = url ?: @"";
    _currentTitle = @"";
    _pendingURL = url;
    _isPopupHost = (url == nil);
    _containerView = [[NSView alloc] initWithFrame:frame];
    _containerView.wantsLayer = YES;
    _containerView.autoresizesSubviews = YES;
    _client = new CraClient(self);
    if (!g_allBrowsers) g_allBrowsers = [NSHashTable weakObjectsHashTable];
    [g_allBrowsers addObject:self];
    if (!_isPopupHost) {
        if (g_contextInitialized) {
            [self createNow];
        } else {
            if (!g_pendingCreation) g_pendingCreation = [NSMutableArray array];
            [g_pendingCreation addObject:self];
        }
    }
    return self;
}

- (void)createNow {
    // Closing pages at quit changes the sidebar, and the window's refresh then asked for a
    // page Chromium could no longer make: Cra crashed at quit in CreateBrowserView or
    // CreateTopLevelWindow.
    if (_isClosed || _browser || g_quitting) return;
    if (!_isIncognito && !ProfileReady(_profilePath, self)) return;
    if (g_chromeHosting) {
        CefBrowserSettings settings;
        CefRefPtr<CefBrowserView> view = CefBrowserView::CreateBrowserView(
            _client, CefStringFromNS(_pendingURL ?: @"about:blank"), settings, nullptr,
            [self requestContext], new CraChromeViewDelegate(self));
        CefWindow::CreateTopLevelWindow(new CraChromeWindowDelegate(self, view));
        return;
    }
    CefWindowInfo windowInfo;
    NSRect b = _containerView.bounds;
    windowInfo.SetAsChild((__bridge void*)_containerView,
                          CefRect(0, 0, (int)MAX(b.size.width, 1), (int)MAX(b.size.height, 1)));
    if (g_useChromeStyle) windowInfo.runtime_style = CEF_RUNTIME_STYLE_CHROME;
    CefBrowserSettings settings;
    CefBrowserHost::CreateBrowser(windowInfo, _client, CefStringFromNS(_pendingURL ?: @"about:blank"), settings,
                                  nullptr, [self requestContext]);
}

- (CefRefPtr<CefRequestContext>)requestContext {
    return _isIncognito ? IncognitoContext() : ProfileContext(_profilePath);
}

- (CefRefPtr<CefBrowser>)cefBrowser { return _browser; }
- (CefRefPtr<CefClient>)cefClient { return _client; }

- (void)hostWindowCreated:(NSWindow*)window {
    self.hostWindow = window;
    [self.delegate browser:self didCreateHostWindow:window];
}

- (void)hostPopupBrowserView:(CefRefPtr<CefBrowserView>)view {
    CefWindow::CreateTopLevelWindow(new CraChromeWindowDelegate(self, view));
}

- (void)adoptBrowser:(CefRefPtr<CefBrowser>)browser {
    _browser = browser;
    self.isCreated = YES;
    if (_pendingFocus) {
        _pendingFocus = NO;
        browser->GetHost()->SetFocus(true);
    }
}

- (void)browserClosed {
    _browser = nullptr;
    self.isClosed = YES;
    self.closedByPage = !self.closeRequested && !g_quitting;
    [g_allBrowsers removeObject:self];
    if (_parked) {
        // Already reported closed when it was parked. Last: this may release self.
        [g_parkedBrowsers removeObject:self];
        return;
    }
    id<CraBrowserDelegate> d = self.delegate;
    [d browserDidClose:self];
}

- (void)downloadUpdated:(CraDownloadInfo*)download {
    if (!_activeDownloads) _activeDownloads = [NSMutableSet set];
    if (download.state == CraDownloadStateInProgress) [_activeDownloads addObject:@(download.identifier)];
    else [_activeDownloads removeObject:@(download.identifier)];
    [self.delegate browser:self didUpdateDownload:download];
    if (_parked && _activeDownloads.count == 0 && _browser) _browser->GetHost()->CloseBrowser(true);
}

/// Hides the page and reports it closed, but keeps the browser on about:blank until its
/// downloads end: Chromium cancels a download when the browser that started it closes
/// (Chrome keeps it going), and only that browser hears how the download goes.
- (void)park {
    _parked = YES;
    if (!g_parkedBrowsers) g_parkedBrowsers = [NSMutableSet set];
    [g_parkedBrowsers addObject:self];
    [g_allBrowsers removeObject:self];
    _browser->GetHost()->SetAudioMuted(true);
    _browser->GetMainFrame()->LoadURL("about:blank");
    if (NSWindow* host = self.hostWindow) {
        [host.parentWindow removeChildWindow:host];
        [host orderOut:nil];
    }
    [self.delegate browserDidClose:self];
}

- (BOOL)hasDevTools { return _browser ? _browser->GetHost()->HasDevTools() : NO; }

- (void)loadURL:(NSString*)url {
    if (_browser) {
        _browser->GetMainFrame()->LoadURL(CefStringFromNS(url));
    } else {
        _pendingURL = url;
    }
}

- (void)goBack { if (_browser) _browser->GoBack(); }
- (void)goForward { if (_browser) _browser->GoForward(); }
- (void)reload { if (_browser) _browser->Reload(); }
- (void)reloadIgnoringCache { if (_browser) _browser->ReloadIgnoreCache(); }
- (void)stopLoading { if (_browser) _browser->StopLoad(); }
- (void)exitFullscreen { if (_browser) _browser->GetHost()->ExitFullscreen(true); }

- (void)setFocused:(BOOL)focused {
    if (_browser) _browser->GetHost()->SetFocus(focused);
    else if (focused) _pendingFocus = YES;
}

- (void)showDevToolsInspectingPoint:(NSPoint)point {
    if (!_browser) return;
    if (self.hostWindow) {
        // Chrome-style: Chrome docks DevTools inside the page window itself.
        _browser->GetHost()->ShowDevTools(CefWindowInfo(), nullptr, CefBrowserSettings(), CefPoint((int)point.x, (int)point.y));
        return;
    }
    if (_browser->GetHost()->HasDevTools()) {
        _browser->GetHost()->ShowDevTools(CefWindowInfo(), nullptr, CefBrowserSettings(),
                                          CefPoint((int)point.x, (int)point.y));
        return;
    }
    NSView* host = [self.delegate devToolsHostViewForBrowser:self];
    CefWindowInfo windowInfo;
    NSRect target = NSZeroRect;
    if (host) {
        NSRect b = host.bounds;
        windowInfo.bounds = CefRect(0, 0, (int)MAX(b.size.width, 1), (int)MAX(b.size.height, 1));
        windowInfo.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
        windowInfo.hidden = true;
        CefString(&windowInfo.window_name) = "DevTools";
    } else {
        // No parent view: CEF creates its own top-level DevTools window (what
        // cefclient does on macOS); we resize it once it exists.
        NSWindow* w = _containerView.window;
        NSRect f = w ? w.frame : NSMakeRect(100, 100, 1100, 760);
        CGFloat width = MIN(1100, MAX(700, f.size.width * 0.8));
        CGFloat height = MIN(800, MAX(500, f.size.height * 0.8));
        target = NSMakeRect(NSMidX(f) - width / 2 + 40, NSMidY(f) - height / 2 - 20, width, height);
        CefString(&windowInfo.window_name) = "DevTools";
    }
    CefBrowserSettings settings;
    _browser->GetHost()->ShowDevTools(windowInfo, new DevToolsClient(target, self, host), settings,
                                      CefPoint((int)point.x, (int)point.y));
}

- (void)showDevTools { [self showDevToolsInspectingPoint:NSZeroPoint]; }
- (void)closeDevTools { if (_browser) _browser->GetHost()->CloseDevTools(); }
- (void)devToolsBrowserCreated:(CefRefPtr<CefBrowser>)browser { _devToolsBrowser = browser; }
- (void)devToolsBrowserClosed { _devToolsBrowser = nullptr; }
- (void)executeJavaScript:(NSString*)script inDevTools:(BOOL)inDevTools {
    if (!inDevTools) { [self executeJavaScript:script]; return; }
    if (!_devToolsBrowser) return;
    CefRefPtr<CefFrame> f = _devToolsBrowser->GetMainFrame();
    if (f) f->ExecuteJavaScript(CefStringFromNS(script), f->GetURL(), 0);
}

- (double)zoomLevel { return _browser ? _browser->GetHost()->GetZoomLevel() : 0; }
- (void)setZoomLevel:(double)level { if (_browser) _browser->GetHost()->SetZoomLevel(level); }

- (void)findText:(NSString*)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext {
    if (_browser) _browser->GetHost()->Find(CefStringFromNS(text), forward, matchCase, findNext);
}
- (void)stopFinding:(BOOL)clearSelection { if (_browser) _browser->GetHost()->StopFinding(clearSelection); }
- (void)setAudioMuted:(BOOL)muted { if (_browser) _browser->GetHost()->SetAudioMuted(muted); }

// MARK: Picture in Picture
//
// Chromium only lets a page enter Picture in Picture while it holds a user
// activation, which clicks in Cra's own UI never give the page. Cra therefore
// first sends the page a harmless key (F19: no page or Chromium shortcut
// listens to it), which the renderer counts as an interaction, then runs the
// request once `navigator.userActivation` reports active. `x`/`y` (view DIPs,
// -1 for none) pick the video under a context-menu click; otherwise the
// playing, largest video wins. Automatic requests (leaving the tab) take only
// an audible, playing video of some size: muted ones are hover previews
// (YouTube's thumbnails play muted on hover) or GIF-like loops.
static NSString* PictureInPictureScript(BOOL automatic, int x, int y) {
    return [NSString stringWithFormat:
        @"(function(auto,x,y){try{"
        "if(document.pictureInPictureElement){if(!auto){document.exitPictureInPicture().catch(function(){});}return;}"
        "var area=function(v){var r=v.getBoundingClientRect();return r.width*r.height;};"
        "var c=Array.prototype.slice.call(document.querySelectorAll('video')).filter(function(v){return !v.disablePictureInPicture&&v.readyState>=1&&v.videoWidth>0;});"
        "if(auto){c=c.filter(function(v){return !v.paused&&!v.ended&&!v.muted&&v.volume>0&&area(v)>=20000;});}"
        "if(!c.length){console.log('__cra_pip:none');return;}"
        "var v=null;"
        "if(x>=0){v=c.filter(function(e){var r=e.getBoundingClientRect();return x>=r.left&&x<=r.right&&y>=r.top&&y<=r.bottom;}).sort(function(a,b){return area(a)-area(b);})[0]||null;}"
        "if(!v){c.sort(function(a,b){return ((b.paused?0:1)-(a.paused?0:1))||(area(b)-area(a));});v=c[0];}"
        "var go=function(){v.requestPictureInPicture().then(function(){console.log('__cra_pip:ok');}).catch(function(e){console.log('__cra_pip:err '+e.name+': '+e.message);});};"
        "var n=0;var t=setInterval(function(){if((navigator.userActivation&&navigator.userActivation.isActive)||++n>20){clearInterval(t);go();}},50);"
        "}catch(e){console.log('__cra_pip:err '+e);}})(%d,%d,%d);", automatic ? 1 : 0, x, y];
}

// Chromium's own NSView for the page (RenderWidgetHostViewCocoa), the one
// AppKit hands real key presses to. CefBrowserHost::SendKeyEvent does not
// reach the page in Chrome-style hosting, so the nudge goes straight to it.
static NSView* FindRenderWidgetHostView(NSView* root) {
    if (!root) return nil;
    if ([NSStringFromClass([root class]) hasPrefix:@"RenderWidgetHostViewCocoa"]) return root;
    for (NSView* v in root.subviews) {
        if (NSView* found = FindRenderWidgetHostView(v)) return found;
    }
    return nil;
}

- (void)nudgeUserActivation {
    if (!_browser) return;
    NSView* root = self.hostWindow ? self.hostWindow.contentView : _containerView;
    NSView* target = FindRenderWidgetHostView(root);
    if (target) {
        NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
        NSInteger win = target.window.windowNumber;
        NSEvent* down = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:now
                                      windowNumber:win context:nil characters:@"\uF716" charactersIgnoringModifiers:@"\uF716"
                                         isARepeat:NO keyCode:0x50];
        NSEvent* up = [NSEvent keyEventWithType:NSEventTypeKeyUp location:NSZeroPoint modifierFlags:0 timestamp:now + 0.01
                                    windowNumber:win context:nil characters:@"\uF716" charactersIgnoringModifiers:@"\uF716"
                                       isARepeat:NO keyCode:0x50];
        [target keyDown:down];
        [target keyUp:up];
        return;
    }
    CefKeyEvent key;
    key.windows_key_code = 0x82;  // VK_F19
    key.native_key_code = 0x50;   // kVK_F19
    key.modifiers = 0;
    key.character = 0xF716;
    key.unmodified_character = 0xF716;
    key.is_system_key = 0;
    key.type = KEYEVENT_RAWKEYDOWN;
    _browser->GetHost()->SendKeyEvent(key);
    key.type = KEYEVENT_KEYUP;
    _browser->GetHost()->SendKeyEvent(key);
}

- (void)requestPictureInPictureInFrame:(CefRefPtr<CefFrame>)frame automatic:(BOOL)automatic x:(int)x y:(int)y {
    if (!_browser) return;
    if (self.isInPictureInPicture) {
        if (!automatic) [self exitPictureInPicture];
        return;
    }
    [self nudgeUserActivation];
    double zoom = pow(1.2, _browser->GetHost()->GetZoomLevel());  // view DIPs → CSS px
    NSString* hit = PictureInPictureScript(automatic, x < 0 ? -1 : (int)(x / zoom), y < 0 ? -1 : (int)(y / zoom));
    NSString* any = PictureInPictureScript(automatic, -1, -1);
    if (frame) {
        // Click coordinates are relative to the top-level view, so only the main frame can hit-test.
        frame->ExecuteJavaScript(CefStringFromNS(frame->IsMain() ? hit : any), frame->GetURL(), 0);
        return;
    }
    // Every frame looks for a video: embedded players live in iframes.
    std::vector<CefString> ids;
    _browser->GetFrameIdentifiers(ids);
    for (const auto& id : ids) {
        CefRefPtr<CefFrame> f = _browser->GetFrameByIdentifier(id);
        if (f && f->IsValid()) f->ExecuteJavaScript(CefStringFromNS(any), f->GetURL(), 0);
    }
}

- (void)requestPictureInPictureAutomatic:(BOOL)automatic {
    [self requestPictureInPictureInFrame:nullptr automatic:automatic x:-1 y:-1];
}

- (void)skipPictureInPictureBy:(double)seconds {
    if (!_browser) return;
    NSString* js = [NSString stringWithFormat:@"(function(){var v=document.pictureInPictureElement;if(!v)return;"
                    "var t=v.currentTime+(%f);if(isFinite(v.duration))t=Math.min(t,v.duration);v.currentTime=Math.max(0,t);})();", seconds];
    std::vector<CefString> ids;
    _browser->GetFrameIdentifiers(ids);
    for (const auto& id : ids) {
        CefRefPtr<CefFrame> f = _browser->GetFrameByIdentifier(id);
        if (f && f->IsValid()) f->ExecuteJavaScript(CefStringFromNS(js), f->GetURL(), 0);
    }
}

- (void)togglePictureInPicturePlayback {
    if (!_browser) return;
    std::vector<CefString> ids;
    _browser->GetFrameIdentifiers(ids);
    for (const auto& id : ids) {
        CefRefPtr<CefFrame> f = _browser->GetFrameByIdentifier(id);
        if (f && f->IsValid()) {
            f->ExecuteJavaScript("(function(){var v=document.pictureInPictureElement;if(!v)return;"
                                 "if(v.paused||v.ended){v.play().catch(function(){});}else{v.pause();}})();", f->GetURL(), 0);
        }
    }
}

- (void)exitPictureInPicture {
    if (!_browser) return;
    std::vector<CefString> ids;
    _browser->GetFrameIdentifiers(ids);
    for (const auto& id : ids) {
        CefRefPtr<CefFrame> f = _browser->GetFrameByIdentifier(id);
        if (f && f->IsValid()) {
            f->ExecuteJavaScript("if(document.pictureInPictureElement){document.exitPictureInPicture().catch(function(){});}",
                                 f->GetURL(), 0);
        }
    }
}
- (void)print { if (_browser) _browser->GetHost()->Print(); }
- (void)viewSource { if (_browser) _browser->GetMainFrame()->ViewSource(); }
- (void)executeJavaScript:(NSString*)script {
    if (_browser) _browser->GetMainFrame()->ExecuteJavaScript(CefStringFromNS(script), _browser->GetMainFrame()->GetURL(), 0);
}
- (void)probeBackgroundColor {
    if (_browser) _browser->GetMainFrame()->ExecuteJavaScript(kBackgroundProbe, _browser->GetMainFrame()->GetURL(), 0);
}
- (void)sendDevToolsMethod:(NSString*)method params:(NSString*)params
                completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
    if (!_browser) { completion(nil, @"no browser"); return; }
    if (!_cdpObserver) {
        _cdpObserver = new CraDevToolsObserver();
        _cdpRegistration = _browser->GetHost()->AddDevToolsMessageObserver(_cdpObserver);
    }
    int messageID = ++_cdpNextID + 100000;  // clear of ids Chromium's own clients use
    _cdpObserver->pending[@(messageID)] = [completion copy];
    // Method names are plain identifiers ("Domain.method"), so no escaping is needed.
    NSString* message = [NSString stringWithFormat:@"{\"id\":%d,\"method\":\"%@\",\"params\":%@}", messageID, method,
                         params.length ? params : @"{}"];
    NSData* data = [message dataUsingEncoding:NSUTF8StringEncoding];
    if (!_browser->GetHost()->SendDevToolsMessage(data.bytes, data.length)) {
        [_cdpObserver->pending removeObjectForKey:@(messageID)];
        completion(nil, @"SendDevToolsMessage failed");
    }
}
- (void)notifyMoveOrResizeStarted { if (_browser) _browser->GetHost()->NotifyMoveOrResizeStarted(); }

- (void)close {
    if (_isClosed || _parked) return;
    self.closeRequested = YES;
    if (_browser && _activeDownloads.count && !g_quitting) {
        [self park];
    } else if (_browser) {
        _browser->GetHost()->CloseBrowser(true);
    } else {
        // Never created; drop it from the pending list and report closed.
        [g_pendingCreation removeObject:self];
        [self browserClosed];
    }
}

@end

// MARK: - Runtime

// MARK: - Chrome-style spike (extensions need Chrome style; on macOS that means a Views window)

static void (^g_spikeWindowHandler)(NSWindow*) = nil;

class SpikeBrowserViewDelegate : public CefBrowserViewDelegate {
public:
    ChromeToolbarType GetChromeToolbarType(CefRefPtr<CefBrowserView> browser_view) override { return CEF_CTT_NONE; }
    cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
    IMPLEMENT_REFCOUNTING(SpikeBrowserViewDelegate);
};

class SpikeWindowDelegate : public CefWindowDelegate {
public:
    explicit SpikeWindowDelegate(CefRefPtr<CefBrowserView> view) : view_(view) {}
    void OnWindowCreated(CefRefPtr<CefWindow> window) override {
        window->AddChildView(view_);
        window->Show();
        NSView* v = (__bridge NSView*)window->GetWindowHandle();
        if (g_spikeWindowHandler && v.window) g_spikeWindowHandler(v.window);
    }
    bool IsFrameless(CefRefPtr<CefWindow> window) override { return true; }
    bool WithStandardWindowButtons(CefRefPtr<CefWindow> window) override { return false; }
    cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_CHROME; }
    CefRect GetInitialBounds(CefRefPtr<CefWindow> window) override { return CefRect(300, 200, 900, 640); }
private:
    CefRefPtr<CefBrowserView> view_;
    IMPLEMENT_REFCOUNTING(SpikeWindowDelegate);
};

// Chrome's crash recovery: when the previous run did not quit cleanly (killed,
// crashed), the profile is left with profile.exit_type = "Crashed" and the
// Chrome runtime restores the last session (Default/Sessions) into a stock
// Chrome window (title bar, location bar) the moment the first browser is
// created. Cra restores its own tabs, so the saved session is dropped and the
// profile marked clean before Chromium reads it.
static void MarkProfileExitedCleanly(NSString* profileDir) {
    NSString* sessions = [profileDir stringByAppendingPathComponent:@"Sessions"];
    [[NSFileManager defaultManager] removeItemAtPath:sessions error:nil];
    NSString* prefs = [profileDir stringByAppendingPathComponent:@"Preferences"];
    NSData* data = [NSData dataWithContentsOfFile:prefs];
    if (!data) return;
    NSError* error = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (![root isKindOfClass:[NSMutableDictionary class]]) return;
    NSMutableDictionary* profile = root[@"profile"];
    if (![profile isKindOfClass:[NSMutableDictionary class]]) return;
    if ([profile[@"exit_type"] isEqual:@"Normal"] && [profile[@"exited_cleanly"] boolValue]) return;
    profile[@"exit_type"] = @"Normal";
    profile[@"exited_cleanly"] = @YES;
    NSData* out = [NSJSONSerialization dataWithJSONObject:root options:0 error:&error];
    if (out) [out writeToFile:prefs atomically:YES];
}

@implementation CraCEFRuntime

+ (void)setChromeHosting:(BOOL)enabled { g_chromeHosting = enabled; }
+ (void)setOwnContextMenus:(BOOL)enabled { g_ownContextMenus = enabled; }
+ (BOOL)chromeHosting { return g_chromeHosting; }

+ (void)setContentBlockingEnabled:(BOOL)enabled { cra_blocker::Enabled().store(enabled); }
+ (BOOL)contentBlockingEnabled { return cra_blocker::Enabled().load(); }

/// Only contexts that finished loading take preferences (an uninitialised one is fatal);
/// the rest get it from ApplyProfilePreferences when they load.
+ (void)setHttpsOnlyModeEnabled:(BOOL)enabled {
    g_httpsOnly = enabled;
    if (!g_contextInitialized) return;
    ApplyHttpsOnly(CefRequestContext::GetGlobalContext());
    for (auto& [path, context] : g_profileContexts) {
        if ([g_readyProfiles containsObject:@(path.c_str())]) ApplyHttpsOnly(context);
    }
    if (g_incognitoContext && g_incognitoReady) ApplyHttpsOnly(g_incognitoContext);
}
+ (void)setBlockedDomains:(NSArray<NSString*>*)domains {
    auto* set = new cra_blocker::DomainSet();
    set->reserve(domains.count);
    for (NSString* d in domains) cra_blocker::AddListLine(*set, d.UTF8String ?: "");
    cra_blocker::Publish(set);
}
+ (void)loadBlockedDomainsFromFile:(NSString*)path completion:(void (^)(NSInteger))completion {
    void (^done)(NSInteger) = [completion copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData* data = [NSData dataWithContentsOfFile:path];
        NSInteger count = 0;
        if (data.length) {
            cra_blocker::DomainSet* set =
                cra_blocker::ParseList(std::string_view(static_cast<const char*>(data.bytes), data.length));
            count = (NSInteger)set->size();
            cra_blocker::Publish(set);
        }
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(count); });
    });
}
+ (NSInteger)blockedDomainCount { return (NSInteger)cra_blocker::Count(); }
+ (BOOL)shouldBlockRequestURL:(NSString*)requestURL onPageURL:(NSString*)pageURL {
    return cra_blocker::ShouldBlock(cra_blocker::WebHost(requestURL.UTF8String ?: ""),
                                    cra_blocker::WebHost(pageURL.UTF8String ?: ""));
}

+ (void)spikeChromeWindowWithURL:(NSString*)url handler:(void (^)(NSWindow*))handler {
    g_spikeWindowHandler = [handler copy];
    CefBrowserSettings settings;
    CefRefPtr<CefBrowserView> view = CefBrowserView::CreateBrowserView(
        new DevToolsClient(NSZeroRect, nil, nil), CefStringFromNS(url), settings, nullptr, nullptr, new SpikeBrowserViewDelegate());
    CefWindow::CreateTopLevelWindow(new SpikeWindowDelegate(view));
}

+ (BOOL)initializeWithCachePath:(NSString*)cachePath
               userAgentProduct:(NSString*)product
                        logPath:(NSString*)logPath
                 useChromeStyle:(BOOL)useChromeStyle
                useMockKeychain:(BOOL)useMockKeychain {
    if (g_libraryLoader) return YES;
    g_useChromeStyle = useChromeStyle;
    g_useMockKeychain = useMockKeychain;
    g_extensionsDirectory = [[cachePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Extensions"];
    g_libraryLoader = new CefScopedLibraryLoader();
    if (!g_libraryLoader->LoadInMain()) {
        NSLog(@"CraCEF: failed to load Chromium Embedded Framework");
        return NO;
    }
    // Make sure the CefAppProtocol NSApplication exists before CefInitialize.
    [CraApplication sharedApplication];

    CefMainArgs mainArgs(*_NSGetArgc(), *_NSGetArgv());
    CefSettings settings;
    // Renderer, GPU and utility processes run in Chromium's seatbelt sandbox
    // (CraHelper enters it before loading the framework).
    settings.no_sandbox = false;
    CefString(&settings.cache_path) = CefStringFromNS(cachePath);
    CefString(&settings.root_cache_path) = CefStringFromNS(cachePath);
    settings.persist_session_cookies = true;
    CefString(&settings.user_agent_product) = CefStringFromNS(product);
    CefString(&settings.log_file) = CefStringFromNS(logPath);
    settings.log_severity = LOGSEVERITY_WARNING;
    settings.background_color = CefColorSetARGB(255, 255, 255, 255);

    // Default plus the spaces' own profiles ("Profile <id>").
    for (NSString* name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:cachePath error:nil]) {
        if ([name isEqualToString:@"Default"] || [name hasPrefix:@"Profile "]) {
            MarkProfileExitedCleanly([cachePath stringByAppendingPathComponent:name]);
        }
    }
    CefRefPtr<CraApp> app(new CraApp());
    if (!CefInitialize(mainArgs, settings, app.get(), nullptr)) {
        int code = CefGetExitCode();
        g_alreadyRunning = (code == CEF_RESULT_CODE_NORMAL_EXIT_PROCESS_NOTIFIED);
        NSLog(@"CraCEF: CefInitialize failed (exit code %d%@)", code, g_alreadyRunning ? @", another instance is running" : @"");
        return NO;
    }
    return YES;
}

+ (BOOL)anotherInstanceWasNotified { return g_alreadyRunning; }
+ (void)setRelaunchHandler:(void (^)(NSArray<NSString*>*))handler { g_relaunchHandler = [handler copy]; }
+ (void)setStrayPageHandler:(void (^)(NSString*))handler { g_strayPageHandler = [handler copy]; }
+ (BOOL)isExtensionWindow:(NSWindow*)window { return window && [g_extensionWindows containsObject:window]; }
+ (BOOL)isPageWindow:(NSWindow*)window {
    for (CraBrowser* b in g_allBrowsers) if (window && b.hostWindow == window) return YES;
    return NO;
}

+ (void)runMessageLoop { CefRunMessageLoop(); }
+ (void)quitMessageLoop { CraQuitMessageLoop(); }
+ (void)shutdown {
    g_incognitoContext = nullptr;
    g_profileContexts.clear();
    g_waitingForProfile = nil;
    CefShutdown();
}

+ (void)closeAllBrowsersAndQuit {
    g_quitting = true;
    if (g_strayClient) g_strayClient->CloseWindows();
    NSArray<CraBrowser*>* all = [g_allBrowsers allObjects];
    if ((all.count == 0 && g_parkedBrowsers.count == 0) || g_liveBrowsers <= 0) {
        CraQuitMessageLoop();
        return;
    }
    for (CraBrowser* b in all) [b close];
    for (CraBrowser* b in [g_parkedBrowsers allObjects]) if (CefRefPtr<CefBrowser> cef = [b cefBrowser]) cef->GetHost()->CloseBrowser(true);
}

+ (NSInteger)liveBrowserCount { return g_liveBrowsers; }
+ (void)endIncognitoSession { g_incognitoContext = nullptr; g_incognitoReady = false; }
+ (NSString*)chromiumVersion {
    return [NSString stringWithFormat:@"%d.%d.%d.%d", CHROME_VERSION_MAJOR, CHROME_VERSION_MINOR,
            CHROME_VERSION_BUILD, CHROME_VERSION_PATCH];
}
+ (NSString*)cefVersion { return @CEF_VERSION; }
+ (BOOL)hasBrowserDevTools { return g_cdpWriteFD >= 0; }
+ (void)setBrowserDevToolsEventHandler:(void (^)(NSString*, NSString*, NSString* _Nullable))handler {
    g_cdpEventHandler = [handler copy];
}
+ (void)sendBrowserDevToolsMethod:(NSString*)method params:(NSString*)params
                       completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
    [self sendBrowserDevToolsMethod:method params:params sessionID:nil completion:completion];
}
+ (void)fetchURL:(NSString*)url headers:(NSDictionary<NSString*, NSString*>*)headers profilePath:(NSString*)profilePath
      completion:(void (^)(NSInteger, NSString*, NSString*, NSString*))completion {
    [self fetchURL:url headers:headers profilePath:profilePath attempt:0 completion:completion];
}
+ (void)fetchURL:(NSString*)url headers:(NSDictionary<NSString*, NSString*>*)headers profilePath:(NSString*)profilePath
         attempt:(int)attempt completion:(void (^)(NSInteger, NSString*, NSString*, NSString*))completion {
    // Chromium's profiles load asynchronously; a fetch waits for its profile like a page does.
    BOOL ready = g_contextInitialized && (!profilePath.length || (ProfileContext(profilePath), [g_readyProfiles containsObject:profilePath]));
    if (!ready) {
        if (attempt >= 60) { completion(0, url, @"", @""); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self fetchURL:url headers:headers profilePath:profilePath attempt:attempt + 1 completion:completion];
        });
        return;
    }
    CefRefPtr<CefRequest> request = CefRequest::Create();
    request->SetURL(CefStringFromNS(url));
    request->SetMethod("GET");
    // Sent like the page's own navigation: stored cookies, first party = the site itself.
    request->SetFlags(UR_FLAG_ALLOW_STORED_CREDENTIALS | UR_FLAG_SKIP_CACHE);
    request->SetFirstPartyForCookies(CefStringFromNS(url));
    CefRequest::HeaderMap map;
    for (NSString* name in headers) map.insert({CefStringFromNS(name), CefStringFromNS(headers[name])});
    request->SetHeaderMap(map);
    CefRefPtr<CefRequestContext> context = profilePath.length ? ProfileContext(profilePath) : CefRequestContext::GetGlobalContext();
    CefRefPtr<CefURLRequest> r = CefURLRequest::Create(request, new FetchClient(completion), context);
    if (r) FetchClient::InFlight().insert(r); else completion(0, url, @"", @"");
}
+ (void)sendBrowserDevToolsMethod:(NSString*)method params:(NSString*)params sessionID:(NSString*)sessionID
                       completion:(void (^)(NSString* _Nullable, NSString* _Nullable))completion {
    if (g_cdpWriteFD < 0) { completion(nil, @"no DevTools pipe"); return; }
    int messageID = ++g_cdpNextID;
    g_cdpPending[@(messageID)] = [completion copy];
    NSString* session = sessionID.length ? [NSString stringWithFormat:@",\"sessionId\":\"%@\"", sessionID] : @"";
    NSString* message = [NSString stringWithFormat:@"{\"id\":%d,\"method\":\"%@\",\"params\":%@%@}", messageID, method,
                         params.length ? params : @"{}", session];
    NSMutableData* data = [[message dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [data appendBytes:"" length:1];
    const char* bytes = (const char*)data.bytes;
    for (size_t sent = 0; sent < data.length;) {
        ssize_t n = write(g_cdpWriteFD, bytes + sent, data.length - sent);
        if (n <= 0) { [g_cdpPending removeObjectForKey:@(messageID)]; completion(nil, @"pipe write failed"); return; }
        sent += (size_t)n;
    }
}

@end

// MARK: - NSApplication subclass

@interface CraApplication () <CefAppProtocol>
@end

@implementation CraApplication {
    BOOL _handlingSendEvent;
    NSHashTable<NSEvent*>* _forwardedKeyEvents;
}

- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent { _handlingSendEvent = handlingSendEvent; }

// A background test instance (CRA_TEST_BACKGROUND, HitchMonitor.swift) never takes the front:
// Chromium activates the app whenever it shows one of its windows.
static BOOL CraTestBackground(void) {
    static BOOL background = [NSProcessInfo.processInfo.environment[@"CRA_TEST_BACKGROUND"] isEqualToString:@"1"];
    return background;
}
- (void)activateIgnoringOtherApps:(BOOL)flag {
    if (!CraTestBackground()) [super activateIgnoringOtherApps:flag];
}
- (void)activate {
    if (!CraTestBackground()) [super activate];
}

// A Chromium page view, wherever it lives: in its own window, or embedded in a Cra
// window's pane (EmbeddedPages.swift), where sendEvent's other two checks miss it.
static BOOL CraIsInPageView(NSView* v) {
    for (NSView* p = v; p; p = p.superview) {
        if ([NSStringFromClass([p class]) isEqualToString:@"WebContentsViewCocoa"]) return YES;
    }
    return NO;
}

// Chrome's rule: when a web view has focus, ⌘-shortcuts go to the page
// first and only reach the menu bar if the page leaves them alone (so ⌘F in
// Google Docs or ⌘← in a text field keep working). Reserved shortcuts are
// taken in OnPreKeyEvent, the rest in OnKeyEvent. Keys the page leaves alone
// come back here from Chromium's CommandDispatcher (redispatchKeyEvent:), and
// those must take the normal path so the menu bar sees them: ⌘C/⌘V/⌘X/⌘A/⌘Z
// only exist as Edit menu items sent to the page's first responder.
- (void)sendEvent:(NSEvent*)event {
    CefScopedSendingEvent sendingEventScoper;
    if ([_forwardedKeyEvents containsObject:event]) {
        [_forwardedKeyEvents removeObject:event];
        [super sendEvent:event];
        return;
    }
    if (event.type == NSEventTypeKeyDown && (event.modifierFlags & NSEventModifierFlagCommand)) {
        NSWindow* key = self.keyWindow;
        NSResponder* fr = key.firstResponder;
        if ([fr isKindOfClass:[NSView class]]) {
            NSView* v = (NSView*)fr;
            for (CraBrowser* b in [g_allBrowsers allObjects]) {
                if ([v isDescendantOf:b.containerView] || (b.hostWindow && key == b.hostWindow) || CraIsInPageView(v)) {
                    if (!_forwardedKeyEvents) _forwardedKeyEvents = [NSHashTable weakObjectsHashTable];
                    [_forwardedKeyEvents addObject:event];
                    [key sendEvent:event];
                    return;
                }
            }
        }
    }
    [super sendEvent:event];
}

// Pages, DevTools and panels are child windows docked over the main window, and
// the page is usually key. Window managers (Rectangle, Magnet, Raycast) move
// the AX focused window, which tore the page off its dock instead of moving
// Cra; hand them the top-level window the child belongs to.
static id CraTopLevelWindow(id element) {
    if (![element isKindOfClass:[NSWindow class]]) return element;
    NSWindow* w = element;
    while (w.parentWindow) w = w.parentWindow;
    return w;
}

- (id)accessibilityFocusedWindow { return CraTopLevelWindow([super accessibilityFocusedWindow]); }
- (id)accessibilityMainWindow { return CraTopLevelWindow([super accessibilityMainWindow]); }

// Cmd-Q, the Dock, logout: give the delegate a say, then tear Chromium down
// in order (browsers first, then the message loop, then CefShutdown in main).
- (void)terminate:(id)sender {
    id<NSApplicationDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(applicationShouldTerminate:)]) {
        NSApplicationTerminateReply reply = [delegate applicationShouldTerminate:self];
        if (reply == NSTerminateCancel) return;
    }
    [CraCEFRuntime closeAllBrowsersAndQuit];
}

@end
