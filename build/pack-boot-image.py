#!/usr/bin/env python3
"""Repack an A50 boot image, replacing the kernel and/or the ramdisk.

Reuses the donor image's header verbatim and patches only kernel_size and
ramdisk_size (SESSION-HANDOFF.md section 6: S-Boot ignores the id digest).

  repack2.py <donor.img> <kernel|-> <ramdisk|-> <out.img>
"""
import struct, sys, hashlib

BOOT_PARTITION_BYTES = 57671680
donor, kpath, rpath, out = sys.argv[1:5]

d = open(donor, 'rb').read()
if d[:8] != b'ANDROID!':
    sys.exit("E: donor is not an Android boot image")
ks, ka, rs, ra, ss, sa, ta, ps, hv, osv = struct.unpack('<10I', d[8:48])
koff = ps
roff = koff + ((ks + ps - 1) // ps) * ps
soff = roff + ((rs + ps - 1) // ps) * ps

kernel  = d[koff:koff+ks] if kpath == '-' else open(kpath, 'rb').read()
ramdisk = d[roff:roff+rs] if rpath == '-' else open(rpath, 'rb').read()
second  = d[soff:soff+ss] if ss else b''

def pad(b):
    r = len(b) % ps
    return b + (b'\0' * (ps - r) if r else b'')

hdr = bytearray(d[:ps])
struct.pack_into('<I', hdr, 8,  len(kernel))    # kernel_size
struct.pack_into('<I', hdr, 16, len(ramdisk))   # ramdisk_size

img = bytes(hdr) + pad(kernel) + pad(ramdisk) + pad(second)
if len(img) > BOOT_PARTITION_BYTES:
    sys.exit(f"E: {len(img)} bytes exceeds the {BOOT_PARTITION_BYTES}-byte boot partition")
open(out, 'wb').write(img)

# Re-parse the written file rather than trusting the write.
v = open(out, 'rb').read()
vks, _, vrs = struct.unpack('<3I', v[8:20])
vkoff = ps
vroff = vkoff + ((vks + ps - 1) // ps) * ps
assert v[:8] == b'ANDROID!'
assert (vks, vrs) == (len(kernel), len(ramdisk))
assert v[vkoff:vkoff+vks] == kernel
assert v[vroff:vroff+vrs] == ramdisk
assert v[48:576] == d[48:576], "name/cmdline drifted"

print(f"donor          {donor}")
print(f"kernel_size    {ks} -> {vks}   sha256 {hashlib.sha256(kernel).hexdigest()}")
print(f"ramdisk_size   {rs} -> {vrs}   sha256 {hashlib.sha256(ramdisk).hexdigest()}")
print(f"out            {out}  {len(img)} bytes  ({BOOT_PARTITION_BYTES-len(img)} spare)")
print(f"out sha256     {hashlib.sha256(v).hexdigest()}")
