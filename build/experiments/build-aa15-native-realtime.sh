#!/bin/bash
# Bounded incremental candidate; the normal full build is the clean reproduction path.
set -euo pipefail
cd /src/kernel/src
parent=full-apparmor-ubports-watchdog-freezer-fix-usb-otg-sleep-fix-usb-otg-core-reinit-wifi-sleep-fix-usb-configfs-fix-bluetooth-protocols
test "$(cat .a50-patched)" = "$parent"
test "$(git rev-parse HEAD)" = bec0c2aff1ee8a02ac9f582d60fe611f1d2bc939
if [ "${1:-}" = --resume ]; then
    test "$(git hash-object build.sh)" = f1823ee2bb4d383e1963365361e45681f99bee11
    test "$(sha256sum .config | cut -d ' ' -f1)" = fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2
else
    test -z "${1:-}"
    test "$(git hash-object build.sh)" = c3cfb35c19cb7683b74f6094ea485b1923e0b1ca
    test "$(sha256sum .config | cut -d ' ' -f1)" = 57f003bc5635e95e56f961f42c9b47054503d55874f0005ca6ccc6cef3751741
fi
test "$(sha256sum arch/arm64/boot/Image | cut -d ' ' -f1)" = 264b91035a1f69989a7e911f339294dd6932622cbdd91cc854b445dd40d4c302
test ! -e /src/out-aa15-native-realtime/Image
mkdir -p /src/out-aa15-native-realtime
if [ "${1:-}" != --resume ]; then
cp .config /src/out-aa14-bluetooth/kernel.config
cp .config /src/out-aa15-native-realtime/parent.config
test "$(grep -c 'echo "CONFIG_RFKILL=y"' build.sh)" = 1
sed -i '/echo "CONFIG_RFKILL=y"/i\    echo "# CONFIG_RT_GROUP_SCHED is not set"' build.sh
fi
test "$(sha256sum /src/out-aa15-native-realtime/parent.config | cut -d ' ' -f1)" = 57f003bc5635e95e56f961f42c9b47054503d55874f0005ca6ccc6cef3751741
export PATH="$PWD/toolchain/bin:$PATH"
export LD_LIBRARY_PATH="$PWD/toolchain/lib:${LD_LIBRARY_PATH:-}"
export ARCH=arm64 SUBARCH=arm64 PLATFORM_VERSION=12.0.0
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export SOURCE_DATE_EPOCH=1763150940 KBUILD_BUILD_USER=a50-halium KBUILD_BUILD_HOST=reproducible
export KBUILD_BUILD_TIMESTAMP="$(date -u -d @1763150940 '+%a %b %e %H:%M:%S UTC %Y')"
export GITHUB_RUN_NUMBER=0
scripts/config --disable RT_GROUP_SCHED
make CC=clang HOSTCC=clang HOSTCXX=clang++ olddefconfig
python3 - <<'PY'
from pathlib import Path
before=set(Path('/src/out-aa15-native-realtime/parent.config').read_text().splitlines())
after=set(Path('.config').read_text().splitlines())
assert before-after == {'CONFIG_RT_GROUP_SCHED=y'}, before-after
assert after-before == {'# CONFIG_RT_GROUP_SCHED is not set'}, after-before
print('PASS: only CONFIG_RT_GROUP_SCHED changed after olddefconfig')
PY
case "$(git hash-object kernel/sched/rt.c)" in
    a35d675109819a6b11f740fec2f71025910279dd)
        git apply --check /src/kernel/patches-experimental/rt-standard-no-group-helpers.patch
        git apply /src/kernel/patches-experimental/rt-standard-no-group-helpers.patch ;;
    cbeb3bef0d66625a1ee0667a501e92217715af35) ;;
    *) echo 'E: unexpected realtime scheduler source' >&2; exit 1 ;;
esac
make CC=clang HOSTCC=clang HOSTCXX=clang++ AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip KCFLAGS=-Wno-error -j4 LOCALVERSION=' - Mint Beta 0' Image
grep -qx '# CONFIG_RT_GROUP_SCHED is not set' .config
grep -q ' rfcomm_init$' System.map
grep -q ' hidp_init$' System.map
grep -q ' bnep_init$' System.map
cp arch/arm64/boot/Image System.map /src/out-aa15-native-realtime/
cp .config /src/out-aa15-native-realtime/kernel.config
awk -F= '$1 !~ /^(incremental_parent|incremental_parent_built_utc|parent_image_sha256|config_sha256|image_bytes|image_sha256|kernel_port_commit|built_utc|rt_group_sched)$/ {if ($1 == "patches") sub(/decon-force-mask-layer.patch/, "decon-force-mask-layer.patch rt-standard-no-group-helpers.patch"); print}' /src/out-aa14-bluetooth/build-manifest.txt > /src/out-aa15-native-realtime/build-manifest.txt
printf '\nincremental_parent=aa14\nparent_image_sha256=264b91035a1f69989a7e911f339294dd6932622cbdd91cc854b445dd40d4c302\nrt_group_sched=n\nconfig_sha256=%s\nimage_bytes=%s\nimage_sha256=%s\nkernel_port_commit=%s\nbuilt_utc=%s\n' \
    "$(sha256sum .config | cut -d ' ' -f1)" "$(stat -c%s arch/arm64/boot/Image)" \
    "$(sha256sum arch/arm64/boot/Image | cut -d ' ' -f1)" \
    "$(git -c safe.directory=/src -C /src rev-parse HEAD)" "$(date -u +%FT%TZ)" >> /src/out-aa15-native-realtime/build-manifest.txt
printf 'full-native-realtime-helpers%s' "${parent#full}" > .a50-patched
cd /src/out-aa15-native-realtime
sha256sum Image System.map kernel.config | tee sha256sums.txt
