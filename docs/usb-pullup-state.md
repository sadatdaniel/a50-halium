# Preserve DWC3 pull-up intent across runtime suspend

4 October 2026. Experimental aa17 boots; physical cable validation pending.

aa16's USB supply notification produced native ONLINE 1 -> 0 -> 1 events
on the awake cable cycle. usb-moded stopped and restarted adbd accordingly.
The remaining reconnect failed in Samsung's DWC3 pull-up function: cable
removal powered down the controller before unbind requested pullup(0).
The early pm_runtime_suspended return skipped updating softconnect. Rebind
then requested pullup(1), logged "pullup is already on" and did not enumerate.
Developer Mode off/on executed the missing disconnect/connect and restored USB.
This was an awake cycle, with suspend counters unchanged at zero.

[Upstream Android common DWC3](https://android.googlesource.com/kernel/common/+/34aea58089b5383152a3697b41fc1f5cebc01efd/drivers/usb/dwc3/gadget.c)
stores requested connection state before returning for a powered-off controller.
The A50 adaptation moves its existing runtime-suspended guard after the
existing locked softconnect update. It retains Samsung's locking, VBUS guard,
PHY sequence and power management. No new wake source, timer, polling daemon
or register access while powered off is added. This is an ordering adaptation,
not a wholesale modern DWC3 driver backport.

## Reproduce and verify

Normal clean builds add --usb-pullup-state-fix to the established full profile
including --usb-supply-events. The build script records both options in its
source-cache sentinel and manifest. build/experiments/build-aa17-pullup-state.sh
provides a strictly guarded incremental reproduction from aa16; it preserves
published parent artifacts and requires the same actual configuration.

build/tests/check-dwc3-pullup.py extracts the actual driver function and runs
a small native C assertion check with mocked platform calls. The original
function compiles and aborts on the suspended-disconnect assertion; the patched
function passes disconnect, resumed rebind, normalization, duplicate request,
active disconnect and no-VBUS intent cases. This checks logic, not hardware
timing. Run it against the Linux source tree, with --expect-failure only for
the original source.

Original driver blob fb70a6702f6f9f7492490853dd1e56f82299da8a;
patched blob dc2e2beb985375c3b52fb24585718f672336983b.
Patch SHA256 01d699123548a422396f6fea2ccbd4cd7a7d061f74177f76c18bbb5ec781829b.
Docker build exited 0 at 07:19:41 UTC. Packaging uses the existing
pack-boot-image.py and verified aa12 donor; read-boot-header.py re-parses it.

| Artifact | SHA256 |
| --- | --- |
| Image, 45,187,088 bytes | 4ca1e8d8e3849a205b60889b557a67c4775d3ffc39ca18e227b5c2961fd84d70 |
| System.map | be0bff5e162c587837de5136930ea0edb019d552c822f90265ec2875230b470e |
| Actual config | fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2 |
| boot-aa17.img, 55,984,128 bytes | a413d2bc4a605489225a0b5d8e512965af83eea39b7abb6097dbc2f7420775c8 |

The ramdisk remains e78e8cb8d5269e81852a1b417d0b28c98f2c4bce8bcb035e2cab19bd9cfd9ac4;
1,687,552 bytes remain in the measured boot partition. The guarded
flash-aa17-candidate.sh requires the running parent boot, exact aa16 partition
prefix, candidate and fallback hashes, boot size and vendor/recovery hashes.
It writes only boot and verifies readback. The private fallback retains aa13
and aa16; the recovery restoration script remains available. These are guards
for this phone, not partition/hash assumptions for another installation.

aa17 boot readback passed, kernel boot ID changed, AppArmor Y, root read-only,
no failed system units. The owner confirms screen and touch work. RTKit again
successfully scheduled audio threads at priority 5. Vendor/recovery hashes
remain unchanged. Native USB testing uses the existing reversible scripts
with --aa17, the user's existing authorized mode, bounded awake hold and an
independent ten-minute rollback. No permanent rescue-mode removal yet.
Repeat attach/detach and sleep/reconnect, then MTP/charging and other release
checks before selecting this kernel for the clean release build.

## aa17 hardware result: awake reconnect and real sleep passed

4 October: three awake cable removal/reinsert cycles returned authorized ADB
automatically, without Developer Mode toggles. Native power-supply detection
reported every ONLINE transition; adbd stopped on removal and produced a new
FUNCTIONFS_ENABLE on reinsert. The first removal/reinsert was 09:32:40/09:33:10,
then 09:36:09/09:36:32 and 09:36:54/09:37:18 Berlin. All used the same kernel
boot. This supersedes the pending hardware result above.

The established native automatic-suspend test then completed four deep cycles,
success 0 -> 4, with zero suspend or resume failures. The current-boot sleep
durations were 2.267, 14.621, 14.578 and 55.943 seconds: 87.409 seconds total.
Ignore the earlier boot's two records in the append-only private logger. Wi-Fi
data wakes were followed by automatic resuspend; the calendar wake deadline was
07:42:42 UTC and cleanup began one second later. No forced mem write was used.
The owner confirmed screen/touch. Wi-Fi association returned; USB reinsert at
09:44:14 produced FUNCTIONFS_ENABLE immediately and authorized host transport,
with no Developer Mode toggle. Internet routing and longer drain/soak checks
are separate. AppArmor's real allow/deny probe and RFCOMM/L2CAP socket creation
passed after this test; root read-only, same boot, protected hashes unchanged
and no failed system units.

The USB manager still sometimes reports a charging-mode UDC write failure
after the controller has powered off on removal, followed by fallback to
undefined. Reconnect now succeeds despite that message. This remaining mode
transition warning and MTP/wall-charger behavior are recorded for validation;
do not claim every USB mode is stable from ADB tests.

At 09:47:30 Berlin, the exact tested native settings were installed through the
packaged device EnvironmentFile interface. USB_MODED_ARGS and hardware adaptation
args are empty, removing old rescue/always-connected flags. No Android tracking,
polling daemon, automatic adbd restart hook or debug flag ships. The generated
daemon command is /usr/sbin/usb_moded --systemd --force-syslog. Temporary files,
timers, collectors and test wake holds were removed; read-only root and normal
authorized debugging returned. The root filesystem overlay and guarded
scripts/experiments/apply-aa17-native-usb.sh reproduce this configuration.
Backup configuration remains private in /userdata/a50-aa17-test; restoring its
original-usb-config.conf and restarting USB is the configuration rollback.
The boot fallback is independent. Final normal-configuration cable check and
clean-image/first-boot/OTA regression remain distinct validation steps.

Final normal-configuration cable cycle passed at 09:48:22/09:48:59 Berlin,
with FUNCTIONFS_ENABLE at 09:49:00 and host transport authorized. No -r/-f/-D,
runtime overrides or test wake holds remained; same boot, root read-only,
suspend counters still 4/0 and no failed system units. Four awake reconnects
and one bounded multi-cycle sleep test are verified; longer soak is pending.
