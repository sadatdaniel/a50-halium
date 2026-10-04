#!/sbin/sh
# Recovery fallback for the controlled aa16 test; does not touch vendor or data.
set -eu
P=/data/a50-aa16-test
test "$(id -u)" = 0
test "$(sha256sum "$P/boot-aa13.img" | cut -d ' ' -f1)" = 8ae7ab85c08c13b0a7f454882dda3c52162a004a718de2be657d3cd75218fca6
B=/dev/block/by-name/boot
test -b "$B"
test "$(readlink -f "$B")" = /dev/block/sda14
test "$(blockdev --getsize64 "$B")" = 57671680
test "$(sha256sum /dev/block/by-name/vendor | cut -d ' ' -f1)" = 48f5e9bfb9ef2dfd032ec7c92986ac1c8886abe7d658430b57ccacb5e3cffe3b
test "$(sha256sum /dev/block/by-name/recovery | cut -d ' ' -f1)" = 8535a9d9193243412fcefc0e6f1ba585d60e1533e65069867444a49d0287e51f
dd if="$P/boot-aa13.img" of="$B" bs=1048576
sync
test "$(head -c 55851008 "$B" | sha256sum | cut -d ' ' -f1)" = 8ae7ab85c08c13b0a7f454882dda3c52162a004a718de2be657d3cd75218fca6
test "$(sha256sum /dev/block/by-name/vendor | cut -d ' ' -f1)" = 48f5e9bfb9ef2dfd032ec7c92986ac1c8886abe7d658430b57ccacb5e3cffe3b
test "$(sha256sum /dev/block/by-name/recovery | cut -d ' ' -f1)" = 8535a9d9193243412fcefc0e6f1ba585d60e1533e65069867444a49d0287e51f
echo 'Working aa13 boot restored and verified. Reboot from recovery.'
