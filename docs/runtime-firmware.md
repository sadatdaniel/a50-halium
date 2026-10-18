# Runtime vendor firmware instead of built-in blobs

17–18 October 2026. Goal: drop the eight proprietary blobs from
`CONFIG_EXTRA_FIRMWARE`, so public CI and the conventional UBports `build.sh`
can build the exact kernel. The phone loads the firmware from its own vendor
partition, as stock Android does.

## Facts established

- All eight files are on the A50 vendor partition (`/vendor/firmware`). The
  kernel cmdline already has `firmware_class.path=/vendor/firmware`, and vendor
  is mounted on the host by about 5–6 s. Halium's `ueventd` starts at t≈7 s
  and serves `/vendor/firmware`; the fallback timeout is 60 s.
- The ABOX driver already defers its SRAM firmware (`request_firmware_nowait`,
  `FW_ACTION_HOTPLUG`). In this boot the request fails at t≈2.19 s, before
  vendor is mounted, and the completion callback never retries
  (a50-ubuntu-touch experiment 007).
- The device tree sets `off on suspend`, so a later successful load enables
  the DSP through the existing completion path.

## Change

`kernel/patches-experimental/abox-firmware-retry.patch`: when the SRAM request
fails, retry `request_firmware_direct()` every 1 s, at most 120 times.
`build-kernel.sh --runtime-firmware` applies it and builds the full profile
with `CONFIG_EXTRA_FIRMWARE=""` (no `--firmware` needed).

CI runs 39033960637 and 39035037389 produced byte-identical Images
(`eae98061…`, 42,827,792 bytes). Compared with aa17's System.map, ignoring LTO
hash suffixes, the only differences are the eight removed `_fw_*` symbols and
the four retry symbols. The clean public build therefore reproduces aa17's
code. (The embedded IKCONFIG text of the CI build differs from aa17's; the
symbol comparison shows it does not reflect the built code. Untraced.)

Boot image `boot-aa17rf.img` was packed from the aa17 donor (ramdisk
`e78e8cb8…` unchanged): 53,624,832 bytes, SHA256 `d588c34d…`, archived in
release `kernel-builds-20261017`.

## Hardware result: ABOX fixed, speaker amplifier not

Flashed with a50-ubuntu-touch `scripts/experiments/flash-boot-image.sh`
(owner present). The candidate booted (root RO, AppArmor Y, zero failed
units), with no `Invalid calliope state` and ABOX runtime `active`, but **no
sound**. The TFA9872 amplifier rejects every stream:

```
tfa98xx_hw_params(): tfa98xx: invalid sample rate 48000.
tfa98xx 7-0034: ASoC: can't set tfa98xx-aif-7-34 hw params: -22
```

Its driver loads `Tfa9872.cnt`/`tfadsp.bin` once at probe, with no retry, before
vendor exists, so it has no rate/profile table. Restored aa17 with the same
script (current-boot guard); healthy, and no amplifier errors.

## Next

Give the tfa98xx container/DSP firmware load the same bounded retry (or
deferred load on first stream), then rebuild, flash with the owner present,
and test speaker, call audio and sleep. Keep aa17 (built-in firmware) as the
shipped kernel until that passes.

## Candidate 2: ABOX + TFA9872 retry — speaker audio works

`tfa98xx-firmware-retry.patch` adds the same bounded direct-load retry for
`Tfa9872.cnt`; `--runtime-firmware` applies both. CI run 39158814601 Image is
`6d000a98…`. Against aa17's System.map, the only differences are the eight
`_fw_*` symbols, the retry symbols, shifted initcall line numbers and one
compiler-renamed static helper in the edited file. Boot image
`boot-aa17rf2.img` is 53,624,832 bytes, SHA256 `7d5855ef…`, archived in
`kernel-builds-20261017`.

Hardware, 18 October, owner present:

```
[    5.312133] samsung-abox 14a50000.abox: SRAM firmware found after 3 retries
[    6.271030] tfa98xx_container_loaded(): tfa98xx: Tfa9872.cnt found after 4 retries
```

Root RO, AppArmor Y, zero failed units, no `invalid sample rate`, ABOX
`active`. **Owner confirms speaker audio works.** Unplugged sleep: 15 real
`PM: suspend entry/exit` cycles (longest 2 min 39 s), no audio errors, zero
failed units, and the owner confirms sound after wake. Owner confirms Bluetooth
headset audio works. Not yet tested: call audio (SIM moved). Repeated cold
boots and an overnight soak continue in daily use, with aa17 kept as fallback.
Rollback: `flash-boot-image.sh` with the aa17 image and the `7d5855ef…` current
hash.
