#!/usr/bin/env python3
"""What a closed issue shipped stays shipped, unless someone changes it on purpose (GitHub #155).

A test that pins a shipped issue's behaviour is marked with the issue:

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/155"), arguments: ...)   Swift Testing
    // promise: #155 #171                                     a harness func (Tests/*.swift), the
    private static func themePreview() { ... }               line right above it (or its attributes)
    # promise: #155                                           a scenario (Tests/Scenarios): the file

Tests/promises.lock records each such test with its issue and a hash of its code (comments and
whitespace left out). A tagged test that changes, is renamed or is deleted fails this check, and so
does a new one, until the lock is updated:

    scripts/promises.py            check the working tree (scripts/test.sh runs it)
    scripts/promises.py --rev HEAD check a commit instead (the push hook, check-promises-hook.sh)
    scripts/promises.py --update   take the tagged tests as they are now

Update the lock only when the promise itself changes: say in the commit which issue's behaviour
changes and why, and tell the issue's reporter. Why: 0.1.30 (#170, #171) changed the theme editor
so a space set to Auto stopped following macOS, rewrote the #155 test to match, and every suite
stayed green until the reporter wrote back.
"""
import hashlib
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCK = ROOT / "Tests" / "promises.lock"
SOURCES = ["Packages/CraCore/Tests", "Tests"]
ISSUE = re.compile(r"github\.com/VictorKildahl/cra/issues/(\d+)")
HEADER = """\
# Tests that pin what a closed issue shipped (scripts/promises.py). Each line: issue, test, hash
# of its code. Change a test here only when the promise changes on purpose: name the issue and why
# in the commit, and tell its reporter. Regenerate with scripts/promises.py --update.
"""


def skip_string(s: str, i: int) -> int:
    """Index just past the string literal whose opening quote (or first #) is at i."""
    hashes = 0
    while s[i] == "#":
        hashes += 1
        i += 1
    if s.startswith('"""', i):
        close = '"""' + "#" * hashes
        end = s.find(close, i + 3)
        return len(s) if end < 0 else end + len(close)
    close = '"' + "#" * hashes
    i += 1
    while i < len(s):
        if s[i] == "\\" and hashes == 0:
            i += 2
            continue
        if s.startswith(close, i):
            return i + len(close)
        if s[i] == "\n":  # unterminated single-line string: give up on it
            return i
        i += 1
    return i


def skip_comment(s: str, i: int) -> int:
    if s.startswith("//", i):
        end = s.find("\n", i)
        return len(s) if end < 0 else end
    end = s.find("*/", i + 2)
    return len(s) if end < 0 else end + 2


def balanced(s: str, i: int, open_: str, close: str) -> int:
    """Index just past the bracket matching the one at i, skipping strings and comments."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c == '"' or (c == "#" and re.match(r'#+"', s[i:])):
            i = skip_string(s, i)
            continue
        if s.startswith("//", i) or s.startswith("/*", i):
            i = skip_comment(s, i)
            continue
        if c == open_:
            depth += 1
        elif c == close:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced")


def normalise(code: str) -> str:
    code = re.sub(r"^\s*//.*$", "", code, flags=re.M)
    return " ".join(code.split())


def files(rev, suffixes=(".swift", ".scenario")):
    """(repo-relative path, text) of every test file, in the working tree or at a commit."""
    if rev is None:
        for base in SOURCES:
            for path in sorted((ROOT / base).rglob("*")):
                if path.suffix in suffixes and path.is_file() and ".build" not in path.parts:
                    yield path.relative_to(ROOT).as_posix(), path.read_text()
        return
    names = git("ls-tree", "-r", "--name-only", rev, "--", *SOURCES).splitlines()
    for name in sorted(names):
        if name.endswith(suffixes) and "/.build/" not in name:
            yield name, git("show", f"{rev}:{name}")


MARK = re.compile(r"^[ \t]*(?://|#)[ \t]*promise:[ \t]*((?:#\d+[ \t,]*)+)$", re.M)


def digest(code: str) -> str:
    return hashlib.sha256(normalise(code).encode()).hexdigest()[:12]


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout


def promises(rev=None):
    """(issue, test id, hash) for every tagged test."""
    found = []
    for rel, s in files(rev):
        marks = list(MARK.finditer(s))
        if rel.endswith(".scenario"):
            # The whole journey is the promise; `#` lines are comments.
            body = re.sub(r"^\s*#.*$", "", s, flags=re.M)
            for issue in sorted({int(n) for m in marks for n in re.findall(r"\d+", m.group(1))}):
                found.append((issue, rel, digest(body)))
            continue
        for m in marks:
            fn = re.compile(r"(?:\s*(?://[^\n]*|@\w+(?:\([^)]*\))?))*\s*(?:(?:private|fileprivate|static|public|internal|nonisolated)\s+)*func\s+(\w+)").match(s, m.end())
            if not fn:
                sys.exit(f"promises: {rel}: a `// promise:` line with no func right below it")
            body_end = balanced(s, s.index("{", fn.end()), "{", "}")
            # A harness runs only what its main() calls: a promise nobody calls proves nothing.
            if len(re.findall(r"\b%s\s*\(" % fn.group(1), re.sub(r"//[^\n]*", "", s))) < 2:
                sys.exit(f"promises: {rel}::{fn.group(1)} is a promise that nothing calls")
            for issue in sorted({int(n) for n in re.findall(r"\d+", m.group(1))}):
                found.append((issue, f"{rel}::{fn.group(1)}", digest(s[fn.start():body_end])))
        for m in re.finditer(r"@Test\s*\(", s):
            attr_end = balanced(s, m.end() - 1, "(", ")")
            issues = sorted({int(n) for n in ISSUE.findall(s[m.start():attr_end])})
            if ".bug(" not in s[m.start():attr_end] or not issues:
                continue
            if re.search(r"\.disabled\b", s[m.start():attr_end]):
                sys.exit(f"promises: {rel}: a .bug test is .disabled; a shipped promise runs or is changed on purpose")
            fn = re.compile(r"\s*func\s+(\w+)").match(s, attr_end)
            if not fn:
                sys.exit(f"promises: {rel}: a .bug test whose func doesn't follow its @Test(...)")
            body_end = balanced(s, s.index("{", fn.end()), "{", "}")
            for issue in issues:
                found.append((issue, f"{rel}::{fn.group(1)}", digest(s[m.start():body_end])))
    return found


def read_lock(rev=None):
    entries = {}
    if rev is not None:
        try:
            text = git("show", f"{rev}:{LOCK.relative_to(ROOT).as_posix()}")
        except subprocess.CalledProcessError:
            text = ""
    else:
        text = LOCK.read_text() if LOCK.exists() else ""
    for line in text.splitlines():
        if line.strip() and not line.startswith("# "):
            issue, test, digest = line.split()
            entries[(int(issue.lstrip("#")), test)] = digest
    return entries


def main():
    args = sys.argv[1:]
    rev = args[args.index("--rev") + 1] if "--rev" in args else None
    current = promises(rev)
    if "--update" in args:
        lines = [f"#{issue:<5} {test}  {value}" for issue, test, value in sorted(current)]
        LOCK.write_text(HEADER + "\n".join(lines) + "\n")
        print(f"promises: {len(current)} tests pinned for {len({i for i, _, _ in current})} issues")
        return 0
    locked = read_lock(rev)
    now = {(issue, test): value for issue, test, value in current}
    problems = []
    for key, value in sorted(now.items()):
        if key not in locked:
            problems.append(f"#{key[0]} {key[1]} is new: lock it with scripts/promises.py --update")
        elif locked[key] != value:
            problems.append(f"#{key[0]} {key[1]} changed")
    for key in sorted(set(locked) - set(now)):
        problems.append(f"#{key[0]} {key[1]} is gone (deleted, renamed or untagged)")
    if problems:
        print("promises: tests that pin a shipped issue's behaviour differ from Tests/promises.lock:")
        for p in problems:
            print(f"  {p}")
        print("If the issue's behaviour is meant to change: scripts/promises.py --update, say in the commit")
        print("which issue changes and why, and tell its reporter. Otherwise put the test back.")
        return 1
    print(f"promises: {len(now)} tests pinned for {len({i for i, _ in now})} issues, unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
