// page_protocol.h says what this is. The Cra.* methods are the CEF patch's (scripts/cef-patches/
// freezing-vote.patch), moved here; the ones that need Cra's other Chromium patches answer "not yet".

#include "cra/page_protocol.h"

#include <algorithm>
#include <limits>
#include <set>
#include <optional>
#include <vector>

#include "base/base64.h"
#include "base/feature_list.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/pickle.h"
#include "base/strings/sys_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/thread_pool.h"
#include "base/values.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/ref_counted.h"
#include "base/scoped_observation.h"
#include "extensions/browser/webstore_installer.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "components/crx_file/id_util.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/install_approval.h"
#include "extensions/common/extension.h"
#include "extensions/common/mojom/manifest.mojom-shared.h"
#include "chrome/browser/picture_in_picture/auto_picture_in_picture_tab_helper.h"
#include "chrome/browser/picture_in_picture/picture_in_picture_window_manager.h"
#include "chrome/browser/translate/chrome_translate_client.h"
#include "components/performance_manager/freezing/freezing_policy.h"
#include "components/performance_manager/public/freezing/cannot_freeze_reason.h"
#include "components/performance_manager/public/freezing/freezing.h"
#include "components/performance_manager/public/graph/graph.h"
#include "components/performance_manager/public/graph/page_node.h"
#include "components/performance_manager/public/performance_manager.h"
#include "components/sessions/content/content_serialized_navigation_builder.h"
#include "components/sessions/core/serialized_navigation_entry.h"
#include "components/sessions/core/session_constants.h"
#include "components/translate/core/browser/translate_download_manager.h"
#include "components/translate/core/browser/translate_manager.h"
#include "components/translate/core/browser/translate_prefs.h"
#include "content/public/browser/cra_live_connection.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/media_session.h"
#include "content/public/browser/web_contents_user_data.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "services/media_session/public/mojom/media_session.mojom.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/restore_type.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/content_features.h"
#include "extensions/browser/view_type_utils.h"
#include "extensions/common/mojom/view_type.mojom.h"
#include "partition_alloc/memory_reclaimer.h"

namespace cra {
namespace {

NSString* JSON(const base::Value& value) {
  std::string text;
  base::JSONWriter::Write(value, &text);
  return base::SysUTF8ToNSString(text);
}

NSString* ErrorJSON(const std::string& message) {
  base::DictValue error;
  error.Set("code", -32000);
  error.Set("message", message);
  return JSON(base::Value(std::move(error)));
}

// Cra's vote to freeze the page, like Arc's freeze token, held while Cra asks for it. Chromium's freezing
// policy freezes the page only while no CannotFreezeReason applies (audible, capturing, Web Locks, WebRTC, ...).
const char kFreezingVoteKey[] = "cra-freezing-vote";

struct FreezingVoteData : public base::SupportsUserData::Data {
  explicit FreezingVoteData(content::WebContents* contents) : vote(contents) {}
  performance_manager::freezing::FreezingVote vote;
};

base::ListValue ReasonList(const performance_manager::freezing::CannotFreezeReasonSet& reasons) {
  base::ListValue list;
  for (auto reason : reasons) {
    list.Append(performance_manager::freezing::CannotFreezeReasonToString(reason));
  }
  return list;
}

bool FreezingAvailable(content::WebContents* contents) {
  auto* graph = performance_manager::PerformanceManager::GetGraph();
  return performance_manager::PerformanceManager::GetPrimaryPageNodeForWebContents(contents) && graph &&
         graph->GetRegisteredObjectAs<performance_manager::FreezingPolicy>();
}

// A tab's back and forward list across a relaunch, as Chrome's session service keeps it (GitHub #273):
// Cra.getHistory gives the last committed entry and up to gMaxPersistNavigationCount on each side, each with
// its page state, pickled as a session command holds them; Cra.restoreHistory puts such a list into a page
// that hasn't navigated yet and loads entry `index`.
constexpr size_t kMaxHistoryEntrySize = std::numeric_limits<uint16_t>::max() - 1024;

void GetHistory(content::WebContents* contents, base::DictValue* result) {
  content::NavigationController& controller = contents->GetController();
  const int current = controller.GetLastCommittedEntryIndex();
  content::NavigationEntry* current_entry = controller.GetLastCommittedEntry();
  std::vector<sessions::SerializedNavigationEntry> navigations;
  int index = 0;
  if (current >= 0 && current_entry && !current_entry->IsInitialEntry()) {
    const int first = std::max(current - sessions::gMaxPersistNavigationCount, 0);
    const int last = std::min(current + sessions::gMaxPersistNavigationCount, controller.GetEntryCount() - 1);
    for (int i = first; i <= last; ++i) {
      content::NavigationEntry* entry = controller.GetEntryAtIndex(i);
      if (!entry || entry->IsInitialEntry()) {
        continue;
      }
      if (i == current) {
        index = static_cast<int>(navigations.size());
      }
      navigations.push_back(sessions::ContentSerializedNavigationBuilder::FromNavigationEntry(i, entry));
    }
  }
  std::string history;
  if (!navigations.empty()) {
    base::Pickle pickle;
    pickle.WriteInt(static_cast<int>(navigations.size()));
    for (const auto& navigation : navigations) {
      navigation.WriteToPickle(kMaxHistoryEntrySize, &pickle);
    }
    history = base::Base64Encode(pickle.AsBytes());
  }
  result->Set("history", history);
  result->Set("index", index);
  result->Set("url", navigations.empty() ? std::string() : navigations[index].virtual_url().spec());
}

void RestoreHistory(content::WebContents* contents,
                    const base::DictValue* params,
                    base::DictValue* result,
                    std::string* error) {
  const std::string* encoded = params ? params->FindString("history") : nullptr;
  std::optional<int> index = params ? params->FindInt("index") : std::nullopt;
  std::string bytes;
  if (!encoded || !index || !base::Base64Decode(*encoded, &bytes)) {
    *error = "needs history (base64) and index";
    return;
  }
  base::Pickle pickle = base::Pickle::WithUnownedBuffer(base::as_byte_span(bytes));
  base::PickleIterator iterator(pickle);
  int count = 0;
  if (!iterator.ReadInt(&count) || count <= 0 || count > 2 * sessions::gMaxPersistNavigationCount + 1 ||
      *index < 0 || *index >= count) {
    *error = "unreadable history";
    return;
  }
  std::vector<sessions::SerializedNavigationEntry> navigations(count);
  for (int i = 0; i < count; ++i) {
    if (!navigations[i].ReadFromPickle(&iterator)) {
      *error = "unreadable history";
      return;
    }
    navigations[i].set_index(i);
  }
  content::NavigationController& controller = contents->GetController();
  content::NavigationEntry* committed = controller.GetLastCommittedEntry();
  if (controller.GetEntryCount() > 1 || controller.GetPendingEntry() || (committed && !committed->IsInitialEntry())) {
    *error = "the page has navigated already";
    return;
  }
  std::vector<std::unique_ptr<content::NavigationEntry>> entries =
      sessions::ContentSerializedNavigationBuilder::ToNavigationEntries(navigations, contents->GetBrowserContext());
  controller.Restore(*index, content::RestoreType::kRestored, &entries);
  controller.LoadIfNecessary();
  result->Set("restored", count);
}

// Arc's translate UI, which Cra draws (GitHub #310). Every method replies with the page's state
// (ChromeTranslateClient::CraTranslateState, patches/translate-ui.patch); Cra.getTranslateState adds the
// languages Chrome can translate to. Cra.translatePage translates to params.target, or to the language Chrome
// would pick. Cra.neverTranslateSite puts the page's host on Chrome's never-translate list, or takes it off
// with params.never false.
void Translate(content::WebContents* contents,
               const std::string& method,
               const base::DictValue* params,
               base::DictValue* result,
               std::string* error) {
  ChromeTranslateClient* client = ChromeTranslateClient::FromWebContents(contents);
  translate::TranslateManager* manager = client ? client->GetTranslateManager() : nullptr;
  if (!manager) {
    *error = "the page has no translate client";
    return;
  }
  if (method == "Cra.translatePage") {
    const std::string* target = params ? params->FindString("target") : nullptr;
    std::optional<std::string> target_code;
    if (target && !target->empty()) {
      target_code = *target;
    }
    manager->ShowTranslateUI(std::nullopt, target_code, /*auto_translate=*/true, /*triggered_from_menu=*/true);
  } else if (method == "Cra.revertTranslation") {
    if (client->GetLanguageState().IsPageTranslated()) {
      manager->RevertTranslation();
    }
  } else if (method == "Cra.neverTranslateSite") {
    const GURL& url = contents->GetLastCommittedURL();
    if (!url.has_host()) {
      *error = "the page has no site";
      return;
    }
    std::optional<bool> never = params ? params->FindBool("never") : std::nullopt;
    std::unique_ptr<translate::TranslatePrefs> prefs = client->GetTranslatePrefs();
    if (never.value_or(true)) {
      prefs->AddSiteToNeverPromptList(url.host());
    } else {
      prefs->RemoveSiteFromNeverPromptList(url.host());
    }
  }
  *result = client->CraTranslateState();
  if (method == "Cra.getTranslateState") {
    std::vector<std::string> codes;
    translate::TranslateDownloadManager::GetSupportedLanguages(/*translate_allowed=*/true, &codes);
    base::ListValue languages;
    for (const std::string& code : codes) {
      languages.Append(code);
    }
    result->Set("languages", std::move(languages));
  }
}

// Chrome's automatic Picture in Picture, which a tab strip drives in Chrome and Cra drives here. "hidden": the
// tab went out of sight; a page with an enterpictureinpicture handler that uses the camera or microphone (a
// Meet call) has it run ({"asked":bool}). "shown": the tab is in front again, which closes the window automatic
// Picture in Picture opened.
void AutoPictureInPicture(content::WebContents* contents,
                          const base::DictValue* params,
                          base::DictValue* result,
                          std::string* error) {
  auto* helper = AutoPictureInPictureTabHelper::FromWebContents(contents);
  const std::string* tab = params ? params->FindString("tab") : nullptr;
  if (!helper) {
    *error = "no automatic Picture in Picture for this page";
    return;
  }
  if (tab && *tab == "shown") {
    helper->OnTabBecameActive();
    return;
  }
  if (!tab || *tab != "hidden") {
    *error = "tab must be hidden or shown";
    return;
  }
  result->Set("pictureInPicture", PictureInPictureWindowManager::GetInstance()->GetWebContents() == contents);
  result->Set("asked", helper->CraOnTabHidden());
}

// The page's media session as Chrome routes it: the actions its navigator.mediaSession handlers take, however
// early the page set them (what CEF's MediaSessionImpl::ShouldRouteAction answered).
class MediaSessionWatch : public content::WebContentsUserData<MediaSessionWatch>,
                          public media_session::mojom::MediaSessionObserver {
 public:
  bool Routes(media_session::mojom::MediaSessionAction action) const { return actions_.count(action) > 0; }

  // media_session::mojom::MediaSessionObserver:
  void MediaSessionInfoChanged(media_session::mojom::MediaSessionInfoPtr info) override {
    if (!info || !changed_) {
      return;
    }
    using SessionState = media_session::mojom::MediaSessionInfo::SessionState;
    NSInteger state = 0;
    switch (info->state) {
      case SessionState::kActive:
        state = 1;
        break;
      case SessionState::kDucking:
        state = 2;
        break;
      case SessionState::kSuspended:
        state = 3;
        break;
      case SessionState::kInactive:
        state = 0;
        break;
    }
    // Chrome sends the whole info again for any change of it (a title, the Picture in Picture state):
    // Cra hears only a change of what it follows.
    if (reported_ && state == state_ && info->is_controllable == controllable_) {
      return;
    }
    reported_ = true;
    state_ = state;
    controllable_ = info->is_controllable;
    changed_(state, controllable_);
  }
  void MediaSessionMetadataChanged(const std::optional<media_session::MediaMetadata>& metadata) override {}
  void MediaSessionActionsChanged(const std::vector<media_session::mojom::MediaSessionAction>& actions) override {
    actions_ = std::set<media_session::mojom::MediaSessionAction>(actions.begin(), actions.end());
  }
  void MediaSessionImagesChanged(
      const base::flat_map<media_session::mojom::MediaSessionImageType, std::vector<media_session::MediaImage>>&
          images) override {}
  void MediaSessionPositionChanged(const std::optional<media_session::MediaPosition>& position) override {}

 private:
  friend class content::WebContentsUserData<MediaSessionWatch>;
  MediaSessionWatch(content::WebContents* contents, MediaSessionChanged changed)
      : content::WebContentsUserData<MediaSessionWatch>(*contents), changed_(changed) {
    content::MediaSession::Get(contents)->AddObserver(receiver_.BindNewPipeAndPassRemote());
  }

  std::set<media_session::mojom::MediaSessionAction> actions_;
  MediaSessionChanged changed_;
  bool reported_ = false;
  NSInteger state_ = 0;
  bool controllable_ = false;
  mojo::Receiver<media_session::mojom::MediaSessionObserver> receiver_{this};
  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

WEB_CONTENTS_USER_DATA_KEY_IMPL(MediaSessionWatch);

struct MediaActionName {
  media_session::mojom::MediaSessionAction action;
  const char* name;
};
constexpr MediaActionName kMediaActions[] = {
    {media_session::mojom::MediaSessionAction::kPlay, "play"},
    {media_session::mojom::MediaSessionAction::kPause, "pause"},
    {media_session::mojom::MediaSessionAction::kPreviousTrack, "previoustrack"},
    {media_session::mojom::MediaSessionAction::kNextTrack, "nexttrack"},
    {media_session::mojom::MediaSessionAction::kSeekBackward, "seekbackward"},
    {media_session::mojom::MediaSessionAction::kSeekForward, "seekforward"},
    {media_session::mojom::MediaSessionAction::kSkipAd, "skipad"},
    {media_session::mojom::MediaSessionAction::kStop, "stop"},
    {media_session::mojom::MediaSessionAction::kToggleMicrophone, "togglemicrophone"},
    {media_session::mojom::MediaSessionAction::kToggleCamera, "togglecamera"},
    {media_session::mojom::MediaSessionAction::kHangUp, "hangup"},
    {media_session::mojom::MediaSessionAction::kPreviousSlide, "previousslide"},
    {media_session::mojom::MediaSessionAction::kNextSlide, "nextslide"},
};

// Cra.mediaSession: {"actions":[names],"pictureInPicture":bool}; with params.action, runs the page's handler for
// it, as media keys do ({"handled":false} when the page has none).
void MediaSessionMethod(content::WebContents* contents,
                        const base::DictValue* params,
                        base::DictValue* result,
                        std::string* error) {
  MediaSessionWatch* watch = MediaSessionWatch::FromWebContents(contents);
  result->Set("pictureInPicture", PictureInPictureWindowManager::GetInstance()->GetWebContents() == contents);
  const std::string* name = params ? params->FindString("action") : nullptr;
  if (!name) {
    base::ListValue actions;
    for (const auto& entry : kMediaActions) {
      if (watch && watch->Routes(entry.action)) {
        actions.Append(entry.name);
      }
    }
    result->Set("actions", std::move(actions));
    return;
  }
  const MediaActionName* found = nullptr;
  for (const auto& entry : kMediaActions) {
    if (*name == entry.name) {
      found = &entry;
    }
  }
  if (!found) {
    *error = "unknown media session action";
    return;
  }
  bool routed = watch && watch->Routes(found->action);
  if (routed) {
    content::MediaSession::Get(contents)->DidReceiveAction(found->action);
  }
  result->Set("handled", routed);
}

// The page that downloads the store's CRX, as WebstoreInstallWithPrompt has one: never shown. It lives until the
// install is over, or until its profile goes away (a quit while an install runs, GitHub #227).
struct WebStoreInstallPage : public base::RefCountedThreadSafe<WebStoreInstallPage>, public ProfileObserver {
  explicit WebStoreInstallPage(Profile* profile)
      : contents(content::WebContents::Create(content::WebContents::CreateParams(profile))) {
    observation.Observe(profile);
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    observation.Reset();
    contents.reset();
  }
  std::unique_ptr<content::WebContents> contents;
  base::ScopedObservation<Profile, ProfileObserver> observation{this};

 private:
  friend class base::RefCountedThreadSafe<WebStoreInstallPage>;
  ~WebStoreInstallPage() override = default;
};

using WebStoreDone = base::OnceCallback<void(base::DictValue result, std::string error)>;

// Cra.installFromWebStore {"id","manifest"} (GitHub #203): installs a Chrome Web Store item in this page's profile
// as the store's "Add to Chrome" does: WebstoreInstaller fetches the signed CRX, CrxInstaller checks the store's
// signature, and it lands as INTERNAL and from the Web Store. No prompt: Cra asks only for extensions the person
// chose to bring over. The CEF patch's code (freezing-vote.patch).
void InstallFromWebStore(content::WebContents* contents, const base::DictValue* params, WebStoreDone done) {
  const std::string* id = params ? params->FindString("id") : nullptr;
  const base::DictValue* manifest = params ? params->FindDict("manifest") : nullptr;
  if (!id || !crx_file::id_util::IdIsValid(*id) || !manifest) {
    std::move(done).Run(base::DictValue(), "needs a valid extension id and its manifest");
    return;
  }
  Profile* profile = Profile::FromBrowserContext(contents->GetBrowserContext());
  if (!profile || profile->IsOffTheRecord()) {
    std::move(done).Run(base::DictValue(), "not in an off-the-record profile");
    return;
  }
  const extensions::Extension* installed = extensions::ExtensionRegistry::Get(profile)->GetInstalledExtension(*id);
  if (installed && installed->location() == extensions::mojom::ManifestLocation::kInternal &&
      installed->from_webstore()) {
    base::DictValue result;
    result.Set("installed", true);
    result.Set("already", true);
    std::move(done).Run(std::move(result), std::string());
    return;
  }
  std::unique_ptr<extensions::InstallApproval> approval = extensions::InstallApproval::CreateWithNoInstallPrompt(
      profile, *id, manifest->Clone(), /*strict_manifest_check=*/false);
  approval->skip_post_install_ui = true;
  approval->use_app_installed_bubble = false;
  auto page = base::MakeRefCounted<WebStoreInstallPage>(profile);
  auto split = base::SplitOnceCallback(std::move(done));
  auto installer = base::MakeRefCounted<extensions::WebstoreInstaller>(
      profile,
      base::BindOnce(
          [](scoped_refptr<WebStoreInstallPage>, WebStoreDone done, const std::string&) {
            base::DictValue result;
            result.Set("installed", true);
            std::move(done).Run(std::move(result), std::string());
          },
          page, std::move(split.first)),
      base::BindOnce(
          [](scoped_refptr<WebStoreInstallPage>, WebStoreDone done, const std::string& id, const std::string& error,
             extensions::WebstoreInstaller::FailureReason) {
            std::move(done).Run(base::DictValue(), error.empty() ? std::string("install failed") : error);
          },
          page, std::move(split.second)),
      page->contents.get(), *id, std::move(approval), extensions::WebstoreInstaller::INSTALL_SOURCE_OTHER);
  installer->Start();
}

// Cra.* methods. Fills `result` or `error`.
void HandleCraMethod(content::WebContents* contents,
                     const std::string& method,
                     const base::DictValue* params,
                     base::DictValue* result,
                     std::string* error) {
  if (method == "Cra.getHistory") {
    GetHistory(contents, result);
  } else if (method == "Cra.restoreHistory") {
    RestoreHistory(contents, params, result, error);
  } else if (method == "Cra.load") {
    // Does nothing unless the page was discarded and hasn't loaded since.
    contents->GetController().LoadIfNecessary();
  } else if (method == "Cra.discard") {
    // Like Chrome's tab discarding with WebContentsDiscard: the renderer goes, the page keeps its back and
    // forward list and each entry's state, and showing it loads it again.
    if (!base::FeatureList::IsEnabled(features::kWebContentsDiscard)) {
      *error = "discarding needs the WebContentsDiscard feature";
      return;
    }
    if (!contents->WasDiscarded()) {
      content::RenderFrameHost* main_frame = contents->GetPrimaryMainFrame();
      result->Set("processEnded", main_frame && main_frame->GetProcess()->FastShutdownIfPossible(
                                                    1u, /*skip_unload_handlers=*/false, /*ignore_workers=*/false,
                                                    /*ignore_keep_alive=*/false, /*ignore_pending_reuse=*/false,
                                                    /*use_outermost_main_frame_check=*/true));
      contents->Discard(base::DoNothing());
    }
    // False when a navigation was about to commit: Chromium keeps the page.
    result->Set("discarded", contents->WasDiscarded());
  } else if (method == "Cra.getFreezingState") {
    result->Set("vote", !!contents->GetUserData(kFreezingVoteKey));
    result->Set("liveConnection", content::CraPageHasOpenedLiveConnection(contents));
    const performance_manager::PageNode* page =
        performance_manager::PerformanceManager::GetPrimaryPageNodeForWebContents(contents).get();
    if (page && FreezingAvailable(contents)) {
      result->Set("frozen", page->GetLifecycleState() == performance_manager::mojom::LifecycleState::kFrozen);
      auto details = performance_manager::freezing::GetCanFreezeDetailsForPageNode(page);
      result->Set("reasons", ReasonList(details.cannot_freeze_reasons));
      result->Set("connectedReasons", ReasonList(details.cannot_freeze_reasons_connected_pages));
    }
  } else if (method == "Cra.setFreezingVote") {
    if (!(params && params->FindBool("vote").value_or(false))) {
      contents->RemoveUserData(kFreezingVoteKey);
    } else if (!contents->GetUserData(kFreezingVoteKey)) {
      if (!FreezingAvailable(contents)) {
        *error = "freezing is not available for this page";
        return;
      }
      contents->SetUserData(kFreezingVoteKey, std::make_unique<FreezingVoteData>(contents));
    }
  } else if (method == "Cra.reclaimMemory") {
    // Closing tabs leaves the browser process's allocator holding the pages they freed. Off the UI thread:
    // it walks every partition.
    base::ThreadPool::PostTask(FROM_HERE, {base::TaskPriority::BEST_EFFORT}, base::BindOnce([] {
                                 ::partition_alloc::MemoryReclaimer::Instance()->ReclaimAll();
                               }));
  } else if (method == "Cra.getTranslateState" || method == "Cra.translatePage" ||
             method == "Cra.revertTranslation" || method == "Cra.neverTranslateSite") {
    Translate(contents, method, params, result, error);
  } else if (method == "Cra.mediaSession") {
    MediaSessionMethod(contents, params, result, error);
  } else if (method == "Cra.autoPictureInPicture") {
    AutoPictureInPicture(contents, params, result, error);
  } else if (method == "Cra.setSpare") {
    // A page made ahead for the next tab that needs one, hidden from extensions' tabs and windows until Cra
    // gives it a tab.
    if (params && params->FindBool("spare").value_or(false)) {
      contents->SetUserData(content::CraSparePageKey(), std::make_unique<base::SupportsUserData::Data>());
    } else {
      contents->RemoveUserData(content::CraSparePageKey());
    }
  } else if (method == "Cra.extensionSidePanel") {
    // An extension's side panel page: like Chrome's, it has no tab (GitHub #265).
    extensions::SetViewType(contents, extensions::mojom::ViewType::kExtensionSidePanel);
  } else {
    // Cra.installFromWebStore is asynchronous (PageSession::Send).
    // need Cra's Chromium patches (scripts/cef-patches).
    *error = "not yet on Chrome's framework: " + method;
  }
}

}  // namespace

void WatchMediaSession(content::WebContents* contents, MediaSessionChanged changed) {
  MediaSessionWatch::CreateForWebContents(contents, changed);
}

int RestorePageHistory(content::WebContents* contents, const std::string& history, int index, std::string* error) {
  base::DictValue params;
  params.Set("history", history);
  params.Set("index", index);
  base::DictValue result;
  RestoreHistory(contents, &params, &result, error);
  return error->empty() ? result.FindInt("restored").value_or(0) : 0;
}

PageSession::PageSession(content::WebContents* contents, ProtocolEvent events)
    : contents_(contents), events_([events copy]), pending_([NSMutableDictionary dictionary]) {}

PageSession::~PageSession() {
  if (host_) {
    host_->DetachClient(this);
  }
  NSDictionary<NSNumber*, ProtocolReply>* pending = pending_;
  pending_ = [NSMutableDictionary dictionary];
  for (NSNumber* key in pending) {
    ProtocolReply reply = pending[key];
    dispatch_async(dispatch_get_main_queue(), ^{
      reply(nil, ErrorJSON("the page closed"));
    });
  }
}

void PageSession::Send(const std::string& method, const std::string& params_json, ProtocolReply reply) {
  const int id = ++next_id_;
  pending_[@(id)] = [reply copy];
  if (method == "Cra.installFromWebStore") {
    std::optional<base::DictValue> params =
        base::JSONReader::ReadDict(params_json.empty() ? "{}" : params_json, base::JSON_PARSE_RFC);
    PageSession* me = this;
    base::WeakPtr<PageSession> alive = weak_factory_.GetWeakPtr();
    InstallFromWebStore(contents_, params ? &*params : nullptr,
                        base::BindOnce(
                            [](base::WeakPtr<PageSession> alive, PageSession* me, int id, base::DictValue result,
                               std::string error) {
                              if (alive) {
                                me->Answer(id, error.empty() ? JSON(base::Value(std::move(result))) : nil,
                                           error.empty() ? nil : ErrorJSON(error));
                              }
                            },
                            alive, me, id));
    return;
  }
  if (method.rfind("Cra.", 0) == 0) {
    std::optional<base::DictValue> params =
        base::JSONReader::ReadDict(params_json.empty() ? "{}" : params_json, base::JSON_PARSE_RFC);
    base::DictValue result;
    std::string error;
    HandleCraMethod(contents_, method, params ? &*params : nullptr, &result, &error);
    // Answered like a protocol method, after the caller has returned.
    Answer(id, error.empty() ? JSON(base::Value(std::move(result))) : nil, error.empty() ? nil : ErrorJSON(error));
    return;
  }
  if (!host_) {
    host_ = content::DevToolsAgentHost::GetOrCreateFor(contents_);
    if (!host_ || !host_->AttachClient(this)) {
      host_ = nullptr;
      Answer(id, nil, ErrorJSON("no DevTools session for this page"));
      return;
    }
  }
  // Method names are plain identifiers ("Domain.method"), so no escaping is needed.
  std::string message = "{\"id\":" + std::to_string(id) + ",\"method\":\"" + method +
                        "\",\"params\":" + (params_json.empty() ? std::string("{}") : params_json) + "}";
  host_->DispatchProtocolMessage(this, base::as_byte_span(message));
}

void PageSession::Answer(int id, NSString* result, NSString* error) {
  ProtocolReply reply = pending_[@(id)];
  [pending_ removeObjectForKey:@(id)];
  if (!reply) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    reply(result, error);
  });
}

void PageSession::DispatchProtocolMessage(content::DevToolsAgentHost* host, base::span<const uint8_t> message) {
  std::string_view text(reinterpret_cast<const char*>(message.data()), message.size());
  std::optional<base::DictValue> dict = base::JSONReader::ReadDict(text, base::JSON_PARSE_RFC);
  if (!dict) {
    return;
  }
  if (std::optional<int> id = dict->FindInt("id")) {
    const base::Value* error = dict->Find("error");
    const base::Value* result = dict->Find("result");
    Answer(*id, error ? nil : (result ? JSON(*result) : @"{}"), error ? JSON(*error) : nil);
    return;
  }
  const std::string* method = dict->FindString("method");
  if (!method) {
    return;
  }
  const base::Value* params = dict->Find("params");
  events_(base::SysUTF8ToNSString(*method), params ? JSON(*params) : @"{}");
}

void PageSession::AgentHostClosed(content::DevToolsAgentHost* host) {
  host_ = nullptr;
  NSDictionary<NSNumber*, ProtocolReply>* pending = [pending_ copy];
  for (NSNumber* key in pending) {
    Answer(key.intValue, nil, ErrorJSON("the page's DevTools session closed"));
  }
}

// Cra drives its own pages, as CEF's client did: Chrome's trusted-client checks are for remote clients.
bool PageSession::IsTrusted() {
  return true;
}

bool PageSession::MayReadLocalFiles() {
  return true;
}

bool PageSession::AllowUnsafeOperations() {
  return true;
}

}  // namespace cra
