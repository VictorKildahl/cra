// history.h says what this is.

#include "cra/history.h"

#include <algorithm>
#include <atomic>
#include <memory>
#include <string>

#include "base/location.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/cancelable_task_tracker.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/history/core/browser/history_backend.h"
#include "components/history/core/browser/history_database.h"
#include "components/history/core/browser/history_db_task.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/url_row.h"
#include "components/keyed_service/core/service_access_type.h"
#include "components/query_parser/query_parser.h"
#include "url/gurl.h"

namespace cra {
namespace {

// Each keystroke starts a search; one that a newer search overtook before the history thread reached it skips
// the scan, so fast typing doesn't queue a scan of the whole history per letter.
std::atomic<uint64_t> g_latest_search{0};

base::CancelableTaskTracker& Tracker() {
  static base::NoDestructor<base::CancelableTaskTracker> tracker;
  return *tracker;
}

// Runs on the history thread: the matching URL rows only (QueryHistory also reads every visit of every match,
// which on a long history and a short word takes seconds).
class SearchTask : public history::HistoryDBTask {
 public:
  SearchTask(std::u16string text, size_t max_count, uint64_t search, HistorySearchDone done)
      : text_(std::move(text)), max_count_(max_count), search_(search), done_([done copy]) {}

  bool RunOnDBThread(history::HistoryBackend* backend, history::HistoryDatabase* db) override {
    if (!db || search_ != g_latest_search.load()) {
      return true;
    }
    history::URLRows rows =
        db->GetTextMatchesWithAlgorithm(text_, query_parser::MatchingAlgorithm::ALWAYS_PREFIX_SEARCH);
    std::sort(rows.begin(), rows.end(), [](const history::URLRow& a, const history::URLRow& b) {
      return a.last_visit() > b.last_visit();
    });
    if (rows.size() > max_count_) {
      rows.resize(max_count_);
    }
    rows_ = std::move(rows);
    return true;
  }

  void DoneRunOnMainThread() override {
    NSMutableArray<NSDictionary<NSString*, id>*>* out = [NSMutableArray arrayWithCapacity:rows_.size()];
    for (const history::URLRow& row : rows_) {
      [out addObject:@{
        @"url" : base::SysUTF8ToNSString(row.url().spec()),
        @"title" : base::SysUTF16ToNSString(row.title()),
        @"visitCount" : @(row.visit_count()),
        @"typedCount" : @(row.typed_count()),
        @"lastVisit" : @(row.last_visit().InSecondsFSinceUnixEpoch()),
      }];
    }
    done_(out);
  }

 private:
  const std::u16string text_;
  const size_t max_count_;
  const uint64_t search_;
  HistorySearchDone done_;
  history::URLRows rows_;
};

}  // namespace

void SearchHistory(Profile* profile, NSString* text, NSInteger max_count, HistorySearchDone done) {
  HistorySearchDone answer = [done copy];
  history::HistoryService* service =
      profile ? HistoryServiceFactory::GetForProfile(profile, ServiceAccessType::EXPLICIT_ACCESS) : nullptr;
  std::u16string query = base::SysNSStringToUTF16(text ?: @"");
  if (!service || query.empty() || max_count <= 0) {
    answer(@[]);
    return;
  }
  uint64_t search = ++g_latest_search;
  service->ScheduleDBTask(FROM_HERE,
                          std::make_unique<SearchTask>(std::move(query), static_cast<size_t>(max_count), search, answer),
                          &Tracker());
}

bool DeleteHistoryURL(Profile* profile, NSString* url) {
  history::HistoryService* service =
      profile ? HistoryServiceFactory::GetForProfile(profile, ServiceAccessType::EXPLICIT_ACCESS) : nullptr;
  GURL page(base::SysNSStringToUTF8(url ?: @""));
  if (!service || !page.is_valid()) {
    return false;
  }
  service->DeleteURLs({page});
  return true;
}

}  // namespace cra
