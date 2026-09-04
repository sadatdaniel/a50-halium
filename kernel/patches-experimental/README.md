# Experimental patches — NOT applied by the build

`build/build-kernel.sh` applies `kernel/patches/` only. Anything here is a
change that has been written and reasoned about but **has not passed a boot
test on real hardware**, so it is deliberately not in the default build.

To try one, copy it into `kernel/patches/`, rebuild, and boot-test it. Keep a
known-good boot image to fall back to before you do.

## `conn-gadget-double-register.patch` — fixes a real, diagnosed kernel bug; **not yet boot-tested**

Unlike the Bluetooth patch below, this one fixes a bug that has been fully
root-caused on hardware. It is here only because it has not itself been
through a boot test yet.

`f_conn_gadget.c` registers a **single file-static `struct miscdevice`** and
`conn_gadget_setup()` calls `misc_register()` on it with no already-registered
check. Because `misc_register()` starts with `INIT_LIST_HEAD(&misc->list)`, a
second instantiation of the conn_gadget configfs function points that node at
itself while its old neighbours still point at it — **`misc_list` becomes
circular**, and the next `list_for_each_entry()` inside `misc_open()` spins
forever *holding `misc_mtx`*, at 100 % CPU.

Every misc-device open on the system then hangs — `mali0`, `ion`, `binder`,
`hwbinder`, `uinput`, the compositor, every Android HAL. It presents as "the
GPU is hung", which is why it cost two sessions to find. Measured: 94 tasks at
`misc_open+0x34`, load average 115.

Reached because `usb_moded` (GNU/Linux side) and Android's `vendor_init`
(container side) both drive USB gadget configfs. `f_mass_storage` survives the
same race by failing loudly with `-EEXIST`; the Samsung functions corrupt the
list silently instead.

Full diagnosis, including why the spinning holder is invisible to D-state
sweeps, `wchan` grouping, SysRq-T and fd inspection: a50-ubuntu-touch
`docs/experiments/006-what-we-missed.md`.

**Status:** applies cleanly to the pinned tree (`git apply --check`). Ubuntu
Touch currently ships a userspace workaround instead — it keeps the container
away from USB gadget configfs entirely
(a50-ubuntu-touch `scripts/apply-device-workarounds.sh`). That workaround is a
stopgap; this patch is the real fix, and promoting it to `kernel/patches/`
after a boot test should let the workaround be deleted.

## `abox-runtime-pm-get-sync.patch` — **DISPROVED, do not use**

Its premise is wrong. It claims `pm_runtime_get()` never invokes the resume
callback, so `abox_enable()` never runs. The boot log says otherwise:

```
[    1.424961] samsung-abox 14a50000.abox: abox_enable
[    1.425029] samsung-abox 14a50000.abox: abox_download_firmware
[    1.425075] Direct firmware load for calliope_sram.bin failed with error -2
[    2.194323] samsung-abox 14a50000.abox: Failed to request firmware
```

`abox_enable()` runs fine at 1.42 s. The DSP never starts because the firmware
is requested before any filesystem exists on this device — the kernel rejects
the boot image's ramdisk as an initramfs ("junk in compressed archive") and
Samsung's SAR_RD loader only brings it up at 2.08 s — and
`abox_complete_sram_firmware_request()` returns early on `!fw` and never
retries. `pm_runtime_get_sync()` would change only the timing, not the outcome.

The actual fix is `CONFIG_EXTRA_FIRMWARE`, which links the blobs into the
kernel image so `fw_get_builtin_firmware()` resolves them with no filesystem at
all. **Audio now works on the device with that.** Full evidence:
a50-ubuntu-touch `docs/experiments/007-abox-firmware-too-early.md`.

Kept here only as the record of a disproved hypothesis.

## `abox-fixup-helper-dai-guard.patch` — fixes a real NULL deref; built and booted

`abox_hw_params_fixup_helper()` hands `w->priv` to
`abox_if_hw_params_fixup_by_dai()` for every widget carrying a stream name, but
`w->priv` is a `snd_soc_dai` only for DAI widgets, so it dereferences a non-DAI
pointer at `dai->dev` (offset 0x10, the observed fault address) and panics.
Guarded the way ASoC's own `snd_soc_dapm_connect_dai_link_widgets()` guards the
identical lookup. The same unguarded code is present verbatim in other Samsung
Exynos ABOX trees, so this is long-standing upstream rather than a local
regression.

## `bluetooth-linux-stack.patch` — enables `CONFIG_BT`; **bootloops the device**

Appends the Linux Bluetooth stack to the Kconfig set: `CONFIG_BT`,
`BT_BREDR`, `BT_LE`, `BT_HCIVHCI`, `BT_RFCOMM(_TTY)`, `BT_BNEP*`, `BT_HIDP`.

The reasoning behind it is sound and still stands:

* `CONFIG_SCSC_BT` is already enabled upstream and provides `/dev/scsc_h4_0`,
  which Samsung's own `android.hardware.bluetooth@1.0-service` drives — that
  service is confirmed running inside the Android container.
* What is missing is the Linux side. With `CONFIG_BT` unset there is no
  `AF_BLUETOOTH` (`hciconfig` → *"Address family not supported by protocol"*)
  and, critically, no `/dev/vhci`, so `bluebinder` — which proxies HCI from the
  Android HAL into the Linux stack — dies with `ENODEV` (*"code: 19"*).
  `CONFIG_BT_HCIVHCI` is the load-bearing option.
* `CONFIG_SCSC_BT_BLUEZ` is deliberately left unset, so the Samsung driver does
  not register its own hci device and race the Android HAL for the same chip.

### What actually happened (2026-08-31)

A kernel carrying this patch was built, packaged into a boot image with the
known-good ramdisk, and flashed. **The device bootlooped.** The failure mode is
specific and worth recording, because it rules things out:

* It was **not** an early kernel panic. The device reached Droidian and sat on
  the boot splash "loading for a while" before rebooting, repeatedly.
* The debug shell on the USB gadget came up during each loop, which means the
  kernel booted, the initramfs ran, and systemd started. The kernel itself is
  fine.
* This device boots with `androidboot.init_fatal_panic=true` and
  `androidboot.init_fatal_reboot_target=recovery` compiled into `CONFIG_CMDLINE`.
  Android's `/init` deliberately crashes the kernel when it hits a fatal error —
  this project has already been bitten by exactly that once, when a dangling
  `/apex` symlink produced an identical-looking reboot loop. A fatal error in
  Android init is therefore the leading hypothesis, not a kernel-level fault.

The boot image also carried a second change (removal of a leftover debug patch,
see `../patches-historical/`), so strictly the bootloop is attributable to
*that pair*, not to Bluetooth alone. Isolating it is the next step and the
reason this patch is parked here rather than deleted.

### How to investigate next

1. Build with **only** this patch on top of the proven set, nothing else, so
   one variable moves.
2. Reproduce the loop, then read Android's own log rather than the Linux one:
   `lxc-attach -n android -- /system/bin/logcat -d -b all`. HAL and init errors
   appear nowhere on the Droidian side. Catching it may need the log written
   out over the network during the loop window.
3. If Android init is the one panicking, look at what the Bluetooth HAL service
   does differently once `/dev/vhci` exists and `AF_BLUETOOTH` is available.

### Update, 2026-08-31: Bluetooth is now isolated as the cause

The caveat above — that the bootloop was attributable to Bluetooth *and* the
debug-patch removal together — has been resolved by testing the other variable
on its own.

A kernel with the debug patch removed and **no Bluetooth** (build
`074aad86958de6b8a4914269826f87f70c7eeb5315bb3842e4d935dacd566be6`) was
packaged with the same known-good ramdisk, flashed, and **booted normally**:
Android container `RUNNING`, Phosh active, stable minutes in.

So removing the debug patch is safe, and this Bluetooth patch is the sole
remaining explanation for the bootloop. The investigation steps above stand,
and step 1 is now done.
