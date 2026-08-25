#!/usr/bin/env python3
"""Make ElevenDE's custom taskbar honor EWMH skip-taskbar state.

Qt marks Widgets panels and invisible edge strips as Tool windows, which publish
_NET_WM_STATE_SKIP_TASKBAR.  Openbox correctly exposes those windows in its
client list, but the custom Shell previously ignored the state and drew a
permanent blank application button beside Start.
"""
from __future__ import annotations

import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-taskbar-filter.py PATH/TO/shell/main.c")

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(f"ElevenDE Shell source not found: {path}")
text = path.read_text(encoding="utf-8")
if "/* LINDOWS-TASKBAR-SKIP-STATE */" in text:
    raise SystemExit("Lindows taskbar skip-state filter is already present")

old_atoms = '''        Atom wm_type_desktop = atom("_NET_WM_WINDOW_TYPE_DESKTOP");
        for (unsigned long i = 0; i < nitems && ntask < MAX_TASKS; i++) {
'''
new_atoms = '''        Atom wm_type_desktop = atom("_NET_WM_WINDOW_TYPE_DESKTOP");
        Atom wm_state_skip_taskbar = atom("_NET_WM_STATE_SKIP_TASKBAR");
        for (unsigned long i = 0; i < nitems && ntask < MAX_TASKS; i++) {
'''
if old_atoms not in text:
    raise SystemExit("ElevenDE taskbar window loop anchor was not found")
text = text.replace(old_atoms, new_atoms, 1)

old_insert = '''            if (tprop) XFree(tprop);
            tasks[ntask].win = ws[i];
'''
new_insert = '''            if (tprop) XFree(tprop);
            /* LINDOWS-TASKBAR-SKIP-STATE: honor the EWMH contract for Qt
               Tool/utility windows.  Widgets uses this for its permanent
               edge trigger and panel, which must never occupy an app button. */
            Atom stype = None;
            int sfmt = 0;
            unsigned long sn = 0, sa = 0;
            unsigned char *sprop = NULL;
            int skip_task = 0;
            if (XGetWindowProperty(dpy, ws[i], atom("_NET_WM_STATE"),
                                   0, 16, False, XA_ATOM, &stype, &sfmt,
                                   &sn, &sa, &sprop) == Success && sprop) {
                if (stype == XA_ATOM && sfmt == 32)
                    for (unsigned long si = 0; si < sn; si++)
                        if (((Atom *)sprop)[si] == wm_state_skip_taskbar) {
                            skip_task = 1;
                            break;
                        }
                XFree(sprop);
            }
            if (skip_task)
                continue;
            tasks[ntask].win = ws[i];
'''
if old_insert not in text:
    raise SystemExit("ElevenDE taskbar state insertion anchor was not found")
text = text.replace(old_insert, new_insert, 1)
path.write_text(text, encoding="utf-8")
print(f"patched EWMH skip-taskbar filtering in {path}")
