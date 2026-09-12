# UBports AppArmor on 4.14

`build/build-kernel.sh --apparmor ubports` selects AppArmor by Kconfig and applies
the two socket mediation patches prescribed by the
[UBports guide](https://docs.ubports.com/en/latest/porting/configure_test_fix/Apparmor.html).
The existing experimental step1/step2/step3 modes remain available unchanged.

Upstream patches are preserved verbatim, including authorship:

- `apparmor-socket-mediation.patch`: [559e4f447556e1ea0b24b035965023b6fba8f2f8](https://github.com/kdrag0n/proton_zf6/commit/559e4f447556e1ea0b24b035965023b6fba8f2f8)
- `apparmor-unix-mediation.patch`: [f076c3083d908253d32d26b49d64faaf4f80b442](https://github.com/kdrag0n/proton_zf6/commit/f076c3083d908253d32d26b49d64faaf4f80b442)

Samsung's source lacks `security/apparmor/.gitignore`. Applying the first patch
excludes only that metadata file; all code hunks apply without adaptation.
Use a fresh source volume so earlier experiment images remain reproducible.

The full profile also carries `security-hook-default.patch`, which corrects
Samsung's empty LSM hook return and was boot-tested with AppArmor in aa4.
Socket mediation and Kconfig default selection in this mode still require a
separate build and device test. Loaded profiles alone do not establish complete
Ubuntu Touch app confinement; test app launches and keyboard vibration as the
guide describes before proceeding to camera/suspend tests.
