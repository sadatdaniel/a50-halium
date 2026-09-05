#!/bin/sh
# Pull the proprietary Samsung firmware blobs the release kernel needs.
#
# These are vendor binaries and are deliberately NOT committed to this
# repository. They live on any stock A50 (SM-A505F) and on a device already
# running this port, under /vendor/firmware.
#
#   Run ON the device:      ./extract-vendor-firmware.sh /tmp/a50-fw
#   then copy that directory to the build host and pass it to
#   build/build-a50-release-kernel.sh --firmware DIR
#
# What each blob is for:
#
#   calliope_sram.bin  ABOX DSP SRAM image - without it the audio DSP never
#   calliope_dram.bin  leaves reset and every PCM write returns -EIO
#   calliope_iva.bin   (small, sits beside the others)
#   tfadsp.bin         speaker-protection algorithm, runs on the ABOX DSP
#   Tfa9872.cnt        TFA9872 amplifier container; without it the amp is
#                      never configured
#   AP_AUDIO_SLSI.bin          extra ABOX firmware the live device tree marks
#   APBargeIn_AUDIO_SLSI.bin   status = "okay"
#   APBiBF_AUDIO_SLSI.bin
#
# They are built into the kernel with CONFIG_EXTRA_FIRMWARE because this
# device has no filesystem at all when the ABOX driver probes at t=1.43s.
set -eu

DST="${1:-./a50-firmware}"

# On a device running this port the Android container's /vendor is visible on
# the host under /android; on stock Android it is just /vendor.
for base in /android/vendor/firmware /vendor/firmware; do
    [ -d "$base" ] && SRC="$base" && break
done
: "${SRC:?could not find /vendor/firmware - run this on the device}"

FIRMWARE="calliope_sram.bin calliope_dram.bin calliope_iva.bin tfadsp.bin \
AP_AUDIO_SLSI.bin APBargeIn_AUDIO_SLSI.bin APBiBF_AUDIO_SLSI.bin Tfa9872.cnt"

mkdir -p "$DST"
missing=0
for f in $FIRMWARE; do
    if [ -f "$SRC/$f" ]; then
        cp "$SRC/$f" "$DST/"
        echo "  ok      $f"
    else
        echo "  MISSING $f"
        missing=$((missing + 1))
    fi
done

( cd "$DST" && sha256sum $FIRMWARE > SHA256SUMS.txt 2>/dev/null || true )

echo
echo "source: $SRC"
echo "output: $DST"
[ "$missing" -eq 0 ] || { echo "E: $missing blob(s) missing" >&2; exit 1; }
echo "all blobs present"
