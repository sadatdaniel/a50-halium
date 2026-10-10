#!/bin/bash
# Guarded incremental aa17 cache; clean reproduction uses --pidfd-wait.
set -euo pipefail
cd /src/kernel/src
parent_profile=full-native-realtime-helpers-apparmor-ubports-watchdog-freezer-fix-usb-otg-sleep-fix-usb-otg-core-reinit-wifi-sleep-fix-usb-configfs-fix-bluetooth-protocols-usb-supply-events-usb-pullup-state-fix
test "$(cat .a50-patched)" = "$parent_profile"
test "$(git rev-parse HEAD)" = bec0c2aff1ee8a02ac9f582d60fe611f1d2bc939
test "$(git hash-object build.sh)" = f1823ee2bb4d383e1963365361e45681f99bee11
test "$(git hash-object kernel/exit.c)" = b137dcd722d45d99fae82e9ac48ed874374e77c4
test "$(sha256sum .config | cut -d ' ' -f1)" = fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2
parent_image=4ca1e8d8e3849a205b60889b557a67c4775d3ffc39ca18e227b5c2961fd84d70
test "$(sha256sum arch/arm64/boot/Image | cut -d ' ' -f1)" = "$parent_image"
test "$(sha256sum /src/out-aa17-pullup-state/Image | cut -d ' ' -f1)" = "$parent_image"
test ! -e /src/out-aa18-pidfd-wait/Image
patch=/src/kernel/patches-experimental/waitid-pidfd.patch
git apply --check "$patch"
git apply "$patch"
test "$(git hash-object kernel/exit.c)" = c6ec29a2273e37b40e11c14edb661c9e2934d4f0
printf '%s' "$parent_profile-pidfd-wait" > .a50-patched
export PATH="$PWD/toolchain/bin:$PATH"
export LD_LIBRARY_PATH="$PWD/toolchain/lib:${LD_LIBRARY_PATH:-}"
export ARCH=arm64 SUBARCH=arm64 PLATFORM_VERSION=12.0.0
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export SOURCE_DATE_EPOCH=1763150940 KBUILD_BUILD_USER=a50-halium KBUILD_BUILD_HOST=reproducible
export KBUILD_BUILD_TIMESTAMP="$(date -u -d @1763150940 '+%a %b %e %H:%M:%S UTC %Y')"
export GITHUB_RUN_NUMBER=0
make CC=clang HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip KCFLAGS=-Wno-error -j4 LOCALVERSION=' - Mint Beta 0' Image
test "$(sha256sum .config | cut -d ' ' -f1)" = fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2
mkdir -p /src/out-aa18-pidfd-wait
cp arch/arm64/boot/Image System.map /src/out-aa18-pidfd-wait/
cp .config /src/out-aa18-pidfd-wait/kernel.config
cp /src/out-aa17-pullup-state/build-manifest.txt /src/out-aa18-pidfd-wait/parent-manifest.txt
{
    printf 'incremental_parent=aa17\nparent_image_sha256=%s\npidfd_wait=1\n' "$parent_image"
    printf 'patch_sha256=%s\nconfig_sha256=%s\nimage_sha256=%s\nbuilt_utc=%s\n' \
        "$(sha256sum "$patch" | cut -d ' ' -f1)" \
        "$(sha256sum .config | cut -d ' ' -f1)" \
        "$(sha256sum arch/arm64/boot/Image | cut -d ' ' -f1)" "$(date -u +%FT%TZ)"
} > /src/out-aa18-pidfd-wait/build-manifest.txt
cd /src/out-aa18-pidfd-wait
sha256sum Image System.map kernel.config > sha256sums.txt
