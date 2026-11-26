#include "cra/managed_extensions.h"

#include <memory>
#include <utility>

#include "base/strings/utf_string_conversions.h"
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

}  // namespace

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
