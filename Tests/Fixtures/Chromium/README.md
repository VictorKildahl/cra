A made-up Chromium profile (Default/) in Chromium's own formats, for the importer tests and
the parser fuzzer (scripts/test-store.sh, scripts/fuzz.sh): a version 3 SNSS session with a
closed tab, a tab with two navigations and a chrome:// page; Bookmarks with a nested, an empty
and a file: entry; Preferences with one extension on, one turned off, one Chrome turned off only for being
Manifest V2 (disable reason 1 << 23, which Cra doesn't apply) and one turned off for both reasons. Every address is on
example.com.
