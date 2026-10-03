# Restore standard Linux Bluetooth protocols

3 October 2026. Fresh aa13 has CONFIG_BT_RFCOMM, BT_BNEP and BT_HIDP
enabled but the pinned Samsung net/bluetooth/Makefile comments out all three
build entries. A privileged standard socket probe succeeds for L2CAP and
returns EPROTONOSUPPORT (93) for RFCOMM. The registered protocol list contains
HCI, L2CAP and SCO, with no RFCOMM. BlueZ reports the matching voice-gateway
socket error. This is a build-rule defect, independent of missing config flags.

Restore the three obj-$(CONFIG_...) entries exactly as in
[Linux v4.14](https://github.com/torvalds/linux/blob/v4.14/net/bluetooth/Makefile).
The [pinned Samsung source](https://github.com/FreshROMs/android_kernel_samsung_exynos9610_mint/blob/bec0c2aff1ee8a02ac9f582d60fe611f1d2bc939/net/bluetooth/Makefile)
retains the standard protocol sources, so no new implementation is needed.
Use --bluetooth-protocols with the existing full profile and all aa13 options.
The choice is recorded in the patch profile and build manifest. A fresh build
is the reproducible path; source volumes with another profile are rejected.

The first bounded candidate may use the retained exact aa13 source/config
to avoid duplicating a large tree on the low-space host. Its base source,
configuration and Image hashes must match before applying the patch. Keep the
aa13 Image/boot image for rollback. This incremental candidate is not proof of
an independently reproducible clean build.

Required hardware checks: normal boot, RFCOMM/HIDP/BNEP initialization,
keyboard input and idle connection, reconnect, sleep/wake, speaker/media audio
and confinement. Missing RFCOMM alone does not prove the user's keyboard
disconnect root cause; HIDP/UHID transport and connection logs still matter.
Do not advertise Bluetooth stability from compilation or socket creation.
No Bluetooth bridge, pairing data, vendor firmware or calibration is changed.

The aa14 incremental build completed successfully. The unchanged .config
hash is 57f003bc5635e95e56f961f42c9b47054503d55874f0005ca6ccc6cef3751741.
Image SHA256 is 264b91035a1f69989a7e911f339294dd6932622cbdd91cc854b445dd40d4c302.
System.map contains rfcomm_init, hidp_init and bnep_init; its SHA256 is
77f283e0ee52e261495d3cad8170079f3565602a7ac8f7c56ff4c657b1601b5c.
The image is an unflashed development candidate. The ordinary phone reboot
requested for the separate Lomiri package fix still uses aa13.

The aa14 Image was packed with the verified aa13 donor boot layout and unchanged
ramdisk. boot-aa14.img is 55,984,128 bytes, leaving 1,687,552 bytes in the
57,671,680-byte boot partition. SHA256:
87840652ebd0ef31ad6cee77ee6e3d8236c25f533513ad3fdb454b52540e8bb4.
The original aa13 ramdisk hash is unchanged:
e78e8cb8d5269e81852a1b417d0b28c98f2c4bce8bcb035e2cab19bd9cfd9ac4.

The first incremental manifest copied the parent image hash and duplicated its
size/parent keys. Metadata is now canonical: child Image hash/size and aa13
parent hash are separate; the patch list includes both USB configfs and
Bluetooth restoration. The build script now emits those fields once, with
its own source revision and build timestamp. This corrects metadata only;
no binary was rebuilt or flashed. The exact child build time was not retained
and is explicitly marked unknown, rather than copying aa13's timestamp.
