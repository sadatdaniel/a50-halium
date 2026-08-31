# a50-halium

**Reproducible device base for the Samsung Galaxy A50** (SM-A505F, Exynos 9610,
codename `a50`, Android 11 vendor base `RP1A.200720.012`).

This repository builds the kernel reproducibly, records how to extract the
vendor blobs, and writes down what is actually true about this device. It is
deliberately **distro-agnostic** — nothing here knows about Droidian or Ubuntu
Touch. Those live in their own repositories and consume what this one produces.

If you want to put Linux on an A50, start here rather than rediscovering all of
it. That is the entire point.

## What "reproducible" means here, concretely

Everything the build depends on is pinned in one file, [`kernel/source.lock`](kernel/source.lock):
the upstream kernel commit, the toolchain commit, the build arguments, the fixed
build clock, and the device's boot-partition limit. `build/build-kernel.sh` reads it,
fetches both trees at exactly those commits, applies this port's patch series,
builds, and writes
a manifest plus sha256 sums of what it produced.

`build.sh -v recovery` produces a kernel `Image` and nothing else. Packaging that
into a flashable boot image needs an initramfs, which is distro-specific, so it
happens downstream — in [a50-droidian](https://github.com/sadatdaniel/a50-droidian)
for Droidian. What this repository owns is the kernel.

```bash
docker build -t a50-halium-build ./build
docker run --rm -v "$PWD:/src" -w /src a50-halium-build ./build/build-kernel.sh
```

The [`kernel` workflow](.github/workflows/kernel.yml) runs exactly that on a
clean GitHub runner that has never seen this device. **The badge is the claim.**
If CI is green, the kernel can be rebuilt from nothing; if CI is red, it
cannot, whatever this file says.

### Bit-for-bit, not just "it builds"

"Reproducible" here means the stronger thing: **the same pin produces
byte-identical artifacts on a different machine.** That does not happen by
accident, and this build closes four measured sources of drift:

| Source of drift | Fix |
|---|---|
| Kernel banner build date (`compile.h`) | `SOURCE_DATE_EPOCH` / `KBUILD_BUILD_TIMESTAMP`, pinned to the upstream commit's own author date |
| Builder's username and hostname compiled into the banner | `KBUILD_BUILD_USER` / `KBUILD_BUILD_HOST` pinned; upstream only sets these on its own CI path |
| `LOCALVERSION` interpolating `$GITHUB_RUN_NUMBER` into the kernel version | pinned to a fixed value |
| Ramdisk `find . \| cpio`: filesystem entry order, real inode numbers, per-file mtimes | `kernel/patches/0003` sorts the list and renumbers inodes; the build script normalises mtimes to `SOURCE_DATE_EPOCH` |

`kernel/expected-artifacts.sha256` records the hashes the current pin must
produce, and CI checks the build against it. Changing the pin, the patches or
the build environment is expected to change those hashes — the point is that it
cannot happen *silently*.

## We do not fork the kernel

The upstream tree — [FreshROMs/android_kernel_samsung_exynos9610_mint](https://github.com/FreshROMs/android_kernel_samsung_exynos9610_mint)
— is public and maintained, and our entire delta against it is **three small patches,
about 70 lines**:

| Patch | What it does |
|---|---|
| `0001-fstab-drop-the-product-first_stage_mount-entries` | This device has no `/product` partition, and Android init treats a missing `first_stage_mount` entry as fatal. |
| `0002-build.sh-append-the-Kconfig-set-a-Linux-userspace-needs` | Turns off Samsung's integrity/anti-exploit subsystems and turns on what systemd, LXC, `lxc-net` and Phosh need. Every option was added one at a time in response to a real boot failure, and the whole set is boot-tested. |
| `0003-build.sh-make-the-ramdisk-cpio-deterministic` | Sorts the ramdisk file list and renumbers cpio inodes, so the same source produces the same bytes on any machine. |

Copying a 200 MB tree to carry 70 lines would add a maintenance burden and make
it harder, not easier, to follow upstream. A pinned commit plus a patch series
says exactly what is ours.

## Layout

```
kernel/source.lock            every pinned input; the single source of truth
kernel/patches/                boot-tested; these are what the build applies
kernel/patches-experimental/  written but NOT boot-tested - read its README
kernel/patches-historical/    kept for the record, never applied - read its README
kernel/config/                Kconfig fragments, each documenting why it exists
build/Dockerfile              pinned build environment (Ubuntu 22.04)
build/build-kernel.sh         fetch -> verify pin -> patch -> build -> checksum
device/samsung-a50/           facts about the hardware that cost time to learn
```

Start with [`device/samsung-a50/device-facts.md`](device/samsung-a50/device-facts.md).
It is short, and it will save you from at least four expensive mistakes —
including one where flashing an oversized image is silently truncated instead
of failing.

## Status

**The kernel this repository builds is boot-verified on real hardware.**
Build `074aad86…` was packaged with the known-good ramdisk, flashed, and booted:
Android LXC container `RUNNING`, Phosh active, stable well past the ~10 s mark
where this device's bootloops announce themselves.

It is also bit-for-bit reproducible: a GitHub runner and a local container
produced byte-identical Images, and `kernel/expected-artifacts.sha256` now gates
CI against that hash.

What exists today: the pinned, containerised kernel build
above, the patch series, the Kconfig fragments, and the device facts.

What does not exist yet: a reproducible **ramdisk** (the boot image above reuses one
extracted from a known-good image, which is the next gap to close), vendor blob
extraction scripts, and an `android-rootfs`
recipe. Those are next.

The kernel this produces is known to boot a full Droidian userspace with
working display, touch, Wi-Fi and audio — see
[a50-droidian](https://github.com/sadatdaniel/a50-droidian) for that side of the
work and for the porting narrative.

## Ports built on this

* [a50-droidian](https://github.com/sadatdaniel/a50-droidian) — Droidian (Debian + Phosh). Working.
* Ubuntu Touch — planned.

## A warning worth reading before you build anything

Kernels built from the private working tree **before 2026-08-31** carry a
leftover debug patch that writes raw sectors into the userdata partition on
every boot. It is documented in
[`kernel/patches-historical/README.md`](kernel/patches-historical/README.md) and
is not applied by this repository. If you have a locally built image from that
period, rebuild it.

## Licence

The kernel source is GPL-2.0, as upstream. The scripts and documentation in this
repository are offered under the same terms so the whole thing stays one
coherent, redistributable unit. No proprietary vendor blobs are committed here —
only the means to extract them from your own device.
