# Filter lists on macOS

In **Settings → Privacy**, choose each source independently. AdAway and Anudeep’s Blacklist are available offline and enabled by default. The tracking protection section groups EasyPrivacy with fingerprinting protection. Connection security covers HTTPS and Secure DNS. The optional subscriptions start off. Each switch controls one subscription, including custom URLs and files. Switching one off removes its downloaded copy. Switch it on again to fetch a fresh copy. **Remove** forgets a custom address. **Add List…** accepts it again.

**AdGuard Popups** hides supported promotional popups. **AdGuard Widgets** hides supported third-party widgets, including some support chats. You can enable either or both.

Choose one HaGeZi list to suit your browsing. **Multi NORMAL** is a starting point for everyday use and allows crash-reporting services. **Multi PRO Mini** is a smaller download drawn from the full PRO list, focused on domains found in popularity rankings. **Multi PRO** covers the full set, including less common trackers, and may require a site exception. Full PRO includes the Mini domains. All three lists are optional. [HaGeZi’s comparison](https://github.com/hagezi/dns-blocklists#pro)

**Update Enabled Lists** refreshes the subscriptions you have switched on. At launch, Cra updates missing copies and copies at least 24 hours old. While running, it checks every six hours for missing copies or copies at least seven days old. A failed update keeps the previous working copy.

**Use my filters** switches personal rules off or on while keeping the saved text. **My filters** accepts one rule per line. For example, `ads.example.org` blocks third-party requests to that domain, `example.org##.sponsored-card` hides that class on example.org and its subdomains, and `news.example.org#@#.sponsored-card` makes an exception on news.example.org. Save changes to apply them to open Chromium pages. On Chromium, subscriptions can match URL paths, wildcards, separators, resource types, first or third party, and the initiating site. Network exceptions apply across subscriptions and the bundled domain list. For example:

```text
||cdn.example.org/promotions/*$script
@@||cdn.example.org/promotions/consent.js$script,domain=news.example.org
@@||trusted.example.org^$document
```

The first rule blocks matching scripts. Images at those URLs can load. The second permits the consent script on the named site and its subdomains. The third permits network requests throughout a document on the trusted site. Element hiding has its own `#@#` exceptions. Cra skips unsupported modifiers, regular-expression network filters, scriptlets, redirects, URL parameter removal and procedural cosmetic rules. It keeps the supported lines when refreshing an older domain-only cache.

Chromium runs network rules locally through Cra’s bundled Manifest V3 helper. The built-in list, domain-only subscriptions such as HaGeZi, and element hiding work without starting the helper. Selecting a list or personal filter with supported network rules loads it in eligible profiles. Removing the last network rule unloads it. While active, the helper receives rule updates from Cra and supplies them to Chromium. It needs no permission to read page content or browsing history. Chromium allows 30,000 dynamic rules for blocking and exceptions. Cra groups domains that share conditions, so a list containing 100,000 domains can fit in a few hundred rules. Combining many regional subscriptions can still exceed the limit. Above the dynamic rule limit, Cra reports the count and keeps the previously accepted filters. With no previously accepted selection, it uses the selected built-in sources. If Privacy reports an activation failure, keep the languages you browse, switch off overlapping lists and update again. The legacy CEF engine uses domain filtering. [Chromium rule limits](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest#dynamic-rules)

With the updated Chromium framework, Cra enables its bundled filter for private windows when it first loads in each profile. The installer respects an existing private-window choice for that profile. Turning off the helper’s private-window permission stops its network rules in that profile’s private windows. This can also disable domain blocking there when advanced rules are active.

## Pause on a website

**Filter lists on this site** in the site menu stores a choice for the exact host across ports and HTTP/HTTPS. Switch it back on to remove the exception. Reload the page after changing it so previously blocked resources and embedded frames load with the new settings. It covers the native domain lists, subscription and personal rules, element hiding and the built-in cookie-banner filter. Connection security and fingerprinting protection have separate settings. The exceptions are browser settings shared across profiles and can be included in settings sync.

## Downloads and privacy

When enabled, a web subscription downloads directly from its provider or CDN on activation and refresh. The provider can see the connection's IP address, time and requested list. Downloads use a separate ephemeral session with cookie handling disabled. Browsing URLs and personal filter rules are not sent to list providers. File subscriptions read the selected local file. The list cache is local. If you enable Cra’s settings sync, the settings bundle can include subscription addresses and the text of personal rules. [Cra settings sync](../Packages/CraCore/Sources/CraCore/SettingsSync.swift)

## Sources and reuse

The optional catalog contains subscription addresses. Cra does not distribute those lists in its application bundle. The notices for Cra’s bundled domain list are separate. Check the source terms before bundling, modifying for distribution, or mirroring any optional list. [Bundled notices](../resources/blocklist/NOTICE.txt)

| Subscription | Publisher and terms |
|---|---|
| EasyList, EasyPrivacy, EasyList Germany, EasyList Italy, Adblock Warning Removal List | The subscriptions refer to the EasyList licensing page, which offers GPL 3 or later or CC BY-SA 3.0 or later, subject to its stated exceptions. [EasyList licensing](https://easylist.to/pages/licence.html) |
| EasyList Cookie List, Fanboy’s Annoyance List and Social Blocking List | Their published file headers specify CC BY 3.0. The Annoyance List already covers the cookie and social lists. [Fanboy subscriptions](https://fanboy.co.nz/) · [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| Liste FR | The published French list specifies CC BY-SA 3.0. [Subscription](https://easylist-downloads.adblockplus.org/liste_fr.txt) · [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| AdGuard Popups and AdGuard Widgets | Separately maintained parts of the Annoyances filter. The publishers document their sources and license in the filter repository. [AdGuard filters](https://adguard.com/kb/general/ad-filtering/adguard-filters/) · [AdGuard filter repository](https://github.com/AdguardTeam/AdguardFilters) |
| HaGeZi Multi NORMAL, PRO and PRO Mini | HaGeZi publishes its assembled lists under GPL-3.0 and documents separate source terms. PRO is a stronger alternative to NORMAL and can affect more sites. [HaGeZi](https://github.com/hagezi/dns-blocklists) · [License](https://github.com/hagezi/dns-blocklists/blob/main/LICENSE) |
| StevenBlack Unified Hosts | This compilation draws on multiple providers with individual licenses and attribution requirements. Use the publisher’s source table when considering redistribution. [Sources and licenses](https://github.com/StevenBlack/hosts#sources-of-hosts-data-unified-in-this-variant) |

## Regional subscriptions

Under **Settings → Privacy**, click **Regional lists** to see the 33 subscriptions. The row starts collapsed and shows how many lists you have selected. Each list has its own switch and is off by default. If you already subscribed to the same address as a custom list, its catalog switch reflects your existing choice.

For German, French, Italian, Dutch, Polish, Chinese, Japanese and Turkish, you can choose a community list, the corresponding AdGuard list, or both. Spanish and Portuguese have individual EasyList switches and a combined AdGuard switch. AdGuard also supplies the Russian and Ukrainian lists. The catalog includes Czech/Slovak, Indonesian/Malay, Vietnamese and Korean subscriptions. [ABP subscription directory](https://adblockplus.org/subscriptions) · [AdGuard language filters](https://adguard.com/kb/general/ad-filtering/adguard-filters/)

IndianList covers sites in Indian languages. Dandelion Sprout’s Nordic Filters covers Norway, Denmark, Iceland, Sweden and Finland. Liste AR covers Arabic, hufilter Hungarian, void.gr Greek, Bulgarian List Bulgarian, EasyList Lithuania Lithuanian and AdBlockFarsi Persian. [Regional subscription directory](https://adblockplus.org/subscriptions)
