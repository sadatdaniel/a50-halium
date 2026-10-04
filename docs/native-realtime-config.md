# Native realtime scheduling for Ubuntu Touch

4 October 2026. The fresh 26.04 RTKit service has CAP_SYS_NICE but its CPU
cgroup rt_runtime_us is zero. The actual aa13/aa14 configuration enables
CONFIG_RT_GROUP_SCHED. The exact Samsung kernel's kernel/sched/core.c,
lines 5330-5341, rejects realtime scheduling with EPERM for a group with a
zero runtime budget when that feature is enabled.

Both [systemd's documented kernel requirements](https://github.com/systemd/systemd/blob/main/README)
and the [official Halium kernel checker](https://github.com/Halium/halium-boot/blob/master/check-kernel-config)
recommend CONFIG_RT_GROUP_SCHED=n. The full Ubuntu Touch profile now writes
that conventional configuration into the existing generated config block.
The base profile is unchanged. No live cgroup-budget, RTKit privilege or
unrestricted-realtime workaround is used.

The source sentinel distinguishes the updated full profile, and the idempotent
configuration helper rejects an older full-profile block. A fresh normal build
and its post-build actual-config check are the reproducible path. Reference
configs and old artifact fingerprints remain historical inputs.

The guarded aa15 experiment uses the exact retained aa14 tree to avoid a
second large source download. It retains the parent config, disables only the
standard Kconfig option using scripts/config, runs olddefconfig, and rejects
any additional configuration changes before compiling. It also updates the
existing generated build block to match the normal full-profile path.
Source/Image/config guards prevent using another parent. This incremental
candidate is not proof of an independent clean rebuild.

Compilation and offline packaging passed; hardware validation is pending. Before release: verify RTKit
can obtain normal scheduling, camera/audio, confinement, Bluetooth protocols,
suspend/resume and Android service health on the new kernel. No candidate has
been flashed, and no live scheduling policy was changed.


The first aa15 compile passed the exact one-option config difference check,
but failed in Samsung kernel/sched/rt.c: direct rt_rq->rq and the private
entity_is_task macro access members absent without RT groups. The build was
stopped; no new Image was produced or installed.

Linux 4.14 already provides rq_of_rt_rq and rt_entity_is_task for both group
configurations, and the same helpers are present in this Samsung tree.
rt-standard-no-group-helpers.patch reuses them at the two failing call sites
and deletes the unused duplicate macro. With groups enabled, the helpers use
the same members; without groups, they use the existing container/task logic.
There is no new scheduler implementation or dummy struct field. All callers
of the duplicate macro were checked; the sole call is replaced.

Patch application passed on the exact source blob
a35d675109819a6b11f740fec2f71025910279dd, producing
cbeb3bef0d66625a1ee0667a501e92217715af35. The normal full profile includes this
compatibility correction and its updated sentinel rejects older cached trees.
The guarded incremental script's --resume accepts only the recorded failed
candidate's config/build block and verified parent; it can then resume with
the focused helper correction. Hardware scheduling behavior remains untested.

## Completed aa15 candidate

The focused retry completed with exit 0 at 2026-10-03T23:03:55Z. The actual
post-build config differs from aa14 only in CONFIG_RT_GROUP_SCHED=n. RFCOMM,
BNEP and HIDP initialization symbols remain in System.map, and AppArmor is
enabled by default. The incremental source/parent guards and full build
manifest are retained under out-aa15-native-realtime.

| Artifact | SHA256 |
| --- | --- |
| Image, 45,187,088 bytes | e67dfa236fc08e5f476f74da243578be356e177ef616c878c723cc425d72fd5b |
| System.map | bdc0fa582132765071c08194a1cbfccf2a3dda88977bed910645b569e2ea0ba1 |
| Actual config | fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2 |
| boot-aa15.img, 55,984,128 bytes | 4a55b320b49e68f7191bc563ad5d165820823f4d7b4c77e1bc34787d41b57f40 |

Packaging used the existing build/pack-boot-image.py with the retained, known
aa12 boot donor (SHA256 795e8b7fffda6b46e318d1bccc542b3a7d807987a7787f5115f0dcb27b7b9dcb):

```
python3 build/pack-boot-image.py out-aa12-wifi-early/boot-aa12.img \
  out-aa15-native-realtime/Image - out-aa15-native-realtime/boot-aa15.img
python3 build/read-boot-header.py out-aa15-native-realtime/boot-aa15.img
```

Re-parsing verified the exact new kernel and unchanged working ramdisk
e78e8cb8d5269e81852a1b417d0b28c98f2c4bce8bcb035e2cab19bd9cfd9ac4.
The boot image leaves 1,687,552 bytes in the measured boot partition. No
candidate was flashed: the connected phone still runs aa13. Successful
compilation and partition fit do not prove scheduler, Bluetooth or suspend
behavior. Validate those on hardware before selecting a release kernel, then
reproduce with the normal full build from clean source.

## Hardware check through aa16 and aa17

4 October: these descendant kernels include the exact aa15 configuration.
Both boots report successful RTKit scheduling of three PulseAudio threads at
priority 5, where aa13 failed with EPERM. AppArmor enforcement passed on aa16;
aa17 boots enabled, with read-only root and user-confirmed display/touch.
This validates normal scheduling availability. Broader media/call/keyboard,
sleep and clean-release reproduction checks remain; compilation-only notes
above are historical.
