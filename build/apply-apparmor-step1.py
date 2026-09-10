#!/usr/bin/env python3
"""AppArmor ladder, STEP 1: compile AppArmor in, SELinux stays the default LSM.

This is the first rung of the plan written into apply-apparmor.py's warning
and experiment 008's appendix after the 2026-09-05 four-variables-at-once
attempt died before USB enumeration:

  step 1  CONFIG_SECURITY_APPARMOR=y ONLY, default LSM untouched        <- this
  step 2  step 1 + CONFIG_DEFAULT_SECURITY_APPARMOR=y
  step 3  step 2 + SELinux bootparam changes

Step 1 is a behavioural probe, not a feature: on 4.14 the major LSMs are
mutually exclusive, so with SELinux still the default, AppArmor is compiled
but INACTIVE. The point is to prove the AppArmor code itself boots on this
kernel - if this boots and step 2 does not, the LSM-default switch is the
culprit and the investigation narrows to that.

VERIFY AFTER BUILD (in the container's .config, not /proc/config.gz - the
IKCONFIG blob on the device is stale):
  CONFIG_SECURITY_APPARMOR=y
  CONFIG_DEFAULT_SECURITY="selinux"     (unchanged)
  CONFIG_SECURITY_SELINUX=y             (unchanged)

VERIFY AFTER FLASH:
  - the phone boots to UI, USB RNDIS comes up (the failure mode of the
    2026-09-05 attempt was: nothing enumerates, recovery needs TWRP)
  - /sys/module/apparmor does NOT appear (inactive, as designed)
  - aa-status still reports apparmor not enabled - expected at step 1
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
]

s = open(PATH).read()
if "CONFIG_SECURITY_APPARMOR=y" in s:
    print("I: AppArmor options already present")
    sys.exit(0)
if s.count(ANCHOR) != 1:
    sys.exit("E: anchor found %d times in %s" % (s.count(ANCHOR), PATH))

add = "".join('    echo \'%s\'\n' % o for o in OPTS)
open(PATH, "w").write(s.replace(ANCHOR, add + ANCHOR))
print("I: build.sh patched with %d AppArmor options (step 1: no LSM switch)" % len(OPTS))
