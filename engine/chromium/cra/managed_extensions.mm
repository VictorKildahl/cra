#include "cra/managed_extensions.h"

#include <memory>
#include <utility>
#include <vector>

#include "base/functional/callback_helpers.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/cra_engine_hooks.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/browser_context.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/management_policy.h"
#include "extensions/common/extension.h"

namespace cra {
namespace {

std::map<std::string, std::set<std::string>>& IdsByProfile() {
  static auto* ids = new std::map<std::string, std::set<std::string>>();
  return *ids;
}

bool Manages(const std::string& profile, const std::string& extension_id) {
  auto it = IdsByProfile().find(profile);
  return it != IdsByProfile().end() && it->second.count(extension_id);
}

// One per profile folder, asked by that profile's ManagementPolicy. Only MustRemainInstalled: the person can still
// turn the extension off or on in a profile, and change its site access, as for any other.
class Provider : public extensions::ManagementPolicy::Provider {
 public:
  explicit Provider(std::string profile) : profile_(std::move(profile)) {}

  std::string GetDebugPolicyProviderName() const override { return "Cra shared extensions"; }

  bool MustRemainInstalled(const extensions::Extension* extension, std::u16string* error) const override {
    if (!extension || !Manages(profile_, extension->id())) {
      return false;
    }
    if (error) {
      *error = u"Cra manages this extension. Remove it, or choose its profiles, in Cra's Settings ▸ Extensions.";
    }
    return true;
  }

 private:
  const std::string profile_;
};

std::map<std::string, std::unique_ptr<Provider>>& Providers() {
  static auto* providers = new std::map<std::string, std::unique_ptr<Provider>>();
  return *providers;
}

std::string FolderOf(const Profile* profile) {
  return profile->GetOriginalProfile()->GetBaseName().AsUTF8Unsafe();
}

bool ManagedByCra(content::BrowserContext* context, const std::string& extension_id) {
  return context && IsManagedExtension(Profile::FromBrowserContext(context), extension_id);
}

std::map<std::string, SharedStorage>& StorageByExtension() {
  static auto* map = new std::map<std::string, SharedStorage>();
  return *map;
}

// The loaded profile in `folder`, nil when it hasn't loaded (this never loads one).
Profile* LoadedProfile(const std::string& folder) {
  ProfileManager* manager = g_browser_process ? g_browser_process->profile_manager() : nullptr;
  if (!manager) {
    return nullptr;
  }
  return manager->GetProfileByPath(manager->user_data_dir().AppendASCII(folder));
}

const SharedStorage* SharedStorageOf(content::BrowserContext* context, const std::string& extension_id,
                                     std::string* folder) {
  if (!context) {
    return nullptr;
  }
  auto it = StorageByExtension().find(extension_id);
  if (it == StorageByExtension().end()) {
    return nullptr;
  }
  *folder = FolderOf(Profile::FromBrowserContext(context));
  return it->second.profiles.count(*folder) ? &it->second : nullptr;
}

// Loads the profile in `folder` in the background if it hasn't loaded: a shared extension's data lives there.
void LoadSoon(const std::string& folder) {
  ProfileManager* manager = g_browser_process ? g_browser_process->profile_manager() : nullptr;
  if (!manager || LoadedProfile(folder)) {
    return;
  }
  manager->LoadProfileByPath(manager->user_data_dir().AppendASCII(folder), /*incognito=*/false, base::DoNothing());
}

content::BrowserContext* StorageContext(content::BrowserContext* context, const std::string& extension_id) {
  std::string folder;
  const SharedStorage* shared = SharedStorageOf(context, extension_id, &folder);
  if (!shared || shared->home == folder) {
    return context;
  }
  Profile* home = LoadedProfile(shared->home);
  if (!home) {
    // Not loaded yet (SetSharedExtensionStorage started it): this profile's own data until it has.
    LoadSoon(shared->home);
    return context;
  }
  return home;
}

std::vector<content::BrowserContext*> StoragePeers(content::BrowserContext* context, const std::string& extension_id) {
  std::vector<content::BrowserContext*> peers;
  std::string folder;
  const SharedStorage* shared = SharedStorageOf(context, extension_id, &folder);
  // Only the home's frontend owns the data, so only it relays.
  if (!shared || shared->home != folder) {
    return peers;
  }
  for (const std::string& profile : shared->profiles) {
    if (profile == folder) {
      continue;
    }
    if (Profile* peer = LoadedProfile(profile)) {
      peers.push_back(peer);
    }
  }
  return peers;
}

}  // namespace

void SetSharedExtensionStorage(std::map<std::string, SharedStorage> by_extension) {
  StorageByExtension() = std::move(by_extension);
  g_extension_storage_context = &StorageContext;
  g_extension_storage_peers = &StoragePeers;
  // Each home loads now, so its data is there when an extension in another profile starts.
  for (const auto& [id, shared] : StorageByExtension()) {
    LoadSoon(shared.home);
  }
}

void SetManagedExtensions(std::map<std::string, std::set<std::string>> ids_by_profile) {
  IdsByProfile() = std::move(ids_by_profile);
}

void WatchManagedExtensions(Profile* profile) {
  g_extension_managed = &ManagedByCra;
  if (!profile || profile->IsOffTheRecord()) {
    return;
  }
  extensions::ExtensionSystem* system = extensions::ExtensionSystem::Get(profile);
  extensions::ManagementPolicy* policy = system ? system->management_policy() : nullptr;
  if (!policy) {
    return;
  }
  std::unique_ptr<Provider>& provider = Providers()[FolderOf(profile)];
  if (!provider) {
    provider = std::make_unique<Provider>(FolderOf(profile));
  }
  // A set: a profile loaded again registers the same provider once.
  policy->RegisterProvider(provider.get());
}

bool IsManagedExtension(const Profile* profile, const std::string& extension_id) {
  return profile && Manages(FolderOf(profile), extension_id);
}

}  // namespace cra
