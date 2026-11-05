#!/usr/bin/env python3 -I
"""Line coverage of the test harnesses, and the gate that matters: changed lines.

  scripts/coverage.py                 against origin/main
  scripts/coverage.py --base <ref>

Runs every harness (scripts/test-*.sh, Tests/test-*.sh) compiled with coverage, plus CraCore's
`swift test --enable-code-coverage` when Packages/CraCore exists, and reports:

  - each measured source file's line coverage;
  - changed lines: of the lines this branch added or changed in files a harness compiles,
    how many ran. Below 70 % fails: new code pays its own way, nothing old has to be backfilled;
  - CraCore below 85 % fails (pure code, every line a decision);
  - changed files no harness compiles (views, CEF glue) are listed, not counted: they are
    covered by scenarios (scripts/scenario.sh), not by percentages.

It is also CI's one run of those tests: a failing test fails it, with that suite's output, after
every suite has run. Lint is separate (scripts/lint.py).

The summary goes to stdout and, in CI, to the job summary (GITHUB_STEP_SUMMARY). Progress and
test failures go to stderr.
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGED_MIN = 70.0
CORE_MIN = 85.0
NOT_HARNESSES = {"scripts/test-update.sh", "scripts/test.sh"}


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, check=True, text=True, capture_output=True, **kw).stdout


def suite(name, cmd, failures, **kw):
    """Runs one test suite; a failure is kept with its output and the next suite still runs."""
    print(f"==> {name}", file=sys.stderr, flush=True)
    r = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, **kw)
    if r.returncode != 0:
        failures.append(name)
        print(f"{r.stdout}{r.stderr}\n{name} failed", file=sys.stderr, flush=True)


def harness_coverage(work, failures):
    """{file: {line: count}} over every harness binary."""
    keep = os.path.join(work, "bin")
    os.makedirs(keep)
    env = dict(os.environ, CRA_TEST_SWIFTC_FLAGS="-profile-generate -profile-coverage-mapping",
               CRA_TEST_KEEP=keep, LLVM_PROFILE_FILE=os.path.join(work, "%p-%m.profraw"))
    scripts = sorted(glob.glob(os.path.join(ROOT, "scripts/test-*.sh")) + glob.glob(os.path.join(ROOT, "Tests/test-*.sh")))
    for s in scripts:
        rel = os.path.relpath(s, ROOT)
        if rel in NOT_HARNESSES:
            continue
        suite(rel, ["bash", s], failures, env=env)
    raws = glob.glob(os.path.join(work, "*.profraw"))
    binaries = sorted(glob.glob(os.path.join(keep, "*")))
    if not raws or not binaries:
        return {}
    merged = os.path.join(work, "merged.profdata")
    run(["xcrun", "llvm-profdata", "merge", "-sparse", "-o", merged] + raws)
    objects = [binaries[0]] + [a for b in binaries[1:] for a in ("-object", b)]
    return lcov_lines(run(["xcrun", "llvm-cov", "export", "-format=lcov", "-instr-profile", merged] + objects))


def core_coverage(failures):
    pkg = os.path.join(ROOT, "Packages/CraCore")
    if not os.path.isdir(pkg):
        return {}
    suite("CraCore", ["swift", "test", "--package-path", pkg, "--enable-code-coverage"], failures)
    if "CraCore" in failures:
        return {}
    # Per line, as the harnesses are: the JSON's segments only mark where regions start, so the
    # other lines kept the 0 of a harness that compiles CraCore without running it.
    codecov = os.path.dirname(run(["swift", "test", "--package-path", pkg, "--show-codecov-path"]).strip())
    bin_path = run(["swift", "build", "--package-path", pkg, "--show-bin-path"]).strip()
    binary = next(b for b in glob.glob(os.path.join(bin_path, "*Tests.xctest/Contents/MacOS/*")) if not b.endswith(".dSYM"))
    return lcov_lines(run(["xcrun", "llvm-cov", "export", "-format=lcov", "-instr-profile",
                           os.path.join(codecov, "default.profdata"), binary]))


def lcov_lines(text):
    out, current = {}, None
    for line in text.splitlines():
        if line.startswith("SF:"):
            current = out.setdefault(line[3:], {})
        elif line.startswith("DA:") and current is not None:
            n, count = line[3:].split(",")[:2]
            current[int(n)] = max(current.get(int(n), 0), int(count))
    return out


def changed_lines(base):
    merge_base = run(["git", "merge-base", base, "HEAD"]).strip()
    diff = run(["git", "diff", "-U0", merge_base, "--", "Sources", "Packages"])
    out, current = {}, None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[4:]
            current = None if path == "/dev/null" else out.setdefault(os.path.join(ROOT, path[2:]), set())
        elif line.startswith("@@") and current is not None:
            m = re.match(r"@@ -\S+ \+(\d+)(?:,(\d+))? @@", line)
            start, count = int(m.group(1)), int(m.group(2) or "1")
            current.update(range(start, start + count))
    # Uncommitted work counts too (a local run before committing).
    for path in run(["git", "diff", "--name-only", "HEAD", "--", "Sources", "Packages"]).split():
        out.setdefault(os.path.join(ROOT, path), set())
    return out


def pct(hit, total):
    return 100.0 * hit / total if total else 100.0


def main():
    base = sys.argv[sys.argv.index("--base") + 1] if "--base" in sys.argv else "origin/main"
    work = tempfile.mkdtemp(prefix="cra-coverage.")
    failures = []
    try:
        cov = harness_coverage(work, failures)
        core = core_coverage(failures)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if failures:
        print("Failed: " + ", ".join(failures), file=sys.stderr)
        return 1
    for f, lines in core.items():
        merged = cov.setdefault(f, {})
        for n, count in lines.items():
            merged[n] = max(merged.get(n, 0), count)

    table = ["| File | Lines | Covered |", "|---|---:|---:|"]
    for f in sorted(cov):
        if not f.startswith(ROOT) or "/Tests/" in f or "/.build/" in f:
            continue
        lines = cov[f]
        hit = sum(1 for c in lines.values() if c > 0)
        table.append(f"| {os.path.relpath(f, ROOT)} | {len(lines)} | {pct(hit, len(lines)):.0f} % |")

    report, failed = [], []
    core_lines = [c for f, lines in core.items() if "/Sources/" in f for c in lines.values()]
    if core_lines:
        core_pct = pct(sum(1 for c in core_lines if c > 0), len(core_lines))
        report.append(f"CraCore: {core_pct:.1f} % of {len(core_lines)} lines (minimum {CORE_MIN:.0f} %)")
        if core_pct < CORE_MIN:
            failed.append(f"CraCore coverage {core_pct:.1f} % < {CORE_MIN:.0f} %")

    changed = changed_lines(base)
    measured, hit, uncovered, unmeasured = 0, 0, [], []
    for f, lines in sorted(changed.items()):
        if f not in cov:
            if f.endswith(".swift") and "/Tests/" not in f:
                unmeasured.append(os.path.relpath(f, ROOT))
            continue
        executable = [n for n in lines if n in cov[f]]
        measured += len(executable)
        missed = sorted(n for n in executable if cov[f][n] == 0)
        hit += len(executable) - len(missed)
        if missed:
            uncovered.append(f"{os.path.relpath(f, ROOT)}: {', '.join(map(str, missed[:30]))}{' …' if len(missed) > 30 else ''}")
    changed_pct = pct(hit, measured)
    report.insert(0, f"Changed lines under test: {hit} of {measured} ran ({changed_pct:.1f} %, minimum {CHANGED_MIN:.0f} %)\n")
    if uncovered:
        report.append("Changed lines no test ran:\n" + "\n".join(f"- {u}" for u in uncovered))
    if unmeasured:
        report.append("Changed files no harness compiles (scenarios cover these):\n" + "\n".join(f"- {u}" for u in unmeasured))
    if measured and changed_pct < CHANGED_MIN:
        failed.append(f"changed-lines coverage {changed_pct:.1f} % < {CHANGED_MIN:.0f} %")

    report.append("\n<details><summary>Every measured file</summary>\n\n" + "\n".join(table) + "\n\n</details>")
    text = "\n".join(report)
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write("## Coverage\n\n" + text + "\n")
    if failed:
        print("coverage: " + "; ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
