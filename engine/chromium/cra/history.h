// A profile's Chromium history searched for the command bar, as Arc's searchHistory asks the profile's
// HistoryService (GitHub #730): ⌘T finds every page the profile has, not only the newest few thousand.
#ifndef CRA_HISTORY_H_
#define CRA_HISTORY_H_

#import <Foundation/Foundation.h>

class Profile;

namespace cra {

// Every page of `profile`'s history whose title or address has a word starting with each word of `text`
// (Chrome's History page search, every word a prefix), the most recently visited first, at most `max_count`.
// Each row: url, title, visitCount, typedCount, lastVisit (seconds since 1970). On the main queue; empty when
// the profile has no history service, or when a newer search started before this one reached the database.
using HistorySearchDone = void (^)(NSArray<NSDictionary<NSString*, id>*>* rows);
void SearchHistory(Profile* profile, NSString* text, NSInteger max_count, HistorySearchDone done);

}  // namespace cra

#endif  // CRA_HISTORY_H_
