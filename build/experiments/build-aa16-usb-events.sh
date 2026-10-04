#!/bin/bash
# Reuse the guarded aa15 build cache; clean reproduction uses --usb-supply-events.
set -euo pipefail
cd /src/kernel/src
test "$(cat .a50-patched)" = full-native-realtime-helpers-apparmor-ubports-watchdog-freezer-fix-usb-otg-sleep-fix-usb-otg-core-reinit-wifi-sleep-fix-usb-configfs-fix-bluetooth-protocols
test "$(git rev-parse HEAD)" = bec0c2aff1ee8a02ac9f582d60fe611f1d2bc939
test "$(git hash-object build.sh)" = f1823ee2bb4d383e1963365361e45681f99bee11
test "$(sha256sum .config | cut -d ' ' -f1)" = fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2
test "$(sha256sum arch/arm64/boot/Image | cut -d ' ' -f1)" = e67dfa236fc08e5f476f74da243578be356e177ef616c878c723cc425d72fd5b
test "$(sha256sum /src/out-aa15-native-realtime/Image | cut -d ' ' -f1)" = e67dfa236fc08e5f476f74da243578be356e177ef616c878c723cc425d72fd5b
test "$(git hash-object drivers/battery_v2/sec_battery.c)" = 3af565e7a47c1782d47528910e509baa76376cec
test ! -e /src/out-aa16-usb-events/Image
git apply --check /src/kernel/patches-experimental/usb-supply-cable-events.patch
git apply /src/kernel/patches-experimental/usb-supply-cable-events.patch
printf '%s' "$(cat .a50-patched)-usb-supply-events" > .a50-patched
export PATH="$PWD/toolchain/bin:$PATH"
export LD_LIBRARY_PATH="$PWD/toolchain/lib:${LD_LIBRARY_PATH:-}"
export ARCH=arm64 SUBARCH=arm64 PLATFORM_VERSION=12.0.0
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export SOURCE_DATE_EPOCH=1763150940 KBUILD_BUILD_USER=a50-halium KBUILD_BUILD_HOST=reproducible
export KBUILD_BUILD_TIMESTAMP="$(date -u -d @1763150940 '+%a %b %e %H:%M:%S UTC %Y')"
export GITHUB_RUN_NUMBER=0
make CC=clang HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip KCFLAGS=-Wno-error -j4 LOCALVERSION=' - Mint Beta 0' Image
test "$(sha256sum .config | cut -d ' ' -f1)" = fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2
mkdir -p /src/out-aa16-usb-events
cp arch/arm64/boot/Image System.map /src/out-aa16-usb-events/
cp .config /src/out-aa16-usb-events/kernel.config
cp /src/out-aa15-native-realtime/build-manifest.txt /src/out-aa16-usb-events/parent-manifest.txt
{
    printf 'incremental_parent=aa15\nparent_image_sha256=e67dfa236fc08e5f476f74da243578be356e177ef616c878c723cc425d72fd5b\nusb_supply_events=1\n'
    printf 'patch_sha256=%s\nconfig_sha256=%s\nimage_sha256=%s\nbuilt_utc=%s\n' \
        "$(sha256sum /src/kernel/patches-experimental/usb-supply-cable-events.patch | cut -d ' ' -f1)" \
        "$(sha256sum .config | cut -d ' ' -f1)" \
        "$(sha256sum arch/arm64/boot/Image | cut -d ' ' -f1)" "$(date -u +%FT%TZ)"
} > /src/out-aa16-usb-events/build-manifest.txt
cd /src/out-aa16-usb-events
sha256sum Image System.map kernel.config > sha256sums.txt
