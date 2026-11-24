#!/usr/bin/env python3
"""Does Cra's engine have every security fix Chrome stable has shipped? Run through scripts/check-engine-update.sh.

  scripts/check-engine-update.sh           print the engine, Chrome stable and each recent security fix
  scripts/check-engine-update.sh --check   exit 1 when the engine lacks a fix or is older than stable (release.sh)
  scripts/check-engine-update.sh --issue   when it does, open or update one "Chromium engine update available"
                                           issue naming the CVEs and the build to move to (hourly,
                                           .github/workflows/engine-updates.yml)

Three sources, all public:
  - Google's version history: the builds Mac stable is SERVING (releases without an end time). The plain versions
    list also names builds that never served stable: it put Beta 159.0.8154.13 first on 19 Nov 2026, and the engine
    moved to that Beta.
  - The Chrome Releases blog feed: each "Stable Channel Update for Desktop" post lists its security fixes as
    "[reward][bug] Severity CVE-…: what".
  - Chromium's commit messages (fetched without files, into a cache): the Bug: lines, the main revision a fix landed
    at (Cr-Commit-Position, or Cr-Original-Commit-Position on a merge) and where a branch left main
    (Cr-Branched-From).

A post's fix is in the engine when the post's build is on the engine's branch and not newer than the engine, when a
commit in the engine's tag names the bug, or when the fix landed on main before the engine's branch left it. The old
check compared version numbers only: on 159 Beta it took 158.0.8127.88's critical fix (CVE-2026-134401) as old.

CRA_ENGINE_SECURITY_DATA=<folder> reads the sources from files instead (Tests/Fixtures/EngineSecurity):
stable-releases.json, feed.json, tags.txt (git ls-remote) and log-<version>.txt (git log records).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path
import html
import json
import os
import re
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CHROMIUM = "https://chromium.googlesource.com/chromium/src.git"
RELEASES = ("https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions/all/releases"
            "?pageSize=50")
FEED = "https://chromereleases.googleblog.com/feeds/posts/default?alt=json&max-results=50"
# Posts older than this before the engine's own tag are not read: their fixes were on main long before it.
WINDOW = timedelta(days=21)
# Stable is the newest build served to at least this share of Macs. Below it are early rollouts of the next Chrome
# and holdbacks of the last (0.5 % each on 24 Nov 2026: 159.0.8154.13 and 157.0.8103.81).
WIDE = 0.1
# Commits fetched per tag: a branch's whole life (its Cr-Commit-Position stays under ~2500).
DEPTH = 4000
TITLE = "Chromium engine update available"
SEVERITIES = ["Critical", "High", "Medium", "Low"]

IN_ENGINE, MISSING, UNVERIFIED = "in the engine", "missing", "not verifiable"

Version = tuple


class Unreadable(Exception):
    """A source could not be read. The message starts with "Could not read" (scripts/check-cef-release-hook.sh)."""


def version(text: str) -> Version:
    return tuple(int(p) for p in text.split("."))


def show(v: Version | None) -> str:
    return ".".join(map(str, v)) if v else "-"


def branch(v: Version) -> Version:
    return v[:3]


@dataclass
class Fix:
    bug: str
    severity: str
    cve: str
    what: str
    post: "Post" = None
    in_the_wild: bool = False
    status: str = ""
    fixed_in: Version | None = None  # the build that has a MISSING fix
    why: str = ""


@dataclass
class Post:
    title: str
    published: datetime
    url: str
    versions: list
    fixes: list = field(default_factory=list)

    @property
    def version(self) -> Version:
        return max(self.versions)


@dataclass
class Commit:
    sha: str
    date: datetime
    bugs: set
    main_position: int | None
    branched_from: int | None


def text_of(markup: str) -> str:
    markup = re.sub(r"(?i)<br\s*/?>|</(p|div|li|tr)>", "\n", markup)
    text = html.unescape(re.sub(r"<[^>]+>", "", markup)).replace("\xa0", " ")
    return "\n".join(re.sub(r"[ \t]+", " ", line).strip() for line in text.splitlines())


def parse_feed(data: dict) -> list:
    """Desktop stable posts with their versions and security fixes (not Extended Stable, ChromeOS, Beta or Dev)."""
    posts = []
    for entry in data.get("feed", {}).get("entry", []):
        title = entry.get("title", {}).get("$t", "")
        if not re.search(r"\bStable\b.*\bDesktop\b", title) or "Extended" in title:
            continue
        text = text_of(entry.get("content", {}).get("$t", ""))
        head = text.split("Security Fixes")[0]
        versions = []
        for full, more in re.findall(r"\b(\d{2,4}\.\d+\.\d+\.\d+)((?:/\.\d+)*)", head):
            versions.append(version(full))
            for patch in re.findall(r"\d+", more):
                versions.append(version(full)[:3] + (int(patch),))
        if not versions:
            continue
        url = next((l.get("href", "") for l in entry.get("link", []) if l.get("rel") == "alternate"), "")
        post = Post(title, datetime.fromisoformat(entry["published"]["$t"]), url, versions)
        wild = set(re.findall(r"exploit for (CVE-\d{4}-\d+)[^\n.]*in the wild", text))
        for bug, severity, cve, what in re.findall(
                r"\[[^\]\n]*\]\s*\[(\d+)\]\s*(Critical|High|Medium|Low)\s+(CVE-\d{4}-\d+)\s*:\s*(.+)", text):
            what = re.split(r"\s+Reported by\b", what)[0].strip().rstrip(".")
            post.fixes.append(Fix(bug, severity, cve, what, post, cve in wild))
        posts.append(post)
    return posts


def parse_log(text: str) -> list:
    """`git log --format=%H%x00%cI%x00%B%x1e` records, newest first."""
    commits = []
    for record in text.split("\x1e"):
        record = record.strip("\n")
        if not record:
            continue
        sha, date, body = record.split("\0", 2)
        bugs = set()
        for line in re.findall(r"(?mi)^[>\s]*(?:Bug|Fixed):\s*(.*)$", body):
            for token in re.split(r"[,\s]+", line):
                m = re.fullmatch(r"(?:.*[/:])?(\d+)", token)
                if m:
                    bugs.add(m.group(1))
        main = re.search(r"Cr-(?:Original-)?Commit-Position: refs/heads/main@\{#(\d+)\}", body)
        branched = re.findall(r"Cr-Branched-From: \w+-refs/heads/main@\{#(\d+)\}", body)
        commits.append(Commit(sha, datetime.fromisoformat(date), bugs,
                              int(main.group(1)) if main else None, int(branched[-1]) if branched else None))
    return commits


class Source:
    """The three sources: live, or from CRA_ENGINE_SECURITY_DATA's files."""

    def __init__(self, data: Path | None = None, cache: Path | None = None):
        self.data = Path(data) if data else None
        self.cache = cache or Path(os.environ.get("CRA_CHROMIUM_LOG_CACHE",
                                                  Path.home() / ".cache/cra/chromium-log.git"))
        self._logs = {}

    def _get(self, url: str, name: str, what: str) -> dict:
        try:
            if self.data:
                return json.loads((self.data / name).read_text())
            request = urllib.request.Request(url, headers={"User-Agent": "cra-engine-security"})
            with urllib.request.urlopen(request, timeout=60) as reply:
                return json.load(reply)
        except Exception as error:
            raise Unreadable(f"Could not read {what}: {error}") from error

    def serving_stable(self) -> list:
        """(version, fraction of Macs) for each build Mac stable serves now."""
        rows = self._get(RELEASES, "stable-releases.json", "Chrome's version history").get("releases", [])
        serving = [(version(r["version"]), float(r.get("fraction", 0))) for r in rows
                   if not r.get("serving", {}).get("endTime")]
        if not serving:
            raise Unreadable("Could not read Chrome's version history: no build is serving Mac stable")
        return serving

    def posts(self) -> list:
        return parse_feed(self._get(FEED, "feed.json", "the Chrome Releases feed"))

    def branch_tags(self, of: Version) -> list:
        pattern = f"refs/tags/{show(branch(of))}.*"
        try:
            if self.data:
                out = (self.data / "tags.txt").read_text()
            else:
                out = subprocess.run(["git", "ls-remote", "--tags", CHROMIUM, pattern], check=True,
                                     capture_output=True, text=True, timeout=120).stdout
        except Exception as error:
            raise Unreadable(f"Could not read Chromium's tags: {error}") from error
        tags = {version(m) for m in re.findall(r"refs/tags/(\d+\.\d+\.\d+\.\d+)$", out, re.M)}
        return sorted(t for t in tags if branch(t) == branch(of))

    def log(self, of: Version) -> list:
        if of not in self._logs:
            self._logs[of] = parse_log(self._read_log(show(of)))
        return self._logs[of]

    def _read_log(self, tag: str) -> str:
        try:
            if self.data:
                return (self.data / f"log-{tag}.txt").read_text()
            git = ["git", "-C", str(self.cache)]
            if not (self.cache / "HEAD").exists():
                self.cache.mkdir(parents=True, exist_ok=True)
                subprocess.run(["git", "init", "-q", "--bare", str(self.cache)], check=True)
                subprocess.run(git + ["remote", "add", "origin", CHROMIUM], check=True)
            have = subprocess.run(git + ["rev-parse", "-q", "--verify", f"refs/tags/{tag}"], capture_output=True)
            if have.returncode:
                # Commits only (no trees or files): a few MB for a branch's whole life.
                subprocess.run(git + ["fetch", "-q", "--filter=tree:0", f"--depth={DEPTH}", "--no-tags", "origin",
                                      f"+refs/tags/{tag}:refs/tags/{tag}"], check=True, timeout=900)
            return subprocess.run(git + ["log", "--format=%H%x00%cI%x00%B%x1e", f"refs/tags/{tag}"], check=True,
                                  capture_output=True, text=True).stdout
        except Exception as error:
            raise Unreadable(f"Could not read Chromium's log for {tag}: {error}") from error


@dataclass
class Report:
    engine: Version
    stable: Version
    fixes: list
    target: Version | None
    newest_on_branch: Version | None
    early: Version | None = None  # a newer build on an early rollout to a few Macs
    early_share: float = 0

    @property
    def open_fixes(self) -> list:
        return [f for f in self.fixes if f.status != IN_ENGINE]

    @property
    def behind(self) -> bool:
        return self.stable > self.engine or bool(self.open_fixes)


def assess(source: Source, engine: Version) -> Report:
    serving = source.serving_stable()
    stable = max((v for v, share in serving if share >= WIDE), default=max(v for v, _ in serving))
    early, early_share = max(((v, s) for v, s in serving if v > stable), default=(None, 0))
    tags = [t for t in source.branch_tags(engine) if t > engine]
    newest = max(tags) if tags else None
    engine_commits = None
    fixes = []
    for post in source.posts():
        if branch(post.version) == branch(engine):
            # The engine's own branch: a build has every fix of the builds before it.
            for fix in post.fixes:
                if engine >= post.version:
                    fix.status, fix.why = IN_ENGINE, f"{show(engine)} is on {show(post.version)}'s branch"
                else:
                    fix.status, fix.fixed_in = MISSING, post.version
            fixes += post.fixes
            continue
        if engine_commits is None:
            engine_commits = source.log(engine)
            engine_date = engine_commits[0].date
            branch_point = next((c.branched_from for c in engine_commits if c.branched_from), None)
        if post.published < engine_date - WINDOW:
            continue
        for fix in post.fixes:
            fixes.append(fix)
            named = [c for c in source.log(post.version) if fix.bug in c.bugs]
            # A commit that landed on main: its main revision says whether the engine's branch had left by then.
            # Branch-only commits (a dependency roll merged into old branches, like M157's ICU roll naming two V8
            # CVEs) and fixes in other repositories (V8, Skia, ANGLE: no chromium/src commit names them) say nothing.
            landed = next((c for c in named if c.main_position), None)
            if any(fix.bug in c.bugs for c in engine_commits):
                fix.status, fix.why = IN_ENGINE, f"merged into {show(engine)}'s branch"
            elif landed and branch_point and landed.main_position <= branch_point:
                fix.status, fix.why = IN_ENGINE, (f"landed on main at #{landed.main_position}, before the branch "
                                                  f"(#{branch_point})")
            elif landed:
                fix.status = MISSING
                if newest and any(fix.bug in c.bugs for c in source.log(newest)):
                    fix.fixed_in = newest
            else:
                where = ("only in a branch-only commit of Chrome " if named else
                         "no chromium/src commit of Chrome ") + f"{show(post.version)}'s branch names it"
                if engine_date > post.published:
                    # Chromium merges such fixes into every branch it ships, and the engine was tagged after the post.
                    fix.status, fix.why = IN_ENGINE, f"{where}; {show(engine)} was tagged after the post"
                else:
                    fix.status, fix.why = UNVERIFIED, f"{where} (V8, Skia, ANGLE, ICU… or before that branch)"
    target = None
    if stable > engine:
        target = stable
    elif any(f.status != IN_ENGINE for f in fixes) and newest:
        open_after = [f.post.published for f in fixes if f.status == UNVERIFIED]
        if all(f.fixed_in for f in fixes if f.status == MISSING) and (
                not open_after or source.log(newest)[0].date > max(open_after)):
            target = newest
    return Report(engine, stable, fixes, target, newest, early, early_share)


def serving_text(report: Report) -> str:
    early = (f" ({show(report.early)} to {report.early_share * 100:g} % of Macs, an early rollout)"
             if report.early else "")
    return f"{show(report.stable)}{early}"


def worst(fixes: list) -> str:
    return min((f.severity for f in fixes), key=SEVERITIES.index, default="")


def summary(report: Report) -> str:
    lines = [f"Engine: {show(report.engine)}", f"Chrome stable for Mac (serving): {serving_text(report)}"]
    if report.fixes:
        lines.append("Security fixes in Chrome stable posts:")
    for f in report.fixes:
        where = f" (in {show(f.fixed_in)})" if f.fixed_in else ""
        wild = ", exploited in the wild" if f.in_the_wild else ""
        lines.append(f"  {f.status:15} {f.severity:8} {f.cve} {f.what}{wild}; Chrome {show(f.post.version)}"
                     f"{where}{'; ' + f.why if f.why else ''}")
    if not report.behind:
        lines.append("The engine is up to date.")
    elif report.target:
        lines.append(f"The engine is behind: build {show(report.target)}.")
    else:
        lines.append("The engine is behind, and no build of its branch has the fix yet: watch for a newer "
                     f"{show(branch(report.engine))} tag, or move to Chrome stable {show(report.stable)}.")
    return "\n".join(lines)


def issue_key(report: Report) -> str:
    fixes = ",".join(sorted(f"{f.cve}={f.status}" for f in report.open_fixes))
    return f"{show(report.target)}|{show(report.stable)}|{fixes}"


def issue_title(report: Report) -> str:
    fixes = report.open_fixes
    if not fixes:
        return TITLE
    cves = ", ".join(f.cve for f in fixes[:3]) + (f" +{len(fixes) - 3}" if len(fixes) > 3 else "")
    wild = ", exploited in the wild" if any(f.in_the_wild for f in fixes) else ""
    return f"{TITLE}: {cves} ({worst(fixes)}{wild})"


def issue_body(report: Report) -> str:
    fixes = report.open_fixes
    out = [f"Cra's engine is built from Chrome `{show(report.engine)}`. Chrome stable for macOS is serving "
           f"{serving_text(report)}."]
    if fixes:
        out += ["", f"**The engine lacks {len(fixes)} security fix{'es' if len(fixes) > 1 else ''} Chrome stable "
                    "has shipped:**", "", "| Severity | CVE | What | Chrome post | In |", "|---|---|---|---|---|"]
        for f in fixes:
            wild = " **(exploited in the wild)**" if f.in_the_wild else ""
            post = f"[{show(f.post.version)}, {f.post.published:%-d %b}]({f.post.url})"
            where = f"`{show(f.fixed_in)}`" if f.fixed_in else (f.why or "no build of the branch yet")
            out.append(f"| {f.severity} | {f.cve}{wild} | {f.what} | {post} | {where} |")
    if report.target:
        same = branch(report.target) == branch(report.engine)
        kind = ("a newer build of the same Chrome version, so the build reuses the checkout" if same else
                "a different Chrome version, so Cra's patches may need rebasing and the build compiles everything")
        out += ["", f"Move to **`{show(report.target)}`**: {kind}. On the Mac that builds the engine "
                    "(docs/chromium-engine.md):", "", "```sh",
                f"CHROMIUM_TAG={show(report.target)} scripts/build-chromium.sh all",
                f"CHROMIUM_TAG={show(report.target)} CRA_ARCH=x64 scripts/build-chromium.sh all",
                "scripts/publish-engine.sh && ENGINE_CPU=x64 scripts/publish-engine.sh", "```", "",
                f"Then set `ENGINE_VERSION={show(report.target)}` in `scripts/fetch-engine.sh` (and `CHROMIUM_TAG` in "
                "`scripts/build-chromium.sh`), run the scenarios on `build/Cra.app`, commit and release."]
    else:
        out += ["", f"No build of the engine's branch (`{show(branch(report.engine))}`) has every fix yet. Watch for a "
                    f"newer tag, or move to Chrome stable `{show(report.stable)}`."]
    out += ["", "_Checked hourly by the engine updates workflow (`scripts/check-engine-update.sh --issue`). This "
                "issue is updated, with a comment, when a new fix or build appears. Close it once a release ships the "
                "new engine._", "", f"<!-- engine-security: {issue_key(report)} -->"]
    return "\n".join(out)


def issue_action(existing_body: str | None, report: Report) -> str:
    """"create", "update" (edit and comment) or "none"."""
    if not report.behind:
        return "none"
    if existing_body is None:
        return "create"
    return "none" if f"<!-- engine-security: {issue_key(report)} -->" in existing_body else "update"


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def file_issue(report: Report) -> None:
    found = json.loads(gh("issue", "list", "--state", "open", "--search", f'"{TITLE}" in:title',
                          "--json", "number,body,title") or "[]")
    found = [i for i in found if i["title"].startswith(TITLE)]
    existing = found[0] if found else None
    action = issue_action(existing["body"] if existing else None, report)
    title, body = issue_title(report), issue_body(report)
    if action == "create":
        print(gh("issue", "create", "--title", title, "--body", body,
                 "--assignee", os.environ.get("GITHUB_REPOSITORY_OWNER", "@me")).strip())
    elif action == "update":
        number = str(existing["number"])
        gh("issue", "edit", number, "--title", title, "--body", body)
        new = [f"{f.severity} {f.cve}" for f in report.open_fixes if f.cve not in existing["body"]]
        news = (f"New security fix{'es' if len(new) > 1 else ''}: {', '.join(new)}. " if new else "") + (
            f"Build `{show(report.target)}`." if report.target else "No build of the branch has every fix yet.")
        gh("issue", "comment", number, "--body", news + " The steps above are updated.")
        print(f"Updated issue #{number}")
    else:
        print("Issue already up to date." if existing else "No issue needed.")


def pinned_engine() -> Version:
    pinned = os.environ.get("ENGINE_VERSION")
    if not pinned:
        m = re.search(r'^ENGINE_VERSION="\$\{ENGINE_VERSION:-([\d.]+)\}"', (ROOT / "scripts/fetch-engine.sh").read_text(),
                      re.M)
        pinned = m.group(1)
    return version(pinned)


def main(argv: list) -> int:
    mode = argv[1] if len(argv) > 1 else ""
    data = os.environ.get("CRA_ENGINE_SECURITY_DATA")
    try:
        report = assess(Source(Path(data) if data else None), pinned_engine())
    except Unreadable as error:
        print(error, file=sys.stderr)
        return 1
    print(summary(report))
    if mode == "--check":
        return 1 if report.behind else 0
    if mode == "--issue":
        file_issue(report)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
