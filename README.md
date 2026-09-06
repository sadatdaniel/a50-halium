# a50-halium — the device base for running Linux on a Galaxy A50

**Samsung Galaxy A50 · SM-A505F · Exynos 9610 · codename `a50`**

[![kernel](https://github.com/sadatdaniel/a50-halium/actions/workflows/kernel.yml/badge.svg)](https://github.com/sadatdaniel/a50-halium/actions/workflows/kernel.yml)

This repository builds the **kernel and boot image** that both Linux ports of
this phone run on, reproducibly, from a pinned upstream commit and a pinned
toolchain. It is deliberately distro-agnostic: nothing here knows about Ubuntu
Touch or Droidian, and both consume what it produces.

```
 * Your warranty is now void.
 *
 * Nobody here is responsible for bricked devices, dead SD cards, lost data,
 * or a phone that will not boot. You are choosing to make these
 * modifications. Read the whole of this file, and the install guide of
 * whichever port you pick, before you flash anything.
```

> **If you only want to put Linux on your phone, you are in the wrong repository.**
> Go to [a50-ubuntu-touch](https://github.com/sadatdaniel/a50-ubuntu-touch) or
> [a50-droidian](https://github.com/sadatdaniel/a50-droidian) — each ships an
> installer. This repository is what they are built on, and it is where to look
> when you want to change the kernel or port a third distribution.

---

## Contents

* [The device](#the-device)
* [Ports built on this](#ports-built-on-this)
* [Build the kernel](#build-the-kernel)
* [Which build script](#which-build-script)
* [Vendor firmware](#vendor-firmware)
* [Pack a boot image](#pack-a-boot-image)
* [What "reproducible" means here](#what-reproducible-means-here)
* [We do not fork the kernel](#we-do-not-fork-the-kernel)
* [Layout](#layout)
* [Status](#status)
* [Things about this device that will cost you a day](#things-about-this-device-that-will-cost-you-a-day)
* [Licence](#licence)

---

## The device

| | |
| ---: | :--- |
| Model | Samsung Galaxy A50, SM-A505F (`a50dd`, dual SIM) |
| SoC | Exynos 9610 (`universal9610`), 4× Cortex-A73 + 4× Cortex-A53 |
| GPU | Mali-G72 MP3 |
| RAM / storage | 4 GB / 128 GB UFS |
| Display | 6.4" Super AMOLED, 1080 × 2340, waterdrop cutout, `ro.sf.lcd_density=420` |
| Kernel | Linux 4.14.194 |
| Vendor base | Android 11, `RP1A.200720.012`, fingerprint `A505FDDS9CWA2` |
| Bootloader | Samsung S-Boot. **No fastboot.** Odin or a custom recovery only |
| Boot partition | `sda14`, **exactly 57,671,680 bytes** |

More, and the reasoning behind each, in
[`device/samsung-a50/device-facts.md`](device/samsung-a50/device-facts.md).
Read it before you build anything — it is short, and it will save you at least
four expensive mistakes.

## Ports built on this

| | |
| --- | --- |
| [**a50-ubuntu-touch**](https://github.com/sadatdaniel/a50-ubuntu-touch) | Ubuntu Touch 26.04, Halium 11. Audio, Bluetooth incl. A2DP, calls, mobile data, Wi-Fi, GPS, Waydroid. Ships a recovery-flashable installer |
| [**a50-droidian**](https://github.com/sadatdaniel/a50-droidian) | Droidian (Debian + Phosh). Display at 60 Hz, touch, Wi-Fi, audio. Ships a `package-sideload` bundle |

Both flash a boot image built here. Neither has an OTA channel; both are
installed by writing a boot image and a rootfs.

## Build the kernel

```bash
git clone https://github.com/sadatdaniel/a50-halium
cd a50-halium
docker build -t a50-halium-build ./build

# the kernel tree cannot live on NTFS (see the traps below) - use a volume
docker run --rm -v a50-ksrc:/src/kernel/src -v "$PWD:/src" -w /src \
    a50-halium-build ./build/build-kernel.sh
```

That produces `out/Image`, `out/System.map`, a build manifest and a checksum
file. The [`kernel` workflow](.github/workflows/kernel.yml) runs exactly this on
a clean GitHub runner that has never seen this device. **The badge is the
claim**: if CI is green the kernel rebuilds from nothing; if it is red it does
not, whatever this file says.

## Which build script

There are two, and picking the wrong one produces a kernel that is missing half
of what the ports need.

| | |
| --- | --- |
| `build/build-kernel.sh` | the **base** kernel: `kernel/patches/*` only. This is what CI builds and what `expected-artifacts.sha256` pins |
| `build/build-a50-release-kernel.sh` | **what the ports actually ship.** The base plus five more patches and three Kconfig additions. Needs `--firmware DIR` |

`build-a50-release-kernel.sh` is the single authoritative recipe for a release.
On top of the base it adds:

| | |
| --- | --- |
| `misc-open-scope-and-tracing` | calls the driver's `f_op->open()` outside the global `misc_mtx`, so one blocking open cannot freeze every misc device on the system |
| `abox-fixup-helper-dai-guard` | NULL-deref fix: `w->priv` is a `snd_soc_dai` only for DAI widgets |
| `bluetooth-linux-stack` | `CONFIG_BT`, `BT_HCIVHCI` and friends — gives `/dev/vhci` |
| `bluetooth-hci-sock-restore` | restores the HCI socket layer this vendor tree comments out. Without it any `AF_BLUETOOTH` socket panics the kernel, which is what made "CONFIG_BT bootloops this device" look like a kernel problem for weeks |
| `decon-force-mask-layer` | exposes the fingerprint HBM mask layer as a module parameter. Defaults off and is inert unless set |
| `CONFIG_EXTRA_FIRMWARE` | the ABOX audio DSP asks for `calliope_sram.bin` at **t = 1.43 s** and this device has no filesystem of any kind until **t = 2.08 s**. Built-in firmware is checked before any filesystem, so it is the only source available in time |
| `CONFIG_RFKILL` | `bluebinder` needs `/dev/rfkill`. It is **not** needed for the Wi-Fi indicator, contrary to an earlier claim in these docs |
| `CONFIG_ANDROID_BINDER_DEVICES` + `anbox-*` | Waydroid needs its own binder domain, and this 4.14 tree has no binderfs, so the extra nodes have to be compiled in statically |

## Vendor firmware

Eight proprietary Samsung blobs are compiled into the release kernel. They are
deliberately not committed. Extract them from your own device — stock Android
or either port will do:

```bash
./build/extract-vendor-firmware.sh /tmp/a50-fw
```

The script verifies all eight are present and fails loudly if any is missing.
Then:

```bash
docker run --rm -v a50-ksrc:/src/kernel/src -v "$PWD:/src" -v /tmp/a50-fw:/fw \
    a50-halium-build ./build/build-a50-release-kernel.sh --firmware /fw --out /src/out
```

## Pack a boot image

```bash
./build/pack-boot-image.py known-good-boot.img out/Image - new-boot.img
```

This reuses a donor image's header and ramdisk and patches only `kernel_size`
and `ramdisk_size`. That is safe here because S-Boot ignores the header `id`
digest — measured, not assumed. The script refuses to write an image larger
than the boot partition rather than let `dd` truncate it silently.

The **ramdisk** is distro-specific and is not built here: Ubuntu Touch uses the
upstream Halium initramfs, Droidian builds its own with
`scripts/build/07-build-ramdisk.sh` in a50-droidian.

## What "reproducible" means here

The stronger thing: **the same pin produces byte-identical artifacts on a
different machine.** That does not happen by accident. Everything the build
depends on is in one file,
[`kernel/source.lock`](kernel/source.lock) — the upstream kernel commit, the
toolchain commit, the build arguments, the fixed build clock, the boot-partition
limit. `build/build-kernel.sh` reads it; nothing else hardcodes those values.

Four measured sources of drift are closed:

| Source of drift | Fix |
|---|---|
| Kernel banner build date (`compile.h`) | `SOURCE_DATE_EPOCH` / `KBUILD_BUILD_TIMESTAMP`, pinned to the upstream commit's own author date |
| Builder's username and hostname compiled into the banner | `KBUILD_BUILD_USER` / `KBUILD_BUILD_HOST` pinned; upstream only sets these on its own CI path |
| `LOCALVERSION` interpolating `$GITHUB_RUN_NUMBER` into the kernel version | pinned to a fixed value |
| Ramdisk `find . \| cpio`: entry order, real inode numbers, per-file mtimes | `kernel/patches/0003` sorts the list and renumbers inodes; the build script normalises mtimes to `SOURCE_DATE_EPOCH` |

`kernel/expected-artifacts.sha256` records the hashes the current pin must
produce, and CI checks the build against it. Changing the pin, the patches or
the build environment is *expected* to change those hashes — the point is that
it cannot happen silently.

One pin does **not** reach the compiler, and this file says so rather than
pretending otherwise: the vendor tree's own `build.sh` declares
`local JOBS; JOBS="$(nproc --all)"`, which overrides any exported `JOBS`
unconditionally. Because this kernel links with ThinLTO, and LTO codegen can
partition differently at different `-j`, `build-kernel.sh` refuses to build when
`nproc --all` disagrees with `BUILD_JOBS` instead of quietly producing an
incomparable artifact.

## We do not fork the kernel

The upstream tree —
[FreshROMs/android_kernel_samsung_exynos9610_mint](https://github.com/FreshROMs/android_kernel_samsung_exynos9610_mint)
— is public and maintained, and a GitHub **fork** of it already exists at
[sadatdaniel/android_kernel_samsung_exynos9610_mint](https://github.com/sadatdaniel/android_kernel_samsung_exynos9610_mint),
which contains the pinned commit and costs nothing to keep. `source.lock` names
it as `KERNEL_MIRROR` and the build falls back to it if upstream ever fails, so
durability is covered without hosting a second copy of a 200 MB tree.

The base delta against upstream is **four small patches, about 70 lines**:

| Patch | What it does |
|---|---|
| `0001-fstab-drop-the-product-first_stage_mount-entries` | This device has no `/product` partition, and Android init treats a missing `first_stage_mount` entry as fatal |
| `0002-build.sh-append-the-Kconfig-set-a-Linux-userspace-needs` | Turns off Samsung's integrity/anti-exploit subsystems and turns on what systemd, LXC, `lxc-net` and Phosh need. Every option was added one at a time in response to a real boot failure, and the whole set is boot-tested |
| `0003-build.sh-make-the-ramdisk-cpio-deterministic` | Sorts the ramdisk file list and renumbers cpio inodes, so the same source produces the same bytes on any machine |
| `0004-build.sh-honour-SOURCE_DATE_EPOCH-for-BUILD_DATE` | Stops a live `date +%s` being compiled into the kernel version string, which made two builds of the same source never match |

Five more live in `kernel/patches-experimental/` and are applied by
`build-a50-release-kernel.sh`; the table under
[Which build script](#which-build-script) says what each does. All nine apply
cleanly to a pristine tree — that is checked, because for a while two of them
did not and the build only worked because a previous run had left the tree
patched.

Copying a 200 MB tree to carry ~200 lines would add a maintenance burden and
make it harder, not easier, to follow upstream. A pinned commit plus a patch
series says exactly what is ours.

## Layout

```
kernel/source.lock             every pinned input; the single source of truth
kernel/patches/                boot-tested base series; what build-kernel.sh applies
kernel/patches-experimental/   applied by build-a50-release-kernel.sh
kernel/patches-historical/     kept for the record, never applied - read its README
kernel/config/                 Kconfig fragments, each documenting why it exists
kernel/expected-artifacts.sha256   what the current pin must produce
build/Dockerfile               pinned build environment
build/build-kernel.sh          fetch -> verify pin -> patch -> build -> checksum
build/build-a50-release-kernel.sh  what the ports ship
build/extract-vendor-firmware.sh   pull the eight proprietary blobs off a device
build/pack-boot-image.py       kernel + donor header/ramdisk -> boot.img
device/samsung-a50/            facts about the hardware that cost time to learn
```

## Status

**The kernel this repository builds is boot-verified on real hardware, and the
chain from pinned source to a booted phone is verified link by link:**

| link | evidence |
|---|---|
| pinned kernel + toolchain commits → `Image` | `074aad86…`, bit-identical on a GitHub runner and a local container, CI-gated against `expected-artifacts.sha256` |
| Halium base ramdisk + tracked tree → ramdisk | `0af4d23f…`, deterministic across runs and machines (a50-droidian's `07-build-ramdisk.sh`) |
| kernel + ramdisk → boot image | `d69a30a6…`, flashed and booted: Phosh active, Android container `RUNNING`, stable past four minutes |
| release kernel → boot image | `90c281f8…`, running on the development device today; what a50-ubuntu-touch's installer carries |
| adaptation package → device | 6/6 fixes applied on a real boot |

Both boot images are published with hashes, so any can be restored from TWRP
rather than existing only on one laptop —
[a50-droidian releases](https://github.com/sadatdaniel/a50-droidian/releases),
[a50-ubuntu-touch releases](https://github.com/sadatdaniel/a50-ubuntu-touch/releases).

What is **not** here, and is not planned to be: an `android-rootfs` recipe (both
ports fetch a GSI from their own upstream) and vendor blob *redistribution*
(only the means to extract them from your own device).

## Things about this device that will cost you a day

Each of these was learned the expensive way.

* **`mkbootimg --cmdline` is silently ignored.** S-Boot merges its own kernel
  command line from the device tree's `bootargs` and never reads the boot image
  header field. Anything that must actually take effect has to go into
  `CONFIG_CMDLINE` and be rebuilt. Verify with a live `cat /proc/cmdline`.
* **The boot partition is exactly 57,671,680 bytes and `dd` does not fail on a
  larger image — it truncates it.** `pack-boot-image.py` refuses; a hand-rolled
  `dd` will not.
* **The kernel tree cannot be checked out on Windows.** `aux.c` is a reserved
  filename and NTFS mangles the tree's symlinks. Build with the source on a
  Docker volume: `-v a50-ksrc:/src/kernel/src`.
* **Do not trust `lxc-checkconfig` or `/proc/config.gz`.** Both read a stale,
  frozen IKCONFIG blob rather than the live config. Verify kernel features by
  using them.
* **`strings Image` cannot see kernel module parameters.** Verify a patch with
  `System.map`, and check a known-good control symbol first — "0 occurrences"
  proves nothing on its own.
* **An identical error string is not evidence of an identical cause.** This
  project lost real time to a test that "reproduced the exact same failure" and
  had in fact hit a shared generic log line from a different code path.
* **`lxc-attach -n android -- /system/bin/logcat -d -b all` is the first thing
  to reach for on any HAL problem.** Android HALs log their real errors only to
  logcat; none of it reaches the Linux journal or `dmesg`. Processes outside the
  container that load Android libraries through libhybris log there too, under
  their own PID.

### One warning about old images

Kernels built from the private working tree **before 2026-08-31** carry a
leftover debug patch that writes raw sectors into the userdata partition on
every boot. It is documented in
[`kernel/patches-historical/README.md`](kernel/patches-historical/README.md) and
is not applied by this repository. If you have a locally built image from that
period, rebuild it.

## Licence

The kernel source is GPL-2.0, as upstream. The scripts and documentation here
are offered under the same terms so the whole thing stays one coherent,
redistributable unit. No proprietary vendor blobs are committed — only the means
to extract them from your own device.
