// Shared extensions (GitHub discussion #595): an extension Cra's Settings ▸ Extensions keeps in every profile, or
// every one the person left it in. Cra decides which; Chrome keeps it installed there (a ManagementPolicy provider:
// chrome://extensions has no Remove for it, chrome.management.uninstall and the Web Store's "Remove from Chrome"
// are refused) and chrome://extensions says it is managed by Cra (patches/extension-managed-by-cra.patch).
#ifndef CRA_MANAGED_EXTENSIONS_H_
#define CRA_MANAGED_EXTENSIONS_H_

#include <map>
#include <set>
#include <string>

class Profile;

namespace cra {

// Profile folder name ("Default", "Profile <id>") → the extension IDs Cra manages there. Replaces the whole map;
// profiles that load later take theirs as they load.
void SetManagedExtensions(std::map<std::string, std::set<std::string>> ids_by_profile);

// A profile loaded (cra/profile_prefs.mm): its management policy asks Cra from now on.
void WatchManagedExtensions(Profile* profile);

// Whether Cra manages `extension_id` in `profile`.
bool IsManagedExtension(const Profile* profile, const std::string& extension_id);

// chrome://extensions' words for it.
inline constexpr char kManagedByCra[] = "Managed by Cra";

}  // namespace cra

#endif  // CRA_MANAGED_EXTENSIONS_H_
