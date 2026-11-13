// Cra's permission prompt (permission_prompt.mm says what it is).
#ifndef CRA_PERMISSION_PROMPT_H_
#define CRA_PERMISSION_PROMPT_H_

#import <Foundation/Foundation.h>

#include <memory>

#include "components/permissions/permission_prompt.h"

namespace cra {

// Asks Cra's app: the requesting origin and CraCEF.h's `kinds` bits; `answer` once decided.
using PermissionAsker = void (^)(NSString* origin, NSUInteger kinds, void (^answer)(BOOL allowed));
// Chrome dropped the request before the app answered.
using PermissionWithdrawn = void (^)(void);

std::unique_ptr<permissions::PermissionPrompt> MakePermissionPrompt(permissions::PermissionPrompt::Delegate* delegate,
                                                                    PermissionAsker ask,
                                                                    PermissionWithdrawn withdrawn);

}  // namespace cra

#endif  // CRA_PERMISSION_PROMPT_H_
