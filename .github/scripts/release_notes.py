#!/usr/bin/env python3
"""
Turns git commits into human-readable release notes.

Invoked from .github/workflows/release.yml (build path) and from
.github/scripts/backfill_release_notes.sh (backfill path). Reads
`git log` between two refs (default: previous tag → HEAD), converts
conventional-commit subjects into plain bullets, and drops
internal-only types (docs, chore, test, ci, build, refactor, style)
so the release page shows what actually changed *for users*.

Per-commit overrides:
  If a commit body contains `Release-note: <text>`, that text replaces
  the auto-translated bullet.

  If a commit body contains `Release-skip:` (any value), the commit
  is omitted from the notes.

Usage:
  release_notes.py                    # previous_tag()..HEAD
  release_notes.py FROM TO            # explicit range
"""

import re
import subprocess
import sys

# Internal concerns, not user-facing.
SKIP_TYPES = {"docs", "chore", "test", "ci", "build", "style", "refactor"}

# Friendly prefix on certain types so the bullet reads less like a commit.
PREFIXES = {
    "fix": "**Fixed:** ",
    "perf": "**Faster:** ",
}

CONVENTIONAL_RE = re.compile(r"^(\w+)(?:\([^)]+\))?!?:\s*(.+)$")
RELEASE_NOTE_RE = re.compile(r"^Release-note:\s*(.+)$", re.IGNORECASE)
RELEASE_SKIP_RE = re.compile(r"^Release-skip:", re.IGNORECASE)


def previous_tag(ref: str = "HEAD") -> str | None:
    """Closest tag before `ref`, or None on first-ever release."""
    try:
        out = subprocess.run(
            ["git", "describe", "--tags", "--abbrev=0", f"{ref}^"],
            capture_output=True, text=True, check=True,
        )
        return out.stdout.strip() or None
    except subprocess.CalledProcessError:
        return None


def commits_in_range(rng: str) -> list[tuple[str, str]]:
    """List of (subject, body) pairs for commits in `rng`."""
    # Separator-driven format so multi-line bodies survive the shell hop.
    fmt = "%s%x1f%b%x1e"
    out = subprocess.run(
        ["git", "log", "--no-merges", f"--pretty=format:{fmt}", rng],
        capture_output=True, text=True, check=True,
    )
    commits = []
    for raw in out.stdout.split("\x1e"):
        raw = raw.strip()
        if not raw:
            continue
        if "\x1f" in raw:
            subject, body = raw.split("\x1f", 1)
        else:
            subject, body = raw, ""
        commits.append((subject.strip(), body.strip()))
    return commits


def humanize(msg: str) -> str:
    """Lightly clean up a commit message for a changelog bullet."""
    msg = msg.strip().rstrip(".")
    if msg and msg[0].islower():
        msg = msg[0].upper() + msg[1:]
    return msg


def commit_to_bullet(subject: str, body: str) -> str | None:
    """None ⇒ omit this commit from the changelog."""
    for line in body.splitlines():
        if RELEASE_SKIP_RE.match(line.strip()):
            return None
    for line in body.splitlines():
        m = RELEASE_NOTE_RE.match(line.strip())
        if m:
            return f"- {m.group(1).strip()}"

    m = CONVENTIONAL_RE.match(subject)
    if not m:
        return f"- {humanize(subject)}"

    ctype, msg = m.group(1).lower(), m.group(2)
    if ctype in SKIP_TYPES:
        return None
    prefix = PREFIXES.get(ctype, "")
    return f"- {prefix}{humanize(msg)}"


def main() -> int:
    if len(sys.argv) == 3:
        rng = f"{sys.argv[1]}..{sys.argv[2]}"
    elif len(sys.argv) == 1:
        prev = previous_tag()
        rng = f"{prev}..HEAD" if prev else "HEAD"
    else:
        sys.stderr.write("usage: release_notes.py [FROM TO]\n")
        return 2

    bullets = []
    for subject, body in commits_in_range(rng):
        bullet = commit_to_bullet(subject, body)
        if bullet:
            bullets.append(bullet)

    if not bullets:
        bullets.append("- Small maintenance release — no user-facing changes.")

    sys.stdout.write("\n".join(bullets) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
