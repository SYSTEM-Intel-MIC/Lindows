#!/usr/bin/env python3
"""Patch only the disposable ElevenDE build copy for Lindows menu policy."""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-lindows-menu.py PATH_TO_MAIN_C")
path = Path(sys.argv[1])
text = path.read_text()

old_locale = '''        if (!nm[0] && zh[0]) snprintf(nm, sizeof nm, "%s", zh);
        if (!nm[0]) continue;
'''
new_locale = '''        size_t zhl = strlen(zh);
        while (zhl && (zh[zhl-1] == '\\n' || zh[zhl-1] == '\\r')) zh[--zhl] = 0;
        /* Lindows is zh_CN-first: use the desktop file's Chinese display
         * name when present, while retaining Name= as the fallback for other
         * locales. */
        const char *menu_lang = getenv("LANG");
        if (zh[0] && menu_lang && !strncmp(menu_lang, "zh", 2))
            snprintf(nm, sizeof nm, "%s", zh);
        else if (!nm[0] && zh[0])
            snprintf(nm, sizeof nm, "%s", zh);
        if (!nm[0]) continue;
'''
if new_locale not in text:
    if old_locale not in text:
        raise SystemExit("Lindows menu locale marker not found")
    text = text.replace(old_locale, new_locale, 1)

old_filter = '''        if (!ex[0]) continue;
        App *a = &apps[napps];
'''
new_filter = '''        if (!ex[0]) continue;
        /* Keep power and session commands in ElevenDE's dedicated Start/SAS
         * controls, never as duplicate unsafe entries under All apps. */
        if (ci_strstr(ex, "systemctl poweroff") || ci_strstr(ex, "systemctl reboot") ||
            ci_strstr(ex, "systemctl suspend") || ci_strstr(ex, "loginctl terminate-session") ||
            ci_strstr(ex, "loginctl lock-session") || ci_strstr(ex, "gnome-session-quit"))
            continue;
        App *a = &apps[napps];
'''
if new_filter not in text:
    if old_filter not in text:
        raise SystemExit("Lindows menu command-filter marker not found")
    text = text.replace(old_filter, new_filter, 1)

old_dedupe = '''    /* dedupe by exec (keep first occurrence) */
    for (int i = 0; i < napps; i++)
        for (int j = i + 1; j < napps; j++)
            if (!strcmp(apps[i].exec, apps[j].exec)) {
                memmove(&apps[j], &apps[j + 1],
                        (size_t)(napps - j - 1) * sizeof(App));
                napps--;
                j--;
            }
    app_dirs_watch_snapshot();
'''
new_dedupe = '''    /* XDG directories are scanned from user/local to system. Keep the first
     * item by desktop ID as well as by Exec so Lindows-owned launchers replace
     * upstream entries even when the adapter changes their command line. */
    for (int i = 0; i < napps; i++)
        for (int j = i + 1; j < napps; j++)
            if (!strcmp(apps[i].exec, apps[j].exec) ||
                !strcmp(apps[i].desktop_id, apps[j].desktop_id)) {
                memmove(&apps[j], &apps[j + 1],
                        (size_t)(napps - j - 1) * sizeof(App));
                napps--;
                j--;
            }
    app_dirs_watch_snapshot();
'''
if new_dedupe not in text:
    if old_dedupe not in text:
        raise SystemExit("Lindows menu dedupe marker not found")
    text = text.replace(old_dedupe, new_dedupe, 1)

path.write_text(text)
print(f"patched Lindows menu policy in {path}")
