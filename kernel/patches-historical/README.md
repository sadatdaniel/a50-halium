# Historical patches — kept for the record, deliberately NOT applied

Nothing in this directory is part of a build. `build/build-kernel.sh` only ever
applies `kernel/patches/`.

## `raw-diag-block-writer.diff`

A debugging patch from the period when the device would not boot at all and
there was no way to get any output off it — no serial, no framebuffer console,
no surviving log. It adds `raw_diag_write()` to `init/main.c` and
`init/initramfs.c`, which `mknod`s the userdata block device (259,16), writes
fixed 512-byte messages to raw sectors, and `sync()`s. Because the write is
physical it survives the reboot that follows a panic — unlike the `sec_debug`
kmsg ring buffer, which this SoC zeroes on every boot. That is exactly what
made it useful: it was the only channel that survived a crash.

It is also why it must never ship. The sectors it writes are `1500000 + slot`
and `1500010 + slot` — roughly 768 MB into the userdata partition, inside the
region where a Droidian `rootfs.img` lives. Every boot of a kernel carrying
this patch scribbles two 512-byte blocks into that partition.

**It was still present, uncommitted, in the working kernel tree on
2026-08-31**, long after it had served its purpose, so every boot image built
in that window carries it. It was removed when this repository was created.
Anyone still running an older locally-built image should rebuild.

It is kept here because the *technique* is worth having. If this device ever
stops booting again in a way that produces no output at all, this is the
instrument that found the answer last time. Read it, understand the sector
arithmetic, and point it at a scratch region before using it again.
