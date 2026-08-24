#!/usr/bin/env bash
# Build audited Lindows 2.0 optional Windows-style components.
# This script never executes upstream install.sh files.  It runs only explicit
# source builds and stages independent Debian packages into the shared PKGS dir.
set -euo pipefail

ROOT="${ROOT:-/workspace}"
OUT="${OUT:-$ROOT/artifacts}"
PKGS="${PKGS:-$OUT/packages}"
WORK="${WORK:-$OUT/work}"
SOURCE_CACHE="${LINDOWS_SOURCE_CACHE:-$OUT/source-cache}"
SOURCE_LOCK="$ROOT/packages/sources.lock.tsv"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

source_locked() {
    local id="$1" dst="$2" row url rev license role cache
    row="$(awk -F '\t' -v id="$id" '$1 == id { print; exit }' "$SOURCE_LOCK")"
    [ -n "$row" ] || die "source lock has no entry for $id"
    IFS=$'\t' read -r _ url rev license role <<<"$row"
    cache="$SOURCE_CACHE/${id}-${rev}"
    if [ ! -d "$cache/.git" ]; then
        rm -rf "$cache"
        mkdir -p "$(dirname "$cache")"
        git clone --filter=blob:none "$url" "$cache"
    fi
    # The restored cache belongs to the GitHub runner UID, while this recipe
    # deliberately runs as root in its isolated container.
    git config --global --add safe.directory "$cache"
    if ! git -C "$cache" cat-file -e "${rev}^{commit}" 2>/dev/null; then
        git -C "$cache" fetch --filter=blob:none origin "$rev"
    fi
    git -C "$cache" checkout --detach "$rev" >/dev/null
    [ "$(git -C "$cache" rev-parse HEAD)" = "$rev" ] || die "unexpected revision for $id"
    rm -rf "$dst"
    mkdir -p "$dst"
    git -C "$cache" archive "$rev" | tar -x -C "$dst"
}

make_deb() {
    local name="$1" version="$2" depends="$3" stage="$4" description="$5"
    mkdir -p "$stage/DEBIAN"
    cat > "$stage/DEBIAN/control" <<CONTROL
Package: $name
Version: $version
Architecture: amd64
Maintainer: SYSTEM-Intel-MIC <opensource@system-intel-mic.invalid>
Depends: $depends
Section: utils
Priority: optional
Description: $description
 Lindows 2.0 bundled component built from a fixed upstream source revision.
CONTROL
    dpkg-deb --build --root-owner-group "$stage" "$PKGS/${name}_${version}_amd64.deb" >/dev/null
}

install_license() {
    local source="$1" stage="$2" package="$3"
    local license
    for license in LICENSE LICENSE.md License COPYING; do
        if [ -f "$source/$license" ]; then
            install -Dm644 "$source/$license" "$stage/usr/share/doc/$package/copyright"
            return 0
        fi
    done
    die "license file missing for $package"
}

install_desktop() {
    local stage="$1" file="$2" name="$3" exec="$4" icon="$5" categories="$6"
    install -Dm644 /dev/stdin "$stage/usr/share/applications/$file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$name
Name[zh_CN]=$name
Comment=Lindows 2.0 Windows-style system component
Exec=$exec
Icon=$icon
Terminal=false
Categories=$categories
DESKTOP
}

[ "$(id -u)" = 0 ] || die "this build must run as root inside the component build container"
command -v cargo >/dev/null 2>&1 || die "a modern Rust/Cargo toolchain is required (use rust:1.95-bookworm)"
command -v rustc >/dev/null 2>&1 || die "a modern Rust toolchain is required (use rust:1.95-bookworm)"
[ -f "$SOURCE_LOCK" ] || die "package source lock is missing: $SOURCE_LOCK"
mkdir -p "$PKGS" "$WORK" "$SOURCE_CACHE"
export DEBIAN_FRONTEND=noninteractive

log "installing extra-component build dependencies"
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl git build-essential cmake pkg-config gawk dpkg-dev \
    python3 python3-gi gir1.2-gtk-3.0 python3-tk \
    python3-pyqt5 python3-requests python3-pil python3-psutil python3-croniter \
    libconfig-dev libcairo2-dev libpango1.0-dev libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev \
    libpam0g-dev libgtk-4-dev libx11-dev libxi-dev libdrm-dev libfreetype-dev \
    libfontconfig1-dev libsystemd-dev libxcb-cursor0 libxcb-xinerama0

log "building Activate Lindows watermark"
SRC="$WORK/activate-linux"; source_locked activate-linux "$SRC"
python3 "$ROOT/scripts/patch-lindows-component-sources.py" activation "$SRC"
# Upstream calls its pkg-config dependency list PKGS; do not let the Lindows
# package-output environment variable overwrite that Makefile variable.
env -u PKGS make -C "$SRC"
STAGE="$WORK/pkg-lindows-activation-watermark"
install -Dm755 "$SRC/activate-linux" "$STAGE/usr/lib/lindows-activation-watermark/activate-linux"
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-activation-watermark" <<'SH'
#!/bin/sh
exec /usr/lib/lindows-activation-watermark/activate-linux "$@"
SH
install_desktop "$STAGE" "lindows-activation-watermark.desktop" "Activate Lindows" "lindows-activation-watermark" "dialog-information" "Utility;Settings;"
install_license "$SRC" "$STAGE" "lindows-activation-watermark"
make_deb "lindows-activation-watermark" "1.0.0+lindows2" "libc6, libcairo2, libconfig9, libx11-6, libxi6" "$STAGE" "Lindows activation watermark visual component"

if [ "${LINDOWS_SKIP_RUST_COMPONENTS:-0}" != "1" ]; then
log "building Lindows Control"
SRC="$WORK/lindows-control"; source_locked lindows-control "$SRC"
python3 "$ROOT/scripts/patch-lindows-component-sources.py" control "$SRC"
cargo build --manifest-path "$SRC/Cargo.toml" --release --locked
STAGE="$WORK/pkg-lindows-control"
install -Dm755 "$SRC/target/release/Lindows_Control" "$STAGE/usr/lib/lindows-control/lindows-control"
install -d "$STAGE/usr/lib/lindows-control"
cp -a "$SRC/images" "$SRC/lang" "$STAGE/usr/lib/lindows-control/"
[ -f "$SRC/src/STXIHEI.TTF" ] && install -Dm644 "$SRC/src/STXIHEI.TTF" "$STAGE/usr/lib/lindows-control/STXIHEI.TTF"
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-control" <<'SH'
#!/bin/sh
cd /usr/lib/lindows-control
exec ./lindows-control "$@"
SH
install_desktop "$STAGE" "lindows-control.desktop" "Control Panel" "lindows-control" "preferences-system" "Settings;System;"
install_license "$SRC" "$STAGE" "lindows-control"
make_deb "lindows-control" "1.1.1+lindows2" "libc6, libgl1, libx11-6, libxkbcommon0" "$STAGE" "Lindows Control Panel"
fi

log "packaging Lindows Troubleshooting through PyQt5 compatibility binding"
SRC="$WORK/lindows-troubleshooting"; source_locked lindows-troubleshooting "$SRC"
STAGE="$WORK/pkg-lindows-troubleshooting"
install -Dm644 "$SRC/main.py" "$STAGE/usr/lib/lindows-troubleshooting/main.py"
sed -i 's/from PySide6\.QtCore import QThread, Signal/from PyQt5.QtCore import QThread, pyqtSignal as Signal/; s/from PySide6\.QtWidgets import (/from PyQt5.QtWidgets import (/' "$STAGE/usr/lib/lindows-troubleshooting/main.py"
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-troubleshooting" <<'SH'
#!/bin/sh
exec python3 /usr/lib/lindows-troubleshooting/main.py "$@"
SH
install_desktop "$STAGE" "lindows-troubleshooting.desktop" "Troubleshooting" "lindows-troubleshooting" "dialog-information" "System;Settings;"
install_license "$SRC" "$STAGE" "lindows-troubleshooting"
make_deb "lindows-troubleshooting" "1.0.0+lindows2" "python3, python3-pyqt5" "$STAGE" "Lindows Windows-style troubleshooting helper"

log "building safe UAC preview UI without PAM integration"
SRC="$WORK/linux-uac"; source_locked linux-uac "$SRC"
# Upstream standalone mode auto-accepts after a timeout.  Lindows only ships
# this as a non-authorising preview, so timeout=0 means "wait for explicit
# cancel/close" rather than accepting anything automatically.
python3 - "$SRC/src/uac_ui.c" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
replacements = {
    'if (app.timeout_sec <= 0) app.timeout_sec = 30;':
        'if (app.timeout_sec < 0) app.timeout_sec = 30;',
    'Uint32 deadline = SDL_GetTicks() + (Uint32)(app.timeout_sec * 1000);':
        'Uint32 deadline = app.timeout_sec > 0 ? SDL_GetTicks() + (Uint32)(app.timeout_sec * 1000) : 0;',
    'int remain_ms = (int)(deadline - SDL_GetTicks());\n        if (remain_ms <= 0) decide(&app, UAC_MSG_ACCEPT, UAC_EXIT_ACCEPT);':
        'int remain_ms = app.timeout_sec > 0 ? (int)(deadline - SDL_GetTicks()) : -1;\n        if (app.timeout_sec > 0 && remain_ms <= 0) decide(&app, UAC_MSG_ACCEPT, UAC_EXIT_ACCEPT);',
    'theme.time_left = remain_ms > 0 ? (remain_ms + 999) / 1000 : 0;':
        'theme.time_left = remain_ms > 0 ? (remain_ms + 999) / 1000 : -1;',
}
for old, new in replacements.items():
    if old not in s:
        raise SystemExit(f'UAC preview safety patch marker not found: {old!r}')
    s = s.replace(old, new, 1)
p.write_text(s)
PY
make -C "$SRC" uac_ui
STAGE="$WORK/pkg-lindows-uac-preview"
install -Dm755 "$SRC/uac_ui" "$STAGE/usr/lib/lindows-uac-preview/uac_ui"
install -Dm755 /dev/stdin "$STAGE/usr/lib/lindows-uac-preview/preview.py" <<'PY'
#!/usr/bin/env python3
import getpass, tkinter as tk
root = tk.Tk(); root.title("用户账户控制"); root.geometry("560x330"); root.configure(bg="#ffffff"); root.resizable(False, False)
tk.Label(root, text="用户账户控制", font=("Sans", 22, "bold"), fg="#202020", bg="#ffffff").pack(anchor="w", padx=32, pady=(28, 8))
tk.Label(root, text="是否允许此应用对 Lindows 进行更改？", font=("Sans", 15), bg="#ffffff", fg="#202020").pack(anchor="w", padx=32)
tk.Label(root, text="Lindows 管理操作（安全预览，不会授权命令）\n当前用户：" + getpass.getuser(), font=("Sans", 12), bg="#ffffff", fg="#555555", justify="left").pack(anchor="w", padx=32, pady=20)
buttons=tk.Frame(root,bg="#ffffff"); buttons.pack(anchor="e", padx=32, pady=20)
tk.Button(buttons,text="否",command=root.destroy,bg="#e9edf2",fg="#202020",relief="flat",padx=22,pady=8).pack(side="left",padx=8)
tk.Button(buttons,text="是（预览）",command=root.destroy,bg="#0f6cbd",fg="white",relief="flat",padx=22,pady=8).pack(side="left")
root.mainloop()
PY
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-uac-preview" <<'SH'
#!/bin/sh
# Preview-only: no PAM module, sudo hook, auto-grant or command authorisation.
exec python3 /usr/lib/lindows-uac-preview/preview.py "$@"
SH
install_desktop "$STAGE" "lindows-uac-preview.desktop" "User Account Control Preview" "用户账户控制预览" "dialog-password" "Settings;Security;"
install_license "$SRC" "$STAGE" "lindows-uac-preview"
make_deb "lindows-uac-preview" "1.0.1+lindows3" "python3, python3-tk" "$STAGE" "Non-authorising Lindows UAC preview"

log "packaging Lindows Defender"
SRC="$WORK/linux-defender"; source_locked linux-defender "$SRC"
STAGE="$WORK/pkg-lindows-defender"
install -Dm644 "$SRC/Linux Defender.py" "$STAGE/usr/lib/lindows-defender/upstream-main.py"
# qfluentwidgets is not packaged by Debian Bookworm.  Keep the audited source
# for attribution but provide a PyQt-free Lindows status front end that always
# launches in the locked runtime rather than failing at import time.
install -Dm755 /dev/stdin "$STAGE/usr/lib/lindows-defender/main.py" <<'PY'
#!/usr/bin/env python3
import tkinter as tk
root = tk.Tk(); root.title("Lindows Defender"); root.geometry("860x540"); root.configure(bg="#ffffff")
tk.Label(root, text="Lindows Defender", font=("Sans", 26, "bold"), fg="#0f6cbd", bg="#ffffff").pack(anchor="w", padx=42, pady=(35, 8))
tk.Label(root, text="安全概览", font=("Sans", 16, "bold"), bg="#ffffff", fg="#202020").pack(anchor="w", padx=42, pady=(18, 4))
tk.Label(root, text="此版本提供本地安全状态预览。它不会扫描、删除文件或修改系统安全策略。", font=("Sans", 13), bg="#ffffff", fg="#444444").pack(anchor="w", padx=42)
box = tk.Label(root, text="状态：预览模式已就绪", font=("Sans", 16), fg="#107c10", bg="#f3fbf3", padx=24, pady=22, relief="solid", bd=1)
box.pack(fill="x", padx=42, pady=32)
tk.Button(root, text="关闭", command=root.destroy, bg="#0f6cbd", fg="white", relief="flat", padx=24, pady=8).pack(anchor="e", padx=42)
root.mainloop()
PY
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-defender" <<'SH'
#!/bin/sh
exec python3 /usr/lib/lindows-defender/main.py "$@"
SH
install_desktop "$STAGE" "lindows-defender.desktop" "Lindows Defender" "lindows-defender" "security-high" "System;Security;"
install_license "$SRC" "$STAGE" "lindows-defender"
make_deb "lindows-defender" "1.0.1+lindows3" "python3, python3-tk" "$STAGE" "Safe Lindows Defender status preview"

log "packaging Lindows Sticky Keys"
SRC="$WORK/linux-sticky-keys"; source_locked linux-sticky-keys "$SRC"
STAGE="$WORK/pkg-lindows-sticky-keys"
install -Dm644 "$SRC/Linux-Sticky-keys.py" "$STAGE/usr/lib/lindows-sticky-keys/upstream-main.py"
# Do not make a desktop tool grab /dev/input as root.  Use the X keyboard
# extension through setxkbmap so the preference is per-session and reversible.
install -Dm755 /dev/stdin "$STAGE/usr/lib/lindows-sticky-keys/main.py" <<'PY'
#!/usr/bin/env python3
import subprocess, tkinter as tk
root = tk.Tk(); root.title("粘滞键"); root.geometry("560x310"); root.configure(bg="#ffffff")
state = tk.BooleanVar(value=False)
def apply():
    subprocess.run(["setxkbmap", "-option", "stickykeys" if state.get() else ""], check=False)
    hint.config(text="已启用" if state.get() else "已关闭")
tk.Label(root, text="粘滞键", font=("Sans", 24, "bold"), bg="#ffffff", fg="#202020").pack(anchor="w", padx=34, pady=(30, 8))
tk.Label(root, text="让 Ctrl、Alt、Shift 和 Super 可逐次按下组合使用。", font=("Sans", 13), bg="#ffffff", fg="#505050").pack(anchor="w", padx=34)
tk.Checkbutton(root, text="启用粘滞键", variable=state, command=apply, font=("Sans", 15), bg="#ffffff", activebackground="#ffffff").pack(anchor="w", padx=34, pady=28)
hint=tk.Label(root, text="已关闭", font=("Sans", 12), bg="#ffffff", fg="#666666"); hint.pack(anchor="w", padx=34)
tk.Button(root, text="关闭", command=root.destroy, bg="#0f6cbd", fg="white", relief="flat", padx=22, pady=7).pack(anchor="e", padx=34, pady=24)
root.mainloop()
PY
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-sticky-keys" <<'SH'
#!/bin/sh
exec python3 /usr/lib/lindows-sticky-keys/main.py "$@"
SH
install_desktop "$STAGE" "lindows-sticky-keys.desktop" "Sticky Keys" "preferences-desktop-accessibility" "preferences-desktop-accessibility" "Settings;Accessibility;"
install_license "$SRC" "$STAGE" "lindows-sticky-keys"
make_deb "lindows-sticky-keys" "1.0.1+lindows3" "python3, python3-tk, x11-xkb-utils" "$STAGE" "Lindows Sticky Keys accessibility preferences"

log "packaging Task Scheduler through PyQt5 compatibility binding"
SRC="$WORK/taskschd4linux"; source_locked taskschd4linux "$SRC"
python3 "$ROOT/scripts/patch-lindows-component-sources.py" task-scheduler "$SRC"
STAGE="$WORK/pkg-lindows-task-scheduler"
install -d "$STAGE/usr/lib/lindows-task-scheduler"
cp -a "$SRC/ltask" "$STAGE/usr/lib/lindows-task-scheduler/"
install -Dm644 "$SRC/main.py" "$STAGE/usr/lib/lindows-task-scheduler/main.py"
# The Lindows source-copy patch supplies a single PyQt5 binding shim; do not
# apply broad text substitutions that can corrupt already-correct signal names.
install -Dm755 /dev/stdin "$STAGE/usr/bin/taskschd" <<'SH'
#!/bin/sh
cd /usr/lib/lindows-task-scheduler
exec python3 main.py "$@"
SH
install_desktop "$STAGE" "lindows-task-scheduler.desktop" "Task Scheduler" "taskschd" "appointment-new" "System;Utility;"
install_license "$SRC" "$STAGE" "lindows-task-scheduler"
make_deb "lindows-task-scheduler" "1.0.1+lindows3" "python3, python3-pyqt6, python3-croniter, policykit-1" "$STAGE" "Windows-style task scheduler for Lindows"

log "packaging Widgets"
SRC="$WORK/windows-widgets"; source_locked windows-widgets "$SRC"
python3 "$ROOT/scripts/patch-lindows-component-sources.py" widgets "$SRC"
STAGE="$WORK/pkg-lindows-widgets"
install -d "$STAGE/usr/lib/lindows-widgets"
cp -a "$SRC/widget_panel" "$STAGE/usr/lib/lindows-widgets/"
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-widgets" <<'SH'
#!/bin/sh
export PYTHONPATH=/usr/lib/lindows-widgets${PYTHONPATH:+:$PYTHONPATH}
exec python3 -m widget_panel.main "$@"
SH
install_desktop "$STAGE" "lindows-widgets.desktop" "Widgets" "lindows-widgets" "preferences-desktop-widget" "Utility;"
install_license "$SRC" "$STAGE" "lindows-widgets"
make_deb "lindows-widgets" "1.0.0+lindows2" "python3, python3-pyqt5, python3-requests, python3-pil" "$STAGE" "Windows-style desktop widgets for Lindows"

if [ "${LINDOWS_SKIP_RUST_COMPONENTS:-0}" != "1" ]; then
log "building namespaced Windows command compatibility tools"
SRC="$WORK/windowshit"; source_locked windowshit "$SRC"
cargo build --manifest-path "$SRC/Cargo.toml" --release --locked
STAGE="$WORK/pkg-lindows-windowshit"
install -d "$STAGE/usr/lib/lindows-windowshit/bin" "$STAGE/usr/bin"
for bin in ipconfig ping tracert pathping whoami hostname ver where tree findstr getmac type sort more clip tasklist taskkill systeminfo fc choice replace expand makecab shutdown robocopy; do
    if [ -x "$SRC/target/release/$bin" ]; then
        install -m755 "$SRC/target/release/$bin" "$STAGE/usr/lib/lindows-windowshit/bin/$bin"
        ln -s "../lib/lindows-windowshit/bin/$bin" "$STAGE/usr/bin/lindows-$bin"
    fi
done
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-windowshit" <<'SH'
#!/bin/sh
printf '%s\n' 'Lindows Windows-compatible commands are namespaced as lindows-ipconfig, lindows-tasklist, lindows-systeminfo and related commands.'
SH
install_desktop "$STAGE" "lindows-windowshit.desktop" "Windows Commands" "lindows-windowshit" "utilities-terminal" "System;Utility;"
install_license "$SRC" "$STAGE" "lindows-windowshit"
make_deb "lindows-windowshit" "0.1.1+lindows2" "libc6" "$STAGE" "Namespaced Windows command compatibility tools"
fi

log "packaging WinSAT"
SRC="$WORK/winsat"; source_locked winsat "$SRC"
STAGE="$WORK/pkg-lindows-winsat"
install -d "$STAGE/usr/lib/lindows-winsat"
cp -a "$SRC/src/pywinsat" "$STAGE/usr/lib/lindows-winsat/"
install -Dm755 /dev/stdin "$STAGE/usr/bin/winsat" <<'SH'
#!/bin/sh
export PYTHONPATH=/usr/lib/lindows-winsat${PYTHONPATH:+:$PYTHONPATH}
# Desktop launch has no arguments: open the upstream graphical WEI view.
# Explicit CLI arguments remain available for terminal users.
if [ "$#" -eq 0 ]; then
    exec python3 -m pywinsat gui --lang zh
fi
exec python3 -m pywinsat "$@"
SH
install_desktop "$STAGE" "lindows-winsat.desktop" "Windows Experience Index" "winsat" "applications-system" "System;Utility;"
install_license "$SRC" "$STAGE" "lindows-winsat"
make_deb "lindows-winsat" "1.0.1+lindows3" "python3, python3-tk" "$STAGE" "Windows Experience Index style benchmark tool"

log "building safe Windows Update preview"
SRC="$WORK/windows-update-preview"; source_locked windows-update-preview "$SRC"
cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$SRC/build" --parallel
STAGE="$WORK/pkg-lindows-update-preview"
install -Dm755 "$SRC/windows_update_in_linux" "$STAGE/usr/lib/lindows-update-preview/windows_update_in_linux"
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-update-preview" <<'SH'
#!/bin/sh
# Preserve the upstream direct TTY/DRM visual renderer. It is intentionally
# privileged because it takes an idle VT, but Lindows permanently disables its
# reboot branch so it always restores the graphical desktop after the preview.
exec pkexec /usr/lib/lindows-update-preview/windows_update_in_linux --no-reboot "$@"
SH
install_desktop "$STAGE" "lindows-update-preview.desktop" "Windows Update Preview" "Windows 更新预览" "software-update-available" "System;Settings;"
install_license "$SRC" "$STAGE" "lindows-update-preview"
make_deb "lindows-update-preview" "1.0.2+lindows4" "libc6, libdrm2, libfreetype6, libfontconfig1, libsystemd0, policykit-1" "$STAGE" "Safe direct-TTY Lindows Windows Update preview"

log "building About Lindows (winver)"
SRC="$WORK/linux-winver"; source_locked linux-winver "$SRC"
make -C "$SRC"
STAGE="$WORK/pkg-lindows-winver"
install -Dm755 "$SRC/winver" "$STAGE/usr/lib/lindows-winver/winver"
install -Dm755 /dev/stdin "$STAGE/usr/bin/winver" <<'SH'
#!/bin/sh
exec /usr/lib/lindows-winver/winver "$@"
SH
install_desktop "$STAGE" "lindows-winver.desktop" "About Lindows" "winver" "help-about" "System;Settings;"
install_license "$SRC" "$STAGE" "lindows-winver"
make_deb "lindows-winver" "1.0.0+lindows2" "libc6, libgtk-4-1" "$STAGE" "Windows winver-style Lindows version information"

log "packaging Feedback Hub"
SRC="$WORK/feedbackhub"; source_locked feedbackhub "$SRC"
STAGE="$WORK/pkg-feedbackhub"
install -d "$STAGE/usr/lib/feedbackhub"
cp -a "$SRC/feedbackhub" "$STAGE/usr/lib/feedbackhub/"
install -Dm755 /dev/stdin "$STAGE/usr/bin/feedbackhub" <<'SH'
#!/bin/sh
export PYTHONPATH=/usr/lib/feedbackhub${PYTHONPATH:+:$PYTHONPATH}
exec python3 -m feedbackhub "$@"
SH
install -Dm644 "$SRC/feedbackhub.desktop" "$STAGE/usr/share/applications/feedbackhub.desktop"
sed -i 's|^Exec=.*|Exec=feedbackhub|' "$STAGE/usr/share/applications/feedbackhub.desktop"
install_license "$SRC" "$STAGE" "feedbackhub"
make_deb "feedbackhub" "1.0.0+lindows2" "python3, python3-gi, gir1.2-gtk-3.0" "$STAGE" "Lindows Feedback Hub"

install -Dm644 "$SOURCE_LOCK" "$PKGS/LINDOWS-2.0-COMPONENTS.txt"
log "built Lindows 2.0 extra component packages"
