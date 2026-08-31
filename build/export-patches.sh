#!/bin/bash
# Export changes made in the working kernel tree back into kernel/patches/.
#
# This is the other half of build/build-kernel.sh, and what makes this
# repository a place to *develop* the kernel rather than only to rebuild it.
#
# The workflow:
#
#   1. ./build/build-kernel.sh          materialises a full kernel git tree at
#                                       kernel/src, checked out at the pinned
#                                       commit with the patch series applied.
#   2. hack on kernel/src               it is a real git checkout - edit, grep,
#                                       bisect, add a driver, whatever.
#   3. ./build/build-kernel.sh          rebuild and boot-test.
#   4. ./build/export-patches.sh        turn what you changed into patch files
#                                       here, so it is reviewable and survives.
#
#   ./build/export-patches.sh [--experimental]
#
# Writes to kernel/patches/ by default. Pass --experimental to write to
# kernel/patches-experimental/ instead, which the build does NOT apply - the
# right place for anything not yet proven on real hardware. Prefer that until
# you have actually booted the device on it; this project has already shipped
# one bootloop by promoting a change before testing it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/kernel/src"
DEST="$REPO_ROOT/kernel/patches"

if [ "${1:-}" = "--experimental" ]; then
    DEST="$REPO_ROOT/kernel/patches-experimental"
fi

[ -d "$SRC/.git" ] || {
    echo "E: no kernel tree at $SRC - run ./build/build-kernel.sh first." >&2
    exit 1
}

# build-kernel.sh applies the series to the working tree without committing, so
# `git diff` here is (existing series + your changes) as one lump. Regenerating
# the whole series from it keeps the two in sync and cannot silently drop an
# existing patch.
if git -C "$SRC" diff --quiet; then
    echo "I: no changes in $SRC - nothing to export."
    exit 0
fi

echo "I: files changed in the kernel tree:"
git -C "$SRC" diff --stat

cat <<'WARN'

W: This regenerates the ENTIRE series in the destination directory from the
W: current working tree, as a single patch. If you meant to add one focused
W: change on top of the existing series, commit it in kernel/src instead and
W: use `git format-patch` there, so each patch keeps its own message.
WARN

printf 'Continue? [y/N] '
read -r reply
case "$reply" in
    y|Y) ;;
    *) echo "I: aborted."; exit 0 ;;
esac

mkdir -p "$DEST"
OUT="$DEST/9999-exported-working-tree.patch"
git -C "$SRC" diff > "$OUT"
echo "I: wrote $OUT ($(wc -l < "$OUT") lines)"
echo "I: split it into properly-described patches before committing - a patch"
echo "I: whose message explains WHY is the only kind worth keeping."
