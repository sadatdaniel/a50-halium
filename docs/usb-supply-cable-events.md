# USB cable event candidate

4 October 2026. Candidate only; not flashed or validated on the A50.

The aa13 Samsung battery driver exposes the USB supply ONLINE property but
contains no power_supply_changed call for psy_usb. The normal usb-moded
power-supply detector depends on those events. A runtime Android detector test
did not restore USB after physical reconnect. The confirmed awake cable cycle
produced battery ONLINE 4 -> 1 -> 4 events but zero USB supply events. The
Android DISCONNECTED event stopped adbd, with no return event after reinsertion.
Rollback restored configuration at 04:09:16 UTC, but Developer Mode still had
to be toggled to recover access. Boot and suspend counters stayed unchanged.

The existing [Samsung Exynos5433 port correction](https://github.com/edp17/android_kernel_samsung_exynos5433/commit/b57dfff88bb9149de5e5966e08543442a8207909)
moves USB notification out of periodic battery polling and into cable work.
The [Sailfish porting guide](https://sailfishos.wiki/books/hardware/page/hadk-hot)
recommends this for supplies whose properties change without USB events.
This candidate adapts its single cable-work notification to the A50's pointer
API: power_supply_changed(battery->psy_usb). Charging settings are unchanged.

The existing Linux 4.14 helper queues native power-supply work, emits the USB
KOBJ_CHANGE event and releases its temporary wake source. Notifications stay
out of periodic monitor work. Early unchanged-cable exits remain unchanged.
The exact original A50 driver blob is 3af565e7a47c1782d47528910e509baa76376cec.
Patch application check passed on the retained source; no hardware fix is claimed.

Normal clean reproduction adds --usb-supply-events to the existing kernel
build command. The source sentinel and manifest record the option. The AppArmor
suffix now preserves the full profile's realtime compatibility marker, preventing
old cached trees from silently matching the newer full profile.

The guarded build/experiments/build-aa16-usb-events.sh reuses aa15's retained
source and objects, refuses unexpected source/config/Image hashes, applies only
the USB notification patch and writes separate out-aa16-usb-events artifacts.
It preserves published aa15 artifacts. Its config must remain byte-identical.
This incremental build does not replace a clean release rebuild.

Before selecting the candidate: collect confirmed cable events; compile and
pack within the measured boot partition; preserve the current working boot and
vendor/recovery hashes; test native power-supply detection without -r/-f; check
repeated USB attach/detach, real suspend/resume, MTP, wall charging, Bluetooth,
realtime scheduling, camera/audio and AppArmor. Vendor is never modified.

## Offline build passed; hardware test pending

Docker a50-kbuild-aa16-usb-events completed with exit 0 at 04:15:16 UTC.
The candidate retains aa15's exact config and passes boot-header re-parsing.
The working ramdisk is unchanged; 1,687,552 bytes remain in the boot partition.

| Artifact | SHA256 |
| --- | --- |
| Image, 45,187,088 bytes | 079fd1d9b90fb4b278ba07ab7685e211b1ff30b1301d5cc8105b1af995e5b885 |
| System.map | a441c5f51bca73c6ac03c404c63f9f5f551cc6aa0dc30b2ca1cfa4eccf8e1100 |
| Actual config | fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2 |
| boot-aa16.img, 55,984,128 bytes | 05a84a04cb162cb8ef0b193859cc8dbc1ad2c20d665f1b978de5e3c52a3531a5 |

Packaging uses the normal build/pack-boot-image.py with the retained aa12 donor
and build/read-boot-header.py. Re-run the guarded full profile for independent
release reproduction; the source cache now has the usb-supply-events suffix.

On the unchanged aa13 phone, /userdata/a50-aa16-test now contains the verified
working boot-aa13.img, the verified candidate, parent boot ID/counters and
vendor/recovery hashes. build/experiments/flash-aa16-candidate.sh refuses any
unexpected boot, image, partition size or protected-partition hash, writes only
boot, verifies readback and leaves reboot as a separate step. Its unexecuted
TWRP fallback restore-aa13-twrp.sh uses the previously verified lowercase boot
label and sda14 identity. No partition has been written. The owner must be
beside the phone before the controlled test in case recovery is needed.

Vendor SHA256: 48f5e9bfb9ef2dfd032ec7c92986ac1c8886abe7d658430b57ccacb5e3cffe3b.
Recovery SHA256: 8535a9d9193243412fcefc0e6f1ba585d60e1533e65069867444a49d0287e51f.
These guards describe this test phone; do not assume them for another installation.

## aa16 hardware result (supersedes candidate-only notes above)

The controlled boot passed on 4 October. Actual AppArmor allow/deny enforcement
and RFCOMM socket creation passed; RTKit now grants audio realtime priority 5.
The owner confirmed screen/touch. Root read-only, protected partitions unchanged.
Native awake cable testing produced USB ONLINE 1 -> 0 -> 1 kernel/udev events
and normal adbd removal/restart. The notification correction therefore worked.
USB still failed to enumerate until Developer Mode was toggled: Samsung DWC3
discarded pullup(0) while runtime-suspended, leaving stale softconnect state.
See [the isolated ordering correction](usb-pullup-state.md). Native detection
is not yet selected permanently; runtime configuration was removed at 09:12:13
Berlin, its hold/collector stopped and the expected stopped collector status
cleared after inspection. Current phone subsequently booted aa17.
