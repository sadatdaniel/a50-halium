#!/bin/bash
# Compatibility wrapper. The release kernel is now `build-kernel.sh --profile full`.
#
#   ./build/build-a50-release-kernel.sh --firmware DIR [--out DIR]
#
# WHY THIS IS A WRAPPER NOW. This used to be a separate script that COPIED the
# five experimental patches into kernel/patches/ so build-kernel.sh's glob
# would pick them up, then removed them again from a trap. That left the
# repository dirty in the middle of a build and hid a real bug: the series was
# applied after the step that needed it, and the build only worked because a
# previous run had left the tree patched.
#
# The patch set and the Kconfig are now selected by a flag, and nothing is
# copied anywhere. What each profile contains, and which port wants which, is
# documented at the top of build-kernel.sh.
#
# It is kept because docs, release manifests and two sibling repositories refer
# to it by name. New callers should use build-kernel.sh directly.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
echo "I: build-a50-release-kernel.sh is now 'build-kernel.sh --profile full'" >&2
exec "$HERE/build-kernel.sh" --profile full "$@"
