A made-up Chromium profile (Default/) in Chromium's own formats, for the importer tests and
the parser fuzzer (scripts/test-store.sh, scripts/fuzz.sh): a version 3 SNSS session with a
closed tab, a tab with two navigations, a new tab page and tabs on a file:, a javascript:, a
chrome://settings, an about:blank and a blob: address (appended as SetTabWindow,
SetTabIndexInWindow and UpdateTabNavigation commands); Bookmarks with a nested, an empty and a
file: entry, a folder of a javascript: and a chrome:// bookmark, and one of only blank, new tab and
blob: bookmarks; Preferences with one extension on, one turned off, one Chrome turned off only for being
Manifest V2 (disable reason 1 << 23, which Cra doesn't apply) and one turned off for both reasons. Every web address is on
example.com.
