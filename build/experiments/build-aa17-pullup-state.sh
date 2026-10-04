#!/bin/bash
# Reuse the guarded aa16 build cache; clean reproduction uses --usb-pullup-state-fix.
set -euo pipefail
cd /src/kernel/src
test "$(cat .a50-patched)" = full-native-realtime-helpers-apparmor-ubports-watchdog-freezer-fix-usb-otg-sleep-fix-usb-otg-core-reinit-wifi-sleep-fix-usb-configfs-fix-bluetooth-protocols-usb-supply-events
test "$(git rev-parse HEAD)" = bec0c2aff1ee8a02ac9f582d60fe611f1d2bc939
test "$(git hash-object build.sh)" = f1823ee2bb4d383e1963365361e45681f99bee11
test "$(sha256sum .config | cut -d ' ' -f1)" = fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2
test "$(sha256sum arch/arm64/boot/Image | cut -d ' ' -f1)" = 079fd1d9b90fb4b278ba07ab7685e211b1ff30b1301d5cc8105b1af995e5b885
test "$(sha256sum /src/out-aa16-usb-events/Image | cut -d ' ' -f1)" = 079fd1d9b90fb4b278ba07ab7685e211b1ff30b1301d5cc8105b1af995e5b885
test "$(git hash-object drivers/usb/dwc3/gadget.c)" = fb70a6702f6f9f7492490853dd1e56f82299da8a
test ! -e /src/out-aa17-pullup-state/Image
python3 /src/build/tests/check-dwc3-pullup.py drivers/usb/dwc3/gadget.c --expect-failure
git apply --check /src/kernel/patches-experimental/dwc3-pullup-state-before-pm.patch
git apply /src/kernel/patches-experimental/dwc3-pullup-state-before-pm.patch
test "$(git hash-object drivers/usb/dwc3/gadget.c)" = dc2e2beb985375c3b52fb24585718f672336983b
python3 /src/build/tests/check-dwc3-pullup.py drivers/usb/dwc3/gadget.c
printf '%s' "$(cat .a50-patched)-usb-pullup-state-fix" > .a50-patched
export PATH="$PWD/toolchain/bin:$PATH"
export LD_LIBRARY_PATH="$PWD/toolchain/lib:${LD_LIBRARY_PATH:-}"
export ARCH=arm64 SUBARCH=arm64 PLATFORM_VERSION=12.0.0
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export SOURCE_DATE_EPOCH=1763150940 KBUILD_BUILD_USER=a50-halium KBUILD_BUILD_HOST=reproducible
export KBUILD_BUILD_TIMESTAMP="$(date -u -d @1763150940 '+%a %b %e %H:%M:%S UTC %Y')"
export GITHUB_RUN_NUMBER=0
make CC=clang HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip KCFLAGS=-Wno-error -j4 LOCALVERSION=' - Mint Beta 0' Image
test "$(sha256sum .config | cut -d ' ' -f1)" = fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2
mkdir -p /src/out-aa17-pullup-state
cp arch/arm64/boot/Image System.map /src/out-aa17-pullup-state/
cp .config /src/out-aa17-pullup-state/kernel.config
cp /src/out-aa16-usb-events/build-manifest.txt /src/out-aa17-pullup-state/parent-manifest.txt
{
    printf 'incremental_parent=aa16\nparent_image_sha256=079fd1d9b90fb4b278ba07ab7685e211b1ff30b1301d5cc8105b1af995e5b885\nusb_supply_events=1\nusb_pullup_state_fix=1\n'
    printf 'patch_sha256=%s\nconfig_sha256=%s\nimage_sha256=%s\nbuilt_utc=%s\n' \
        "$(sha256sum /src/kernel/patches-experimental/dwc3-pullup-state-before-pm.patch | cut -d ' ' -f1)" \
        "$(sha256sum .config | cut -d ' ' -f1)" \
        "$(sha256sum arch/arm64/boot/Image | cut -d ' ' -f1)" "$(date -u +%FT%TZ)"
} > /src/out-aa17-pullup-state/build-manifest.txt
cd /src/out-aa17-pullup-state
sha256sum Image System.map kernel.config > sha256sums.txt
