// profile_prefs.h says what this is. Each setting says why Cra sets it where the CEF bridge did
// (Sources/CraCEF/CraCEF.mm, ApplyProfilePreferences and the secure DNS observers).

#include "cra/profile_prefs.h"

#include <map>
#include <memory>
#include <optional>

#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_multi_source_observation.h"
#include "base/strings/sys_string_conversions.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_manager_observer.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/themes/theme_service_factory.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"

namespace cra {
namespace {

bool g_https_only = false;
bool g_fingerprinting = false;
NSInteger g_website_appearance = 0;
bool g_stopped = false;
void (^g_profile_loaded)(NSString*) = nil;
void (^g_extension_settings_changed)(void) = nil;
void (^g_secure_dns_changed)(void) = nil;
bool g_extension_settings_pending = false;
bool g_secure_dns_pending = false;

// Cra's own pref (patches/cra-prefs.patch), read by fingerprinting-protection.patch: pages get a seed for the
// profile and launch, and Blink noises canvas, WebGL and offline audio readback with it.
constexpr char kFingerprintingProtection[] = "cra.fingerprinting_protection";

void ApplyWebsiteAppearance(Profile* profile) {
  ThemeService* themes = ThemeServiceFactory::GetForProfile(profile);
  if (!themes) {
    return;
  }
  auto scheme = g_website_appearance == 1   ? ThemeService::BrowserColorScheme::kLight
                : g_website_appearance == 2 ? ThemeService::BrowserColorScheme::kDark
                                            : ThemeService::BrowserColorScheme::kSystem;
  if (themes->GetBrowserColorScheme() != scheme) {
    themes->SetBrowserColorScheme(scheme);
  }
}

void ApplySettings(Profile* profile) {
  PrefService* prefs = profile->GetPrefs();
  ApplyWebsiteAppearance(profile);
  // No local address offered to WebRTC at all, so nothing is announced over mDNS and macOS never asks for
  // Local Network access for a page's peer connection.
  prefs->SetString("webrtc.ip_handling_policy", "default_public_interface_only");
  // Cra shows downloads in its own sidebar.
  prefs->SetBoolean("download_bubble.partial_view_enabled", false);
  // Every download asks where to go, and Cra's app answers (its save panel or its Downloads folder;
  // patches/cra-downloads.patch).
  prefs->SetBoolean("download.prompt_for_download", true);
  prefs->SetBoolean("https_only_mode_enabled", g_https_only);
  if (prefs->FindPreference(kFingerprintingProtection)) {
    prefs->SetBoolean(kFingerprintingProtection, g_fingerprinting);
  }
}

// Every profile of Chrome's, including each one's off-the-record profile.
template <typename Function>
void ForEachProfile(Function function) {
  if (!g_browser_process || !g_browser_process->profile_manager()) {
    return;
  }
  for (Profile* profile : g_browser_process->profile_manager()->GetLoadedProfiles()) {
    function(profile);
    for (Profile* off_the_record : profile->GetAllOffTheRecordProfiles()) {
      function(off_the_record);
    }
  }
}

// Picking a provider changes mode and templates one after the other: one call for both.
void NotifySecureDNS() {
  if (!g_secure_dns_changed || g_secure_dns_pending || g_stopped) {
    return;
  }
  g_secure_dns_pending = true;
  dispatch_async(dispatch_get_main_queue(), ^{
    g_secure_dns_pending = false;
    if (g_secure_dns_changed && !g_stopped) {
      g_secure_dns_changed();
    }
  });
}

// An install changes extensions.settings several times in a row: one reload for all of them. On disk the pref
// lags ~10 s behind (Chrome's pref writer batches), so the app reads the live one (GitHub #43).
void NotifyExtensionSettings() {
  if (!g_extension_settings_changed || g_extension_settings_pending || g_stopped) {
    return;
  }
  g_extension_settings_pending = true;
  dispatch_async(dispatch_get_main_queue(), ^{
    g_extension_settings_pending = false;
    if (g_extension_settings_changed && !g_stopped) {
      g_extension_settings_changed();
    }
  });
}

class Profiles : public ProfileManagerObserver, public ProfileObserver {
 public:
  void Start() {
    manager_ = g_browser_process->profile_manager();
    manager_->AddObserver(this);
    for (Profile* profile : manager_->GetLoadedProfiles()) {
      Added(profile, /*notify=*/false);
    }
    local_state_.Init(g_browser_process->local_state());
    for (const char* name : {"dns_over_https.mode", "dns_over_https.templates"}) {
      local_state_.Add(name, base::BindRepeating(&NotifySecureDNS));
    }
  }

  void Stop() {
    local_state_.RemoveAll();
    extension_settings_.clear();
  }

  // ProfileManagerObserver:
  void OnProfileAdded(Profile* profile) override { Added(profile, /*notify=*/true); }
  void OnProfileManagerDestroying() override {
    observations_.RemoveAllObservations();
    // The manager being destroyed: g_browser_process no longer returns it.
    manager_->RemoveObserver(this);
    manager_ = nullptr;
    Stop();
  }

  // ProfileObserver:
  void OnOffTheRecordProfileCreated(Profile* off_the_record) override { ApplySettings(off_the_record); }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    extension_settings_.erase(profile);
    observations_.RemoveObservation(profile);
  }

 private:
  void Added(Profile* profile, bool notify) {
    ApplySettings(profile);
    if (!observations_.IsObservingSource(profile)) {
      observations_.AddObservation(profile);
    }
    auto registrar = std::make_unique<PrefChangeRegistrar>();
    registrar->Init(profile->GetPrefs());
    registrar->Add("extensions.settings", base::BindRepeating(&NotifyExtensionSettings));
    extension_settings_[profile] = std::move(registrar);
    // The app hears about every profile but Default, which loads first (as from the CEF bridge).
    if (notify && g_profile_loaded && profile->GetBaseName().value() != "Default") {
      NSString* path = base::SysUTF8ToNSString(profile->GetPath().value());
      dispatch_async(dispatch_get_main_queue(), ^{
        if (g_profile_loaded && !g_stopped) {
          g_profile_loaded(path);
        }
      });
    }
  }

  raw_ptr<ProfileManager> manager_ = nullptr;
  base::ScopedMultiSourceObservation<Profile, ProfileObserver> observations_{this};
  PrefChangeRegistrar local_state_;
  std::map<Profile*, std::unique_ptr<PrefChangeRegistrar>> extension_settings_;
};

Profiles& TheProfiles() {
  static auto* profiles = new Profiles();
  return *profiles;
}

}  // namespace

void StartProfilePrefs() {
  TheProfiles().Start();
  NotifySecureDNS();
}

void StopProfilePrefs() {
  g_stopped = true;
  TheProfiles().Stop();
}

void SetHttpsOnly(bool enabled) {
  g_https_only = enabled;
  ForEachProfile([](Profile* profile) { profile->GetPrefs()->SetBoolean("https_only_mode_enabled", g_https_only); });
}

void SetFingerprintingProtection(bool enabled) {
  g_fingerprinting = enabled;
  ForEachProfile([](Profile* profile) {
    if (profile->GetPrefs()->FindPreference(kFingerprintingProtection)) {
      profile->GetPrefs()->SetBoolean(kFingerprintingProtection, g_fingerprinting);
    }
  });
}

void SetWebsiteAppearance(NSInteger mode) {
  g_website_appearance = mode;
  ForEachProfile([](Profile* profile) {
    if (!profile->IsOffTheRecord()) {
      ApplyWebsiteAppearance(profile);
    }
  });
}

NSInteger WebsiteAppearance() {
  return g_website_appearance;
}

NSString* SecureDNSPreference(const char* name) {
  if (g_stopped || !g_browser_process || !g_browser_process->local_state()) {
    return nil;
  }
  const PrefService::Preference* pref = g_browser_process->local_state()->FindPreference(name);
  if (!pref || !pref->GetValue()->is_string()) {
    return nil;
  }
  return base::SysUTF8ToNSString(pref->GetValue()->GetString());
}

bool SecureDNSIsManaged() {
  PrefService* local = g_browser_process ? g_browser_process->local_state() : nullptr;
  if (!local || g_stopped) {
    return false;
  }
  for (const char* name : {"dns_over_https.mode", "dns_over_https.templates"}) {
    const PrefService::Preference* pref = local->FindPreference(name);
    if (pref && !pref->IsUserModifiable()) {
      return true;
    }
  }
  return false;
}

bool SetSecureDNS(NSString* mode, NSString* templates) {
  PrefService* local = g_browser_process ? g_browser_process->local_state() : nullptr;
  if (!local || g_stopped || SecureDNSIsManaged()) {
    return false;
  }
  // Provider first when turning secure on, mode first otherwise, so the network service never sees "secure"
  // without a server in between.
  if ([mode isEqualToString:@"secure"]) {
    local->SetString("dns_over_https.templates", base::SysNSStringToUTF8(templates));
    local->SetString("dns_over_https.mode", base::SysNSStringToUTF8(mode));
  } else {
    local->SetString("dns_over_https.mode", base::SysNSStringToUTF8(mode));
    local->SetString("dns_over_https.templates", base::SysNSStringToUTF8(templates));
  }
  return true;
}

void SetSecureDNSHandler(void (^handler)(void)) {
  g_secure_dns_changed = [handler copy];
  if (g_browser_process && g_browser_process->local_state()) {
    NotifySecureDNS();
  }
}

NSString* PreferenceJSON(Profile* profile, NSString* name) {
  if (!profile || g_stopped) {
    return nil;
  }
  const PrefService::Preference* pref = profile->GetPrefs()->FindPreference(base::SysNSStringToUTF8(name));
  if (!pref) {
    return nil;
  }
  std::string json;
  base::JSONWriter::Write(*pref->GetValue(), &json);
  return base::SysUTF8ToNSString(json);
}

bool SetPreferenceJSON(Profile* profile, NSString* name, NSString* json) {
  if (!profile || g_stopped) {
    return false;
  }
  std::string key = base::SysNSStringToUTF8(name);
  const PrefService::Preference* pref = profile->GetPrefs()->FindPreference(key);
  std::optional<base::Value> value = base::JSONReader::Read(base::SysNSStringToUTF8(json), base::JSON_PARSE_RFC);
  if (!pref || !pref->IsUserModifiable() || !value || value->type() != pref->GetType()) {
    return false;
  }
  profile->GetPrefs()->Set(key, *value);
  return true;
}

bool ResetPreference(Profile* profile, NSString* name) {
  if (!profile || g_stopped) {
    return false;
  }
  std::string key = base::SysNSStringToUTF8(name);
  const PrefService::Preference* pref = profile->GetPrefs()->FindPreference(key);
  if (!pref || !pref->IsUserModifiable()) {
    return false;
  }
  profile->GetPrefs()->ClearPref(key);
  return true;
}

void SetProfileLoadedHandler(void (^handler)(NSString*)) {
  g_profile_loaded = [handler copy];
}

void SetExtensionSettingsHandler(void (^handler)(void)) {
  g_extension_settings_changed = [handler copy];
}

}  // namespace cra
