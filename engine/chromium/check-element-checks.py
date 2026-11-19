#!/usr/bin/env python3
"""check-element-checks.py <chromium src>: fails when Chrome's own code CHECKs that it found a UI element.

On the engine a page's Browser is a profile's hidden one, whose views Chrome's element tracker may not find:
Clear browsing data's Cancel crashed Cra 0.1.50 on `CHECK(browser_element)` after
`ui::ElementTracker::GetUniqueElement(kBrowserViewElementId, …)` (crash-clear-browsing-data-cancel).
cra-browser-element-checks.patch turns those into null checks. This runs after the patches (apply.sh), so a new
Chrome that adds another such CHECK stops the engine build until it gets the same treatment.
"""
import pathlib
import re
import sys

LOOKUP = re.compile(r"(\w+)\s*=\s*(?:ui::)?ElementTracker::GetElementTracker\(\)\s*->\s*(?:GetUniqueElement|GetFirstMatchingElement)\(")
LOOKUP_START = re.compile(r"(\w+)\s*=\s*$")
CALL = re.compile(r"ElementTracker::GetElementTracker\(\)\s*->\s*(?:GetUniqueElement|GetFirstMatchingElement)\(")


def findings(src: pathlib.Path):
    root = src / "chrome" / "browser"
    for path in sorted(root.rglob("*")):
        if path.suffix not in (".cc", ".mm") or "test" in path.name or "/test/" in str(path):
            continue
        lines = path.read_text(errors="replace").splitlines()
        for i, line in enumerate(lines):
            if not CALL.search(line):
                continue
            # The variable the lookup is assigned to, on this line or the one before (clang-format splits them).
            m = LOOKUP.search(line) or (LOOKUP_START.search(lines[i - 1]) if i else None)
            if not m:
                continue
            name = m.group(1)
            for j in range(i + 1, min(i + 6, len(lines))):
                if re.search(rf"\b(?:CHECK|DCHECK|CHECK_NE)\(\s*{re.escape(name)}\b", lines[j]):
                    yield f"{path.relative_to(src)}:{j + 1}: {lines[j].strip()}"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    found = list(findings(pathlib.Path(sys.argv[1])))
    if found:
        print("Chrome CHECKs that it found a UI element; on the engine a page's hidden Browser may have none, and Cra")
        print("crashes (crash-clear-browsing-data-cancel). Make each a null check, as cra-browser-element-checks.patch does:")
        print("\n".join(f"  {f}" for f in found))
        sys.exit(1)
    print("element checks: none")


if __name__ == "__main__":
    main()
