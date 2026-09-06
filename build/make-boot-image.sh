#!/bin/bash
# Pack a kernel into the boot image a given port flashes.
#
#   ./build/make-boot-image.sh --port ubports|droidian --image out/Image \
#                              --donor DONOR.img [--out boot.img]
#
# WHY --port EXISTS. The kernel is shared; the *ramdisk* is not. Ubuntu Touch
# boots the upstream Halium initramfs and Droidian boots one this project
# builds, and they are not interchangeable - swapping them gets you a device
# that reaches the bootloader and then nothing, with no message saying why.
#
# The ramdisk comes out of a donor boot image rather than being built here:
# this device's boot header values have to come from an image that has actually
# booted it (S-Boot ignores the header id digest but not the addresses), so a
# donor is needed anyway, and taking the ramdisk from the same place means the
# two always match.
#
# So this script's real job is to refuse the mismatch. It hashes the donor and
# checks it against the table below; a donor that is not a known-good image for
# the port you asked for is an error, not a warning.
#
# Donors are published, per port, in this repository's releases.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=""; IMAGE="$REPO_ROOT/out/Image"; DONOR=""; OUT=""; FORCE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --port)  PORT="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --donor) DONOR="$2"; shift 2 ;;
        --out)   OUT="$2"; shift 2 ;;
        --force-unknown-donor) FORCE=1; shift ;;
        *) echo "E: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Known-good donors, per port. Each has booted this device.
#   ubports  - carries the upstream Halium initramfs (initramfs-tools-halium,
#              `dynparts` release)
#   droidian - carries this project's own initramfs, 0af4d23f
UBPORTS_DONORS="90c281f8da080f7bc1a9ec9aa822e0ae10bd19a77804717e0c3f6ea83cffd03b
53fe13b5"
DROIDIAN_DONORS="d69a30a67c87c3a499e86edbaa8ee366b2dc3b55c24d04de5715d871a3a55565
550504fe
d921fda0"

case "$PORT" in
    ubports)  KNOWN="$UBPORTS_DONORS" ;;
    droidian) KNOWN="$DROIDIAN_DONORS" ;;
    *) echo "E: --port must be 'ubports' or 'droidian', not '${PORT:-}'" >&2; exit 2 ;;
esac

[ -f "$IMAGE" ] || { echo "E: --image $IMAGE not found" >&2; exit 1; }
[ -n "$DONOR" ] && [ -f "$DONOR" ] || {
    echo "E: --donor DONOR.img is required." >&2
    echo "E: take the boot image for this port from this repository's releases:" >&2
    echo "E:   ubports  -> a50-ubports-halium-*   (boot.img)" >&2
    echo "E:   droidian -> a50-droidian-halium-*  (boot.img)" >&2
    exit 2; }

OUT="${OUT:-$REPO_ROOT/out/boot-$PORT.img}"

donor_sha="$(sha256sum "$DONOR" | cut -d' ' -f1)"
match=""
for k in $KNOWN; do
    case "$donor_sha" in "$k"*) match=1; break ;; esac
done
if [ -z "$match" ]; then
    echo "E: $DONOR (sha256 $donor_sha)" >&2
    echo "E: is not a known-good donor for --port $PORT." >&2
    echo "E:" >&2
    echo "E: The ramdisk is taken from the donor, and the two ports' ramdisks" >&2
    echo "E: are NOT interchangeable - the wrong one gives you a device that" >&2
    echo "E: reaches the bootloader and then stops, silently." >&2
    echo "E:" >&2
    echo "E: If this really is a new known-good image for this port, add its" >&2
    echo "E: hash to the table in this script (with the boot test that earned" >&2
    echo "E: it), or pass --force-unknown-donor to skip this check." >&2
    [ -n "$FORCE" ] || exit 1
    echo "W: --force-unknown-donor given; continuing anyway" >&2
fi

echo "I: port     $PORT"
echo "I: kernel   $IMAGE ($(sha256sum "$IMAGE" | cut -c1-16)…)"
echo "I: donor    $DONOR ($(echo "$donor_sha" | cut -c1-16)…)  header + ramdisk"

# '-' keeps the donor's ramdisk. Only the kernel is replaced.
python3 "$REPO_ROOT/build/pack-boot-image.py" "$DONOR" "$IMAGE" - "$OUT"

echo "I: $OUT"
sha256sum "$OUT"
