#!/usr/bin/env python3
"""The web features whose browser side Cra provides, and the tests that keep them working (docs/web-features.md).

On the engine Cra shows Chrome's pages in its own windows while each page's Chrome Browser keeps a never-seen
window of its own. Chrome's code for a page's file picker, print preview, dialogs, prompts and choosers reads
that window, and 0.1.49 shipped with every file picker cancelled (#571) and print preview 3 pt tall (#574)
because nothing exercised them. Tests/web-features.tsv lists every way a page reaches its browser: each method
of content::WebContentsDelegate (Chrome's interface for it) and the features Chrome serves outside it
(permission prompts, choosers, passkeys, payments, sharing). Each row is tested by scenarios, by a line in
docs/release-checklist.md, or says why a page can't reach it on a Mac.

  scripts/web-features.py                  check the map: every scenario it names exists, every checklist row has
                                           its line in docs/release-checklist.md (scripts/test.sh)
  scripts/web-features.py --chromium SRC   also check it against that Chromium tree: every WebContentsDelegate
                                           method is in the map, and the map has none Chrome dropped
                                           (scripts/build-chromium.sh and scripts/publish-engine.sh, so a new
                                           Chrome's new page hook stops the engine until someone decides its test)
  scripts/web-features.py --scenarios      the scenarios, one per line (scripts/scenario.sh web-features): the
                                           map's, then Tests/release-gate.tsv's (what a release once shipped
                                           broken outside the map: DevTools, profiles, a page's new tab…)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DELEGATE_HEADER = "content/public/browser/web_contents_delegate.h"
KINDS = {"delegate", "feature"}


def read_map(path):
    """Rows of (line number, kind, name, how, what). `how` is `scenarios a,b`, `checklist` or `n/a: <why>`."""
    rows = []
    for n, raw in enumerate(path.read_text().splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        cols = raw.split("\t")
        if len(cols) != 4:
            sys.exit(f"{path.name}:{n}: four tab-separated columns (kind, name, how, what), got {len(cols)}")
        rows.append((n, *[c.strip() for c in cols]))
    return rows


def read_gate(path):
    """Rows of (line number, scenario, issue, what broke) from Tests/release-gate.tsv; none when it isn't there."""
    if not path.is_file():
        return []
    rows = []
    for n, raw in enumerate(path.read_text().splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        cols = (raw.split("\t") + ["", ""])[:3]
        rows.append((n, *[c.strip() for c in cols]))
    return rows


def scenarios_of(how):
    return [s.strip() for s in how[len("scenarios "):].split(",") if s.strip()] if how.startswith("scenarios ") else []


def delegate_methods(header_text):
    """The virtual methods content::WebContentsDelegate declares, in order."""
    text = re.sub(r"//[^\n]*", "", header_text)
    start = text.find("class CONTENT_EXPORT WebContentsDelegate")
    text = text[start:] if start >= 0 else text
    names = []
    for name in re.findall(r"virtual\s+[^;{(]*?\b(\w+)\s*\(", text):
        if name not in names and name != "WebContentsDelegate":
            names.append(name)
    return names


def check(root, chromium=None):
    """Problems with the map, one string each."""
    problems = []
    tsv = root / "Tests/web-features.tsv"
    rows = read_map(tsv)
    scenario_dir = root / "Tests/Scenarios"
    checklist = (root / "docs/release-checklist.md").read_text()
    seen = {}
    for n, kind, name, how, what in rows:
        where = f"{tsv.name}:{n} {name}"
        if kind not in KINDS:
            problems.append(f"{where}: kind is {kind!r}, not one of {sorted(KINDS)}")
        if (kind, name) in seen:
            problems.append(f"{where}: also on line {seen[(kind, name)]}")
        seen[(kind, name)] = n
        if not what:
            problems.append(f"{where}: says nothing about what a page does to reach it")
        if how.startswith("scenarios "):
            names = scenarios_of(how)
            if not names:
                problems.append(f"{where}: names no scenario")
            for s in names:
                if not (scenario_dir / f"{s}.scenario").is_file():
                    problems.append(f"{where}: no scenario Tests/Scenarios/{s}.scenario")
        elif how == "checklist":
            if f"web feature: {name}" not in checklist:
                problems.append(f"{where}: no line with 'web feature: {name}' in docs/release-checklist.md")
        elif how.startswith("n/a:"):
            if len(how[len("n/a:"):].strip()) < 8:
                problems.append(f"{where}: n/a needs a reason")
        else:
            problems.append(f"{where}: how is {how!r}: 'scenarios a,b', 'checklist' or 'n/a: <why>'")
    gate = root / "Tests/release-gate.tsv"
    for n, scenario, issue, what in read_gate(gate):
        where = f"{gate.name}:{n} {scenario}"
        if not (scenario_dir / f"{scenario}.scenario").is_file():
            problems.append(f"{where}: no scenario Tests/Scenarios/{scenario}.scenario")
        if not re.fullmatch(r"#\d+|crash-[\w-]+", issue):
            problems.append(f"{where}: issue is {issue!r}, not '#<n>' or 'crash-<what-crashed>'")
        if not what:
            problems.append(f"{where}: says nothing about what broke")
    if chromium is not None:
        header = Path(chromium) / DELEGATE_HEADER
        if not header.is_file():
            problems.append(f"no {DELEGATE_HEADER} in {chromium}")
        else:
            methods = delegate_methods(header.read_text())
            mapped = {name for _, kind, name, _, _ in rows if kind == "delegate"}
            for m in methods:
                if m not in mapped:
                    problems.append(f"WebContentsDelegate::{m} is new in this Chrome and not in {tsv.name}: "
                                    "find what a page does to reach it and add its row with a test "
                                    "(docs/web-features.md)")
            for m in sorted(mapped - set(methods)):
                problems.append(f"{tsv.name}: WebContentsDelegate::{m} is gone from this Chrome; take its row out")
    return problems


def all_scenarios(root):
    """The map's scenarios, then the release gate's, each once."""
    names = []
    for _, _, _, how, _ in read_map(root / "Tests/web-features.tsv"):
        for s in scenarios_of(how):
            if s not in names:
                names.append(s)
    for _, s, _, _ in read_gate(root / "Tests/release-gate.tsv"):
        if s and s not in names:
            names.append(s)
    return names


def main(argv):
    if argv[1:2] == ["--scenarios"]:
        print("\n".join(all_scenarios(ROOT)))
        return 0
    chromium = None
    if argv[1:2] == ["--chromium"]:
        if len(argv) < 3:
            sys.exit("usage: scripts/web-features.py --chromium <chromium src>")
        chromium = argv[2]
    problems = check(ROOT, chromium)
    for p in problems:
        print(f"✗ {p}")
    if problems:
        print(f"web features: {len(problems)} problem(s) (docs/web-features.md)")
        return 1
    rows = read_map(ROOT / "Tests/web-features.tsv")
    tested = sum(1 for r in rows if r[3].startswith("scenarios "))
    gate = len(read_gate(ROOT / "Tests/release-gate.tsv"))
    print(f"web features: {len(rows)} rows, {tested} tested; {len(all_scenarios(ROOT))} scenarios with the "
          f"release gate's {gate}"
          + (", every WebContentsDelegate method of this Chrome mapped" if chromium else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
