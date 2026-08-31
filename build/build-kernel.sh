#!/bin/bash
# Build the A50 kernel and boot image from nothing but this repository.
#
# Fetches the upstream kernel and the toolchain at the exact commits pinned in
# kernel/source.lock, applies this port's patch series, builds, and reports the
# sha256 of every artifact. Nothing device-specific is baked into the container
# image - the pin is the only thing that decides what comes out.
#
#   ./build/build-kernel.sh [--out DIR] [--jobs N] [--keep-src]
#
# Inside the container image built from build/Dockerfile:
#   docker run --rm -v "$PWD:/src" a50-halium-build ./build/build-kernel.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"
JOBS="$(nproc)"
KEEP_SRC=0

while [ $# -gt 0 ]; do
    case "$1" in
        --out)      OUT_DIR="$2"; shift 2 ;;
        --jobs)     JOBS="$2"; shift 2 ;;
        --keep-src) KEEP_SRC=1; shift ;;
        *) echo "E: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# --- read the pin -----------------------------------------------------------
LOCK="$REPO_ROOT/kernel/source.lock"
[ -r "$LOCK" ] || { echo "E: $LOCK not readable" >&2; exit 1; }
# Only KEY=VALUE lines; comments and blanks ignored. Values are not quoted in
# the file, so read them rather than sourcing it as shell.
lock_get() {
    local key="$1" val
    val="$(grep -E "^${key}=" "$LOCK" | head -1 | cut -d= -f2-)"
    [ -n "$val" ] || { echo "E: $key missing from $LOCK" >&2; exit 1; }
    printf '%s' "$val"
}

KERNEL_REPO="$(lock_get KERNEL_REPO)"
KERNEL_COMMIT="$(lock_get KERNEL_COMMIT)"
TOOLCHAIN_REPO="$(lock_get TOOLCHAIN_REPO)"
TOOLCHAIN_BRANCH="$(lock_get TOOLCHAIN_BRANCH)"
TOOLCHAIN_COMMIT="$(lock_get TOOLCHAIN_COMMIT)"
BUILD_DEVICE="$(lock_get BUILD_DEVICE)"
BUILD_VARIANT="$(lock_get BUILD_VARIANT)"
BOOT_PARTITION_BYTES="$(lock_get BOOT_PARTITION_BYTES)"

SRC="$REPO_ROOT/kernel/src"
TOOLCHAIN="$SRC/toolchain"

echo "I: kernel    $KERNEL_REPO @ $KERNEL_COMMIT"
echo "I: toolchain $TOOLCHAIN_REPO @ $TOOLCHAIN_COMMIT"
echo "I: building  -d $BUILD_DEVICE -v $BUILD_VARIANT with -j$JOBS"

# --- kernel source at the pinned commit -------------------------------------
if [ ! -d "$SRC/.git" ]; then
    rm -rf "$SRC"
    mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin "$KERNEL_REPO"
    # Fetching one commit by sha keeps this to a single tree instead of the
    # whole history. GitHub allows it; a host that does not will need the
    # branch fetched instead.
    git -C "$SRC" fetch -q --depth 1 origin "$KERNEL_COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
fi

ACTUAL="$(git -C "$SRC" rev-parse HEAD)"
if [ "$ACTUAL" != "$KERNEL_COMMIT" ]; then
    echo "E: kernel source is at $ACTUAL, not the pinned $KERNEL_COMMIT" >&2
    echo "E: delete $SRC and re-run." >&2
    exit 1
fi

# --- this port's patch series ------------------------------------------------
# Applied to the working tree, not committed, so the checked-out commit stays
# verifiable against the pin above.
if [ ! -e "$SRC/.a50-patched" ]; then
    for p in "$REPO_ROOT"/kernel/patches/*.patch; do
        [ -e "$p" ] || continue
        echo "I: applying $(basename "$p")"
        git -C "$SRC" apply --whitespace=nowarn "$p"
    done
    touch "$SRC/.a50-patched"
fi

# --- toolchain at the pinned commit ------------------------------------------
# build.sh runs `git pull` on this directory when it already exists. Leaving it
# on a DETACHED HEAD makes that pull fail harmlessly ("You are not currently on
# a branch") instead of quietly advancing the toolchain mid-build.
if [ ! -d "$TOOLCHAIN/.git" ]; then
    rm -rf "$TOOLCHAIN"
    git clone -q --single-branch -b "$TOOLCHAIN_BRANCH" "$TOOLCHAIN_REPO" "$TOOLCHAIN"
    git -C "$TOOLCHAIN" checkout -q --detach "$TOOLCHAIN_COMMIT"
fi

TC_ACTUAL="$(git -C "$TOOLCHAIN" rev-parse HEAD)"
if [ "$TC_ACTUAL" != "$TOOLCHAIN_COMMIT" ]; then
    echo "E: toolchain is at $TC_ACTUAL, not the pinned $TOOLCHAIN_COMMIT" >&2
    exit 1
fi

# --- build -------------------------------------------------------------------
cd "$SRC"
export JOBS
./build.sh -d "$BUILD_DEVICE" -v "$BUILD_VARIANT"

# --- collect and check --------------------------------------------------------
mkdir -p "$OUT_DIR"
for f in Image boot.img; do
    [ -e "$SRC/out/$f" ] || { echo "E: build produced no out/$f" >&2; exit 1; }
    cp "$SRC/out/$f" "$OUT_DIR/$f"
done

BOOT_SIZE="$(stat -c%s "$OUT_DIR/boot.img")"
echo "I: boot.img is $BOOT_SIZE bytes (partition holds $BOOT_PARTITION_BYTES)"
if [ "$BOOT_SIZE" -gt "$BOOT_PARTITION_BYTES" ]; then
    echo "E: boot.img exceeds the boot partition. Flashing it would be silently" >&2
    echo "E: truncated by dd and the device would not boot." >&2
    exit 1
fi

( cd "$OUT_DIR" && sha256sum Image boot.img | tee sha256sums.txt )

cat > "$OUT_DIR/build-manifest.txt" <<MANIFEST
kernel_repo=$KERNEL_REPO
kernel_commit=$KERNEL_COMMIT
toolchain_repo=$TOOLCHAIN_REPO
toolchain_commit=$TOOLCHAIN_COMMIT
build_device=$BUILD_DEVICE
build_variant=$BUILD_VARIANT
patches=$(cd "$REPO_ROOT/kernel/patches" && ls *.patch 2>/dev/null | tr '\n' ' ')
boot_img_bytes=$BOOT_SIZE
built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MANIFEST

echo "I: artifacts in $OUT_DIR"
[ "$KEEP_SRC" = 1 ] || echo "I: source kept at $SRC (delete it to force a clean re-fetch)"
