// fetch.h says what this is.

#include "cra/fetch.h"

#include <memory>
#include <set>
#include <string>

#include "base/strings/sys_string_conversions.h"
#include "base/time/time.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/storage_partition.h"
#include "net/base/load_flags.h"
#include "net/cookies/site_for_cookies.h"
#include "net/http/http_response_headers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace cra {
namespace {

constexpr net::NetworkTrafficAnnotationTag kTraffic = net::DefineNetworkTrafficAnnotation("cra_fetch", R"(
    semantics {
      sender: "Cra"
      description: "A page Cra reads for the user with their own session, as a tab of theirs would: a live folder's list (GitHub pull requests and issues)."
      trigger: "A live folder the user made refreshes."
      data: "The user's cookies for the site."
      destination: WEBSITE
    }
    policy {
      cookies_allowed: YES
      cookies_store: "user"
      setting: "Remove the live folder."
      policy_exception_justification: "Not implemented."
    })");

// Loaders stay alive until they answer.
std::set<std::unique_ptr<network::SimpleURLLoader>>& InFlight() {
  static auto* loaders = new std::set<std::unique_ptr<network::SimpleURLLoader>>();
  return *loaders;
}

}  // namespace

void Fetch(Profile* profile, const GURL& url, NSDictionary<NSString*, NSString*>* headers, bool restricted,
           FetchDone done) {
  FetchDone answer = [done copy];
  auto request = std::make_unique<network::ResourceRequest>();
  request->url = url;
  request->method = "GET";
  // Sent like the site's own page: its stored cookies, the site as its own first party.
  request->site_for_cookies = net::SiteForCookies::FromUrl(url);
  request->request_initiator = url::Origin::Create(url);
  request->credentials_mode = network::mojom::CredentialsMode::kInclude;
  request->load_flags = net::LOAD_BYPASS_CACHE;
  if (restricted) {
    request->redirect_mode = network::mojom::RedirectMode::kManual;
  }
  for (NSString* name in headers) {
    request->headers.SetHeader(base::SysNSStringToUTF8(name), base::SysNSStringToUTF8(headers[name]));
  }
  std::unique_ptr<network::SimpleURLLoader> owned = network::SimpleURLLoader::Create(std::move(request), kTraffic);
  network::SimpleURLLoader* loader = owned.get();
  if (restricted) {
    loader->SetTimeoutDuration(base::Seconds(20));
  }
  InFlight().insert(std::move(owned));
  auto factory = profile->GetDefaultStoragePartition()->GetURLLoaderFactoryForBrowserProcess();
  loader->DownloadToString(
      factory.get(),
      base::BindOnce(
          [](network::SimpleURLLoader* loader, GURL asked, bool restricted, FetchDone answer,
             std::optional<std::string> body) {
            const network::mojom::URLResponseHead* head = loader->ResponseInfo();
            int code = head && head->headers ? head->headers->response_code() : 0;
            bool redirect = restricted && code >= 300 && code < 400;
            NSInteger status = (body || redirect) ? code : 0;
            GURL final_url = loader->GetFinalURL().is_valid() ? loader->GetFinalURL() : asked;
            if (redirect) {
              if (std::optional<std::string> location = head->headers->GetNormalizedHeader("Location")) {
                GURL next = final_url.Resolve(*location);
                if (next.is_valid()) {
                  final_url = next;
                }
              }
            }
            NSString* mime = head ? base::SysUTF8ToNSString(head->mime_type) : @"";
            NSString* text = body ? (base::SysUTF8ToNSString(*body) ?: @"") : @"";
            NSString* where = base::SysUTF8ToNSString(final_url.spec());
            for (auto it = InFlight().begin(); it != InFlight().end(); ++it) {
              if (it->get() == loader) {
                InFlight().erase(it);
                break;
              }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
              answer(status, where, mime, text);
            });
          },
          loader, url, restricted, answer),
      restricted ? 4 * 1024 * 1024 : 64 * 1024 * 1024);
}

}  // namespace cra
