# Starting a new port on this base (Ubuntu Touch / UBports, or anything else)

You are picking up a Samsung Galaxy A50 (SM-A505F, Exynos 9610, codename `a50`)
that **already boots a full Linux userspace with working display, touch, Wi-Fi
and audio** — under Droidian. Your job is to reuse that, not rediscover it.

Read this file, then `device/samsung-a50/device-facts.md`, before touching
anything. Both are short. Several of the facts in them cost days.

---

## 0. The two rules that matter more than any technical detail

**Documentation and convention are everything.**

1. **Verify, never assume.** Every claim in these repos that says "confirmed" or
   "verified" was checked against the live device or a hash. Anything else is
   marked as unverified, inherited, or a hypothesis — and you should treat it
   that way. When you find a claim that is wrong, *correct it in the repo* and
   say what disproved it. This project has already corrected three of its own
   documented "facts" that were wrong, and each one had previously cost a
   session real time.

2. **Follow the ecosystem's conventions, don't invent your own.** Read the
   upstream porting guide for your distro *in full* before designing anything.
   This project hand-wrote a recovery `update-binary` before discovering that
   Droidian packages adaptations as Debian packages and builds flashable zips
   with `package-sideload`. That work had to be thrown away. For Ubuntu Touch
   the equivalents are Halium's own docs and UBports' porting guide — read them
   first.

Document as you go: **verify → document → commit**. A failed experiment that is
written down is worth more than a success that is not.

---

## 1. What already exists

| Repo | What it is |
|---|---|
| [`a50-halium`](https://github.com/sadatdaniel/a50-halium) | **Start here.** Distro-agnostic device base: reproducible kernel build, patch series, device facts. Nothing in it knows about Droidian. |
| [`a50-droidian`](https://github.com/sadatdaniel/a50-droidian) | The Droidian port. Read it for *how each piece of hardware was made to work* — the diagnoses transfer even though the packaging does not. |
| [`android_kernel_samsung_exynos9610_mint`](https://github.com/sadatdaniel/android_kernel_samsung_exynos9610_mint) | A fork of the upstream kernel, used as `KERNEL_MIRROR`. Do not delete. |

### Artifacts, all hash-pinned and published as GitHub Releases

| Artifact | sha256 | Status |
|---|---|---|
| Kernel `Image` | `074aad86…` | Bit-for-bit reproducible, CI-gated, boot-verified |
| Initramfs base (Halium build output) | `5dc6f1f9…` | Pinned, published |
| Canonical ramdisk | `0af4d23f…` | Deterministic, boot-verified |
| Boot image | `d69a30a6…` | Boots, stable |

The kernel is genuinely reproducible: a GitHub runner and a local container
produce byte-identical output, and CI fails if that changes.

---

## 2. How to operate the device

The device has **no `adbd` in the running Linux system**. That is by design, not
a fault. There are two states and two different ways in:

### TWRP recovery — full `adb`

`adb devices` shows `recovery`. Use it for anything touching the offline
filesystem: flashing, loop-mounting `rootfs.img`, pushing/pulling large files.

```sh
./scripts/flash/03-flash.sh <boot.img>      # from a50-droidian, device in TWRP
adb reboot
```

### Running Linux — a raw TCP shell over USB

The initramfs brings up a USB RNDIS gadget and a shell on **`192.168.2.15:23`**.
Driver script: `a50-droidian/scripts/test/debug-cmds.ps1`, which takes either
`-Commands "a","b"` or `-ScriptFile cmds.txt` (prefer the file form from any
non-PowerShell caller — the array form loses its quoting).

The host adapter needs `192.168.2.20/24`; it is usually already configured.

### Getting from running Linux back to TWRP — unreliable, plan for it

`systemctl reboot --reboot-argument=recovery` **sometimes** works and sometimes
reboots straight back into Linux. In one session it succeeded three times then
failed four times in a row. Retry; if it will not land, the physical button
combo is the fallback and you will need the device's owner.

Two alternatives are already tested and **do not work** — do not retry them:

* The AOSP bootloader control block (writing `boot-recovery` to `misc`) is
  ignored by S-Boot. Confirmed by writing it, rebooting into Linux, and reading
  the value back still unconsumed.
* glibc's `reboot()` takes one argument and supplies the magics itself, so it
  cannot pass `recovery`. `RESTART2` needs the raw syscall (142 on aarch64).

Useful discovery: **`/dev/disk/by-partlabel/` is populated**, even though both
Android `by-name` directories are absent. `boot=sda14`, `recovery=sda15`,
`misc=sda19`, `userdata=sda32`.

---

## 3. The build environment

A **persistent local Docker container named `halium-build`** (Ubuntu 22.04) holds
the historical working state. It is not tied to any session:

```sh
docker start halium-build
docker exec halium-build sh -c '...'
```

| Path inside it | What |
|---|---|
| `/root/kernel-mint` | The kernel working tree (shallow clone, `--depth 1`) |
| `/root/kernel-mint/tools/make/bin/mkbootimg` | **Use this mkbootimg, not a system one** |
| `/tmp/real-initrd-extract` | The working initramfs tree — now also rescued into git |
| `/work/*.img` | Historical boot images |

On Windows hosts, `docker exec` paths get mangled by MSYS — prefix with
`MSYS_NO_PATHCONV=1`. Bind mounts are worse: the container-side half of
`-v host:container` gets rewritten and the mount silently lands nowhere, so a
build "succeeds" while its output goes into an anonymous volume. Use
`docker create` + `docker cp` instead. Note that `MSYS_NO_PATHCONV=1` stops
*both* halves being rewritten, so the host half then has to be written
Windows-style (`C:/Users/...`) or Docker cannot find it.

Also on Windows: git's default `core.autocrlf=true` rewrites every text file on
checkout, and a clean clone of this repository then **cannot build** - the
container reports `exec ./build/build-kernel.sh: no such file or directory` for
a file that is plainly there, because the shebang is `#!/bin/bash\r`. This was
measured, not predicted, on 2026-09-01. The repository now carries a
`.gitattributes` forcing LF; if you cloned it before that existed, re-clone with
`git clone -c core.autocrlf=false`.

**You should not need that container.** `a50-halium` rebuilds the kernel from
scratch:

```sh
docker build -t a50-halium-build ./build
docker run --rm -v "$PWD:/src" -w /src a50-halium-build ./build/build-kernel.sh
```

---

## 4. What works, and what made it work

Each of these is a *diagnosis* that transfers to any distro, even though the
packaging does not:

| Hardware | The actual fix |
|---|---|
| Display | `/dev/ion` is `0600 root:root`; the compositor runs unprivileged and cannot allocate a single gralloc buffer. This 4.14 kernel predates dma-buf heaps, so legacy ION is the *only* allocator Mali's gralloc has. |
| Phosh/compositor start | `CONFIG_VT=y` so `/dev/tty0` exists. **Not** `CONFIG_FRAMEBUFFER_CONSOLE` — fbcon crashes against the Samsung decon driver; bare VT does not. |
| Wi-Fi | The driver exposes three netdevs all typed `managed`; the network manager binds `p2p0` (Wi-Fi Direct), which scans fine and can never associate. Force `wlan0`. |
| Audio | **The vendor audio HAL is 32-bit only.** A 64-bit audio server silently falls back to the generic stub and gets a stream with a NULL op table. Bridge through Android's own 64-bit `audio.hidl_compat` over `/dev/hwbinder`. |
| Frame pacing | The default `energy_adaptive` governor starves the compositor (~37fps). `schedutil` gives a measured 60. |

**The single most valuable debugging technique in this project:**

```sh
lxc-attach -n android -- /system/bin/logcat -d -b all
```

Android HAL errors appear **nowhere** in the Linux journal or `dmesg`. Processes
running *outside* the container that load Android libraries via libhybris log
there too, under their own PID. This is what found the display root cause after
`strace` and binder debugfs had both been exhausted.

---

## 5. Mistakes already made — do not repeat them

* **Never hand-roll the kernel build.** Kernels built with a bare `make`
  compiled cleanly and *never booted* — verified against a known-good ramdisk as
  a control. The tree's own `build.sh` sets `KCONFIG_BUILTINCONFIG` (a second
  baseline defconfig merged through the environment), `ANDROID_MAJOR_VERSION`,
  `PLATFORM_VERSION` and the toolchain's `LD_LIBRARY_PATH`. This is why
  `build-kernel.sh` shells out to it and must never "clean that up".
* **Change one variable per boot test.** A kernel that changed two things at
  once bootlooped the device and cost an hour isolating which. This is the
  project's own rule and it was broken by the session that wrote it down.
* **`/proc/config.gz` and `lxc-checkconfig` lie here** — they read a stale frozen
  IKCONFIG blob. Check features empirically, or via `/proc` (e.g. `/proc/sysvipc`
  exists ⇒ `CONFIG_SYSVIPC=y`).
* **`mkbootimg --cmdline` is silently ignored.** S-Boot merges its own from the
  device tree's `bootargs`. Anything that must take effect goes in
  `CONFIG_CMDLINE` and needs a rebuild. Verify with a live `cat /proc/cmdline`.
* **The boot partition truncates silently** at 57,671,680 bytes. `dd` does not
  fail; the device just will not boot.
* **An identical error string is not an identical cause.** Real time was lost to
  a renderer test that "reproduced the exact same failure" — it reproduced a
  shared generic log line from a completely different code path. Read the code
  that emits a message before reasoning from it.
* **Don't trust a guard you haven't seen fire.** A checksum check in this repo
  used `awk '$1 ~ /^[0-9a-f]{64}$/'`; mawk (Debian's default) does not support
  `{64}` intervals, so it matched nothing and the guard passed everything while
  printing a success message.
* **`runonce` targets fire before the Android container is up.** On this port
  every one of them silently no-opped and was marked permanently done. That is
  how the device ran for days with no display cutout. Order device setup
  *after* the container, and check `/var/lib/runonce/done/` timestamps when
  something is simply *absent* rather than broken.

---

## 6. Where to actually start for Ubuntu Touch

1. **Reuse the kernel unchanged.** It is reproducible and boot-verified. Build
   it from `a50-halium` and confirm you get `074aad86…`. If you get that hash,
   your toolchain is correct before you have flashed anything.
2. **Check UT's kernel requirements against ours.** Ubuntu Touch's Halium
   version may want config options Droidian did not (apparmor is the usual one,
   and `CONFIG_SECURITY_APPARMOR` is worth checking first). Add them as a new
   patch in `kernel/patches/`, one at a time, boot-testing each.
3. **The ramdisk will be different and that is expected.** Ours is Halium's
   `initramfs-tools-halium` output plus four documented patches — the `/dev/kmsg`
   mknod, the skipped `/proc` move, a `/dev/sda32` fallback because udev never
   creates by-name symlinks, and forcing `BOOT_MODE=halium`. **Those four fixes
   are device facts and will very likely be needed again**, whatever initramfs
   UT builds. `a50-droidian/initrd/tree/` has them tracked as readable text.
4. **Vendor blobs and the Android container.** The Android side is already
   proven to run (75+ HAL processes). `android_device_samsung_a505f` and
   `android_vendor_samsung_a505f` exist as forks if you need device/vendor trees.
5. **Bluetooth is the known open bug.** `CONFIG_BT` + `CONFIG_BT_HCIVHCI` are
   needed (`bluebinder` fails `ENODEV` without `/dev/vhci`), but enabling them
   **bootloops this device**. The kernel itself boots fine — it reaches Linux and
   systemd starts — so the leading hypothesis is Android's `/init` hitting a
   fatal error and deliberately panicking the kernel, because this device runs
   with `androidboot.init_fatal_panic=true`. Catching `logcat` inside the
   bootloop window is the next step. Patch is parked in
   `kernel/patches-experimental/`.

---

## 7. Keep a way back

Always have a known-good boot image on hand before flashing, and never leave the
device bootlooping at the end of a session. Published, with hashes:

* `a50-droidian` release `boot-images-2026-09-01` — three boot images, all of
  which have booted this device
* `a50-droidian` release `initrd-2026-08-31` — the initramfs base and tree

Restore any of them with `scripts/flash/03-flash.sh <img>` from TWRP.
