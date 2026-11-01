#!/usr/bin/env python3 -I
"""Mutation testing of the pure code: proof the tests assert something.

Each mutant flips one operator (== to !=, < to >=, && to ||, true to false, + 1 to - 1,
drops a !) in one of the files below and runs the tests that cover that file. A mutant the
tests catch is killed; one they don't survives, and points at a decision nothing checks.
Below 70 % killed fails. Weekly in CI (scripts take minutes: every mutant is a compile).

  scripts/mutate.py                  every target
  scripts/mutate.py DevToolsToggle   targets whose path contains the word
"""
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIN_SCORE = 70.0

# Pure decisions and the harness that checks them.
TARGETS = [
    ("Sources/Cra/Services/DevToolsToggle.swift", ["bash", "scripts/test-policies.sh"]),
    ("Sources/Cra/UI/Windows/ExtensionLaunch.swift", ["bash", "scripts/test-policies.sh"]),
    ("Sources/Cra/UI/ToolbarComposition.swift", ["bash", "scripts/test-policies.sh"]),
    ("Sources/Cra/Services/SidebarIntegrity.swift", ["bash", "scripts/test-store.sh"]),
    ("Sources/Cra/App/AppComposition.swift", ["bash", "scripts/test-store.sh"]),
    ("Sources/Cra/App/FeatureFlags.swift", ["bash", "scripts/test-policies.sh"]),
] + [(os.path.relpath(p, ROOT), ["swift", "test", "--package-path", "Packages/CraCore"])
     for p in sorted(glob.glob(os.path.join(ROOT, "Packages/CraCore/Sources/CraCore/*.swift")))]

OPERATORS = [
    (r" == ", " != "), (r" != ", " == "), (r" < ", " >= "), (r" > ", " <= "), (r" <= ", " > "), (r" >= ", " < "),
    (r" && ", " || "), (r" \|\| ", " && "), (r"\btrue\b", "false"), (r"\bfalse\b", "true"),
    (r" \+ 1\b", " - 1"), (r" - 1\b", " + 1"), (r"(?<=[\s(,])!(?=[A-Za-z_(])", ""),
]


def mutants(text):
    lines = text.split("\n")
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith(("//", "///", "import ", "case ", "enum ", "struct ", "@")):
            continue
        code = line.split("//", 1)[0]
        for pattern, repl in OPERATORS:
            for m in re.finditer(pattern, code):
                # Skip generics and string literals: crude, but a bad mutant only fails to compile.
                if code.count('"', 0, m.start()) % 2:
                    continue
                mutated = line[:m.start()] + repl + line[m.end():]
                yield i + 1, f"{m.group(0).strip() or '!'} → {repl.strip() or '(nothing)'}", "\n".join(lines[:i] + [mutated] + lines[i + 1:])


def main():
    words = [a for a in sys.argv[1:] if not a.startswith("-")]
    killed, survived, invalid = 0, [], 0
    for rel, cmd in TARGETS:
        if words and not any(w in rel for w in words):
            continue
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        original = open(path, encoding="utf-8").read()
        baseline = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if baseline.returncode != 0:
            sys.exit(f"{' '.join(cmd)} fails before any mutation:\n{baseline.stdout[-1500:]}{baseline.stderr[-1500:]}")
        k = s = 0
        try:
            for line, what, text in mutants(original):
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text)
                try:
                    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=300)
                    out = r.stdout + r.stderr
                except subprocess.TimeoutExpired:
                    k += 1  # a mutant that hangs the tests is caught
                    continue
                if r.returncode == 0:
                    s += 1
                    survived.append(f"{rel}:{line}: {what}")
                elif "error:" in out and "FAIL:" not in out and "failed" not in out.lower().split("error:")[0][-200:]:
                    invalid += 1  # did not compile: not a mutant
                else:
                    k += 1
        finally:
            with open(path, "w", encoding="utf-8") as f:
                f.write(original)
        killed += k
        print(f"{rel}: {k} killed, {s} survived")
    total = killed + len(survived)
    score = 100.0 * killed / total if total else 100.0
    print(f"\nMutation score: {score:.1f} % ({killed} of {total} killed, {invalid} did not compile)")
    for s in survived:
        print(f"  survived {s}")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(f"## Mutation testing\n\n{score:.1f} % killed ({killed} of {total})\n\n" + "".join(f"- survived {s}\n" for s in survived))
    return 0 if score >= MIN_SCORE else 1


if __name__ == "__main__":
    sys.exit(main())
