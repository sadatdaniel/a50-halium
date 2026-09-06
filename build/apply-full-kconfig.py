#!/usr/bin/env python3
"""Append the full profile's Kconfig to the kernel tree's own build.sh.

The vendor tree assembles its config from core + merge_config fragments + an
appended block written by kernel/patches/0002. This adds to that same block,
which is why it has to run after the patch series and not before it.

  apply-full-kconfig.py <path/to/kernel/build.sh> "<space separated firmware>"

Idempotent: a tree that already carries it is left alone.
"""
import sys

path, fw = sys.argv[1], " ".join(sys.argv[2].split())
s = open(path).read()
anchor = '} >> "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"'

if "CONFIG_EXTRA_FIRMWARE=" in s:
    print("I: build.sh already carries the full-profile Kconfig")
    raise SystemExit

assert s.count(anchor) == 1, "anchor found %d times" % s.count(anchor)

add = (
    '    echo \'CONFIG_EXTRA_FIRMWARE="%s"\'\n'
    '    echo \'CONFIG_EXTRA_FIRMWARE_DIR="firmware"\'\n'
    '    echo "CONFIG_RFKILL=y"\n'
    '    echo "CONFIG_RFKILL_INPUT=y"\n'
    '    echo \'CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"\'\n'
) % fw

open(path, "w").write(s.replace(anchor, add + anchor))
print("I: build.sh patched with CONFIG_EXTRA_FIRMWARE, CONFIG_RFKILL and the anbox binder devices")
