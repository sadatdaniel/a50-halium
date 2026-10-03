#!/bin/bash
# Bounded incremental experiment from the exact retained aa13 kernel.
set -euo pipefail
cd /src/kernel/src
parent=full-apparmor-ubports-watchdog-freezer-fix-usb-otg-sleep-fix-usb-otg-core-reinit-wifi-sleep-fix-usb-configfs-fix
test "$(cat .a50-patched)" = "$parent"
test "$(git rev-parse HEAD)" = bec0c2aff1ee8a02ac9f582d60fe611f1d2bc939
test "$(sha256sum .config | cut -d ' ' -f1)" = 57f003bc5635e95e56f961f42c9b47054503d55874f0005ca6ccc6cef3751741
test "$(sha256sum arch/arm64/boot/Image | cut -d ' ' -f1)" = 9ecb60339027e0024cfcded50eddd351c90a0d5fe17b4d06eb6fe70f93dd2840
test "$(sha256sum net/bluetooth/Makefile | cut -d ' ' -f1)" = b855c6643110609a0d7ecc2aab28b478a8b3d74f3b3d433654e9f9dc518c9fbb
git apply --check /src/kernel/patches-experimental/bluetooth-standard-protocols.patch
git apply /src/kernel/patches-experimental/bluetooth-standard-protocols.patch
export PATH="$PWD/toolchain/bin:$PATH"
export LD_LIBRARY_PATH="$PWD/toolchain/lib:${LD_LIBRARY_PATH:-}"
export ARCH=arm64 SUBARCH=arm64 PLATFORM_VERSION=12.0.0
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export SOURCE_DATE_EPOCH=1763150940 KBUILD_BUILD_USER=a50-halium KBUILD_BUILD_HOST=reproducible
export KBUILD_BUILD_TIMESTAMP="$(date -u -d @1763150940 '+%a %b %e %H:%M:%S UTC %Y')"
export GITHUB_RUN_NUMBER=0
mkdir -p /src/out-aa14-bluetooth
make CC=clang HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip KCFLAGS=-Wno-error -j4 LOCALVERSION=' - Mint Beta 0' Image
test "$(sha256sum .config | cut -d ' ' -f1)" = 57f003bc5635e95e56f961f42c9b47054503d55874f0005ca6ccc6cef3751741
grep -q ' rfcomm_init$' System.map
grep -q ' hidp_init$' System.map
grep -q ' bnep_init$' System.map
cp arch/arm64/boot/Image System.map /src/out-aa14-bluetooth/
cp /src/out-aa13-usb-configfs/build-manifest.txt /src/out-aa14-bluetooth/build-manifest.txt
printf '\nbluetooth_protocols=1\nincremental_parent=aa13\nconfig_sha256=%s\nimage_bytes=%s\n' \
    "$(sha256sum .config | cut -d ' ' -f1)" "$(stat -c%s arch/arm64/boot/Image)" >> /src/out-aa14-bluetooth/build-manifest.txt
sha256sum /src/kernel/patches-experimental/bluetooth-standard-protocols.patch >> /src/out-aa14-bluetooth/build-manifest.txt
printf '%s-bluetooth-protocols' "$parent" > .a50-patched
cd /src/out-aa14-bluetooth
sha256sum Image System.map | tee sha256sums.txt
