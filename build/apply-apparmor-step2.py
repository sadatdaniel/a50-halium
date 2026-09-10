#!/usr/bin/env python3
"""AppArmor ladder, STEP 2: step 1 + AppArmor as the DEFAULT LSM.

Second rung of the plan written into apply-apparmor.py's warning and
experiment 008's appendix, after the 2026-09-05 four-variables-at-once
attempt died before USB enumeration:

  step 1  CONFIG_SECURITY_APPARMOR=y ONLY, default LSM untouched
  step 2  step 1 + CONFIG_DEFAULT_SECURITY_APPARMOR=y            <- this
  step 3  step 2 + SELinux bootparam changes (only if 2 misbehaves)

Only ONE variable moves relative to a boot-tested step 1: the default LSM
switch. On 4.14 the major LSMs are mutually exclusive; with this config
AppArmor is the active LSM and SELinux stays compiled in but is not
selected at boot. CONFIG_SECURITY_SELINUX_BOOTPARAM_VALUE is deliberately
NOT touched here - that is rung 3, and the Android container already runs
permissive via CONFIG_CMDLINE (androidboot.selinux=permissive).

IF THIS DOES NOT BOOT (the 2026-09-05 failure mode): no ping, no adb, no
USB gadget on the host - failure is in LSM init or Samsung code that
assumes SELinux. Recovery needs TWRP (Volume Up + Power from off).
Capture the evidence: /proc/last_kmsg after a forced reboot from TWRP.

VERIFY AFTER BUILD (container .config, NOT /proc/config.gz - stale IKCONFIG):
  CONFIG_SECURITY_APPARMOR=y
  CONFIG_DEFAULT_SECURITY_APPARMOR=y
  CONFIG_DEFAULT_SECURITY="apparmor"
  CONFIG_SECURITY_SELINUX=y                    (still built, not default)

VERIFY AFTER FLASH:
  - phone boots to UI, USB RNDIS comes up
  - /sys/module/apparmor exists; aa-status lists profiles
  - the container reaches RUNNING and sys.boot_completed=1
  - media-hub-server stops crashing on openUri (the apparmor Context
    path is what kills it today - see a50-ubuntu-touch experiment 018)
"""
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "kernel/src/build.sh"
ANCHOR = '} >> "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"'

OPTS = [
    "CONFIG_SECURITY=y",
    "CONFIG_SECURITYFS=y",
    "CONFIG_SECURITY_NETWORK=y",
    "CONFIG_SECURITY_PATH=y",
    "CONFIG_SECURITY_APPARMOR=y",
    "CONFIG_SECURITY_APPARMOR_HASH=y",
    "CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE=1",
    "CONFIG_DEFAULT_SECURITY_APPARMOR=y",
    'CONFIG_DEFAULT_SECURITY="apparmor"',
]

s = open(PATH).read()
if "CONFIG_SECURITY_APPARMOR=y" in s:
    print("I: AppArmor options already present")
    sys.exit(0)
if s.count(ANCHOR) != 1:
    sys.exit("E: anchor found %d times in %s" % (s.count(ANCHOR), PATH))

add = "".join('    echo \'%s\'\n' % o for o in OPTS)
open(PATH, "w").write(s.replace(ANCHOR, add + ANCHOR))
print("I: build.sh patched with %d options (step 2: AppArmor default LSM)" % len(OPTS))
