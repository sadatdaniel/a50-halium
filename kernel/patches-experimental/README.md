# Experimental patches — NOT applied by the build

`build/build-kernel.sh` applies `kernel/patches/` only. Anything here is a
change that has been written and reasoned about but **has not passed a boot
test on real hardware**, so it is deliberately not in the default build.

To try one, copy it into `kernel/patches/`, rebuild, and boot-test it. Keep a
known-good boot image to fall back to before you do.

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
