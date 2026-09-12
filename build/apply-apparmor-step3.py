#!/usr/bin/env python3
"""AppArmor ladder, STEP 3a: select AppArmor at RUNTIME via the kernel cmdline.

Historical note: experiment 019's pre-console/layout diagnosis was disproven.
Persisted logs showed AppArmor initialized, then journald panicked in usercopy
because Samsung's empty LSM hooks lost their default return code. The full
profile now fixes that with security-hook-default.patch; aa4 booted normally.
This rung keeps the boot-tested step-1 config EXACTLY (SELinux stays the
Kconfig default) and flips the same runtime variable - chosen_lsm - via

    security=apparmor

appended to CONFIG_CMDLINE. CONFIG_CMDLINE_EXTEND=y, so this is appended
to whatever S-Boot passes, the same mechanism the rest of the cmdline
uses (S-Boot ignores the boot image's own cmdline field - kernel.md
risk 2).

Outcomes:
  boots + aa-status shows profiles -> the runtime selection works, the
      AppArmor is ON (this does not diagnose the earlier failure): verify
      media-hub stops crashing on openUri, the camera app's permission
      error clears, and the container still reaches sys.boot_completed=1
  dies pre-console like step 2 -> the selection LOGIC kills it at
      runtime; rung 3b is a source diff of security/ + Samsung early
      init against a working AppArmor-default 4.14

No earlycon here on purpose: the UART address is unverified and a wrong
earlycon can hang early boot all by itself - that would be a second
variable wearing a diagnostic's coat.
"""
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "kernel/src/build.sh"
ANCHOR = '} >> "$BUILD_CONFIG_DIR/$BUILD_DEVICE_TMP_CONFIG"'

CMDLINE = ("quiet androidboot.init_fatal_panic=true "
           "androidboot.init_fatal_reboot_target=recovery rcu_nocbs=0-3 "
           "noirqdebug nosoftlockup mce=ignore_ce cgroup_disable=pressure "
           "systemd.unified_cgroup_hierarchy=0 security=apparmor")

OPTS = [
    "CONFIG_SECURITY=y",
    "CONFIG_SECURITYFS=y",
    "CONFIG_SECURITY_NETWORK=y",
    "CONFIG_SECURITY_PATH=y",
    "CONFIG_SECURITY_APPARMOR=y",
    "CONFIG_SECURITY_APPARMOR_HASH=y",
    'CONFIG_CMDLINE="%s"' % CMDLINE,
]

s = open(PATH).read()
if "security=apparmor" in s:
    print("I: step3 cmdline already present")
    sys.exit(0)
if s.count(ANCHOR) != 1:
    sys.exit("E: anchor found %d times in %s" % (s.count(ANCHOR), PATH))

add = "".join('    echo \'%s\'\n' % o for o in OPTS)
open(PATH, "w").write(s.replace(ANCHOR, add + ANCHOR))
print("I: build.sh patched with step 3a (runtime security=apparmor via cmdline)")
