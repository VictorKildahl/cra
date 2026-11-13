#!/usr/bin/env python3
"""What Cra owes its GitHub Sponsors in a release, from the tiers on the Sponsors page.

    scripts/sponsors.py            since the latest v* tag
    scripts/sponsors.py v0.1.30    since that tag
    scripts/sponsors.py 2026-11-01 since that day (UTC)

The perks come from the tier descriptions on GitHub, so editing a tier there changes
this report. A tier includes the perks of the cheaper tiers of its kind (monthly or
one-time), and a custom amount gets the highest tier at or below it, as GitHub does.

  - "release notes": one-time sponsors are named in the next release notes; monthly
    sponsors once a year (due when no release in the past 365 days lists them in its
    `sponsors` field in cra-website's releases.ts, CRA_WEBSITE to point elsewhere).
  - "ask Backers first": active monthly sponsors to ask about the next big feature.
  - "logo": companies whose logo belongs on crabrowser.app/support.

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
    "notes": (r"release notes", "Name in these release notes"),
    "ask": (r"ask backers first|say in what", "Ask first about the next big feature"),
    "logo": (r"\blogo\b", "Logo on crabrowser.app/support"),
}
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
    pages = sh("gh", "api", "graphql", "--paginate", "--slurp", "-f", f"query={QUERY}", env=env)
    pages = [p["data"]["viewer"] for p in json.loads(pages)]
    tiers = [t for t in pages[0]["sponsorsListing"]["tiers"]["nodes"] if not t["isCustomAmount"]]
    ships = [s for p in pages for s in p["sponsorshipsAsMaintainer"]["nodes"]]
    return tiers, ships


def tier_title(tier):
    m = re.match(r"\*\*(.+?)\*\*", tier["description"] or "")
    return m.group(1) if m else tier["name"]


def thanked_in_past_year(names):
    """Whether a release from the past 365 days thanks one of `names` as a sponsor."""
    path = WEBSITE / "src/content/releases.ts"
    if not path.exists():
        print(f"  (no {path}; monthly sponsors all show as due)")
        return False
    cutoff = (dt.date.today() - dt.timedelta(days=365)).isoformat()
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
    tiers, ships = fetch()

    for s in ships:
        t = s["tier"]
        own = [x for x in tiers if x["isOneTime"] == t["isOneTime"] and x["monthlyPriceInDollars"] <= t["monthlyPriceInDollars"]]
        s["reward"] = tier_title(max(own, key=lambda x: x["monthlyPriceInDollars"])) if own else None
        s["perks"] = {p for p, (pat, _) in PERKS.items() for x in own if re.search(pat, x["description"] or "", re.I)}
        s["new"] = dt.datetime.fromisoformat(s["createdAt"].replace("Z", "+00:00")).timestamp() > since
        e, private = s["sponsorEntity"], s["privacyLevel"] == "PRIVATE"
        who = "private sponsor, don't name; reach them privately" if private else f"{e['name'] or e['login']} (@{e['login']})"
        s["line"] = f"{who}  ·  {t['name']}" + (f", {s['reward']}" if s["reward"] else "") + f"  ·  since {s['createdAt'][:10]}"
        s["names"] = [] if private else [e["name"], e["login"]]

    def due(s, perk):
        if perk not in s["perks"]:
            return False
        if perk != "notes":  # a private sponsor can still be asked, in private
            return s["isActive"] and not s["tier"]["isOneTime"]
        if not s["names"]:  # private: never named
            return False
        if s["tier"]["isOneTime"]:
            return s["new"]
        return s["isActive"] and not thanked_in_past_year(s["names"])

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
