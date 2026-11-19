#!/usr/bin/env python3
"""engine/chromium/check-element-checks.py, on made-up Chrome files: it must flag Chrome code that CHECKs it found
a UI element (Clear browsing data's Cancel crashed Cra 0.1.50 on one, crash-clear-browsing-data-cancel) and leave
null checks and tests alone. Run by scripts/test.sh."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

CHECKER = pathlib.Path(__file__).resolve().parent.parent / "engine" / "chromium" / "check-element-checks.py"

CHECKED = """
void Notify(tabs::TabInterface* tab) {
  ui::TrackedElement* const browser_element =
      ui::ElementTracker::GetElementTracker()->GetUniqueElement(
          kBrowserViewElementId, context);
  CHECK(browser_element);
}
"""
ONE_LINE = """
  auto* element = ui::ElementTracker::GetElementTracker()->GetFirstMatchingElement(kSomeId, context);
  CHECK(element);
"""
NULL_CHECKED = """
  ui::TrackedElement* const browser_element =
      ui::ElementTracker::GetElementTracker()->GetUniqueElement(
          kBrowserViewElementId, context);
  if (!browser_element) {
    return;
  }
"""


class ElementChecks(unittest.TestCase):
    def run_checker(self, files):
        with tempfile.TemporaryDirectory() as src:
            for name, text in files.items():
                path = pathlib.Path(src, name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            return subprocess.run([sys.executable, str(CHECKER), src], capture_output=True, text=True)

    def test_flags_a_check_on_a_split_lookup(self):
        r = self.run_checker({"chrome/browser/ui/webui/settings/handler.cc": CHECKED})
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("chrome/browser/ui/webui/settings/handler.cc:6: CHECK(browser_element);", r.stdout)

    def test_flags_a_check_on_a_one_line_lookup(self):
        r = self.run_checker({"chrome/browser/ui/thing.mm": ONE_LINE})
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("thing.mm:3: CHECK(element);", r.stdout)

    def test_null_checks_pass(self):
        r = self.run_checker({"chrome/browser/ui/webui/settings/handler.cc": NULL_CHECKED})
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("element checks: none", r.stdout)

    def test_tests_are_left_alone(self):
        r = self.run_checker({"chrome/browser/ui/handler_unittest.cc": CHECKED,
                              "chrome/browser/ui/test/helper.cc": CHECKED})
        self.assertEqual(r.returncode, 0, r.stdout)


if __name__ == "__main__":
    unittest.main()
