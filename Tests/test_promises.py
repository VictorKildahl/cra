#!/usr/bin/env python3
"""scripts/promises.py pins tests by issue (#n) and by crash ID (crash-a-b), on a throwaway copy of the layout."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/promises.py"

SCENARIO = """# promise: crash-fedcm-dialog
# What the journey checks.
cra://open?url=${PAGE}
expect-log loaded
"""

CORE = """import Testing
struct PerfTests {
    @Test(.bug(id: "crash-perf-counter-overflow")) func saturates() {
        #expect(Int64.max.addingReportingOverflow(0).overflow == false)
    }
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/155")) func themeFollowsMacOS() {
        #expect(true)
    }
    @Test func untagged() {}
}
"""

HARNESS = """enum StoreTests {
    static func main() { zenFaviconSize() }

    // promise: crash-zen-favicon-size
    /// An SVG favicon is drawn small.
    private static func zenFaviconSize() {
        check(64)
    }
}
"""


class PromisesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy(SCRIPT, self.root / "scripts/promises.py")
        self.write("Tests/Scenarios/fedcm.scenario", SCENARIO)
        self.write("Packages/CraCore/Tests/CraCoreTests/PerfTests.swift", CORE)
        self.write("Tests/StoreTests.swift", HARNESS)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def run_script(self, *args):
        return subprocess.run(["python3", "-I", str(self.root / "scripts/promises.py"), *args],
                              capture_output=True, text=True)

    def lock(self):
        result = self.run_script("--update")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return (self.root / "Tests/promises.lock").read_text()

    def test_crash_ids_and_issues_are_locked(self):
        lock = self.lock()
        entries = [line.split()[:2] for line in lock.splitlines() if not line.startswith("# ")]
        self.assertEqual(entries, [
            ["#155", "Packages/CraCore/Tests/CraCoreTests/PerfTests.swift::themeFollowsMacOS"],
            ["crash-fedcm-dialog", "Tests/Scenarios/fedcm.scenario"],
            ["crash-perf-counter-overflow", "Packages/CraCore/Tests/CraCoreTests/PerfTests.swift::saturates"],
            ["crash-zen-favicon-size", "Tests/StoreTests.swift::zenFaviconSize"],
        ])
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("4 tests pinned for 1 issues and 3 crash fixes, unchanged", result.stdout)

    def test_an_issue_line_keeps_its_old_format(self):
        lock = self.lock()
        self.assertRegex(lock, r"(?m)^#155   Packages/CraCore/Tests/CraCoreTests/PerfTests\.swift::themeFollowsMacOS  [0-9a-f]{12}$")

    def test_a_changed_crash_test_fails(self):
        self.lock()
        self.write("Tests/Scenarios/fedcm.scenario", SCENARIO.replace("expect-log loaded\n", ""))
        self.write("Tests/StoreTests.swift", HARNESS.replace("check(64)", "check(4096)"))
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn("crash-fedcm-dialog Tests/Scenarios/fedcm.scenario changed", result.stdout)
        self.assertIn("crash-zen-favicon-size Tests/StoreTests.swift::zenFaviconSize changed", result.stdout)

    def test_a_deleted_or_untagged_crash_test_fails(self):
        self.lock()
        (self.root / "Tests/Scenarios/fedcm.scenario").unlink()
        self.write("Packages/CraCore/Tests/CraCoreTests/PerfTests.swift",
                   CORE.replace('@Test(.bug(id: "crash-perf-counter-overflow")) func saturates', "@Test func saturates"))
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn("crash-fedcm-dialog Tests/Scenarios/fedcm.scenario is gone", result.stdout)
        self.assertIn("crash-perf-counter-overflow Packages/CraCore/Tests/CraCoreTests/PerfTests.swift::saturates is gone",
                      result.stdout)

    def test_a_new_crash_test_needs_the_lock(self):
        self.lock()
        self.write("Tests/Scenarios/tooltip.scenario", "# promise: crash-tooltip-over-sheet\nwait 1\n")
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertIn("crash-tooltip-over-sheet Tests/Scenarios/tooltip.scenario is new", result.stdout)

    def test_a_promise_line_it_cant_read_stops_the_check(self):
        # A misspelt tag would otherwise leave the test unpinned without a word.
        for tag in ["Crash-FedCM", "crash_fedcm", "crash-", "fedcm"]:
            with self.subTest(tag=tag):
                self.write("Tests/Scenarios/fedcm.scenario", SCENARIO.replace("crash-fedcm-dialog", tag))
                result = self.run_script("--update")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("names no issue (#n) or crash ID", result.stdout + result.stderr)

    def test_a_crash_promise_nothing_calls_stops_the_check(self):
        self.write("Tests/StoreTests.swift", HARNESS.replace("static func main() { zenFaviconSize() }", "static func main() {}"))
        result = self.run_script("--update")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("zenFaviconSize is a promise that nothing calls", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
