#!/usr/bin/env python3
"""scripts/web-features.py: the map of every way a page reaches its browser (docs/web-features.md), on a throwaway
copy of the layout and a made-up Chromium header."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/web-features.py"
spec = importlib.util.spec_from_file_location("web_features", SCRIPT)
web_features = importlib.util.module_from_spec(spec)
spec.loader.exec_module(web_features)

HEADER = """namespace content {
class CONTENT_EXPORT WebContentsDelegate {
 public:
  WebContentsDelegate();
  // A page's file picker.
  virtual void RunFileChooser(RenderFrameHost* render_frame_host,
                              scoped_refptr<FileSelectListener> listener);
  virtual bool IsFullscreenForTabOrPending(const WebContents* web_contents);
  virtual ~WebContentsDelegate();
};
}
"""

MAP = """# kind\tname\thow\twhat
delegate\tRunFileChooser\tscenarios upload-picker\t<input type=file>
delegate\tIsFullscreenForTabOrPending\tn/a: only Chrome's own window asks\tdocument.fullscreenElement
feature\tpasskey with Touch ID\tchecklist\tnavigator.credentials.create
"""


class WebFeaturesTests(unittest.TestCase):
    def layout(self, tsv=MAP, checklist="- web feature: passkey with Touch ID. On webauthn.io…\n", header=HEADER):
        root = Path(tempfile.mkdtemp())
        (root / "Tests/Scenarios").mkdir(parents=True)
        (root / "Tests/Scenarios/upload-picker.scenario").write_text("cra://open?url=${PAGE}\n")
        (root / "Tests/web-features.tsv").write_text(tsv)
        (root / "docs").mkdir()
        (root / "docs/release-checklist.md").write_text(checklist)
        src = root / "chromium"
        (src / "content/public/browser").mkdir(parents=True)
        (src / "content/public/browser/web_contents_delegate.h").write_text(header)
        return root, src

    def test_a_complete_map_passes(self):
        root, src = self.layout()
        self.assertEqual(web_features.check(root, src), [])

    def test_the_delegate_methods_are_read_from_the_header(self):
        self.assertEqual(web_features.delegate_methods(HEADER), ["RunFileChooser", "IsFullscreenForTabOrPending"])

    def test_a_new_chrome_page_hook_fails_until_it_is_mapped(self):
        root, src = self.layout(header=HEADER.replace(
            "  virtual ~WebContentsDelegate();",
            "  virtual void OpenEyeDropper(RenderFrameHost* frame);\n  virtual ~WebContentsDelegate();"))
        problems = web_features.check(root, src)
        self.assertEqual(len(problems), 1)
        self.assertIn("WebContentsDelegate::OpenEyeDropper is new in this Chrome", problems[0])

    def test_a_method_chrome_dropped_must_leave_the_map(self):
        root, src = self.layout(header=HEADER.replace(
            "  virtual bool IsFullscreenForTabOrPending(const WebContents* web_contents);\n", ""))
        self.assertEqual(web_features.check(root, src),
                         ["web-features.tsv: WebContentsDelegate::IsFullscreenForTabOrPending is gone from this Chrome; "
                          "take its row out"])

    def test_without_a_chromium_tree_only_the_map_is_checked(self):
        root, _ = self.layout(header=HEADER.replace("RunFileChooser", "Renamed"))
        self.assertEqual(web_features.check(root), [])

    def test_a_scenario_that_does_not_exist_fails(self):
        root, src = self.layout(tsv=MAP.replace("scenarios upload-picker", "scenarios upload-picker,upload-gone"))
        self.assertEqual(web_features.check(root, src),
                         ["web-features.tsv:2 RunFileChooser: no scenario Tests/Scenarios/upload-gone.scenario"])

    def test_a_checklist_row_needs_its_line(self):
        root, src = self.layout(checklist="- something else\n")
        problems = web_features.check(root, src)
        self.assertEqual(len(problems), 1)
        self.assertIn("passkey with Touch ID: no line with 'web feature: passkey with Touch ID'", problems[0])

    def test_not_applicable_needs_a_reason(self):
        root, src = self.layout(tsv=MAP.replace("n/a: only Chrome's own window asks", "n/a: "))
        self.assertIn("IsFullscreenForTabOrPending: n/a needs a reason", web_features.check(root, src)[0])

    def test_an_unknown_how_fails(self):
        root, src = self.layout(tsv=MAP.replace("scenarios upload-picker", "tested by hand"))
        self.assertIn("how is 'tested by hand'", web_features.check(root, src)[0])

    def test_a_row_twice_fails(self):
        root, src = self.layout(tsv=MAP + "delegate\tRunFileChooser\tscenarios upload-picker\tagain\n")
        self.assertIn("also on line 2", web_features.check(root, src)[0])

    def test_the_scenario_list_has_each_scenario_once(self):
        root, _ = self.layout(tsv=MAP + "feature\tfolder upload\tscenarios upload-picker\twebkitdirectory\n")
        self.assertEqual(web_features.all_scenarios(root), ["upload-picker"])

    # Tests/release-gate.tsv: what a release once shipped broken, run by every release with the map's scenarios.

    def gate(self, root, rows):
        (root / "Tests/release-gate.tsv").write_text("# scenario\tissue\twhat broke\n" + rows)

    def test_the_release_gate_runs_after_the_map_each_scenario_once(self):
        root, src = self.layout()
        (root / "Tests/Scenarios/devtools-draws.scenario").write_text("# promise: #468\n")
        self.gate(root, "devtools-draws\t#468\tDevTools stayed blank after 0.1.44\n"
                        "upload-picker\t#571\tupload buttons did nothing\n")
        self.assertEqual(web_features.check(root, src), [])
        self.assertEqual(web_features.all_scenarios(root), ["upload-picker", "devtools-draws"])

    def test_without_a_release_gate_only_the_map_runs(self):
        root, _ = self.layout()
        self.assertEqual(web_features.all_scenarios(root), ["upload-picker"])

    def test_a_release_gate_scenario_that_does_not_exist_fails(self):
        root, src = self.layout()
        self.gate(root, "devtools-gone\t#468\tDevTools stayed blank\n")
        self.assertEqual(web_features.check(root, src),
                         ["release-gate.tsv:2 devtools-gone: no scenario Tests/Scenarios/devtools-gone.scenario"])

    def test_a_release_gate_row_names_its_issue_and_what_broke(self):
        root, src = self.layout()
        self.gate(root, "upload-picker\tsome day\tupload buttons did nothing\nupload-picker\t#571\t\n")
        problems = web_features.check(root, src)
        self.assertEqual(len(problems), 2)
        self.assertIn("release-gate.tsv:2 upload-picker: issue is 'some day'", problems[0])
        self.assertIn("release-gate.tsv:3 upload-picker: says nothing about what broke", problems[1])


if __name__ == "__main__":
    unittest.main()
