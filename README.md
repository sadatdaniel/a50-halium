# a50-halium

**Reproducible device base for the Samsung Galaxy A50** (SM-A505F, Exynos 9610,
codename `a50`, Android 11 vendor base `RP1A.200720.012`).

This repository builds the kernel and boot image, records how to extract the
vendor blobs, and writes down what is actually true about this device. It is
deliberately **distro-agnostic** — nothing here knows about Droidian or Ubuntu
Touch. Those live in their own repositories and consume what this one produces.

If you want to put Linux on an A50, start here rather than rediscovering all of
it. That is the entire point.

## What "reproducible" means here, concretely

Everything the build depends on is pinned in one file, [`kernel/source.lock`](kernel/source.lock):
the upstream kernel commit, the toolchain commit, the build arguments, and the
device's boot-partition size limit. `build/build-kernel.sh` reads that file,
fetches both trees at exactly those commits, applies this port's patch series,
builds, refuses to finish if the image would not fit the partition, and writes
a manifest plus sha256 sums of everything it produced.

```bash
docker build -t a50-halium-build ./build
docker run --rm -v "$PWD:/src" -w /src a50-halium-build ./build/build-kernel.sh
```

The [`kernel` workflow](.github/workflows/kernel.yml) runs exactly that on a
clean GitHub runner that has never seen this device. **The badge is the claim.**
If CI is green, the boot image can be rebuilt from nothing; if CI is red, it
cannot, whatever this file says.

## We do not fork the kernel

The upstream tree — [FreshROMs/android_kernel_samsung_exynos9610_mint](https://github.com/FreshROMs/android_kernel_samsung_exynos9610_mint)
— is public and maintained, and our entire delta against it is **two patches,
about 65 lines**:

| Patch | What it does |
|---|---|
| `0001-fstab-drop-the-product-first_stage_mount-entries` | This device has no `/product` partition, and Android init treats a missing `first_stage_mount` entry as fatal. |
| `0002-build.sh-append-the-Kconfig-set-a-Linux-userspace-needs` | Turns off Samsung's integrity/anti-exploit subsystems and turns on what systemd, LXC, `lxc-net`, Phosh and the Bluetooth stack need. Every option was added one at a time in response to a real boot failure. |

Copying a 200 MB tree to carry 65 lines would add a maintenance burden and make
it harder, not easier, to follow upstream. A pinned commit plus a patch series
says exactly what is ours.

## Layout

```
kernel/source.lock            every pinned input; the single source of truth
kernel/patches/               this port's patch series, applied by the build
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

Early. What exists today: the pinned, containerised kernel and boot-image build
above, the patch series, the Kconfig fragments, and the device facts.

What does not exist yet: vendor blob extraction scripts, an `android-rootfs`
recipe, and any published release artifact. Those are next.

The boot image this produces is known to boot a full Droidian userspace with
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
