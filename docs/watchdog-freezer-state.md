# Watchdog freezer state restoration — candidate, not yet boot-tested

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
Patch application and build-script syntax pass. Kernel build and phone tests
are pending. Run build/tests/test_watchdog_freezer.py inside a50-halium-build
with original source read-only at /ksrc and this repository at /port; it writes
only /tmp. No private device logs are committed.

Consulted https://docs.kernel.org/watchdog/watchdog-kernel-api.html . Searches
for the exact Samsung helper names found no ready upstream backport.
