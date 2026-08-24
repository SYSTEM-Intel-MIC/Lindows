#!/usr/bin/env python3
"""Patch the vendored ElevenDE copy used by Lindows only.

ElevenDE's desktop intentionally opens ordinary files through xdg-open. A
.desktop file is therefore treated as text unless the shell explicitly parses
its Exec field. Keep upstream untouched and add that behavior to the Lindows
build copy so desktop application launchers behave like Windows shortcuts.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-desktop-launcher.py PATH_TO_MAIN_C")

path = Path(sys.argv[1])
text = path.read_text()
old = '''    } else {
        /* files go to the DEFAULT application via xdg-open (MIME based).
         * The old "explorer.exe || xdg-open" never reached xdg-open because
         * explorer.exe happily "opens" any path -- which is why archives
         * and documents popped up in the file manager. */
        snprintf(cmd, sizeof cmd, "xdg-open '%s' || explorer.exe '%s'",
                 path, path);
    }
'''
new = '''    } else if (strstr(path, ".desktop") && access(path, R_OK) == 0) {
        /* ElevenDE desktop application shortcuts must execute Exec= directly.
         * Ordinary files continue to use the user's MIME association below. */
        FILE *df = fopen(path, "r");
        char line[1024];
        cmd[0] = 0;
        if (df) {
            while (fgets(line, sizeof line, df)) {
                if (!strncmp(line, "Exec=", 5)) {
                    snprintf(cmd, sizeof cmd, "%s", line + 5);
                    cmd[strcspn(cmd, "\\r\\n")] = 0;
                    break;
                }
            }
            fclose(df);
        }
        if (!cmd[0]) {
            snprintf(cmd, sizeof cmd, "xdg-open '%s' || explorer.exe '%s'",
                     path, path);
        }
    } else {
        /* files go to the DEFAULT application via xdg-open (MIME based). */
        snprintf(cmd, sizeof cmd, "xdg-open '%s' || explorer.exe '%s'",
                 path, path);
    }
'''
if old not in text:
    raise SystemExit("ElevenDE open_path block was not found; source layout changed")
text = text.replace(old, new, 1)
old_label = '''            snprintf(ic[nic].label, sizeof ic[nic].label, "%s", de->d_name);
            snprintf(ic[nic].path, sizeof ic[nic].path, "%s/%s", dir, de->d_name);
'''
new_label = '''            size_t label_len = strlen(de->d_name);
            if (label_len > 8 && !strcmp(de->d_name + label_len - 8, ".desktop"))
                label_len -= 8;
            snprintf(ic[nic].label, sizeof ic[nic].label, "%.*s",
                     (int)label_len, de->d_name);
            snprintf(ic[nic].path, sizeof ic[nic].path, "%s/%s", dir, de->d_name);
'''
if old_label not in text:
    raise SystemExit("ElevenDE desktop label block was not found; source layout changed")
text = text.replace(old_label, new_label, 1)
old_icon = '        const char *nm = ic[i].is_dir ? "folder" : file_icon_name(ic[i].label);\n        int kind = ic[i].is_dir ? VI_FOLDER : VI_FILE;\n'
new_icon = '''        const char *nm = ic[i].is_dir ? "folder" : file_icon_name(ic[i].label);
        int kind = ic[i].is_dir ? VI_FOLDER : VI_FILE;
        /* ElevenDE enumerates ~/Desktop as ordinary files.  Lindows therefore
         * maps its known launchers here, at the same layer as Install Lindows,
         * instead of relying on the .desktop Icon= field. */
        if (strstr(ic[i].path, "/Install Lindows.desktop"))
            nm = "lindows-installer";
        else if (strstr(ic[i].path, "/注册表编辑器.desktop"))
            nm = "linux-regedit";
        else if (strstr(ic[i].path, "/Microsoft Edge.desktop"))
            nm = "microsoft-edge";
        else if (strstr(ic[i].path, "/终端.desktop"))
            nm = "lindows-windowshit";
'''
if old_icon not in text:
    raise SystemExit("ElevenDE desktop icon block was not found; source layout changed")
path.write_text(text.replace(old_icon, new_icon, 1))
print(f"patched {path}")
