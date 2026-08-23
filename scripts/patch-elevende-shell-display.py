#!/usr/bin/env python3
"""Validate, rather than overwrite, ElevenDE's native X11 reflow support.

The locked ElevenDE 3.5.1 source already contains the Kali-tested shell_reflow()
path, root ConfigureNotify handling and a DisplayWidth/DisplayHeight polling
fallback.  Earlier Lindows builds injected a second, partial RandR handler and
used SIGUSR1 as an out-of-band layout trigger.  That duplicate path could drift
from the upstream shell and reintroduce stale geometry after a mode switch.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-shell-display.py PATH_TO_MAIN_C")

path = Path(sys.argv[1])
text = path.read_text()
required = {
    "shell reflow helper": "static void shell_reflow(",
    "root ConfigureNotify handler": "case ConfigureNotify:",
    "root geometry event subscription": "XSelectInput(dpy, root, PropertyChangeMask | StructureNotifyMask);",
    "live-width fallback": "DisplayWidth(dpy, scr)",
    "live-height fallback": "DisplayHeight(dpy, scr)",
}
missing = [label for label, marker in required.items() if marker not in text]
if missing:
    raise SystemExit(
        "locked ElevenDE shell lacks required resolution-reflow support: "
        + ", ".join(missing)
    )
print(f"validated native ElevenDE display reflow in {path}")
