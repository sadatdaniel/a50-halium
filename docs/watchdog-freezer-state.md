# Watchdog freezer state restoration — aa8 development validation

Use --watchdog-freezer-fix with full/ubports and a fresh source volume.
Do not include --abox-freezer-isolation in this candidate build.

The recovered aa7 /proc/last_kmsg records hardware timeouts after the freezer:
return at 129.128663s, storage timeout at 146.630060s, then I2C, GPU,
sensor-hub and Wi-Fi timeouts. The final BRK at slsi_mlme_tx_rx+0x39c is the
missing-confirmation WARN. Samsung's hardlockup hook replaces regs->pc before
report_bug, explaining why the later displayed PC=0 is not reliable evidence
of a NULL callback. The phone rebooted automatically into the verified aa1.
Both ABOX callbacks were skipped; no ABOX power-cycle appears in the test
window. That intervention did not prevent the failure.

The freezer's emergency multistage watchdog start unconditionally arms the
secondary timer, even if it was off before stop. These paired helpers are only
called from kernel/power/process.c in this tree. The driver defaults to off at
boot; systemd RuntimeWatchdogUSec=0 and Android watchdogd is disabled.
The captured start programs count=0xb32b, control=0x5c3c: 45867 ticks with
prescaler 93 and divisor 128. At the 26MHz oscillator rate that is about 21s,
matching the beginning of failures after start at 124.004070s. The device tree
specifies 30s and the secondary ratio is 70 percent. Causation remains a
hypothesis pending the fixed-kernel test.

The patch records hardware ENABLE under the existing lock during stop and
only restores a previously active timer. Normal watchdog start/keepalive,
panic/reset, nowayout and security paths are unchanged. New logs expose the
pre-stop state. This preserves state rather than disabling a watchdog globally.

Mock-register tests compile the actual patched helpers with -Wall -Wextra
-Werror and cover inactive/active repeated pairs, unmatched start and no device.
Patch application and build-script syntax pass. Kernel build and initial phone tests now pass as detailed below. Run build/tests/test_watchdog_freezer.py inside a50-halium-build
with original source read-only at /ksrc and this repository at /port; it writes
only /tmp. No private device logs are committed.

Consulted https://docs.kernel.org/watchdog/watchdog-kernel-api.html . Searches
for the exact Samsung helper names found no ready upstream backport.

## Validation update, 2026-09-13 10:20 CEST

Two freezer-only cycles passed with normal ABOX behavior; the first was
observed for ten minutes before repetition. Both stages of both cycles
confirmed was_enabled=0 and kept the secondary watchdog stopped.

One devices-stage test ran08:19:30–08:19:36 and returned successfully
(success3/fail0 total). Windows then reported Device Descriptor Request
Failed, while the phone believed its USB gadget was configured. Wi-Fi
remained usable; the phone did not reboot. Unbinding/rebinding the existing
g1 UDC restored enumeration, but recreated rndis0 without its address.
Restoring its original10.15.19.82/24 address plus temporary169.254.68.82/16
allowed USB SSH using Windows' existing link-local subnet. Host address
change was denied by Windows administrator permissions; no host setting
was successfully changed. A gadget DCTL stop timeout occurred during the
manual reconnect, separate from the original watchdog failure cascade.

Same aa8 boot remained responsive over both Wi-Fi and recovered USB at
10:20 CEST, over two hours after the devices-stage test. No full deep sleep
attempted. Device-stage return does not establish complete driver resume:
USB still needs a fix. Watchdog correction stays opt-in pending broader
validation. Screen/touch response from user for aa8 remains pending.
