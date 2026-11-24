#!/usr/bin/env python3
"""scripts/check-engine-update.sh (scripts/engine-security.py): does the engine have every security fix Chrome
stable has shipped? Run on Tests/Fixtures/EngineSecurity: Google's version history and the Chrome Releases feed as
they stood on 24 Nov 2026, and Chromium's real commit messages for the tags involved (`git log` records).

On 24 Nov 2026 Cra's engine was 159.0.8154.13, a Beta build the old check took for stable (it read the plain
versions list). Chrome stable 158.0.8127.88/.89 shipped CVE-2026-134401 (Critical, Variations) on 23 Nov, and the
old check, seeing 158 < 159, said the engine was up to date. The fix reached the 159 branch in 159.0.8154.45.
"""
from pathlib import Path
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/check-engine-update.sh"
FIXTURES = ROOT / "Tests/Fixtures/EngineSecurity"

spec = importlib.util.spec_from_file_location("engine_security", ROOT / "scripts/engine-security.py")
es = importlib.util.module_from_spec(spec)
sys.modules["engine_security"] = es  # dataclasses look their module up
spec.loader.exec_module(es)


def run(*args, engine="159.0.8154.13", data=FIXTURES):
    env = dict(os.environ, ENGINE_VERSION=engine, CRA_ENGINE_SECURITY_DATA=str(data))
    return subprocess.run([str(SCRIPT), *args], env=env, capture_output=True, text=True, cwd=ROOT)


def post(published, version, fixes, wild=()):
    lines = "".join(f"<div>[N/A][{bug}] {sev} {cve}: {what}. <i>Reported by someone</i></div>"
                    for bug, sev, cve, what in fixes)
    wild = "".join(f"<p>Google is aware that an exploit for {cve} exists in the wild.</p>" for cve in wild)
    return {"title": {"$t": "Stable Channel Update for Desktop"}, "published": {"$t": published},
            "link": [{"rel": "alternate", "href": f"https://example.invalid/{version}"}],
            "content": {"$t": f"<p>The Stable channel has been updated to {version} for Windows and Mac.</p>"
                              f"<b>Security Fixes and Rewards</b>{lines}{wild}"}}


def commit(sha, date, body):
    return f"{sha}\0{date}\0{body}\n\x1e"


class Fixture:
    """A copy of the fixture folder whose files a test replaces."""

    def __init__(self, test):
        self.dir = Path(tempfile.mkdtemp())
        test.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.dir)]))
        for f in FIXTURES.iterdir():
            (self.dir / f.name).write_bytes(f.read_bytes())

    def feed(self, *entries):
        (self.dir / "feed.json").write_text(json.dumps({"feed": {"entry": list(entries)}}))
        return self

    def log(self, tag, *commits):
        (self.dir / f"log-{tag}.txt").write_text("".join(commits))
        return self


class Cve2026134401(unittest.TestCase):
    """The day the old check said the engine was up to date."""

    def test_the_engine_on_the_beta_build_is_behind(self):
        r = run("--check")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("CVE-2026-134401", r.stdout)
        self.assertIn("Critical", r.stdout)
        self.assertIn("159.0.8154.45", r.stdout)

    def test_the_fix_is_traced_to_the_tag_that_has_it(self):
        report = es.assess(es.Source(FIXTURES), (159, 0, 8154, 13))
        [fix] = report.fixes
        self.assertEqual(fix.cve, "CVE-2026-134401")
        self.assertEqual(fix.status, es.MISSING)
        self.assertEqual(fix.fixed_in, (159, 0, 8154, 45))
        self.assertEqual(report.target, (159, 0, 8154, 45))
        self.assertTrue(report.behind)

    def test_the_build_with_the_fix_is_up_to_date(self):
        r = run("--check", engine="159.0.8154.45")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("CVE-2026-134401", r.stdout)

    def test_stable_is_what_most_macs_are_served(self):
        # The versions list named 159.0.8154.13 first. Mac stable served it only as a 0.5 % early rollout (and
        # 157.0.8103.81 to another 0.5 %); 158.0.8127.89 went to everyone else.
        report = es.assess(es.Source(FIXTURES), (159, 0, 8154, 13))
        self.assertEqual(report.stable, (158, 0, 8127, 89))
        self.assertEqual(report.early, (159, 0, 8154, 13))
        self.assertIn("159.0.8154.13 to 0.5 %", es.summary(report))


class SameBranch(unittest.TestCase):
    def test_an_older_build_of_stables_branch_misses_the_posts_fixes(self):
        r = run("--check", engine="158.0.8127.37")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("CVE-2026-134401", r.stdout)
        self.assertIn("158.0.8127.89", r.stdout)

    def test_a_newer_build_of_the_posts_branch_has_its_fixes_without_reading_git(self):
        f = Fixture(self)
        for log in f.dir.glob("log-*.txt"):
            log.unlink()
        report = es.assess(es.Source(f.dir), (158, 0, 8127, 89))
        self.assertFalse(report.behind)
        self.assertEqual([x.status for x in report.fixes], [es.IN_ENGINE])


class OtherBranch(unittest.TestCase):
    BRANCHED = "Cr-Branched-From: 5abc82b75a12aba2070f008c93349d463e81dc10-refs/heads/main@{#1739869}"

    def fixture(self, main_position):
        """Engine 159.0.8154.13 (branched at main #1739869), a 158 post fixing bug 111, landed on main at
        `main_position`."""
        f = Fixture(self)
        f.feed(post("2026-11-23T12:00:00-08:00", "158.0.8127.89", [(111, "High", "CVE-2026-1", "Use after free in Blink")]))
        f.log("158.0.8127.89", commit("a" * 40, "2026-11-21T19:00:00-08:00",
                                      f"Fix it\n\n(cherry picked from commit {'b' * 40})\n\nBug: 111\n"
                                      f"Cr-Original-Commit-Position: refs/heads/main@{{#{main_position}}}\n"
                                      "Cr-Commit-Position: refs/branch-heads/8127_36@{#20}\n"))
        return f

    def test_a_fix_that_landed_on_main_before_the_branch_is_in_the_engine(self):
        report = es.assess(es.Source(self.fixture(1739000).dir), (159, 0, 8154, 13))
        self.assertEqual([x.status for x in report.fixes], [es.IN_ENGINE])
        self.assertFalse(report.behind)

    def test_a_fix_that_landed_after_the_branch_is_missing(self):
        report = es.assess(es.Source(self.fixture(1750000).dir), (159, 0, 8154, 13))
        self.assertEqual([x.status for x in report.fixes], [es.MISSING])
        self.assertEqual(report.fixes[0].fixed_in, None)  # no 159 tag names bug 111
        self.assertTrue(report.behind)

    def test_a_fix_merged_to_the_engines_branch_is_in_the_engine(self):
        f = self.fixture(1750000)
        f.log("159.0.8154.13", commit("c" * 40, "2026-11-17T14:58:27-08:00",
                                      f"[M159] Fix it\n\n> Bug: 111\n\nBug: 999,111\n{self.BRANCHED}\n"))
        report = es.assess(es.Source(f.dir), (159, 0, 8154, 13))
        self.assertEqual([x.status for x in report.fixes], [es.IN_ENGINE])

    def test_a_fix_outside_chromium_src_counts_when_the_engine_was_tagged_after_the_post(self):
        # V8, Skia, ANGLE: no chromium/src commit names the bug. 159.0.8154.13 was tagged 17 Nov.
        f = Fixture(self).feed(post("2026-11-10T12:00:00-08:00", "158.0.8127.37", [(222, "High", "CVE-2026-2", "Type Confusion in V8")]))
        f.log("158.0.8127.37", commit("d" * 40, "2026-11-09T10:00:00-08:00", "Incrementing VERSION to 158.0.8127.37\n"))
        report = es.assess(es.Source(f.dir), (159, 0, 8154, 13))
        self.assertEqual([x.status for x in report.fixes], [es.IN_ENGINE])

    def test_a_fix_outside_chromium_src_after_the_engine_moves_it_to_a_newer_tag(self):
        f = Fixture(self).feed(post("2026-11-23T12:00:00-08:00", "158.0.8127.89", [(222, "Critical", "CVE-2026-2", "Type Confusion in V8")], wild=["CVE-2026-2"]))
        report = es.assess(es.Source(f.dir), (159, 0, 8154, 13))
        [fix] = report.fixes
        self.assertEqual(fix.status, es.UNVERIFIED)
        self.assertTrue(fix.in_the_wild)
        self.assertTrue(report.behind)
        self.assertEqual(report.target, (159, 0, 8154, 45))  # tagged 23 Nov, after the post
        r = run("--check", data=f.dir)
        self.assertIn("in the wild", r.stdout)

    def branch_only(self, published):
        """A post's fix whose only commit is a branch-only dependency roll: no main revision (the M157 ICU roll that
        named two 157.0.8103.79 V8 CVEs, 604a1c1548)."""
        f = Fixture(self).feed(post(published, "157.0.8103.79", [(444, "High", "CVE-2026-4", "Use after free in V8")]))
        f.log("157.0.8103.79", commit("e" * 40, "2026-11-05T00:08:03-08:00",
                                      "[M157] Roll src/third_party/icu/ 2a51536df..c670d12 (2 commits)\n\n"
                                      "Bug: 574025697, 444\nCr-Commit-Position: refs/branch-heads/8103@{#1213}\n"
                                      "Cr-Branched-From: e7baefea94b4a90087e3043e4a8effec33c2025f-refs/heads/main@{#1717349}\n"))
        return es.assess(es.Source(f.dir), (159, 0, 8154, 13))

    def test_a_branch_only_fix_counts_when_the_engine_was_tagged_after_the_post(self):
        report = self.branch_only("2026-11-11T12:00:00-08:00")
        self.assertEqual([x.status for x in report.fixes], [es.IN_ENGINE])
        self.assertFalse(report.behind)

    def test_a_branch_only_fix_after_the_engine_is_not_called_missing(self):
        report = self.branch_only("2026-11-23T12:00:00-08:00")
        self.assertEqual([x.status for x in report.fixes], [es.UNVERIFIED])
        self.assertEqual(report.target, (159, 0, 8154, 45))

    def test_posts_from_well_before_the_engine_are_not_read(self):
        f = Fixture(self).feed(post("2026-10-01T12:00:00-07:00", "157.0.8103.20", [(333, "High", "CVE-2026-3", "Old")]))
        report = es.assess(es.Source(f.dir), (159, 0, 8154, 13))
        self.assertEqual(report.fixes, [])
        self.assertFalse(report.behind)


class NewerStable(unittest.TestCase):
    def test_a_newer_stable_than_the_engine_is_the_target_even_without_a_post(self):
        f = Fixture(self).feed()
        report = es.assess(es.Source(f.dir), (157, 0, 8103, 79))
        self.assertTrue(report.behind)
        self.assertEqual(report.target, (158, 0, 8127, 89))


class Parsing(unittest.TestCase):
    def test_a_posts_versions_fixes_and_skipped_titles(self):
        posts = es.parse_feed(json.loads((FIXTURES / "feed.json").read_text()))
        self.assertEqual(len(posts), 1)  # ChromeOS, Extended Stable and Dev are other posts
        [p] = posts
        self.assertEqual(p.version, (158, 0, 8127, 89))
        self.assertEqual([(x.bug, x.severity, x.cve, x.what) for x in p.fixes],
                         [("554051967", "Critical", "CVE-2026-134401", "Improper input validation in Variations")])

    def test_commit_trailers(self):
        commits = es.parse_log((FIXTURES / "log-159.0.8154.45.txt").read_text())
        fix = next(c for c in commits if "554051967" in c.bugs)
        self.assertEqual(fix.main_position, 1750792)  # the quoted original, not branch-heads/8154@{#1203}
        self.assertEqual(fix.branched_from, 1739869)
        self.assertIn("588460249", fix.bugs)

    def test_the_issue_changes_only_when_its_news_does(self):
        report = es.assess(es.Source(FIXTURES), (159, 0, 8154, 13))
        body = es.issue_body(report)
        self.assertEqual(es.issue_action(None, report), "create")
        self.assertEqual(es.issue_action(body, report), "none")
        self.assertEqual(es.issue_action(body.replace("CVE-2026-134401", "CVE-2026-1"), report), "update")


if __name__ == "__main__":
    unittest.main()
