#!/usr/bin/env python3
"""Select AppArmor as the default LSM following the UBports 4.14 guide.

build-kernel.sh also applies the guide's two socket mediation patches for this
mode. Keep the older experiment rungs available to reproduce their images.
"""
import pathlib
import runpy

runpy.run_path(str(pathlib.Path(__file__).with_name("apply-apparmor-step2.py")),
               run_name="__main__")
