# Wi-Fi system-sleep candidate (aa12)

Experimental; aa12 is not hardware-tested.

On aa10, USB recovery succeeded but ordinary deep sleep returned after 0.011 s
with a WLBT mailbox wake and no memory-interface power-down. Disabling Wi-Fi
temporarily allowed 22.620 s of real sleep and memory power-down. Sending the
existing SETSUSPENDMODE 1 command before sleep allowed memory power-down with
Wi-Fi still connected; a data frame woke it after 1.105 s. Normal mode was
restored afterward. Neither comparison establishes battery life or reliable
automatic suspend.

The standard cfg80211 suspend/resume callbacks were no-ops. This patch extracts
the existing vendor SETSUSPENDMODE operation into a shared helper and invokes
it before the process freezer through a PM notifier. The late cfg80211 callbacks remain no-ops. An already-prepared userspace sleep state is left
alone. A mode changed by Linux PM is restored on resume; failed preparation
is rolled back because the failed device's resume callback will not run.
Failed restoration keeps a marker and blocks another suspend instead of
silently treating a partially restored state as the new baseline.

The notifier holds RTNL while invoking the helper, preserving interface
registration. The existing helper owns its own driver mutexes and firmware
transactions. Full firmware/parent-device PM ordering needs hardware testing.
The vendor helper's existing packet-filter logging/error semantics are not
redesigned here; the callbacks propagate its returned result.

Build with --wifi-sleep-fix on a fresh source volume. The aa11 recipe also
includes --apparmor ubports --watchdog-freezer-fix --usb-otg-sleep-fix
--usb-otg-core-reinit, retaining hardened usercopy.

The compiled callback check exercises repeated cycles, existing sleep mode,
inactive/missing interfaces, preparation rollback and restoration errors.
Firmware operations are mocked; a successful check is not a hardware pass.
After compilation, repeat the guarded PM ladder, connected Wi-Fi real sleep,
post-wake networking and delayed health, then automatic screen-off sleep and
incoming-notification tests. Preserve the known-working boot and TWRP.

## aa11 evidence and aa12 timing change

Aa11 passed the freezer/devices/core ladder and real AppArmor enforcement.
Two full sleeps lasted 0.011 seconds with MIF blocked; manual preparation three
seconds before sleep allowed 0.970 seconds and MIF power-down before a TCP wake.
This motivates earlier preparation, without assuming network wakes are faulty.
Aa12 prepares in PM_SUSPEND_PREPARE, before processes freeze, and restores in
PM_POST_SUSPEND, including abort paths. No arbitrary delay is added. Registration
happens after driver initialization; detach unregisters before stopping the
driver. A failed prepare rolls back itself because the PM core excludes that
notifier from rollback. A failed restore retains the marker but does not stop
other devices' post-suspend callbacks. Mock tests cover these branches; firmware
readiness, actual sleep duration, and automatic screen-off behavior remain unproven.
