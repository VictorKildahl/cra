# Filter lists on macOS

**Settings → Privacy** has one switch, **Block ads and trackers** (on by default), and one choice under it:

- **Standard** uses Cra's built-in lists, AdAway and Anudeep's Blacklist. They work offline and rarely get in a page's way.
- **Strict** adds EasyList and EasyPrivacy, which catch more ads and trackers, and the lists that take ads out of sites' own pages and data: uBlock filters – Ads, uBlock filters – Quick fixes and AdGuard – Ads. These handle YouTube's in-stream video ads and the promoted posts on X and Instagram. Now and then a page needs ad blocking turned off for it.

Turning the switch off turns all of these off; turning it back on gives Standard. Settings shows Strict while EasyList and EasyPrivacy are both on, and Strict's other three lists show the same way under **Advanced…**, each with its own switch. Settings from before these three lists were added that were already on Strict get them once.

The **Block lists** row says how many rules are in use and from how many lists, each rule counted once however many lists name it.

**Block lists → Advanced…** is for people who know filter lists: each source has its own switch there. AdAway and Anudeep's Blacklist are available offline. The optional subscriptions start off. Each switch controls one subscription, including custom URLs and files. Switching one off removes its downloaded copy. Switch it on again to fetch a fresh copy. **Remove** forgets a custom address. **Add List…** accepts it again.

Under each list that is on, and under Cra's built-in lists, is how many of its rules Cra uses: blocked domains, network rules (paths, exceptions, rules for some sites) and element-hiding rules. Rules Cra reads but can't apply, such as scriptlets and redirects, are counted after it ("48,210 rules · 3,102 Cra can’t use"). On the legacy CEF engine a list's network rules don't count, only its domains and element hiding. **My filters** shows the same count for your own rules.

**AdGuard Popups** hides supported promotional popups. **AdGuard Widgets** hides supported third-party widgets, including some support chats. You can enable either or both.

Choose one HaGeZi list to suit your browsing. **Multi NORMAL** is a starting point for everyday use and allows crash-reporting services. **Multi PRO Mini** is a smaller download drawn from the full PRO list, focused on domains found in popularity rankings. **Multi PRO** covers the full set, including less common trackers, and may require a site exception. Full PRO includes the Mini domains. All three lists are optional. [HaGeZi’s comparison](https://github.com/hagezi/dns-blocklists#pro)

**Update Enabled Lists** refreshes the subscriptions you have switched on. At launch, Cra updates missing copies and copies at least 24 hours old. While running, it checks every six hours for missing copies or copies at least seven days old. A failed update keeps the previous working copy.

Site-specific cosmetic rules can hide an entire advertising container based on what it contains. For example, `news.example##aside:has(> div[data-ad-unit-id])` also applies to matching containers added after the page loads. A simple selector can also use `:empty` or exclude classes and attributes with `:not()`. For example, `##.ad-slot:not(.adsbygoogle)` hides matching slots while preserving the excluded class.

**Use my filters** switches personal rules off or on while keeping the saved text. **My filters** accepts one rule per line. For example, `ads.example.org` blocks third-party requests to that domain, `example.org##.sponsored-card` hides that class on example.org and its subdomains, and `news.example.org#@#.sponsored-card` makes an exception on news.example.org. Save changes to apply them to open Chromium pages. On Chromium, subscriptions can match URL paths, wildcards, separators, resource types, first or third party, and the initiating site. Network exceptions apply across subscriptions and the bundled domain list. For example:

```text
||cdn.example.org/promotions/*$script
@@||cdn.example.org/promotions/consent.js$script,domain=news.example.org
@@||trusted.example.org^$document
```

The first rule blocks matching scripts. Images at those URLs can load. The second permits the consent script on the named site and its subdomains. The third permits network requests throughout a document on the trusted site. Element hiding has its own `#@#` exceptions. Cra skips unsupported modifiers, regular-expression network filters, scriptlets, redirects, URL parameter removal and procedural cosmetic rules. It keeps the supported lines when refreshing an older domain-only cache.

Chromium runs network rules locally through Cra’s bundled Manifest V3 helper. The built-in list, domain-only subscriptions such as HaGeZi, and element hiding work without starting the helper. Selecting a list or personal filter with supported network rules loads it in eligible profiles. Removing the last network rule unloads it. While active, the helper receives rule updates from Cra and supplies them to Chromium. The helper also has scripting access to HTTP and HTTPS sites, used for one thing: when a selected network rule blocks the AdShield loader, Chromium registers a document-start script on eligible sites, respecting site pauses and loader exceptions. It checks script elements for the matching loader, removes its inline failure callback on a trusted load error, and inspects inline application/json state if the loader is present or failed. When the state identifies AdShield and has a unique enabled adblock-wall flag, it rewrites that flag to false before deferred page code reads it. Page contents and browsing URLs stay in the tab and are never sent to Cra. Separately, Cra’s isolated page-recovery script reads the page’s dialogs and short notices, in the tab, to close a consent dialog its cookie-banner rules hid (without choosing a consent option) and to hide an adblock notice when the Adblock Warning Removal List is on. Chromium allows 30,000 dynamic rules for blocking and exceptions. Cra groups domains that share conditions, so a list containing 100,000 domains can fit in a few hundred rules. Combining many regional subscriptions can still exceed the limit. Above the dynamic rule limit, Cra reports the count and keeps the previously accepted filters. With no previously accepted selection, it uses the selected built-in sources. If Privacy reports an activation failure, keep the languages you browse, switch off overlapping lists and update again. The legacy CEF engine uses domain filtering. [Chromium rule limits](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest#dynamic-rules)

With the updated Chromium framework, Cra enables its bundled filter for private windows when it first loads in each profile. The installer respects an existing private-window choice for that profile.

The helper is part of Cra, like Chrome’s own component extensions: chrome://extensions doesn’t list it and other extensions can’t see it through `chrome.management`, so it can’t be switched off or removed there (#844). **Settings → Privacy** is the one place that controls it.

## Scriptlets and procedural hiding

YouTube's in-stream ads arrive inside the page's own player data, and X and Instagram mark a promoted post only by a label such as "Ad" or "Sponsored". Network and stylesheet rules cannot reach either. For these, lists use two other kinds of rule, and Cra runs both itself:

- **Scriptlets**, such as `youtube.com##+js(json-prune, playerResponse.adPlacements)`, are small named functions. They run in every frame of the site before the page's own scripts and take the ads out of its data before the page reads it. Cra reads uBlock Origin's `##+js(…)`, AdGuard's `#%#//scriptlet(…)` and Adblock Plus's `#$#` forms. It runs its own implementation of each name (`Resources/blocklist/scriptlets.js`), including `set-constant`, `json-prune` and its fetch and XHR variants, `abort-on-property-read/write`, `abort-current-script`, the timer and event-listener defusers, `no-fetch-if`, `remove-attr`, `replace-node-text` and `edit-inbound-object`. A name it does not implement is counted among the rules Cra can't use. `trusted-` scriptlets, which can rewrite a page's data freely, run only from uBlock Origin's own lists and your own filters.
- **Procedural hiding** rules, such as `x.com#?#div[data-testid="cellInnerDiv"]:has(span:has-text(/^Ad$/))`, find an element by its text (`:has-text`, `:contains`), its surroundings (`:has`, `:upward`, `:xpath`) or its computed style (`:matches-css`). They also cover site-specific selectors too complex for the stylesheet path. They run in Cra's own world on each page and again as the page changes (`Resources/blocklist/procedural.js`). `:style()` runs only from trusted lists, the same as `trusted-` scriptlets. A procedural rule for every site is left out.

Lists' `!#if env_chromium` blocks are read; blocks for uBlock Origin itself, AdGuard or Safari are not. Pausing a site stops its scriptlets and procedural hiding as well, from the page's next load. Pages that are already open run new or changed rules from their next load.

## Pages in Safari's engine

Pages that open in WebKit (the protected-media services, and sites switched to Safari's engine) block with the same lists. Their network rules go to WebKit as content-blocker lists, which WebKit compiles once per change and keeps between launches. WebKit has no 30,000-rule limit, so these pages get the whole selection; a selection over 70,000 rules is split into several lists. Scriptlets, element hiding and procedural hiding run there as on Chromium pages, and **Ad Blocking** in the site menu pauses a WebKit page's site too. Redirect rules don't apply in WebKit. [Details](protected-media.md#ad-blocking)

## Pause on a website

**Ad Blocking** in the site menu (the address bar's site button) stores a choice for the exact host across ports and HTTP/HTTPS. Switch it back on to remove the exception. Reload the page after changing it so previously blocked resources and embedded frames load with the new settings. It covers the native domain lists, subscription and personal rules, element hiding and the built-in cookie-banner filter. Connection security and fingerprinting protection have separate settings. The exceptions are browser settings shared across profiles and can be included in settings sync.

## Downloads and privacy

When enabled, a web subscription downloads directly from its provider or CDN on activation and refresh. The provider can see the connection's IP address, time and requested list. Downloads use a separate ephemeral session with cookie handling disabled. Browsing URLs and personal filter rules are not sent to list providers. File subscriptions read the selected local file. The list cache is local. If you enable Cra’s settings sync, the settings bundle can include subscription addresses and the text of personal rules. [Cra settings sync](../Packages/CraCore/Sources/CraCore/SettingsSync.swift)

## Sources and reuse

The optional catalog contains subscription addresses. Cra does not distribute those lists in its application bundle. The notices for Cra’s bundled domain list are separate. Check the source terms before bundling, modifying for distribution, or mirroring any optional list. [Bundled notices](../resources/blocklist/NOTICE.txt)

| Subscription | Publisher and terms |
|---|---|
| EasyList, EasyPrivacy, EasyList Germany, EasyList Italy, Adblock Warning Removal List | The subscriptions refer to the EasyList licensing page, which offers GPL 3 or later or CC BY-SA 3.0 or later, subject to its stated exceptions. [EasyList licensing](https://easylist.to/pages/licence.html) |
| uBlock filters (Ads, Badware risks, Privacy, Unbreak, Quick fixes, Experimental, Cookie Notices, Annoyances) | uBlock Origin's volunteers publish them under GPL 3. Cra fetches them from their own address and does not bundle them. Its scriptlets are Cra's own implementation. [uAssets](https://github.com/uBlockOrigin/uAssets) · [License](https://github.com/uBlockOrigin/uAssets/blob/master/LICENSE) |
| AdGuard – Ads, Mobile Ads, Cookie Notices, Social Widgets, Mobile App Banners, Other Annoyances | AdGuard's builds in uBlock Origin's syntax (Ads without EasyList), under GPL 3. [AdGuard filters](https://adguard.com/kb/general/ad-filtering/adguard-filters/) · [AdGuard filter repository](https://github.com/AdguardTeam/AdguardFilters) |
| EasyList Cookie List, Fanboy’s Annoyance List and Social Blocking List | Their published file headers specify CC BY 3.0. The Annoyance List already covers the cookie and social lists. [Fanboy subscriptions](https://fanboy.co.nz/) · [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| Liste FR | The published French list specifies CC BY-SA 3.0. [Subscription](https://easylist-downloads.adblockplus.org/liste_fr.txt) · [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) |
| AdGuard Popups and AdGuard Widgets | Separately maintained parts of the Annoyances filter. The publishers document their sources and license in the filter repository. [AdGuard filters](https://adguard.com/kb/general/ad-filtering/adguard-filters/) · [AdGuard filter repository](https://github.com/AdguardTeam/AdguardFilters) |
| HaGeZi Multi NORMAL, PRO and PRO Mini | HaGeZi publishes its assembled lists under GPL-3.0 and documents separate source terms. PRO is a stronger alternative to NORMAL and can affect more sites. [HaGeZi](https://github.com/hagezi/dns-blocklists) · [License](https://github.com/hagezi/dns-blocklists/blob/main/LICENSE) |
| StevenBlack Unified Hosts | This compilation draws on multiple providers with individual licenses and attribution requirements. Use the publisher’s source table when considering redistribution. [Sources and licenses](https://github.com/StevenBlack/hosts#sources-of-hosts-data-unified-in-this-variant) |

## Regional subscriptions

Under **Settings → Privacy**, click **Regional lists** to see the 33 subscriptions. The row starts collapsed and shows how many lists you have selected. Each list has its own switch and is off by default. If you already subscribed to the same address as a custom list, its catalog switch reflects your existing choice.

For German, French, Italian, Dutch, Polish, Chinese, Japanese and Turkish, you can choose a community list, the corresponding AdGuard list, or both. Spanish and Portuguese have individual EasyList switches and a combined AdGuard switch. AdGuard also supplies the Russian and Ukrainian lists. The catalog includes Czech/Slovak, Indonesian/Malay, Vietnamese and Korean subscriptions. [ABP subscription directory](https://adblockplus.org/subscriptions) · [AdGuard language filters](https://adguard.com/kb/general/ad-filtering/adguard-filters/)

IndianList covers sites in Indian languages. Dandelion Sprout’s Nordic Filters covers Norway, Denmark, Iceland, Sweden and Finland. Liste AR covers Arabic, hufilter Hungarian, void.gr Greek, Bulgarian List Bulgarian, EasyList Lithuania Lithuanian and AdBlockFarsi Persian. [Regional subscription directory](https://adblockplus.org/subscriptions)

The Advanced catalog offers lists Cra can apply. Three sources are deferred until the corresponding rules work: [URL Tracking Protection](https://ublockorigin.github.io/uAssets/filters/privacy-removeparam.txt) needs URL parameter removal, [LAN protection](https://ublockorigin.github.io/uAssets/filters/lan-block.txt) needs LAN request matching, and [URLhaus](https://gitlab.com/malware-filter/urlhaus-filter) needs full-page blocking.
