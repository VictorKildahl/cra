// Cra's permission prompt (chrome/browser/cra_permission_hook.h): Chrome's permission request manager makes one
// for a page of Cra's instead of its bubble, and Cra's app asks (Arc's card over the page, GitHub #371), as the
// CEF bridge's OnShowPermissionPrompt did.

#include "cra/permission_prompt.h"

#include <optional>
#include <vector>

#include "base/memory/weak_ptr.h"
#include "base/strings/sys_string_conversions.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/permission_uma_constants.h"
#include "components/permissions/request_type.h"
#include "components/permissions/resolvers/permission_prompt_options.h"
#include "url/gurl.h"

namespace cra {
namespace {

using permissions::RequestType;

// Chrome's request types as CraCEF.h's `kinds` bits, the CEF bridge's kPermissionKinds: 1 camera, 2 microphone,
// 4 location, 8 notifications, 16 a type with no bit, and from 1 << 5 Chrome's other types.
NSUInteger KindOf(RequestType type) {
  switch (type) {
    case RequestType::kCameraStream:
    case RequestType::kCameraPanTiltZoom:
      return 1;
    case RequestType::kMicStream:
      return 2;
    case RequestType::kGeolocation:
      return 4;
    case RequestType::kNotifications:
      return 8;
    case RequestType::kClipboard:
      return 1 << 5;
    case RequestType::kWindowManagement:
      return 1 << 6;
    case RequestType::kLocalNetwork:
      return 1 << 7;
    case RequestType::kLoopbackNetwork:
      return 1 << 8;
    case RequestType::kStorageAccess:
      return 1 << 9;
    case RequestType::kTopLevelStorageAccess:
      return 1 << 10;
    case RequestType::kLocalFonts:
      return 1 << 11;
    case RequestType::kIdleDetection:
      return 1 << 12;
    case RequestType::kMidiSysex:
      return 1 << 13;
    case RequestType::kMultipleDownloads:
      return 1 << 14;
    case RequestType::kKeyboardLock:
      return 1 << 15;
    case RequestType::kPointerLock:
      return 1 << 16;
    case RequestType::kRegisterProtocolHandler:
      return 1 << 18;
    case RequestType::kArSession:
      return 1 << 19;
    case RequestType::kVrSession:
      return 1 << 20;
    case RequestType::kHandTracking:
      return 1 << 21;
    case RequestType::kSensors:
      return 1 << 22;
    case RequestType::kDiskQuota:
      return 1 << 23;
    case RequestType::kIdentityProvider:
      return 1 << 24;
    case RequestType::kCapturedSurfaceControl:
      return 1 << 25;
    case RequestType::kWebAppInstallation:
      return 1 << 26;
    case RequestType::kFileSystemAccess:
      return 1 << 27;
    case RequestType::kAmbientLogin:
      return 1 << 28;
    default:
      return 16;
  }
}

class Prompt : public permissions::PermissionPrompt {
 public:
  Prompt(permissions::PermissionPrompt::Delegate* delegate, PermissionAsker ask, PermissionWithdrawn withdrawn)
      : delegate_(delegate->GetWeakPtr()), withdrawn_(withdrawn) {
    NSUInteger kinds = 0;
    for (const auto& request : delegate->Requests()) {
      kinds |= KindOf(request->request_type());
    }
    NSString* origin = base::SysUTF8ToNSString(delegate->GetRequestingOrigin().spec());
    base::WeakPtr<Prompt> me = weak_factory_.GetWeakPtr();
    ask(origin, kinds, ^(BOOL allowed) {
      if (!me || !me->delegate_) {
        return;
      }
      me->answered_ = true;
      // Accepting or denying finishes the request, which can delete this prompt: nothing of it after.
      base::WeakPtr<permissions::PermissionPrompt::Delegate> requests = me->delegate_;
      if (allowed) {
        requests->Accept(std::monostate());
      } else {
        requests->Deny(std::monostate());
      }
    });
  }

  // Chrome dropped the request before Cra answered (the page navigated or closed, or a newer request took its
  // place): Cra's card for it goes (GitHub #286).
  ~Prompt() override {
    if (!answered_ && withdrawn_) {
      withdrawn_();
    }
  }

  bool UpdateAnchor() override { return true; }
  TabSwitchingBehavior GetTabSwitchingBehavior() override { return kKeepPromptAlive; }
  permissions::PermissionPromptDisposition GetPromptDisposition() const override {
    return permissions::PermissionPromptDisposition::ANCHORED_BUBBLE;
  }
  bool IsAskPrompt() const override { return true; }
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override { return std::nullopt; }
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants() const override { return {}; }
  std::optional<permissions::feature_params::PermissionElementPromptPosition> GetPromptPosition() const override {
    return std::nullopt;
  }

 private:
  base::WeakPtr<permissions::PermissionPrompt::Delegate> delegate_;
  PermissionWithdrawn withdrawn_;
  bool answered_ = false;
  base::WeakPtrFactory<Prompt> weak_factory_{this};
};

}  // namespace

std::unique_ptr<permissions::PermissionPrompt> MakePermissionPrompt(permissions::PermissionPrompt::Delegate* delegate,
                                                                    PermissionAsker ask,
                                                                    PermissionWithdrawn withdrawn) {
  return std::make_unique<Prompt>(delegate, ask, withdrawn);
}

}  // namespace cra
