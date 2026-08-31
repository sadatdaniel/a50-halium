#!/bin/bash
# Build the A50 kernel from nothing but this repository.
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
JOBS=""                 # empty until the pin is read; see BUILD_JOBS below
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
SOURCE_DATE_EPOCH="$(lock_get SOURCE_DATE_EPOCH)"
KBUILD_BUILD_USER="$(lock_get KBUILD_BUILD_USER)"
KBUILD_BUILD_HOST="$(lock_get KBUILD_BUILD_HOST)"
BUILD_JOBS="$(lock_get BUILD_JOBS)"

# Parallelism comes from the pin, not from the build machine, because this
# kernel links with LTO and LLVM's LTO codegen can partition differently at
# different job counts - which changes the emitted code and the artifact hash.
# --jobs still overrides, for a quick local compile, but then the result is not
# comparable with anything else and the script says so.
if [ -n "$JOBS" ] && [ "$JOBS" != "$BUILD_JOBS" ]; then
    echo "W: building with -j$JOBS instead of the pinned -j$BUILD_JOBS."
    echo "W: the resulting Image is NOT comparable to a pinned build's hash."
else
    JOBS="$BUILD_JOBS"
fi

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
    if ! git -C "$SRC" fetch -q --depth 1 origin "$KERNEL_COMMIT" 2>/dev/null; then
        # Upstream can disappear, go private, or rewrite history. KERNEL_MIRROR
        # is our own fork of it and already contains this exact commit, so the
        # build survives that without the pin changing meaning.
        KERNEL_MIRROR="$(grep -E '^KERNEL_MIRROR=' "$LOCK" | head -1 | cut -d= -f2- || true)"
        [ -n "$KERNEL_MIRROR" ] || {
            echo "E: could not fetch $KERNEL_COMMIT from $KERNEL_REPO, and no KERNEL_MIRROR is set." >&2
            exit 1
        }
        echo "W: upstream fetch failed - falling back to the mirror $KERNEL_MIRROR"
        git -C "$SRC" remote set-url origin "$KERNEL_MIRROR"
        git -C "$SRC" fetch -q --depth 1 origin "$KERNEL_COMMIT"
    fi
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

# --- make the build deterministic --------------------------------------------
# Without this section two builds of the same pin differ, and the sha256 sums
# below would record noise rather than mean anything. Each export closes one
# measured source of drift:
#
#   SOURCE_DATE_EPOCH / KBUILD_BUILD_TIMESTAMP
#       the kernel compiles its build date into the banner in compile.h.
#   KBUILD_BUILD_USER / KBUILD_BUILD_HOST
#       otherwise the builder's own username and hostname are compiled in.
#       upstream build.sh only sets these when BUILD_KERNEL_CI is true, which
#       is not the path this script uses.
#   GITHUB_RUN_NUMBER
#       upstream's SET_LOCALVERSION interpolates it into LOCALVERSION for the
#       default branch, so the string lands in the kernel version. Docker does
#       not pass host environment through, but pin it rather than rely on that.
export SOURCE_DATE_EPOCH
export KBUILD_BUILD_USER KBUILD_BUILD_HOST
export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$SOURCE_DATE_EPOCH" '+%a %b %e %H:%M:%S UTC %Y')"
export GITHUB_RUN_NUMBER=0

# Harmless side effect worth knowing about: upstream build.sh reports its own
# elapsed time as now minus BUILD_DATE, and patch 0004 pins BUILD_DATE to
# SOURCE_DATE_EPOCH. So a successful build ends by announcing something like
# "Kernel build took 6963h:02m:06s" - that is the age of the pin, not a hang.
# Measured 2026-09-01: 6963h02m is exactly 2025-11-14T20:09Z to the build time.

# The ramdisk is an uncompressed newc cpio built straight from a directory in
# the source tree, so every file's mtime is baked into it and would otherwise
# be whenever the checkout happened. Ordering and inode numbering are handled
# by kernel/patches/0003.
find "$SRC/tools/make/ramdisk" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

# --- build -------------------------------------------------------------------
cd "$SRC"
export JOBS
./build.sh -d "$BUILD_DEVICE" -v "$BUILD_VARIANT"

# --- collect and check --------------------------------------------------------
# `build.sh -v recovery` produces out/Image and nothing else. Assembling a
# bootable image from it needs an initramfs, which is distro-specific and
# therefore lives downstream (a50-droidian's scripts/build/02-build-boot-image.sh).
# What this repository is responsible for is the kernel, reproducibly.
mkdir -p "$OUT_DIR"
[ -e "$SRC/out/Image" ] || { echo "E: build produced no out/Image" >&2; exit 1; }
cp "$SRC/out/Image" "$OUT_DIR/Image"
# Not a `[ ... ] && cp` one-liner: under `set -e` that exits the script when the
# file is absent, because the whole list is the command being tested.
if [ -e "$SRC/System.map" ]; then
    cp "$SRC/System.map" "$OUT_DIR/System.map"
fi

# The Image is the bulk of the eventual boot image, so an oversized one is
# worth catching here rather than after a silent dd truncation on the device.
IMAGE_SIZE="$(stat -c%s "$OUT_DIR/Image")"
echo "I: Image is $IMAGE_SIZE bytes (the boot partition holds $BOOT_PARTITION_BYTES in total,"
echo "I: and the packaged boot image must also fit a ramdisk inside that)"
if [ "$IMAGE_SIZE" -gt "$BOOT_PARTITION_BYTES" ]; then
    echo "E: the kernel Image alone exceeds the boot partition; no ramdisk could fit." >&2
    exit 1
fi

( cd "$OUT_DIR" && sha256sum Image | tee sha256sums.txt )

cat > "$OUT_DIR/build-manifest.txt" <<MANIFEST
kernel_repo=$KERNEL_REPO
kernel_commit=$KERNEL_COMMIT
toolchain_repo=$TOOLCHAIN_REPO
toolchain_commit=$TOOLCHAIN_COMMIT
build_device=$BUILD_DEVICE
build_variant=$BUILD_VARIANT
patches=$(cd "$REPO_ROOT/kernel/patches" && ls *.patch 2>/dev/null | tr '\n' ' ')
image_bytes=$IMAGE_SIZE
built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MANIFEST

echo "I: artifacts in $OUT_DIR"
[ "$KEEP_SRC" = 1 ] || echo "I: source kept at $SRC (delete it to force a clean re-fetch)"
