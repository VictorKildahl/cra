// A page's own DevTools protocol session, as CEF's SendDevToolsMessage gave the CEF bridge: what
// -[CraBrowser sendDevToolsMethod:params:completion:] uses. Cra's own methods (Cra.*, which CEF answered in
// scripts/cef-patches/freezing-vote.patch) are answered here, in the browser process, without the page.
#ifndef CRA_PAGE_PROTOCOL_H_
#define CRA_PAGE_PROTOCOL_H_

#import <Foundation/Foundation.h>

#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "content/public/browser/devtools_agent_host_client.h"

namespace content {
class DevToolsAgentHost;
class WebContents;
}  // namespace content

namespace cra {

// Result JSON (the reply's "result" object) or error JSON (its "error" object), on the main queue.
using ProtocolReply = void (^)(NSString* result, NSString* error);
// An event: its method and its params JSON.
using ProtocolEvent = void (^)(NSString* method, NSString* params);

// The page's media session changed: its state as CraCEF.h's CraMediaSessionState (0 inactive, 1 active,
// 2 ducking, 3 suspended) and whether Chrome's global media controls offer it (MediaSessionImpl::IsControllable).
using MediaSessionChanged = void (^)(NSInteger state, bool controllable);

// Starts following the page's media session (the actions its handlers take, for Cra.mediaSession, and its
// state, for `changed`). Once per page, as it is made.
void WatchMediaSession(content::WebContents* contents, MediaSessionChanged changed);

// Puts a saved back and forward list (Cra.getHistory's "history", base64) into a page that hasn't navigated yet
// and loads entry `index`, as Cra.restoreHistory does. The number of entries, or 0 with `error` set.
int RestorePageHistory(content::WebContents* contents, const std::string& history, int index, std::string* error);

class PageSession : public content::DevToolsAgentHostClient {
 public:
  PageSession(content::WebContents* contents, ProtocolEvent events);
  PageSession(const PageSession&) = delete;
  PageSession& operator=(const PageSession&) = delete;
  ~PageSession() override;

  void Send(const std::string& method, const std::string& params_json, ProtocolReply reply);

  // content::DevToolsAgentHostClient:
  void DispatchProtocolMessage(content::DevToolsAgentHost* host, base::span<const uint8_t> message) override;
  void AgentHostClosed(content::DevToolsAgentHost* host) override;
  bool IsTrusted() override;
  bool MayReadLocalFiles() override;
  bool AllowUnsafeOperations() override;

 private:
  void Answer(int id, NSString* result, NSString* error);

  raw_ptr<content::WebContents> contents_;
  scoped_refptr<content::DevToolsAgentHost> host_;
  ProtocolEvent events_;
  NSMutableDictionary<NSNumber*, ProtocolReply>* pending_;
  int next_id_ = 100000;  // clear of ids Chromium's own clients use, as in the CEF bridge
  base::WeakPtrFactory<PageSession> weak_factory_{this};
};

}  // namespace cra

#endif  // CRA_PAGE_PROTOCOL_H_
