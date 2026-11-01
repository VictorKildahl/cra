#!/usr/bin/env python3 -I
"""Cra's own lint: the bug classes that kept shipping, as rules over Sources/Cra.

Existing code is grandfathered in Tests/lint-baseline.txt (rule, file, count); a file that
gains a finding fails, one that loses one is reported so the baseline can come down
(scripts/lint.py --update-baseline). Rules:

  layer-colour-outside-transaction
      A colour or opacity set on a CALayer Cra made itself (not a view's backing layer)
      outside CATransaction.begin()/commit() with actions disabled animates for 0.25 s:
      a flash on every theme or window-activation change. Inits are exempt (not on screen), and
      so is a layer whose `actions` map the property to NSNull().
  timer-outside-scheduler
      Timer.scheduledTimer in App/, Services/ or Model/: decisions taken from time run on the
      injectable clock (Scheduler), or no test can reach them. UI animation timers are exempt.
  wall-clock-in-decision
      Date() in a file whose decisions run on the clock (store, tab sleep, live folders).
  raw-observation-tracking
      withObservationTracking reached directly. The closure must read properties of an
      @Observable class; a struct copied out before it (or a plain class) is never tracked and
      the view silently stops updating. New sites go through CraCore's observeChanges(of:apply:),
      where that is reviewed once.
  importer-without-fixture
      An importer (enum …Importer) without a checked-in profile under Tests/Fixtures/<Name>:
      parsers are tested against files in the source browser's format, not dictionaries.
"""
import collections
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Sources", "Cra")
BASELINE = os.path.join(ROOT, "Tests", "lint-baseline.txt")

LAYER_SET = re.compile(r"\b(?!layer\b)(\w*[Ll]ayer)\.(backgroundColor|borderColor|colors|opacity|shadowColor|fillColor|strokeColor)\s*=")
FUNC_START = re.compile(r"^\s*(?:@\w+\s+)*(?:(?:private|fileprivate|internal|public|override|static|final|class|nonisolated|convenience|required|@objc)\s+)*(func\s|init[(?!])")
CLOCK_FILES = {"Services/SidebarStore.swift", "Services/BrowserManager.swift", "Services/LiveFolderManager.swift",
               "Services/SidebarIntegrity.swift", "App/AppComposition.swift"}


def swift_files():
    for dirpath, _, names in os.walk(SOURCES):
        for n in sorted(names):
            if n.endswith(".swift"):
                full = os.path.join(dirpath, n)
                yield os.path.relpath(full, SOURCES), full


def code(line):
    """The line without a trailing // comment (good enough: no rule matches inside strings)."""
    return line.split("//", 1)[0]


def findings():
    out = collections.Counter()
    where = collections.defaultdict(list)

    def hit(rule, rel, lineno):
        out[(rule, rel)] += 1
        where[(rule, rel)].append(lineno)

    for rel, full in swift_files():
        with open(full, encoding="utf-8") as f:
            lines = f.readlines()
        depth, in_init = 0, False
        top = rel.split("/", 1)[0]
        # Layers with the animation turned off for good: fillLayer.actions = ["backgroundColor": NSNull(), …]
        quiet = {(name, prop) for name, body in re.findall(r"\b(\w+)\.actions\s*=\s*\[([^\]]*)\]", "".join(lines))
                 for prop in re.findall(r'"(\w+)"\s*:\s*NSNull\(\)', body)}
        for i, raw in enumerate(lines, 1):
            line = code(raw)
            m = FUNC_START.match(line)
            if m:
                depth, in_init = 0, m.group(1).startswith("init")
            depth += line.count("CATransaction.begin()") - line.count("CATransaction.commit()")
            for m in LAYER_SET.finditer(line):
                if depth <= 0 and not in_init and "setDisableActions" not in line and (m.group(1), m.group(2)) not in quiet:
                    hit("layer-colour-outside-transaction", rel, i)
            if "Timer.scheduledTimer" in line and top in ("App", "Services", "Model") and rel != "Services/Scheduler.swift":
                hit("timer-outside-scheduler", rel, i)
            if rel in CLOCK_FILES and re.search(r"\bDate\(\)", line):
                hit("wall-clock-in-decision", rel, i)
            if "withObservationTracking" in line:
                hit("raw-observation-tracking", rel, i)
            for name in re.findall(r"\benum (\w+)Importer\b", line):
                if not os.path.isdir(os.path.join(ROOT, "Tests", "Fixtures", name)):
                    hit("importer-without-fixture", f"{rel}:{name}", i)
    return out, where


def load_baseline():
    base = collections.Counter()
    if os.path.exists(BASELINE):
        with open(BASELINE, encoding="utf-8") as f:
            for line in f:
                if line.strip() and not line.startswith("#"):
                    rule, rel, n = line.rstrip("\n").split("\t")
                    base[(rule, rel)] = int(n)
    return base


def main():
    found, where = findings()
    if "--update-baseline" in sys.argv:
        with open(BASELINE, "w", encoding="utf-8") as f:
            f.write("# scripts/lint.py findings in code older than the rule. Only ever lower these.\n")
            for (rule, rel), n in sorted(found.items()):
                f.write(f"{rule}\t{rel}\t{n}\n")
        print(f"Baseline: {sum(found.values())} findings in {len(found)} files")
        return 0
    base = load_baseline()
    failed = False
    for key, n in sorted(found.items()):
        if n > base.get(key, 0):
            failed = True
            rule, rel = key
            lines = ", ".join(map(str, where[key]))
            print(f"Sources/Cra/{rel.split(':')[0]}: {rule}: {n} (baseline {base.get(key, 0)}), lines {lines}")
    lower = [(k, base[k], found.get(k, 0)) for k in sorted(base) if found.get(k, 0) < base[k]]
    for (rule, rel), was, now in lower:
        print(f"note: {rel}: {rule} down from {was} to {now}; run scripts/lint.py --update-baseline")
    if failed:
        print("lint: new findings (see the rule descriptions at the top of scripts/lint.py)")
        return 1
    print(f"lint: clean ({sum(found.values())} grandfathered findings)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
