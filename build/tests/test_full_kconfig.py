from pathlib import Path
import subprocess,tempfile,sys
helper=Path(__file__).resolve().parents[1]/'apply-full-kconfig.py'
with tempfile.TemporaryDirectory() as d:
    p=Path(d)/'build.sh'; p.write_text('} >> "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"\n')
    subprocess.run([sys.executable,str(helper),str(p),'sample.bin'],check=True)
    expected=p.read_bytes(); assert expected.count(b'echo "# CONFIG_RT_GROUP_SCHED is not set"')==1
    subprocess.run([sys.executable,str(helper),str(p),'sample.bin'],check=True)
    assert p.read_bytes()==expected
    p.write_text(p.read_text().replace('    echo "# CONFIG_RT_GROUP_SCHED is not set"\n',''))
    stale=subprocess.run([sys.executable,str(helper),str(p),'sample.bin'],capture_output=True,text=True)
    assert stale.returncode and 'Old full-profile configuration' in stale.stderr
print('PASS: native realtime config generation, byte-idempotence and stale full-profile rejection')
