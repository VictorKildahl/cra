// The engine test build's checks (spike_checks.h). Everything runs on the UI thread, step after step.
//
// Shape under test (docs/chromium-engine.md): one Chrome Browser per Cra window, its Chrome window
// never shown; Cra's own NSWindow shows the pages' views.
//
// Switches: --cra-spike, --cra-spike-page=<file url> (a page that keeps a value in localStorage),
// --cra-spike-extension=<extension id> (loaded with --load-extension), --cra-spike-screen=<part of a
// display's name> (where Cra's window goes).

#include "cra/spike_checks.h"

#import <Cocoa/Cocoa.h>

#include <string>

#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/chrome_browser_main_extra_parts.h"
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/web_contents.h"
#include "ui/gfx/native_ui_types.h"
#include "url/gurl.h"

namespace cra {
namespace {

int g_failures = 0;

void Report(const char* check, bool ok, const std::string& detail = "") {
  if (!ok) {
    ++g_failures;
  }
  fprintf(stderr, "CRA-SPIKE %s %s%s%s\n", ok ? "PASS" : "FAIL", check, detail.empty() ? "" : ": ",
          detail.c_str());
}

void After(base::TimeDelta delay, base::OnceClosure step) {
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(FROM_HERE, std::move(step), delay);
}

std::string Switch(const char* name) {
  return base::CommandLine::ForCurrentProcess()->GetSwitchValueASCII(name);
}

NSView* PageView(content::WebContents* contents) {
  return contents->GetNativeView().GetNativeNSView();
}

// Moves a page's view out of Chrome's hidden window into one of Cra's panes.
void Embed(content::WebContents* contents, NSView* pane) {
  NSView* view = PageView(contents);
  [view removeFromSuperview];
  view.frame = pane.bounds;
  view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [pane addSubview:view];
}

class SpikeRun : public TabStripModelObserver {
 public:
  void Start() {
    ProfileManager* profiles = g_browser_process->profile_manager();
    base::FilePath root = profiles->user_data_dir();
    Report("engine started (Cra's startup part ran in Chrome's browser process)", true);
    profiles->CreateProfileAsync(root.AppendASCII("Default"),
                                 base::BindOnce(&SpikeRun::OnProfileA, base::Unretained(this)));
  }

 private:
  void OnProfileA(Profile* profile) {
    a_ = profile;
    g_browser_process->profile_manager()->CreateProfileAsync(
        g_browser_process->profile_manager()->user_data_dir().AppendASCII("Profile 1"),
        base::BindOnce(&SpikeRun::OnProfileB, base::Unretained(this)));
  }

  void OnProfileB(Profile* profile) {
    b_ = profile;
    Report("two profiles", a_ && b_ && a_->GetPath() != b_->GetPath(),
           a_ && b_ ? a_->GetPath().BaseName().value() + " + " + b_->GetPath().BaseName().value() : "");
    if (!a_ || !b_) {
      return Quit();
    }
    MakeWindow();
  }

  void MakeWindow() {
    NSScreen* screen = NSScreen.mainScreen;
    NSString* wanted = base::SysUTF8ToNSString(Switch("cra-spike-screen"));
    for (NSScreen* s in NSScreen.screens) {
      if (wanted.length && [s.localizedName containsString:wanted]) {
        screen = s;
      }
    }
    NSRect area = screen.visibleFrame;
    NSRect frame = NSMakeRect(NSMinX(area) + 40, NSMinY(area) + 40, 1100, 640);
    window_ = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    window_.releasedWhenClosed = NO;
    window_.title = @"Cra engine test";
    NSView* content = window_.contentView;
    left_ = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, 640)];
    right_ = [[NSView alloc] initWithFrame:NSMakeRect(550, 0, 550, 640)];
    [content addSubview:left_];
    [content addSubview:right_];
    [window_ orderFront:nil];

    // One Chrome Browser per profile, as Cra will have one per window. CreateBrowserWindow makes Chrome's
    // window; nothing shows it.
    browser_a_ = CreateBrowserWindow(BrowserWindowCreateParams(*a_, true));
    browser_b_ = CreateBrowserWindow(BrowserWindowCreateParams(*b_, true));
    browser_a_->GetTabStripModel()->AddObserver(this);
    GURL page(Switch("cra-spike-page"));
    chrome::AddTabAt(browser_a_, page, -1, true);
    chrome::AddTabAt(browser_b_, page, -1, true);
    page_a_ = browser_a_->GetTabStripModel()->GetActiveWebContents();
    page_b_ = browser_b_->GetTabStripModel()->GetActiveWebContents();
    Embed(page_a_, left_);
    Embed(page_b_, right_);
    After(base::Seconds(3), base::BindOnce(&SpikeRun::CheckPages, base::Unretained(this)));
  }

  void CheckPages() {
    bool loaded = !page_a_->IsLoading() && !page_b_->IsLoading();
    Report("pages load in both profiles", loaded,
           base::UTF16ToUTF8(page_a_->GetTitle()) + " / " + base::UTF16ToUTF8(page_b_->GetTitle()));
    bool visible = page_a_->GetVisibility() == content::Visibility::VISIBLE &&
                   page_b_->GetVisibility() == content::Visibility::VISIBLE;
    Report("both pages visible in Cra's window (two tabs of two Browsers on screen at once)", visible);
    bool embedded = PageView(page_a_).superview == left_ && PageView(page_b_).superview == right_;
    Report("pages stay in Cra's window (Chrome didn't take its views back)", embedded);
    // Profile isolation: profile A keeps a value; profile B's page, same origin, doesn't see it.
    page_a_->GetPrimaryMainFrame()->ExecuteJavaScriptForTests(
        u"localStorage.setItem('cra', 'a'); localStorage.getItem('cra')",
        base::BindOnce(&SpikeRun::OnStoredInA, base::Unretained(this)), 0);
  }

  void OnStoredInA(base::Value result) {
    bool stored = result.is_string() && result.GetString() == "a";
    page_b_->GetPrimaryMainFrame()->ExecuteJavaScriptForTests(
        u"String(localStorage.getItem('cra'))",
        base::BindOnce(&SpikeRun::OnReadInB, base::Unretained(this), stored), 0);
  }

  void OnReadInB(bool stored, base::Value result) {
    std::string seen = result.is_string() ? result.GetString() : "?";
    Report("profiles keep their storage apart", stored && seen == "null", "B sees " + seen);
    // A popup from a click: Chrome puts it in the opener's tab strip (OnTabStripModelChanged).
    page_a_->GetPrimaryMainFrame()->ExecuteJavaScriptWithUserGestureForTests(
        u"window.open(location.href + '#popup'); 'opened'", base::DoNothing(), 0);
    After(base::Seconds(2), base::BindOnce(&SpikeRun::CheckPopup, base::Unretained(this)));
  }

  void OnTabStripModelChanged(TabStripModel* model,
                              const TabStripModelChange& change,
                              const TabStripSelectionChange& selection) override {
    if (change.type() != TabStripModelChange::kInserted) {
      return;
    }
    for (const auto& inserted : change.GetInsert()->contents) {
      if (inserted.contents != page_a_) {
        popup_ = inserted.contents;
      }
    }
  }

  void CheckPopup() {
    Report("a popup arrives as a tab of the opener's Browser", popup_ != nullptr,
           popup_ ? popup_->GetVisibleURL().spec() : "nothing arrived");
    if (!popup_) {
      return ExtensionPopup();
    }
    Report("the popup keeps its opener", popup_->HasOpener());
    // Cra shows it as its own tab: its view goes where the opener's was.
    Embed(popup_, left_);
    popup_->GetPrimaryMainFrame()->ExecuteJavaScriptForTests(
        u"String(window.opener !== null)",
        base::BindOnce(&SpikeRun::OnPopupOpener, base::Unretained(this)), 0);
  }

  void OnPopupOpener(base::Value result) {
    Report("window.opener reaches the opener", result.is_string() && result.GetString() == "true");
    ExtensionPopup();
  }

  void ExtensionPopup() {
    std::string id = Switch("cra-spike-extension");
    ExtensionsContainer* container = ExtensionsContainer::From(*browser_a_);
    windows_before_ = NSApp.windows.count;
    bool asked = container && container->ShowToolbarActionPopupForAPICall(
                                  id, base::BindOnce(&SpikeRun::OnExtensionPopup, base::Unretained(this)));
    Report("an extension's popup can be asked for in a hidden Chrome window", asked,
           container ? "" : "no extensions container");
    After(base::Seconds(3), base::BindOnce(&SpikeRun::CheckExtensionPopup, base::Unretained(this)));
  }

  void OnExtensionPopup(extensions::ExtensionHost* host) { popup_host_ = host != nullptr; }

  void CheckExtensionPopup() {
    NSInteger shown = 0;
    for (NSWindow* w in NSApp.windows) {
      if (w.visible && w != window_) {
        ++shown;
      }
    }
    Report("the extension's popup opened", popup_host_, popup_host_ ? "" : "no popup host");
    Report("the extension's popup is on screen", shown > 0, std::to_string(shown) + " window(s) besides Cra's");
    Quit();
  }

  void Quit() {
    fprintf(stderr, "CRA-SPIKE DONE %d failure(s)\n", g_failures);
    // The test quits as the app will: Chrome's own exit, every Browser closes.
    chrome::AttemptExit();
  }

  raw_ptr<Profile> a_ = nullptr;
  raw_ptr<Profile> b_ = nullptr;
  raw_ptr<BrowserWindowInterface> browser_a_ = nullptr;
  raw_ptr<BrowserWindowInterface> browser_b_ = nullptr;
  raw_ptr<content::WebContents> page_a_ = nullptr;
  raw_ptr<content::WebContents> page_b_ = nullptr;
  raw_ptr<content::WebContents> popup_ = nullptr;
  bool popup_host_ = false;
  NSUInteger windows_before_ = 0;
  NSWindow* __strong window_ = nil;
  NSView* __strong left_ = nil;
  NSView* __strong right_ = nil;
};

class SpikeParts : public ChromeBrowserMainExtraParts {
 public:
  void PostBrowserStart() override {
    if (!base::CommandLine::ForCurrentProcess()->HasSwitch("cra-spike")) {
      return;
    }
    run_ = std::make_unique<SpikeRun>();
    run_->Start();
  }

 private:
  std::unique_ptr<SpikeRun> run_;
};

}  // namespace

std::unique_ptr<ChromeBrowserMainExtraParts> MakeSpikeParts() {
  return std::make_unique<SpikeParts>();
}

}  // namespace cra
