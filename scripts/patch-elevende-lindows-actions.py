#!/usr/bin/env python3
"""Apply Lindows-only session/logout and power-action routing to build copies."""
from pathlib import Path
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: patch-elevende-lindows-actions.py MAIN_C SAS_CONFIG_JSON")
main = Path(sys.argv[1])
config = Path(sys.argv[2])
text = main.read_text()
old = '''            else if (i == 1) { launch_cmd("systemctl suspend");  menu_hide(); }
            else if (i == 2) { launch_cmd("systemctl poweroff"); menu_hide(); }
            else if (i == 3) { launch_cmd("systemctl reboot");   menu_hide(); }
'''
new = '''            else if (i == 1) { launch_cmd("lindows-power-action suspend");  menu_hide(); }
            else if (i == 2) { launch_cmd("lindows-power-action poweroff"); menu_hide(); }
            else if (i == 3) { launch_cmd("lindows-power-action reboot");   menu_hide(); }
'''
if new not in text:
    if old not in text:
        raise SystemExit("Lindows power-action marker not found")
    main.write_text(text.replace(old, new, 1))

cfg = config.read_text()
old_logout = '''        "注销": {
            "command": "loginctl",
            "args": ["terminate-session", "self"],
            "fallback": [
                { "command": "openbox", "args": ["--exit"] }
            ],
            "exitAfter": true
        },'''
new_logout = '''        "注销": {
            "command": "/usr/local/bin/lindows-logout",
            "args": [],
            "fallback": [],
            "exitAfter": true
        },'''
if new_logout not in cfg:
    if old_logout not in cfg:
        raise SystemExit("Lindows logout-action marker not found")
    config.write_text(cfg.replace(old_logout, new_logout, 1))
print("patched Lindows session/logout and power routing")
