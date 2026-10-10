# Completing the existing pidfd wait backport

10 October 2026. Candidate aa18 builds and packs successfully; it is unflashed.
The connected phone remains on the tested aa17 kernel.

## Evidence and upstream implementation

Bounded native diagnostics find no kernel OOM kill in this boot, an empty sampled
Android crash buffer, and no Android ANR since its session boot. Approximately
1.6 GiB is available at the sample. These are observations, not long-use proof.
The deferred physical background test did not observe an unplug. Its temporary
observer units and wake holds are removed; normal suspend activation remains.

NetworkManager's dispatcher repeatedly reports unknown child status 0xffffffff.
The accompanying GLib diagnostic is waitid(P_PIDFD) failing with EINVAL. The
routing script can execute while its exit status is misreported; neither these
logs nor the probe establishes a cause for the suspected Waydroid crash or slow
networking. Do not disable dispatch scripts or alter network routes as a fix.

The real child-process probe confirms pidfd_open and exit polling work on aa17,
but running-child WNOHANG, nonblocking waits and exit-status retrieval fail with
EINVAL. Its ordinary child wait still returns the expected status 37. The same
probe passes on the existing Linux build runtime. All waits are bounded and
only its own harmless child is created/reaped.

Upstream Linux [3695eae](https://github.com/torvalds/linux/commit/3695eae5fee0605f316fbaad0b9e3de791d7dfaf)
adds P_PIDFD to waitid. This vendor tree already contains the two-argument
pidfd_get_pid helper and working poll support. The minimal kernel/exit.c
adaptation uses the [v5.10 implementation](https://github.com/torvalds/linux/blob/v5.10/kernel/exit.c)
for the helper signature and nonblocking semantics, retaining existing
P_PID/P_PGID behavior and normal parent-child permission checks.
SO_PEERPIDFD and the existing polkit authentication configuration are unchanged.

## Reproduction

- build/tests/check-pidfd-wait.py: real syscall/poll/status/WNOWAIT/reap probe.
  aa17 returns 1; supported Linux returns 0. Run with python3 on the native host.
- kernel/patches-experimental/waitid-pidfd.patch: valid source backport.
- build/experiments/build-aa18-pidfd-wait.sh: guarded incremental aa17 cache,
  checking source pin, parent image, configuration, source hash and profile.
- build/build-kernel.sh --pidfd-wait: explicit clean-build option, recorded in
  patch list, cache sentinel and manifest. Defaults and base expected hashes
  remain unchanged; fresh full reproduction has not been run in this checkpoint.

Fresh full profile adds --pidfd-wait to the existing aa17 invocation:

```sh
./build/build-kernel.sh --profile full --firmware PRIVATE_FIRMWARE_DIR \
  --apparmor ubports --watchdog-freezer-fix --usb-otg-sleep-fix \
  --usb-otg-core-reinit --wifi-sleep-fix --usb-configfs-fix \
  --bluetooth-protocols --usb-supply-events --usb-pullup-state-fix \
  --pidfd-wait --out out-aa18-pidfd-wait
```

Cached build uses the existing source/toolchain without network or downloads.
Configuration remains fa778177456d3e295ef1783a483da59bf105ea8fee8faa6c2e48fa25508ba8e2.
Kernel Image: def115c02458bf53c78219645250a8c15f624c94cfa1eee9694a90c9ff8d710f.
Patch: dbf36cd263b5f19cacb07d93c7e2099ff5f0dd254cb212d1c19ad8bcebd83e74.

Reuse the established packer with the boot-verified aa17 donor:

```sh
python3 build/pack-boot-image.py out-aa17-pullup-state/boot-aa17.img \
  out-aa18-pidfd-wait/Image - out-aa18-pidfd-wait/boot-aa18.img
```

It reparses/verifies the output, preserving header and ramdisk. Candidate is
55,984,128 bytes, 1,687,552 bytes below the 57,671,680-byte boot partition limit.
Boot SHA256: 81f172febf16ebc8d132565f5bda3de8c6200df177647d8034d8a34971ec9776.
Ramdisk SHA256: e78e8cb8d5269e81852a1b417d0b28c98f2c4bce8bcb035e2cab19bd9cfd9ac4.
Build manifest and checksums are retained with the private local artifacts.
Syntax, patch application and parent/config guards pass; compile/link/pack pass.
There is no boot or positive phone syscall result for aa18 yet.

## Hardware and release gates

Use a guarded boot-only test with the owner available for recovery and verified
known-good aa17 rollback. Preserve vendor and TWRP. After boot, repeat the real
probe, normal security/audio/app health, native dispatcher exit-status check,
awake USB cable cycles and actual unplugged suspend. The existing sleep observer
currently pins aa17: it must not be bypassed or reused on aa18 without an explicit
image guard/update. Then validate Waydroid's existing background window and long
soak. No production kernel pin or release payload changes before this evidence.
