#!/usr/bin/env python3
"""The test-*.sh loops (scripts/coverage.py and nightly.yml's sanitizer job) run only harnesses: every script they pick up
is a suite in scripts/test.sh, and the two copies of the skip list agree."""
import importlib.util
from pathlib import Path
import re
import shlex
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("coverage", ROOT / "scripts/coverage.py")
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)


def looped():
    """What coverage.py and the nightly loop run as harnesses, relative to the repo."""
    found = {str(p.relative_to(ROOT)) for d in ("scripts", "Tests") for p in (ROOT / d).glob("test-*.sh")}
    return sorted(found - coverage.NOT_HARNESSES)


def suites():
    """Every argument of every `suite "name" cmd ...` line in scripts/test.sh."""
    args = set()
    for line in (ROOT / "scripts/test.sh").read_text().splitlines():
        if re.match(r'\s*suite\s+"', line):
            args.update(shlex.split(line)[2:])
    return args


class HarnessTests(unittest.TestCase):
    def test_every_looped_script_is_a_suite_in_test_sh(self):
        missing = [s for s in looped() if s not in suites()]
        self.assertEqual(missing, [], "\n".join(
            f"{s}: coverage.py and the nightly sanitizer loop run it as a harness, but scripts/test.sh doesn't. "
            "Wire it into scripts/test.sh with a `suite` line, or rename it if it isn't a test." for s in missing))

    def test_coverage_pys_ordering_lists_name_only_harnesses(self):
        stale = [s for s in coverage.SERIAL + coverage.FIRST if s.endswith(".sh") and s not in looped()]
        self.assertEqual(stale, [], "scripts/coverage.py's SERIAL or FIRST names scripts it doesn't run as harnesses")

    def test_the_nightly_skip_list_is_coverage_pys(self):
        nightly = (ROOT / ".github/workflows/nightly.yml").read_text()
        skip = re.search(r'case "\$t" in (\S+)\) continue', nightly)
        self.assertIsNotNone(skip, "nightly.yml: no `case \"$t\" in ...) continue` line in the harness loop")
        self.assertEqual(set(skip.group(1).split("|")), coverage.NOT_HARNESSES,
                         "nightly.yml's harness loop skips other files than scripts/coverage.py's NOT_HARNESSES")


if __name__ == "__main__":
    unittest.main()
