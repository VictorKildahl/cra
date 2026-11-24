# Filter lists on macOS

In **Settings → Privacy**, turn on **Block ads and trackers** and switch on the lists you want. Cra ships its own domain list. The optional subscriptions start off. Each switch controls one subscription, including custom URLs and files. Switching one off removes its downloaded copy. Switch it on again to fetch a fresh copy. **Remove** forgets a custom address. **Add List…** accepts it again.

**Update Enabled Lists** refreshes the subscriptions you have switched on. At launch, Cra updates missing copies and copies at least 24 hours old. While running, it checks every six hours for missing copies or copies at least seven days old. Switching off the main blocker pauses new downloads. A failed update keeps the previous working copy.

**My filters** accepts one rule per line. For example, `ads.example.org` blocks third-party requests to that domain, `example.org##.sponsored-card` hides that class on example.org and its subdomains, and `news.example.org#@#.sponsored-card` makes an exception on news.example.org. Save changes to apply them to open Chromium pages. The Mac supports whole-domain blocking and simple CSS element filters in the main document. Filter syntax that relies on URL paths, resource-specific network blocking, procedural selectors or scriptlets needs a more capable matching engine.

## Downloads and privacy

When enabled, a web subscription downloads directly from its provider or CDN on activation and refresh. The provider can see the connection's IP address, time and requested list. Downloads use a separate ephemeral session with cookie handling disabled. Browsing URLs and personal filter rules are not sent to list providers. File subscriptions read the selected local file. The list cache is local. If you enable Cra’s settings sync, the settings bundle can include subscription addresses and the text of personal rules. [Cra settings sync](../Packages/CraCore/Sources/CraCore/SettingsSync.swift)

## Sources and reuse

The optional catalog contains subscription addresses. Cra does not distribute those lists in its application bundle. The notices for Cra’s bundled domain list are separate. Check the source terms before bundling, modifying for distribution, or mirroring any optional list. [Bundled notices](../resources/blocklist/NOTICE.txt)

| Subscription | Publisher and terms |
|---|---|
| EasyList, EasyPrivacy, EasyList Germany, EasyList Italy, Adblock Warning Removal List | The subscriptions refer to the EasyList licensing page, which offers GPL 3 or later or CC BY-SA 3.0 or later, subject to its stated exceptions. [EasyList licensing](https://easylist.to/pages/licence.html) |
| EasyList Cookie List, Fanboy’s Annoyance List and Social Blocking List | Their published file headers specify CC BY 3.0. The Annoyance List already covers the cookie and social lists. [Fanboy subscriptions](https://fanboy.co.nz/) · [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| Liste FR | The published French list specifies CC BY-SA 3.0. [Subscription](https://easylist-downloads.adblockplus.org/liste_fr.txt) · [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| HaGeZi Multi NORMAL and PRO | HaGeZi publishes its assembled lists under GPL-3.0 and documents separate source terms. PRO is a stronger alternative to NORMAL and can affect more sites. [HaGeZi](https://github.com/hagezi/dns-blocklists) · [License](https://github.com/hagezi/dns-blocklists/blob/main/LICENSE) |
| StevenBlack Unified Hosts | This compilation draws on multiple providers with individual licenses and attribution requirements. Use the publisher’s source table when considering redistribution. [Sources and licenses](https://github.com/StevenBlack/hosts#sources-of-hosts-data-unified-in-this-variant) |
