# Wi-Fi system-sleep candidate (aa11)

Experimental; no aa11 hardware result yet.

On aa10, USB recovery succeeded but ordinary deep sleep returned after 0.011 s
with a WLBT mailbox wake and no memory-interface power-down. Disabling Wi-Fi
temporarily allowed 22.620 s of real sleep and memory power-down. Sending the
existing SETSUSPENDMODE 1 command before sleep allowed memory power-down with
Wi-Fi still connected; a data frame woke it after 1.105 s. Normal mode was
restored afterward. Neither comparison establishes battery life or reliable
automatic suspend.

The standard cfg80211 suspend/resume callbacks were no-ops. This patch extracts
the existing vendor SETSUSPENDMODE operation into a shared helper and invokes
it from those callbacks. An already-prepared userspace sleep state is left
alone. A mode changed by Linux PM is restored on resume; failed preparation
is rolled back because the failed device's resume callback will not run.
Failed restoration keeps a marker and blocks another suspend instead of
silently treating a partially restored state as the new baseline.

cfg80211 holds RTNL while invoking these callbacks, preserving interface
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
