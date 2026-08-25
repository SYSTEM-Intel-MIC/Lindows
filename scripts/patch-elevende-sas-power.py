#!/usr/bin/env python3
"""Route ElevenDE SAS footer power actions through Lindows' fixed bridge."""
from __future__ import annotations

import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-sas-power.py PATH/TO/saswindow.cpp")

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = '''    connect(sleep, &QAction::triggered, this, [this] {
        hideSas();
        runSystem(QStringLiteral("systemctl"), {QStringLiteral("suspend")});
    });
    connect(shutdown, &QAction::triggered, this, [this] {
        hideSas();
        runSystem(QStringLiteral("systemctl"), {QStringLiteral("poweroff")});
    });
    connect(reboot, &QAction::triggered, this, [this] {
        hideSas();
        runSystem(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
    });
'''
new = '''    // Start and SAS must use the same fixed-function polkit bridge.  Direct
    // systemctl calls from a normal SAS process are silently rejected by
    // logind/polkit on installed Lindows systems.
    connect(sleep, &QAction::triggered, this, [this] {
        hideSas();
        runSystem(QStringLiteral("/usr/local/bin/lindows-power-action"),
                  {QStringLiteral("suspend")});
    });
    connect(shutdown, &QAction::triggered, this, [this] {
        hideSas();
        runSystem(QStringLiteral("/usr/local/bin/lindows-power-action"),
                  {QStringLiteral("poweroff")});
    });
    connect(reboot, &QAction::triggered, this, [this] {
        hideSas();
        runSystem(QStringLiteral("/usr/local/bin/lindows-power-action"),
                  {QStringLiteral("reboot")});
    });
'''
if new not in text:
    if old not in text:
        raise SystemExit("SAS footer power action marker was not found")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
print(f"patched SAS footer power actions in {path}")
