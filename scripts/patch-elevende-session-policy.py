#!/usr/bin/env python3
"""Apply the Lindows Live/installed ElevenDE login policy to a build copy."""
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) == 2 else None
if path is None or not path.is_file():
    raise SystemExit("usage: patch-elevende-session-policy.py PATH/TO/session/elevende-session")

old = '''# Login gate: show a Win11-style login screen with a password field before
# the desktop starts. Skips (or continues) if the lock cannot run.
if [ -x /usr/local/bin/elevende-lock ]; then
    echo "elevende-session: login gate"
    /usr/local/bin/elevende-lock --login || true
    echo "elevende-session: unlocked"
fi
'''
new = '''# LINDOWS-SESSION-POLICY: Live media enters its disposable user session
# directly. Installed systems retain ElevenDE's own Win11-style login gate;
# no external display-manager greeter is involved.
if [ "${LINDOWS_LIVE_SESSION:-0}" != "1" ] && [ ! -d /run/live ] && \\
        [ -x /usr/local/bin/elevende-lock ]; then
    echo "elevende-session: ElevenDE native login gate"
    /usr/local/bin/elevende-lock --login || true
    echo "elevende-session: unlocked"
else
    echo "elevende-session: Live session bypasses the login gate"
fi
'''
text = path.read_text(encoding="utf-8")
if "LINDOWS-SESSION-POLICY" in text:
    raise SystemExit("Lindows session policy is already present")
if old not in text:
    raise SystemExit("ElevenDE login gate marker was not found")
text = text.replace(old, new, 1)

old_shell = '''echo "elevende-session: starting shell"
/usr/local/bin/elevende-shell >/tmp/elevende-shell.log 2>&1 &
SHELL_PID=$!
'''
new_shell = '''echo "elevende-session: starting shell"
# The shell owns the desktop, taskbar and desktop icons.  It must remain a
# single long-lived process: restarting it from a tight loop during RandR
# transitions repeatedly recreates the taskbar and can leave temporary blank
# icon surfaces.  Exit diagnostics stay in /tmp/elevende-shell.log for the
# session-level recovery path rather than inducing a restart storm here.
/usr/local/bin/elevende-shell >/tmp/elevende-shell.log 2>&1 &
SHELL_PID=$!
'''
if old_shell not in text:
    raise SystemExit("ElevenDE shell startup marker was not found")
text = text.replace(old_shell, new_shell, 1)

old_openbox = '''echo "elevende-session: starting Openbox ($RC_FILE)"
openbox --config-file "$RC_FILE"
rc=$?

echo "elevende-session: Openbox exited ($rc), stopping session"
'''
new_openbox = '''# The display launcher distinguishes an intentional ElevenDE logout from an
# unexpected session failure.  Clear a stale marker before Openbox starts.  The
# SAS-only lindows-logout helper creates a new marker before it requests an
# Openbox exit; normal crashes must stay unmarked and reach systemd recovery.
LOGOUT_MARKER="$HOME/.cache/lindows-elevende-logout"
mkdir -p "$HOME/.cache"
rm -f "$LOGOUT_MARKER"
echo "elevende-session: starting Openbox ($RC_FILE)"
openbox --config-file "$RC_FILE"
rc=$?

echo "elevende-session: Openbox exited ($rc), stopping session"
'''
if old_openbox not in text:
    raise SystemExit("ElevenDE Openbox logout preparation marker was not found")
text = text.replace(old_openbox, new_openbox, 1)

old_dbus = '''export DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_PID
'''
new_dbus = '''export DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_PID

# loginctl power, suspend and reboot actions need a desktop polkit agent.  Do
# not bypass authorization with sudo or a policy relaxation; run the standard
# agent inside the user session so approved actions get a visible prompt.
POLKIT_PID=""
if command -v lxqt-policykit-agent >/dev/null 2>&1; then
    lxqt-policykit-agent >/tmp/elevende-polkit.log 2>&1 &
    POLKIT_PID=$!
fi
'''
if old_dbus not in text:
    raise SystemExit("ElevenDE D-Bus session marker was not found")
text = text.replace(old_dbus, new_dbus, 1)

old_cleanup = '''[ -n "${DBUS_PID:-}" ] && kill "$DBUS_PID" 2>/dev/null || true
exit $rc
'''
new_cleanup = '''[ -n "${POLKIT_PID:-}" ] && kill "$POLKIT_PID" 2>/dev/null || true
[ -n "${DBUS_PID:-}" ] && kill "$DBUS_PID" 2>/dev/null || true
exit $rc
'''
if old_cleanup not in text:
    raise SystemExit("ElevenDE session cleanup marker was not found")
text = text.replace(old_cleanup, new_cleanup, 1)

old_locale = '''export LANG=C.UTF-8
export LC_ALL=C.UTF-8
'''
new_locale = '''# Lindows is Chinese-first.  Keep desktop entry localization and application
# labels coherent with the image locale instead of forcing the C locale.
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh
'''
if old_locale not in text:
    raise SystemExit("ElevenDE session locale marker was not found")
text = text.replace(old_locale, new_locale, 1)
path.write_text(text, encoding="utf-8")
print("patched ElevenDE session for Live bypass, native login and zh_CN locale")
