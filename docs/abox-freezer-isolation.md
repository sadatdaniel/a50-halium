# ABOX freezer isolation (session 20)

This is a diagnostic experiment, not a suspend/resume fix. Default builds are
unchanged. Add `--abox-freezer-isolation` to the full/ubports build invocation
to include the experimental patch. Use a fresh source volume. The build
manifest and source sentinel record the option.

The root-only `freezer_skip_pm` module parameter defaults off. When enabled,
ABOX PREPARE refuses every PM test level except freezer. At freezer level it
skips ABOX PREPARE and its matching POST callback, preserving other notifiers
and the task freezer. The pairing survives a parameter change between calls.
The diagnostic patch intentionally uses the pinned kernel's internal power.h
for its exact test enum; it is not a proposed upstream interface.

This does not prevent independent ABOX runtime PM. A test is only informative
if the captured log confirms that ABOX did not power-cycle. Do not infer that
from the parameter alone. Never use this mode for real suspend or a daily build.

Evidence: aa6 returns from freezer, then freezes. Its final captured sequence
ends after ABOX firmware reload and restore; a Wi-Fi scan also starts during
restore. Previous experiment 018 failures implicate several possible paths.
ABOX is a lead, not established causation. This experiment changes only its
PM notifier behavior when explicitly enabled; AppArmor and usercopy stay on.

The separate abox-qos-log-initialized.patch fixes a confirmed uninitialized
log argument. It is not included in this build, keeping the isolation delta
focused. The huge req value appears before suspend too and is not evidence
of an actual enormous QoS update.

Upstream comparison found commit
5e0f4b78db1043d1eff0a4f45ae8912fe9c4e793 in android.googlesource.com/kernel/exynos,
which balances a runtime PM reference on suspend failure. The omission exists
here, but aa6 logged successful PREPARE, so that error-path fix does not explain
this capture and has not been bundled into the isolation experiment.

Validation so far: patch applies to preserved aa6 source; build script syntax
passes; extracted patched notifier compiled with mocked PM operations verifies
non-freezer refusal, PREPARE/POST pairing, and unchanged default behavior.
These tests do not validate hardware, concurrency, or a complete kernel build.
Full build and controlled device test pending. Keep aa1 automatic restoration
and image-sized read-back verification before any experimental boot.
