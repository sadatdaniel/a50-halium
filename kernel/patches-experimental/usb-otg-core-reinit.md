# aa10 USB core restoration candidate

Status: experimental, compiling; no phone or suspend validation yet.

The aa9 diagnostic PM ladder passed, but one real sleep returned after 0.011 s
and USB endpoint commands timed out (-110). A software gadget reconnect failed;
a physical cable cycle restored USB. aa10 reproduces the core exit/init part of
that recovery before starting the previously active OTG peripheral endpoints.

Enable with `--usb-otg-sleep-fix --usb-otg-core-reinit`. The second flag requires
the first and has its own source-cache profile and manifest field. Both are
opt-in. Use a fresh source volume. AppArmor ubports and the watchdog freezer fix
remain enabled in the candidate; no security configuration is weakened.

Core exit drops the old PHY references before core init acquires replacements.
The role mutex remains held, but the IRQ spinlock is dropped for sleeping PHY
operations. Binding/VBUS state is checked again before endpoint restart. Errors
propagate through the existing balanced runtime-PM path. Vendor core-init error
unwind is not redesigned by this experiment; hardware recovery after an init
failure is still unproven.

Validation: `build/tests/test_usb_core_reinit.py` applies the actual patches to
an aa8 source baseline, extracts and compiles the actual sleep helpers, then
checks repeated cycles, lock/ref balance, inactive/host/unplug cases, unbinding
while initialization sleeps, and injected errors. PHY operations are mocked;
these checks do not establish register restoration or hardware sleep success.
Shell syntax and patch whitespace checks pass.

Build: full profile, pinned firmware/compiler recipe, `--apparmor ubports
--watchdog-freezer-fix --usb-otg-sleep-fix --usb-otg-core-reinit`.
Before a real sleep test, boot with the aa1 fallback guard, confirm AppArmor and
basic phone health, repeat diagnostic stages, then inspect actual sleep time,
failed_resume counters, USB, Wi-Fi, display/touch and delayed stability.