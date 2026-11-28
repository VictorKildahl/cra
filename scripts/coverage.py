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

Suites run CRA_TEST_JOBS at a time (default: one per core), CraCore's `swift test` among them;
most of a harness's time is waiting, not computing. The longest start first (FIRST), the harnesses
that link CraCore once its library is built (scripts/harness-cracore.sh), and the ones in SERIAL
(on screen, sheets, git) run alone afterwards.

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
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGED_MIN = 70.0
CORE_MIN = 85.0
NOT_HARNESSES = {"scripts/test-update.sh", "scripts/test.sh"}
JOBS = max(1, int(os.environ.get("CRA_TEST_JOBS") or os.cpu_count() or 1))
# Run alone, after the others: windows ordered on screen or sheets that need the key window,
# and the two that failed while another run of every suite shared the Mac.
SERIAL = ["scripts/test-dialogs.sh", "scripts/test-display.sh", "scripts/test-pager-mask.sh",
          "scripts/test-pip-overlay.sh", "scripts/test-chromium-window-corners.sh", "scripts/test-feed-counts.sh"]
# Started first, so none of them is what is left running at the end: the longest on CI (28 Nov 2026).
LIBRARY = "CraCore library for the harnesses"
FIRST = ["CraCore", LIBRARY, "scripts/test-store.sh", "Tests/test-browser-manager.sh", "scripts/test-easel-canvas.sh",
         "scripts/test-link-summary-image.sh"]
PRINT = threading.Lock()


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, check=True, text=True, capture_output=True, **kw).stdout


def suite(name, cmd, failures, **kw):
    """Runs one test suite; a failure is kept with its output and the next suite still runs.
    Safe from several threads: a suite's lines print together, when it ends."""
    start = time.monotonic()
    r = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, **kw)
    with PRINT:
        print(f"==> {name} ({time.monotonic() - start:.0f} s)", file=sys.stderr, flush=True)
        if r.returncode != 0:
            failures.append(name)
            print(f"{r.stdout}{r.stderr}\n{name} failed", file=sys.stderr, flush=True)


def run_all(tasks, jobs):
    """Runs (name, fn, needs) tasks on `jobs` threads. A free thread takes the first task in the list
    whose `needs` (a task name or None) has finished. Returns {name: fn's result}; raises the first
    exception a task raised, after every task has run."""
    pending, done, results, errors = list(tasks), set(), {}, []
    cond = threading.Condition()

    def worker():
        while True:
            with cond:
                while True:
                    if not pending:
                        return
                    task = next((t for t in pending if t[2] is None or t[2] in done), None)
                    if task:
                        pending.remove(task)
                        break
                    cond.wait()
            try:
                results[task[0]] = task[1]()
            except Exception as e:  # noqa: BLE001 (raised again below)
                errors.append(e)
            finally:
                with cond:
                    done.add(task[0])
                    cond.notify_all()

    threads = [threading.Thread(target=worker) for _ in range(max(1, jobs))]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    if errors:
        raise errors[0]
    return results


def links_cracore(harness):
    with open(os.path.join(ROOT, harness)) as f:
        return "harness-cracore.sh" in f.read()


def all_coverage(work, failures):
    """({file: {line: count}} over every harness binary, the same for CraCore's own tests)."""
    keep = os.path.join(work, "bin")
    os.makedirs(keep)
    env = dict(os.environ, CRA_TEST_SWIFTC_FLAGS="-profile-generate -profile-coverage-mapping",
               CRA_TEST_KEEP=keep, LLVM_PROFILE_FILE=os.path.join(work, "%p-%m.profraw"))
    scripts = sorted(glob.glob(os.path.join(ROOT, "scripts/test-*.sh")) + glob.glob(os.path.join(ROOT, "Tests/test-*.sh")))
    harnesses = [os.path.relpath(s, ROOT) for s in scripts]
    harnesses = [h for h in harnesses if h not in NOT_HARNESSES]
    # CraCore's library once, before the harnesses that link it, so they don't all build it at once.
    tasks = [("CraCore", lambda: core_coverage(failures), None),
             (LIBRARY, lambda: suite(LIBRARY, ["bash", "-c", "source scripts/harness-cracore.sh"], failures, env=env), None)]
    tasks += [(h, lambda h=h: suite(h, ["bash", h], failures, env=env), LIBRARY if links_cracore(h) else None)
              for h in harnesses if h not in SERIAL]
    tasks.sort(key=lambda t: FIRST.index(t[0]) if t[0] in FIRST else len(FIRST))  # stable: the rest stay in order
    core = run_all(tasks, JOBS)["CraCore"]
    for h in harnesses:
        if h in SERIAL:
            suite(h, ["bash", h], failures, env=env)
    raws = glob.glob(os.path.join(work, "*.profraw"))
    binaries = sorted(glob.glob(os.path.join(keep, "*")))
    if not raws or not binaries:
        return {}, core
    merged = os.path.join(work, "merged.profdata")
    run(["xcrun", "llvm-profdata", "merge", "-sparse", "-o", merged] + raws)
    objects = [binaries[0]] + [a for b in binaries[1:] for a in ("-object", b)]
    return lcov_lines(run(["xcrun", "llvm-cov", "export", "-format=lcov", "-instr-profile", merged] + objects)), core


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
        cov, core = all_coverage(work, failures)
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
