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

Compilation and hardware validation are pending. Before release: verify RTKit
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
