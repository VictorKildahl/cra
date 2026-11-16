// Cra's hook into Chrome's permission prompts (engine/chromium in the Cra repository; patches/cra-permissions.patch).
// //cra sets it; Chrome never does.
#ifndef CHROME_BROWSER_CRA_PERMISSION_HOOK_H_
#define CHROME_BROWSER_CRA_PERMISSION_HOOK_H_

#include <memory>

#include "components/permissions/permission_prompt.h"

namespace cra {

// The prompt for a page of Cra's: Cra's own (its app asks), or nullptr for a page that isn't Cra's, which gets
// Chrome's.
using PermissionPromptHook = std::unique_ptr<permissions::PermissionPrompt> (*)(
    content::WebContents* web_contents,
    permissions::PermissionPrompt::Delegate* delegate);
inline PermissionPromptHook g_permission_prompt = nullptr;

}  // namespace cra

#endif  // CHROME_BROWSER_CRA_PERMISSION_HOOK_H_
