#!/usr/bin/env python3
"""Ensure the Lindows icon overlay is staged after ElevenDE regenerates icons."""
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) == 2 else None
if path is None or not path.is_file():
    raise SystemExit("usage: patch-elevende-icon-overlay-staging.py PATH/TO/build-deb.sh")

marker = '        python3 make_tray_black.py\n'
insertion = '''        python3 make_tray_black.py
        # LINDOWS-ICON-OVERLAY: keep component aliases after the upstream
        # SVG/ICO generation step has rebuilt assets/icons.
        if [ -d icons-lindows-overlay ]; then
            cp -a icons-lindows-overlay/. icons/
        fi
'''
text = path.read_text(encoding="utf-8")
if "LINDOWS-ICON-OVERLAY" in text:
    raise SystemExit("Lindows icon overlay staging patch is already present")
if marker not in text:
    raise SystemExit("ElevenDE icon-generation marker was not found")
path.write_text(text.replace(marker, insertion, 1), encoding="utf-8")
print("patched ElevenDE build-deb.sh to stage the Lindows icon overlay")
