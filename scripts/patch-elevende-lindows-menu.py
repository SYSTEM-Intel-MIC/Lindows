#!/usr/bin/env python3
"""Patch only the disposable ElevenDE build copy for Lindows menu policy."""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-lindows-menu.py PATH_TO_MAIN_C")
path = Path(sys.argv[1])
text = path.read_text()

old_zh_parse = '''            } else if (!strncmp(p, "Name[", 5) && strncmp(p, "Name[en", 7) &&
                       !zh[0]) {
                char *eq = strchr(p, '=');
                if (eq) snprintf(zh, sizeof zh, "%s", eq + 1);
            } else if (!strncmp(p, "Exec=", 5) && !ex[0]) {
'''
new_zh_parse = '''            } else if ((!strncmp(p, "Name[zh_CN]=", 12) ||
                        !strncmp(p, "Name[zh]=", 9)) && !zh[0]) {
                char *eq = strchr(p, '=');
                if (eq) snprintf(zh, sizeof zh, "%s", eq + 1);
            } else if (!strncmp(p, "Exec=", 5) && !ex[0]) {
'''
if new_zh_parse not in text:
    if old_zh_parse not in text:
        raise SystemExit("Lindows menu zh_CN parse marker not found")
    text = text.replace(old_zh_parse, new_zh_parse, 1)

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
        if (ci_strstr(ex, "lindows-installer") || ci_strstr(ex, "calamares") ||
            ci_strstr(ex, "install-system") || ci_strstr(ex, "debian-installer") ||
            ci_strstr(de->d_name, "lindows-installer") ||
            ci_strstr(de->d_name, "install-system") || ci_strstr(de->d_name, "calamares") ||
            ci_strstr(de->d_name, "debian-installer") ||
            !strcmp(nm, "安装 Lindows") || !strcmp(nm, "安装系统") ||
            ci_strstr(nm, "install lindows") || ci_strstr(nm, "install system") ||
            ci_strstr(ex, "systemctl poweroff") || ci_strstr(ex, "systemctl reboot") ||
            ci_strstr(ex, "systemctl suspend") || ci_strstr(ex, "loginctl terminate-session") ||
            ci_strstr(ex, "loginctl lock-session") || ci_strstr(ex, "gnome-session-quit") ||
            ci_strstr(ex, "lxqt-leave") || ci_strstr(ex, "xfce4-session-logout") ||
            ci_strstr(ex, "mate-session-save") || ci_strstr(ex, "openbox --exit") ||
            ci_strstr(ex, "lindows-power-action") || ci_strstr(ex, "shutdown") ||
            ci_strstr(ex, "poweroff") || ci_strstr(ex, "reboot") ||
            ci_strstr(ex, "suspend") || ci_strstr(ex, "logout") ||
            ci_strstr(ex, "lockscreen") || ci_strstr(de->d_name, "shutdown") ||
            ci_strstr(de->d_name, "restart") || ci_strstr(de->d_name, "reboot") ||
            ci_strstr(de->d_name, "logout") || ci_strstr(de->d_name, "logoff") ||
            ci_strstr(de->d_name, "lockscreen") || ci_strstr(de->d_name, "lxqt-leave") ||
            ci_strstr(de->d_name, "lxqt-shutdown") || ci_strstr(de->d_name, "lxqt-reboot") ||
            ci_strstr(de->d_name, "lxqt-suspend") || ci_strstr(de->d_name, "lxqt-lock") ||
            !strcmp(nm, "注销") ||
            !strcmp(nm, "关机") || !strcmp(nm, "重启") || !strcmp(nm, "重新启动") ||
            !strcmp(nm, "睡眠") || !strcmp(nm, "挂起") ||
            !strcmp(nm, "锁屏") || !strcmp(nm, "锁定") ||
            ci_strstr(nm, "shutdown") || ci_strstr(nm, "restart") ||
            ci_strstr(nm, "reboot") || ci_strstr(nm, "logout") ||
            ci_strstr(nm, "logoff") || ci_strstr(nm, "lockscreen"))
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
