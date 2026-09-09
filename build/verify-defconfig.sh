#!/bin/bash
# Verify that kernel/configs/exynos9610-a50_ut_defconfig reproduces the kernel
# configuration the boot-proven kernel was built with, using a BARE
# `make <defconfig>` - which is what UBports' halium-generic-adaptation-build-
# tools does, and what this device has never been able to survive.
#
#   docker run --rm -v a50-ksrc:/src -v "$PWD:/repo" -w /src \
#       a50-halium-build /repo/build/verify-defconfig.sh /src/.config.a50-orig
#
# WHY THIS EXISTS. docs/kernel.md risk 1 - "a bare `make` does not boot this
# device" - was the port's largest open item and the reason releases ship
# a50-halium's kernel instead of the one the adaptation tools build. The cause
# is two things the vendor build.sh does that a bare make does not:
#
#   1. KCONFIG_BUILTINCONFIG points at a SECOND defconfig
#      (exynos9610-a50_default_defconfig) merged through the environment, and
#      the defconfig it actually builds is generated at build time, not checked
#      in. Miss either and .config is quietly incomplete rather than obviously
#      wrong.
#   2. It exports ANDROID_MAJOR_VERSION=r. The top-level Kconfig reads that
#      into a string symbol, and several drivers are `depends on
#      ANDROID_MAJOR_VERSION >= "q"` / `>= "r"`. With the variable unset the
#      comparison fails, the symbols become invisible, and they are dropped
#      SILENTLY - no warning beyond one line about an undefined environment
#      variable.
#
# Measured on 2026-09-09, bare make against this defconfig:
#
#   without ANDROID_MAJOR_VERSION   3 symbols lost, 0 gained
#       CONFIG_HALL_EVENT_REVERSE, CONFIG_HALL_NEW_NODE,
#       CONFIG_USB_F_CONN_GADGET_NDOP
#   with ANDROID_MAJOR_VERSION=r    0 lost, 0 gained - byte-identical
#
# So the single checked-in defconfig plus that one variable is sufficient. That
# third lost symbol is not cosmetic: conn_gadget is the driver whose double
# registration corrupts misc_list and produced this port's original display
# blocker (a50-ubuntu-touch experiment 006).
#
# This checks the CONFIG only. It does not prove the resulting Image is
# identical - the adaptation tools use Google's prebuilt Clang while this repo
# pins Proton Clang (risk 3), so a hash match is not expected and a boot test
# is still the final word.
set -euo pipefail

REF="${1:-$(cd "$(dirname "$0")/.." && pwd)/kernel/configs/reference-full.config}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEFCONFIG="$HERE/kernel/configs/exynos9610-a50_ut_defconfig"

[ -f "$REF" ] || { echo "E: reference config not found: $REF" >&2; exit 2; }
[ -f "$DEFCONFIG" ] || { echo "E: $DEFCONFIG missing" >&2; exit 2; }

cp "$DEFCONFIG" arch/arm64/configs/exynos9610-a50_ut_defconfig
trap 'rm -f arch/arm64/configs/exynos9610-a50_ut_defconfig' EXIT

norm() { grep -vE '^#|^$' "$1" | sort; }
fail=0

for mode in without with; do
    rm -f .config
    if [ "$mode" = with ]; then
        ANDROID_MAJOR_VERSION=r make ARCH=arm64 exynos9610-a50_ut_defconfig >/dev/null 2>&1
    else
        env -u ANDROID_MAJOR_VERSION make ARCH=arm64 exynos9610-a50_ut_defconfig >/dev/null 2>&1
    fi
    norm "$REF" > /tmp/ref.txt
    norm .config > /tmp/got.txt
    lost=$(comm -23 /tmp/ref.txt /tmp/got.txt | wc -l)
    gained=$(comm -13 /tmp/ref.txt /tmp/got.txt | wc -l)
    printf "  %-8s ANDROID_MAJOR_VERSION:  %d lost, %d gained\n" "$mode" "$lost" "$gained"
    comm -23 /tmp/ref.txt /tmp/got.txt | sed 's/^/      lost: /'

    if [ "$mode" = with ] && { [ "$lost" -ne 0 ] || [ "$gained" -ne 0 ]; }; then
        echo "E: with ANDROID_MAJOR_VERSION=r the config must match exactly" >&2
        fail=1
    fi
done

[ "$fail" -eq 0 ] && echo "OK: bare make + ANDROID_MAJOR_VERSION=r reproduces the reference config"
exit "$fail"
