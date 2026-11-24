A made-up Arc profile in Arc's own file format (Arc 1.170 field names), for the importer
tests (scripts/test-store.sh) and the onboarding-import scenario (CRA_ARC_DIR). No real
browsing data: every web address is on example.com. Two spaces, Home on the default profile and
Work on "Profile 2" (named "Client" in User Data/Local State), two favorites, a pinned folder,
a split view in Today, two archived tabs (and an about:blank and a blob: one, which an import
leaves out) and a sidebar width. Each profile has its own
extensions and pinned extensions in its Preferences: "Fixture Everywhere" in both, "Fixture
Client" only in Profile 2, and "Fixture Personal Off" in Default, turned off.
StorableLinkRouting.json holds three Air Traffic Control routes: Google Meet to the most recent
space, work.example.com to a Little Arc in Work (written by hand in Arc, #258) and an
"Is equal to" route to Home, with Little Arc as the default.
company.thebrowser.Browser.plist stands in for Arc's preferences: domainToProfilePreferences,
the profile picked for a site in a Little Arc (example.com on Default, work.example.com on
Profile 2, other.example.com on a Profile 9 no space is on).
SidebarItemsFaviconCache holds an icon each for the pinned folder's two tabs (orange for
home-p1, blue for home-p2), named md5(item id) as Arc names them: two tabs on one host with
different icons (#673). ArchiveItemsFaviconCache holds a green icon for the archived tab a1,
named md5(a1); a2 has none.
