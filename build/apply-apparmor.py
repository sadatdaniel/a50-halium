#!/usr/bin/env python3
"""Build AppArmor in and make it the default LSM.

!!! THIS DOES NOT BOOT, AND IT IS NOT THE GPS FIX. Read this first. !!!

Boot-tested 2026-09-05: the resulting kernel does not boot at all - no ping,
no adb, no USB gadget enumerating, so it fails before userspace, earlier than
the Android container this change was expected to upset. Recovery needed TWRP.
The option set below changes four things at once; if you retry, enable
CONFIG_SECURITY_APPARMOR alone first and leave SELinux the default LSM.

The GPS reasoning below is also wrong. AppArmor is NOT required for location:
TrustStorePermissionManager checks
TRUST_STORE_PERMISSION_MANAGER_IS_RUNNING_UNDER_TESTING before it reads any
AppArmor profile, and a systemd drop-in setting that makes sessions work on
this exact kernel. Verified. See a50-ubuntu-touch
docs/experiments/009-gps-permissions.md. AppArmor is still wanted for app
confinement - just not for this.

The quoted error below was never observed either; the real one is
com.lomiri.location.Service.Error.CreatingSession, returned to the caller and
never logged.

Ubuntu Touch identifies applications through AppArmor. Without it
lomiri-location-service cannot establish which app is asking for a position
and refuses every session:

    Error creating session: Client lacks permissions to access the service
    with the given criteria

which is why GPS never gets a fix even though the GNSS HAL is fine - this
device registers android.hardware.gnss@1.0 through @2.1 and both gpsd and
sec_gnss_service run. It is also why app confinement has never worked here.

Measured before this change: `aa-status` says "apparmor not present",
/sys/module/apparmor does not exist, /sys/kernel/security is absent, and the
kernel image contains zero AppArmor strings (against 10 for selinux).

Option set is Halium's, from Halium/halium-boot check-kernel-config: AppArmor
enabled and made the default, SELinux still built but not the default and off
at boot. On 4.14 the major LSMs are mutually exclusive, so one of them has to
give, and Ubuntu Touch needs AppArmor. The Android container already runs
permissive on this port - CONFIG_CMDLINE carries androidboot.selinux=permissive
- so nothing there depends on SELinux enforcing.
"""
import sys

PATH = "kernel/src/build.sh"
ANCHOR = '} >> "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"'

OPTS = [
    # AppArmor itself
    "CONFIG_SECURITY=y",
    "CONFIG_SECURITYFS=y",
    "CONFIG_SECURITY_NETWORK=y",
    "CONFIG_SECURITY_PATH=y",
    "CONFIG_SECURITY_APPARMOR=y",
    "CONFIG_SECURITY_APPARMOR_HASH=y",
    "CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE=1",
    # make it the default LSM
    "CONFIG_DEFAULT_SECURITY_APPARMOR=y",
    'CONFIG_DEFAULT_SECURITY="apparmor"',
    # SELinux stays built for the Android container, but off at boot
    "CONFIG_SECURITY_SELINUX_BOOTPARAM_VALUE=0",
    "# CONFIG_DEFAULT_SECURITY_SELINUX is not set",
    "# CONFIG_DEFAULT_SECURITY_DAC is not set",
]

s = open(PATH).read()
if "CONFIG_SECURITY_APPARMOR=y" in s:
    print("I: AppArmor options already present")
    sys.exit(0)
if s.count(ANCHOR) != 1:
    sys.exit("E: anchor found %d times in %s" % (s.count(ANCHOR), PATH))

add = "".join('    echo \'%s\'\n' % o for o in OPTS)
open(PATH, "w").write(s.replace(ANCHOR, add + ANCHOR))
print("I: build.sh patched with %d AppArmor/LSM options" % len(OPTS))
