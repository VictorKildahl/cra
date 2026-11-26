#!/usr/bin/env python3
"""What Cra owes its GitHub Sponsors in a release, from the tiers on the Sponsors page.

    scripts/sponsors.py            since the latest v* tag
    scripts/sponsors.py v0.1.30    since that tag
    scripts/sponsors.py 2026-11-01 since that day (UTC)

The perks come from the tier descriptions on GitHub, so editing a tier there changes
this report. A tier includes the perks of the cheaper tiers of its kind (monthly or
one-time), and a custom amount gets the highest tier at or below it, as GitHub does.

  - "release notes": one-time sponsors are named in the next release notes; monthly
    sponsors as often as their tier says ("when you join", "once a year", "twice a year",
    "every quarter", "every release"; due when no release in that span lists them in its `sponsors` field
    in cra-website's releases.ts, CRA_WEBSITE to point elsewhere), and again after they
    raise their monthly amount: only releases from the day of the raise on count as
    thanking them for it.
  - "logo": companies whose logo belongs on crabrowser.app/support.
  - "readme" / "home page": company tiers from $250 a month whose logo also belongs in the
    GitHub README / on the crabrowser.app home page while they sponsor.
  - "welcome": public company sponsors who joined (or moved up) since the tag and get a
    welcome post from @crabrowser.

Private sponsors are never named; they're listed so they can be reached privately.
Needs VictorKildahl's token with the `user` (or `read:user`) scope.
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEBSITE = Path(os.environ.get("CRA_WEBSITE", ROOT.parent / "cra-website"))
PERKS = {  # perk -> (pattern in a tier description, what it means)
    "notes": (r"release notes|notes of every release", "Name in these release notes"),
    "logo": (r"\blogo\b", "Logo on crabrowser.app/support"),
    "readme": (r"logo in the GitHub README", "Logo in the GitHub README"),
    "home": (r"home page", "Logo on the crabrowser.app home page"),
    "welcome": (r"post from @crabrowser", "Welcome post from @crabrowser (once, when they join)"),
}
EVERY = [  # how often a monthly tier's name is in the release notes, in days
    (r"every release", 0),
    (r"every quarter", 91),
    (r"twice a year", 182),
    (r"once a year", 365),
    (r"when you join", 36500),  # once: any release since they joined counts
]
QUERY = """
query($endCursor: String) { viewer {
  sponsorsListing { tiers(first: 50) { nodes {
    name description monthlyPriceInDollars isOneTime isCustomAmount } } }
  sponsorshipsAsMaintainer(first: 100, after: $endCursor, includePrivate: true,
                           activeOnly: false, orderBy: {field: CREATED_AT, direction: ASC}) {
    pageInfo { hasNextPage endCursor }
    nodes { createdAt isActive privacyLevel
      tier { name monthlyPriceInDollars isOneTime }
      sponsorEntity { ... on User { login name } ... on Organization { login name } } } } } }"""
RAISES = """
query($endCursor: String) { viewer {
  sponsorsActivities(first: 100, after: $endCursor, period: ALL, includePrivate: true, actions: [TIER_CHANGE]) {
    pageInfo { hasNextPage endCursor }
    nodes { timestamp
      previousSponsorsTier { name monthlyPriceInDollars isOneTime }
      sponsorsTier { monthlyPriceInDollars isOneTime }
      sponsor { ... on User { login } ... on Organization { login } } } } } }"""


def sh(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, text=True, cwd=ROOT, **kw).stdout


def since_from(arg):
    if sh("git", "tag", "-l", arg).strip():
        return int(sh("git", "for-each-ref", "--format=%(creatordate:unix)", f"refs/tags/{arg}"))
    try:
        return int(dt.datetime.strptime(arg, "%Y-%m-%d").replace(tzinfo=dt.timezone.utc).timestamp())
    except ValueError:
        sys.exit(f"sponsors.py: '{arg}' is neither a tag nor a YYYY-MM-DD date")


def fetch():
    env = dict(os.environ)
    env.setdefault("GH_TOKEN", sh("gh", "auth", "token", "--user", "VictorKildahl").strip())
    def query(q):
        pages = sh("gh", "api", "graphql", "--paginate", "--slurp", "-f", f"query={q}", env=env)
        return [p["data"]["viewer"] for p in json.loads(pages)]
    pages = query(QUERY)
    tiers = [t for t in pages[0]["sponsorsListing"]["tiers"]["nodes"] if not t["isCustomAmount"]]
    ships = [s for p in pages for s in p["sponsorshipsAsMaintainer"]["nodes"]]
    changes = [a for p in query(RAISES) for a in p["sponsorsActivities"]["nodes"]]
    return tiers, ships, latest_raises(changes)


def latest_raises(changes):
    """login -> the latest tier change that raised a monthly sponsorship, from TIER_CHANGE activities."""
    raises = {}
    for a in changes:
        old, new, who = a["previousSponsorsTier"], a["sponsorsTier"], a["sponsor"]
        if not (old and new and who) or old["isOneTime"] or new["isOneTime"]:
            continue
        if new["monthlyPriceInDollars"] <= old["monthlyPriceInDollars"]:
            continue
        if who["login"] not in raises or a["timestamp"] > raises[who["login"]]["timestamp"]:
            raises[who["login"]] = a
    return raises


def tier_title(tier):
    m = re.match(r"\*\*(.+?)\*\*", tier["description"] or "")
    return m.group(1) if m else tier["name"]


def tier_perks(descriptions):
    """The perks a sponsor's tiers promise, by the PERKS patterns."""
    descriptions = list(descriptions)
    return {p for p, (pat, _) in PERKS.items() for text in descriptions if re.search(pat, text or "", re.I)}


def notes_every(descriptions):
    """Days between a monthly sponsor's names in the release notes: the most often any of
    their tiers promises, so a tier that says "Everything in Insider" keeps Insider's pace.
    Once a year when no tier says how often."""
    days = [d for pat, d in EVERY for text in descriptions if re.search(pat, text or "", re.I)]
    return min(days, default=365)


def thanked_within(names, days, raised=None, path=None, today=None):
    """Whether a release from the past `days` days thanks one of `names` as a sponsor, and when
    `raised` (a YYYY-MM-DD day) is given, a release from that day on: a sponsor who pays more
    is named again. Release dates are days, so a release on the day of the raise counts.
    0 days means every release, so no earlier release counts."""
    if days == 0:
        return False
    path = path or WEBSITE / "src/content/releases.ts"
    if not path.exists():
        print(f"  (no {path}; monthly sponsors all show as due)")
        return False
    cutoff = ((today or dt.date.today()) - dt.timedelta(days=days)).isoformat()
    cutoff = max(cutoff, raised or "")
    for entry in path.read_text().split("\n  {\n    version:")[1:]:
        date = re.search(r'date: "([\d-]+)"', entry)
        if not date or date.group(1) < cutoff:
            continue
        field = re.search(r"sponsors: \[(.*?)\]", entry, re.S)
        if field and any(n and f'login: "{n}"' in field.group(1) for n in names):
            return True
    return False


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else sh("git", "tag", "-l", "v*", "--sort=-creatordate").split()[0]
    since = since_from(arg)
    tiers, ships, raises = fetch()

    for s in ships:
        t = s["tier"]
        own = [x for x in tiers if x["isOneTime"] == t["isOneTime"] and x["monthlyPriceInDollars"] <= t["monthlyPriceInDollars"]]
        s["reward"] = tier_title(max(own, key=lambda x: x["monthlyPriceInDollars"])) if own else None
        s["perks"] = tier_perks(x["description"] for x in own)
        s["every"] = notes_every(x["description"] for x in own)
        s["new"] = dt.datetime.fromisoformat(s["createdAt"].replace("Z", "+00:00")).timestamp() > since
        e, private = s["sponsorEntity"], s["privacyLevel"] == "PRIVATE"
        raise_ = raises.get(e.get("login")) if s["isActive"] and not t["isOneTime"] else None
        s["raised"] = raise_["timestamp"][:10] if raise_ else None
        s["new"] = s["new"] or bool(raise_ and dt.datetime.fromisoformat(raise_["timestamp"].replace("Z", "+00:00")).timestamp() > since)
        who = "private sponsor, don't name; reach them privately" if private else f"{e['name'] or e['login']} (@{e['login']})"
        s["line"] = f"{who}  ·  {t['name']}" + (f", {s['reward']}" if s["reward"] else "") + f"  ·  since {s['createdAt'][:10]}"
        if raise_:
            s["line"] += f", raised from {raise_['previousSponsorsTier']['name']} on {s['raised']}"
        s["names"] = [] if private else [e["name"], e["login"]]

    def due(s, perk):
        if perk not in s["perks"]:
            return False
        if perk == "welcome":  # once, in public, when they join or move up
            return s["isActive"] and s["new"] and bool(s["names"])
        if perk != "notes":  # a private company is reached privately about its logo
            return s["isActive"] and not s["tier"]["isOneTime"]
        if not s["names"]:  # private: never named
            return False
        if s["tier"]["isOneTime"]:
            return s["new"]
        return s["isActive"] and not thanked_within(s["names"], s["every"], s["raised"])

    print(f"Sponsors, for the release after {arg}:")
    for perk, (_, title) in PERKS.items():
        print(f"\n{title}:")
        rows = [s["line"] for s in ships if due(s, perk)]
        print("\n".join(f"  {r}" for r in rows) if rows else "  nobody")
    print(f"\nNew since {arg}:")
    rows = [s["line"] for s in ships if s["new"]]
    print("\n".join(f"  {r}" for r in rows) if rows else "  nobody")


if __name__ == "__main__":
    main()
