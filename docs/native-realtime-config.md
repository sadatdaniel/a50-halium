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
