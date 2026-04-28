#!/usr/bin/env bash
# Walk every tag in chronological order and rewrite its GitHub Release body
# to use the human-readable format (Install block + bullets from
# release_notes.py over `prev_tag..tag`).
#
# Idempotent: running it again produces identical bodies. Skips tags that
# have no GitHub Release attached (rare, but the workflow could fail mid-
# release before creating one).
#
# Usage:
#   .github/scripts/backfill_release_notes.sh          # dry run, prints
#   APPLY=1 .github/scripts/backfill_release_notes.sh  # actually write

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Tags from oldest → newest. `creatordate` so v0.1.10 sorts after v0.1.9.
TAGS=$(git tag --sort=creatordate)
PREV=""

for TAG in $TAGS; do
  if [ -z "$PREV" ]; then
    RANGE="$TAG"  # initial release: every commit reachable
  else
    RANGE="${PREV}..${TAG}"
  fi

  # APK filename pattern matches the build workflow.
  VERSION=${TAG#v}
  APK="Groceries-v${VERSION}.apk"

  if [ -z "$PREV" ]; then
    # First-ever tag — there's no previous version to diff against, so
    # a commit-by-commit changelog overstates an "initial release". One
    # human bullet is plenty.
    BULLETS="- Initial release of Groceries — shared household shopping lists, pantry tracking, recipes, and meal planning."
  else
    BULLETS=$(python3 .github/scripts/release_notes.py \
      "$PREV" "$TAG" 2>/dev/null || echo "- Small maintenance release.")
  fi

  BODY=$(cat <<EOF
## Install

Download **${APK}** from the Assets below and open it on your Android device. First-time install? You may need to allow your browser to install apps from unknown sources.

> Already have Groceries? Install the new APK straight over the top — your sign-in, household, and lists are preserved.

---

### What's new

${BULLETS}
EOF
)

  if [ "${APPLY:-0}" = "1" ]; then
    if gh release view "$TAG" >/dev/null 2>&1; then
      printf '%s\n' "$BODY" | gh release edit "$TAG" --notes-file - >/dev/null
      echo "✓ updated $TAG"
    else
      echo "skip $TAG — no GitHub Release attached"
    fi
  else
    echo "=== $TAG (range: $RANGE) ==="
    printf '%s\n\n' "$BODY"
  fi

  PREV="$TAG"
done
