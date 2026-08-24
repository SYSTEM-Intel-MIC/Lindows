#!/usr/bin/env python3
"""Inject Lindows component icon aliases into ElevenDE's application resolver."""
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) == 2 else None
if path is None or not path.is_file():
    raise SystemExit("usage: patch-elevende-lindows-component-icons.py PATH/TO/shell/main.c")

entries = (
    ("linux-pcmanager", "linux-pcmanager"),
    ("linux-regedit", "linux-regedit"),
    ("lindows-bsod-demo", "lindows-bsod"),
    ("lindows-bsod", "lindows-bsod"),
    ("devmgr", "lindows-device-manager"),
    ("lindows-store", "lindows-store"),
    ("linux-store", "lindows-store"),
    ("copilot-for-linux", "copilot-for-linux"),
    ("peazip", "peazip"),
    ("lindows-activation-watermark", "lindows-activation-watermark"),
    ("lindows-troubleshooting", "lindows-troubleshooting"),
    ("lindows-uac-preview", "lindows-uac-preview"),
    ("uac_ui", "lindows-uac-preview"),
    ("lindows-defender", "lindows-defender"),
    ("lindows-sticky-keys", "lindows-sticky-keys"),
    ("lindows-widgets", "lindows-widgets"),
    ("lindows-windowshit", "lindows-windowshit"),
    ("winsat", "lindows-winsat"),
    ("lindows-update-preview", "lindows-update-preview"),
    ("windows_update_in_linux", "lindows-update-preview"),
    ("winver", "lindows-winver"),
    ("feedbackhub", "feedbackhub"),
)
marker = '        { "", "" }\n'
text = path.read_text(encoding="utf-8")
if '/* LINDOWS-COMPONENT-ICON-MAP */' in text:
    raise SystemExit("Lindows component icon map is already present")
if marker not in text:
    raise SystemExit("ElevenDE app icon table marker was not found")
block = '        /* LINDOWS-COMPONENT-ICON-MAP */\n' + ''.join(
    f'        {{ "{window_class}", "{icon}" }},\n' for window_class, icon in entries
)
path.write_text(text.replace(marker, block + marker, 1), encoding="utf-8")
print(f"added {len(entries)} Lindows component icon resolver aliases")
