# Samsung Galaxy A50 (SM-A505F) — device facts

Hard-won facts about this specific device. Each one cost real time to discover;
none of them is guessable from documentation.

## Bootloader and boot image

* **The bootloader silently ignores `mkbootimg --cmdline`.** Samsung's S-Boot
  merges its own command line from the device tree's `bootargs`, not from the
  boot image header. Any kernel command-line flag that must actually take
  effect has to be compiled into `CONFIG_CMDLINE` and the kernel rebuilt.
  Always confirm with a live `cat /proc/cmdline` — never assume.
* **The boot partition is exactly 57,671,680 bytes.** A larger image does not
  fail to flash: `dd` truncates it silently and the device will not boot.
  `build/build-kernel.sh` refuses to finish if the image exceeds this.
* **Use the kernel tree's own `mkbootimg`** (`tools/make/bin/mkbootimg`), not a
  system-installed one. The system tool computes `header_version 1` addressing
  differently and rejects this device's official-style overflow address values.

## Kernel

* Linux 4.14.194, Exynos 9610 (`universal9610`), `ro.hardware = exynos9610`.
* **`/proc/config.gz` and `lxc-checkconfig` both lie on this device.** They read
  a stale, frozen embedded IKCONFIG blob rather than the live kernel's real
  configuration. Verify kernel features empirically — does the feature work when
  used — not by reading either of those.
* **`CONFIG_IPC_NS` at kernel level is a dead end.** Both `CONFIG_POSIX_MQUEUE=y`
  and `CONFIG_SYSVIPC=y` (either satisfies its dependency) regress early boot,
  in two different ways. Solve it in the container configuration instead.
* **`CONFIG_FRAMEBUFFER_CONSOLE` crashes against the Samsung decon driver.**
  `CONFIG_VT=y` on its own is safe: `decon_notify.c` only hooks the fbdev
  notifier chain, which nothing but fbcon drives, and there is no
  `register_vt_notifier` anywhere in the `dpu20` tree.

## Storage and partitions

* No `/product` partition exists. Android init treats a missing
  `first_stage_mount` entry as fatal, so both `/product` lines have to be
  removed from `fstab.exynos9610` — this is `kernel/patches/0001`.
* userdata is `/dev/block/sda32`, major:minor `259:16`.
* UFS platform path: `/dev/block/platform/13520000.ufs/by-name/<name>`.

## Graphics

* 1080x2340, 60 Hz, waterdrop cutout centred horizontally at the top. The
  cutout path lives in the vendor's own `config_mainBuiltInDisplayCutout`.
* This 4.14 kernel predates dma-buf heaps, so **legacy ION (`/dev/ion`) is the
  only buffer allocator Mali's gralloc has**, and it is created `0600
  root:root`. Anything running as an unprivileged user that talks to a graphics
  HAL needs that fixed first.

## Audio

* **The real audio HAL is 32-bit only.** `audio.primary.exynos9610.so` exists in
  `/vendor/lib/hw` but not in `/vendor/lib64/hw`, and
  `/vendor/bin/hw/android.hardware.audio.service` is itself a 32-bit binary. A
  64-bit userspace audio server cannot load it and will silently fall back to
  the generic stub, which hands back a stream with a NULL op table. Bridge it
  through Android's own 64-bit `audio.hidl_compat` wrapper over `/dev/hwbinder`
  instead.

## Bluetooth

* `CONFIG_SCSC_BT` is already set upstream and provides `/dev/scsc_h4_0`, which
  Samsung's own `android.hardware.bluetooth@1.0-service` drives.
* The Linux side is what is missing: with `CONFIG_BT` unset there is no
  `AF_BLUETOOTH` and no `/dev/vhci`, so a binder-to-vhci proxy fails with
  `ENODEV`. `CONFIG_BT_HCIVHCI` is the load-bearing option.
* Leave `CONFIG_SCSC_BT_BLUEZ` unset, so the Samsung driver does not register
  its own hci device and race the Android HAL for the same chip.

## Input

* Touchscreen `sec_touchscreen` on `event4` works. Volume keys work.
* **The power button generates zero kernel input events**, despite `gpio_keys`
  (`event3`) existing and libinput seeing the device. Unexplained, open.

## Diagnostics

* An idle device reports a **load average of ~16 forever**. It is 16 TrustZone
  kernel threads parked in uninterruptible sleep, not a spin. Read the runqueue
  field of `/proc/loadavg` instead.
