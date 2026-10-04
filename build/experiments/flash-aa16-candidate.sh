#!/bin/sh
# Controlled aa16 test: caller must have the owner beside the phone for recovery.
set -eu
P=/userdata/a50-aa16-test
test "$(id -u)" = 0
test "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$P/parent-boot-id")"
test "$(cat /sys/module/apparmor/parameters/enabled)" = Y
test "$(blockdev --getsize64 /dev/disk/by-partlabel/boot)" = 57671680
test "$(stat -c%s "$P/boot-aa16.img")" = 55984128
test "$(sha256sum "$P/boot-aa16.img" | cut -d ' ' -f1)" = 05a84a04cb162cb8ef0b193859cc8dbc1ad2c20d665f1b978de5e3c52a3531a5
test "$(sha256sum "$P/boot-aa13.img" | cut -d ' ' -f1)" = 8ae7ab85c08c13b0a7f454882dda3c52162a004a718de2be657d3cd75218fca6
test "$(head -c 55851008 /dev/disk/by-partlabel/boot | sha256sum | cut -d ' ' -f1)" = 8ae7ab85c08c13b0a7f454882dda3c52162a004a718de2be657d3cd75218fca6
sha256sum -c "$P/protected-partitions.sha256"
dd if="$P/boot-aa16.img" of=/dev/disk/by-partlabel/boot bs=4M conv=fsync
test "$(head -c 55984128 /dev/disk/by-partlabel/boot | sha256sum | cut -d ' ' -f1)" = 05a84a04cb162cb8ef0b193859cc8dbc1ad2c20d665f1b978de5e3c52a3531a5
sha256sum -c "$P/protected-partitions.sha256"
sync
echo 'Candidate written and read back; vendor/recovery hashes unchanged. Reboot separately.'
