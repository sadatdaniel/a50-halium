#!/bin/bash
# Build the A50 kernel that this port actually ships: audio + Bluetooth.
#
# build/build-kernel.sh builds the *base* kernel from kernel/patches/ only.
# This script builds the release kernel on top of it, and is the single
# authoritative recipe for what is in the published boot image. If you change
# what the port ships, change it here.
#
#   ./build/build-a50-release-kernel.sh --firmware DIR [--out DIR]
#
# --firmware DIR must contain the vendor blobs listed in FIRMWARE below. They
# are proprietary Samsung files and are deliberately NOT committed to this
# repository; pull them off a running device with
# build/extract-vendor-firmware.sh.
#
# Inside the build container:
#   docker run --rm -v "$PWD:/src" -v /path/to/fw:/fw a50-halium-build \
#       ./build/build-a50-release-kernel.sh --firmware /fw --out /src/out
#
# What this adds on top of kernel/patches/:
#
#   misc-open-scope-and-tracing.patch
#       The scope fix the running kernel (uname #4) was built with. Calls the
#       driver's f_op->open() outside the global misc_mtx, so one blocking
#       open cannot freeze every misc device on the system.
#
#   abox-fixup-helper-dai-guard.patch
#       NULL-deref fix: abox_hw_params_fixup_helper() handed w->priv to
#       abox_if_hw_params_fixup_by_dai() for every widget with a stream name,
#       but w->priv is a snd_soc_dai only for DAI widgets.
#
#   bluetooth-linux-stack.patch
#       CONFIG_BT, BT_HCIVHCI and friends. Gives /dev/vhci.
#
#   bluetooth-hci-sock-restore.patch
#       Restores the HCI socket layer this vendor tree comments out. Without
#       it any AF_BLUETOOTH socket panics the kernel, which is what made
#       "CONFIG_BT bootloops this device" look like a kernel problem.
#
#   CONFIG_EXTRA_FIRMWARE
#       The ABOX DSP asks for calliope_sram.bin at t=1.43s, and no filesystem
#       exists on this device until t=2.08s. Built-in firmware is checked
#       before any filesystem, so this is the only source available in time.
#
#   CONFIG_RFKILL
#       bluebinder needs /dev/rfkill. NOT needed for the Wi-Fi indicator,
#       contrary to an earlier claim in the docs - Wi-Fi works without it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FW_DIR=""
OUT_DIR="$REPO_ROOT/out"

while [ $# -gt 0 ]; do
    case "$1" in
        --firmware) FW_DIR="$2"; shift 2 ;;
        --out)      OUT_DIR="$2"; shift 2 ;;
        *) echo "E: unknown argument: $1" >&2; exit 2 ;;
    esac
done

FIRMWARE="calliope_sram.bin calliope_dram.bin calliope_iva.bin tfadsp.bin \
AP_AUDIO_SLSI.bin APBargeIn_AUDIO_SLSI.bin APBiBF_AUDIO_SLSI.bin Tfa9872.cnt"

[ -n "$FW_DIR" ] || { echo "E: --firmware DIR is required (see build/extract-vendor-firmware.sh)" >&2; exit 2; }
for f in $FIRMWARE; do
    [ -f "$FW_DIR/$f" ] || { echo "E: missing firmware blob: $FW_DIR/$f" >&2; exit 1; }
done

EXTRA="misc-open-scope-and-tracing abox-fixup-helper-dai-guard \
bluetooth-linux-stack bluetooth-hci-sock-restore decon-force-mask-layer"

# build-kernel.sh applies kernel/patches/*.patch, so stage the experimental
# ones there. Numbered after 0004 to keep the series order deterministic.
i=5
for p in $EXTRA; do
    src="$REPO_ROOT/kernel/patches-experimental/$p.patch"
    [ -f "$src" ] || { echo "E: missing patch: $src" >&2; exit 1; }
    cp "$src" "$REPO_ROOT/kernel/patches/000$i-$p.patch"
    echo "I: staged 000$i-$p.patch"
    i=$((i + 1))
done

cleanup() {
    for p in $EXTRA; do rm -f "$REPO_ROOT"/kernel/patches/000[0-9]-"$p".patch; done
}
trap cleanup EXIT

# The kernel source has to exist before build-kernel.sh runs, so the firmware
# can be dropped into it and build.sh edited. build-kernel.sh skips its own
# clone when kernel/src/.git is already present, and still verifies the pin.
LOCK="$REPO_ROOT/kernel/source.lock"
KREPO="$(grep -E '^KERNEL_REPO=' "$LOCK" | cut -d= -f2-)"
KCOMMIT="$(grep -E '^KERNEL_COMMIT=' "$LOCK" | cut -d= -f2-)"
SRC="$REPO_ROOT/kernel/src"

if [ ! -d "$SRC/.git" ]; then
    rm -rf "$SRC"; mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin "$KREPO"
    git -C "$SRC" fetch -q --depth 1 origin "$KCOMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
fi
echo "I: kernel source at $(git -C "$SRC" rev-parse HEAD)"

# CONFIG_EXTRA_FIRMWARE_DIR is hardcoded to "firmware" by firmware/Makefile,
# i.e. relative to the kernel source root.
mkdir -p "$SRC/firmware"
for f in $FIRMWARE; do cp "$FW_DIR/$f" "$SRC/firmware/"; done
echo "I: installed $(echo $FIRMWARE | wc -w) firmware blobs into kernel/src/firmware/"

# The Kconfig anchor below is created by kernel/patches/0002, so the series has
# to be applied before we look for it. build-kernel.sh normally does this, but
# it runs after this point - on a freshly cloned tree the anchor would not exist
# yet and the assert would fire. Apply here and drop the same sentinel, so
# build-kernel.sh skips its own apply and the result is identical either way.
if [ ! -e "$SRC/.a50-patched" ]; then
    for p in "$REPO_ROOT"/kernel/patches/*.patch; do
        [ -e "$p" ] || continue
        echo "I: applying $(basename "$p")"
        git -C "$SRC" apply --whitespace=nowarn "$p"
    done
    touch "$SRC/.a50-patched"
fi

# Append our Kconfig to the same generated set kernel/patches/0002 writes.
python3 - "$SRC/build.sh" "$FIRMWARE" <<'PY'
import sys
path, fw = sys.argv[1], " ".join(sys.argv[2].split())
s = open(path).read()
anchor = '} >> "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"'
if "CONFIG_EXTRA_FIRMWARE=" in s:
    print("I: build.sh already carries the release Kconfig"); raise SystemExit
assert s.count(anchor) == 1, "anchor found %d times" % s.count(anchor)
add = (
    '    echo \'CONFIG_EXTRA_FIRMWARE="%s"\'\n'
    '    echo \'CONFIG_EXTRA_FIRMWARE_DIR="firmware"\'\n'
    '    echo "CONFIG_RFKILL=y"\n'
    '    echo "CONFIG_RFKILL_INPUT=y"\n'
) % fw
open(path, "w").write(s.replace(anchor, add + anchor))
print("I: build.sh patched with CONFIG_EXTRA_FIRMWARE and CONFIG_RFKILL")
PY

"$REPO_ROOT/build/build-kernel.sh" --out "$OUT_DIR"

echo
echo "I: release kernel in $OUT_DIR"
sha256sum "$OUT_DIR"/Image
