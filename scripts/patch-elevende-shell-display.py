#!/usr/bin/env python3
"""Patch the disposable ElevenDE build copy for reliable RandR reflow.

The upstream shell has a ConfigureNotify path and a periodic fallback, but its
fallback uses DisplayWidth/DisplayHeight.  On the Lindows Xorg/Openbox path
those values can remain cached after xrandr changes the root geometry, leaving
the old desktop and taskbar size painted over a larger gray root window.
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
}
missing = [label for label, marker in required.items() if marker not in text]
if missing:
    raise SystemExit("locked ElevenDE shell lacks required display support: " + ", ".join(missing))

old = '''        /* A few Xvfb/driver combinations update the root geometry without
           delivering ConfigureNotify. Poll the live screen size as a fallback
           so the DE never remains laid out for the old resolution. */
        const int live_w = DisplayWidth(dpy, scr);
        const int live_h = DisplayHeight(dpy, scr);
        if (live_w != scr_w || live_h != scr_h) {
            shell_reflow(live_w, live_h);
            dirty = 1;
            act_changed = 1;
        }
'''
new = '''        /* Some Xorg/RandR combinations update the root window before the
           cached Screen object. Query root geometry directly so every
           screen-sized ElevenDE surface immediately follows xrandr. */
        XWindowAttributes root_attr;
        if (XGetWindowAttributes(dpy, root, &root_attr) &&
            (root_attr.width != scr_w || root_attr.height != scr_h)) {
            shell_reflow(root_attr.width, root_attr.height);
            dirty = 1;
            act_changed = 1;
        }
'''
if new not in text:
    if old not in text:
        raise SystemExit("ElevenDE display polling marker not found")
    text = text.replace(old, new, 1)
path.write_text(text)
print(f"patched root-geometry display reflow in {path}")
