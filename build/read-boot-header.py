import struct, sys, hashlib
p = sys.argv[1]
d = open(p,'rb').read()
assert d[:8]==b'ANDROID!', d[:8]
(ks,ka,rs,ra,ss,sa,ta,ps,hv,osv) = struct.unpack('<10I', d[8:48])
name = d[48:64].rstrip(b'\0').decode()
cmd  = d[64:576].rstrip(b'\0').decode()
print(f"file            {p}")
print(f"file_size       {len(d)}")
print(f"kernel_size     {ks}")
print(f"kernel_addr     0x{ka:08x}")
print(f"ramdisk_size    {rs}")
print(f"ramdisk_addr    0x{ra:08x}")
print(f"second_size     {ss}  second_addr 0x{sa:08x}")
print(f"tags_addr       0x{ta:08x}")
print(f"page_size       {ps}")
print(f"header_version  {hv}  os_version 0x{osv:08x}")
print(f"name            {name!r}")
print(f"cmdline         {cmd!r}")
kpages=(ks+ps-1)//ps
koff=ps
roff=koff+kpages*ps
print(f"kernel  sha256  {hashlib.sha256(d[koff:koff+ks]).hexdigest()}")
print(f"ramdisk sha256  {hashlib.sha256(d[roff:roff+rs]).hexdigest()}")
print(f"tail32 nonzero  {any(d[-32:])}")
