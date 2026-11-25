A data folder whose Default profile has a Chromium `History` (schema version 70, Chrome 159) with two pages
that Cra's own history.json doesn't have, for `command-bar-whole-history.scenario` (#730):

- `https://haystack-recent.example.com/` "Haystack recent page", visited 10 days before the fixture was made
- `https://haystack-ancient.example.com/` "Haystack ancient page", visited 400 days before: Chrome's 90-day
  expiry would delete it

Made with the `.schema` of an engine-written History and Python's sqlite3 (times are Chrome's: microseconds
since 1601). No real browsing in it.
