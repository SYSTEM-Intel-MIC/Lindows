#!/usr/bin/env bash
# Build all non-Debian Lindows components in a Debian Bookworm container.
# This script deliberately does not run upstream install.sh/build.sh files.
set -euo pipefail

ROOT="${ROOT:-/workspace}"
OUT="${OUT:-$ROOT/artifacts}"
PKGS="${PKGS:-$OUT/packages}"
WORK="${WORK:-$OUT/work}"
SOURCE_CACHE="${LINDOWS_SOURCE_CACHE:-$OUT/source-cache}"
SOURCE_LOCK="$ROOT/packages/sources.lock.tsv"
BINARY_LOCK="$ROOT/packages/binaries.lock.tsv"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
    [ "$(id -u)" = 0 ] || die "this build must run as root inside the Debian build container"
}

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
    # actions/cache restores files with the runner UID while this recipe runs
    # as root in a Bookworm container. Mark only this immutable cache checkout
    # as safe before inspecting its locked commit.
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

fetch_binary_locked() {
    local id="$1" row filename url digest license
    row="$(awk -F '\t' -v id="$id" '$1 == id { print; exit }' "$BINARY_LOCK")"
    [ -n "$row" ] || die "binary lock has no entry for $id"
    IFS=$'\t' read -r _ filename url digest license <<<"$row"
    curl --fail --location --retry 3 --output "$PKGS/$filename" "$url"
    printf '%s  %s\n' "$digest" "$filename" | (cd "$PKGS" && sha256sum -c -)
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
 Lindows bundled component built from a fixed upstream source revision.
CONTROL
    dpkg-deb --build --root-owner-group "$stage" "$PKGS/${name}_${version}_amd64.deb" >/dev/null
}

require_root
[ -f "$SOURCE_LOCK" ] || die "missing package source lock: $SOURCE_LOCK"
[ -f "$BINARY_LOCK" ] || die "missing binary source lock: $BINARY_LOCK"
export DEBIAN_FRONTEND=noninteractive
rm -rf "$PKGS" "$WORK"
mkdir -p "$PKGS" "$WORK" "$SOURCE_CACHE"

log "installing component build dependencies"
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip zip xz-utils dpkg-dev \
    build-essential cmake ninja-build meson pkg-config \
    libgtk-3-dev libjson-glib-dev libdrm-dev libfreetype-dev \
    libfontconfig1-dev libsystemd-dev libgl1-mesa-dev libxkbcommon-dev \
    libxrandr-dev xorg-dev libxi-dev libxtst-dev libdbus-1-dev libcrypt-dev libpam0g-dev libwayland-dev wayland-protocols \
    libgdk-pixbuf-2.0-dev librsvg2-bin qt6-base-dev qt6-svg-dev \
    libgl1-mesa-dev libpng-dev libxft-dev libx11-dev libfontconfig1-dev \
    libgtk-3-dev \
    python3 python3-pil python3-gi gir1.2-gtk-3.0 \
    udisks2 dosfstools ntfs-3g mtools

log "acquiring published ElevenDE 3.5.1 from the locked source cache"
ELEV_SRC="$WORK/ElevenDE"
source_locked elevende "$ELEV_SRC"
[ -f "$ELEV_SRC/build-deb.sh" ] || die "ElevenDE source package is incomplete"
log "patching only the Lindows build copy: execute desktop .desktop launchers"
python3 "$ROOT/scripts/patch-elevende-desktop-launcher.py" "$ELEV_SRC/shell/main.c"
python3 "$ROOT/scripts/patch-elevende-shell-display.py" "$ELEV_SRC/shell/main.c"
python3 "$ROOT/scripts/patch-elevende-settings-display.py" "$ELEV_SRC/apps/settings/main.cpp"
python3 "$ROOT/scripts/patch-elevende-lindows-component-icons.py" "$ELEV_SRC/shell/main.c"
python3 "$ROOT/scripts/patch-elevende-lindows-menu.py" "$ELEV_SRC/shell/main.c"
python3 "$ROOT/scripts/patch-elevende-lindows-actions.py" "$ELEV_SRC/shell/main.c" "$ELEV_SRC/wm/sas-config.json"
python3 "$ROOT/scripts/patch-elevende-session-policy.py" "$ELEV_SRC/session/elevende-session"
python3 "$ROOT/scripts/patch-elevende-icon-overlay-staging.py" "$ELEV_SRC/build-deb.sh"
[ -d "$ROOT/packages/elevende/icons" ] || die "Lindows Windows 11 icon overlay is missing"
rm -rf "$ELEV_SRC/assets/icons-lindows-overlay"
cp -a "$ROOT/packages/elevende/icons" "$ELEV_SRC/assets/icons-lindows-overlay"
# ElevenDE's own winlogin/lock code is preserved. Lindows does not replace it
# with the retired LightDM PAM mutation; the dedicated session policy handles
# Live bypass and installed-system authentication separately.
# The shell patch uses the RandR API directly; make the pinned upstream shell
# link against libXrandr in the isolated component build.
sed -i 's/x11 xft fontconfig freetype2 libpng/x11 xft fontconfig freetype2 libpng xrandr/g' "$ELEV_SRC/shell/Makefile"

log "building ElevenDE 3.5.1 from locked source revision"
(
    cd "$ELEV_SRC"
    BUILD_DIR="$WORK/elevende-build" bash ./build-deb.sh
    cp elevende_3.5.1_amd64.deb "$PKGS/"
)

log "building LinuxPCManager package"
PC="$WORK/linux-pcmanager"
source_locked linux-pcmanager "$PC"
STAGE="$WORK/pkg-linux-pcmanager"
mkdir -p "$STAGE/usr/lib/linux-pcmanager" "$STAGE/usr/bin" "$STAGE/usr/share/applications"
cp -a "$PC/src/." "$STAGE/usr/lib/linux-pcmanager/"
install -m 755 /dev/stdin "$STAGE/usr/bin/linux-pcmanager" <<'LAUNCH'
#!/bin/sh
exec python3 /usr/lib/linux-pcmanager/main.py "$@"
LAUNCH
install -m 644 "$PC/linux-pcmanager.desktop" "$STAGE/usr/share/applications/linux-pcmanager.desktop"
make_deb "linux-pcmanager" "1.0.0+lindows1" "python3, python3-tk, policykit-1, xdotool, wmctrl, x11-utils, pulseaudio-utils | alsa-utils" "$STAGE" "Windows-style Linux PC Manager"

log "building linux-regedit package"
REG="$WORK/regedit"
source_locked regedit "$REG"
meson setup "$REG/build" "$REG" --buildtype=release
meson compile -C "$REG/build"
STAGE="$WORK/pkg-linux-regedit"
install -Dm755 "$REG/build/linux-regedit" "$STAGE/usr/local/bin/linux-regedit"
install -Dm644 /dev/stdin "$STAGE/usr/share/applications/linux-regedit.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Registry Editor
Name[zh_CN]=注册表编辑器
Comment=Browse Linux system and user configuration files
Exec=linux-regedit
Icon=preferences-system
Terminal=false
Categories=System;Settings;
DESKTOP
make_deb "linux-regedit" "0.1+lindows1" "libgtk-3-0, libjson-glib-1.0-0, man-db" "$STAGE" "Windows-style Linux configuration registry editor"

log "building Lindows BSOD package"
BSOD="$WORK/bsod"
source_locked bsod "$BSOD"
meson setup "$BSOD/build" "$BSOD" --buildtype=release
meson compile -C "$BSOD/build"
STAGE="$WORK/pkg-lindows-bsod"
install -Dm755 "$BSOD/build/bsod" "$STAGE/usr/local/sbin/lindows-bsod"
# The upstream renderer directly seizes a VT/DRM master and therefore requires
# root.  Lindows exposes a safe X11 demonstration instead: it never reboots,
# never changes the active VT and Escape always restores the desktop.
install -Dm755 /dev/stdin "$STAGE/usr/lib/lindows-bsod-preview.py" <<'PY'
#!/usr/bin/env python3
import tkinter as tk
root = tk.Tk()
root.configure(bg="#0078d7")
root.attributes("-fullscreen", True)
root.title("Lindows Blue Screen Demo")
frame = tk.Frame(root, bg="#0078d7")
frame.place(relx=0.5, rely=0.47, anchor="center")
tk.Label(frame, text=":(", fg="white", bg="#0078d7", font=("Sans", 72)).pack(anchor="w")
tk.Label(frame, text="Lindows 蓝屏演示\n这是一个安全预览，不会重启或修改系统。\n按 Esc 返回桌面。", fg="white", bg="#0078d7", justify="left", font=("Sans", 20)).pack(anchor="w", pady=(18, 0))
root.bind("<Escape>", lambda _event: root.destroy())
root.mainloop()
PY
install -Dm755 /dev/stdin "$STAGE/usr/local/bin/lindows-bsod-demo" <<'LAUNCH'
#!/bin/sh
exec python3 /usr/lib/lindows-bsod-preview.py "$@"
LAUNCH
install -Dm644 /dev/stdin "$STAGE/usr/share/applications/lindows-bsod.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Lindows Blue Screen Demo
Name[zh_CN]=Lindows 蓝屏演示
Comment=Safe blue-screen demonstration; Escape returns to the desktop
Exec=lindows-bsod-demo
Icon=lindows-bsod
Terminal=false
Categories=System;
DESKTOP
install -Dm644 "$BSOD/LICENSE" "$STAGE/usr/share/doc/lindows-bsod/copyright"
make_deb "lindows-bsod" "1.0.3+lindows2" "python3, python3-tk" "$STAGE" "Safe reversible Lindows blue-screen demonstration"

log "building Device Manager package"
DEVMGR="$WORK/devmgr"
source_locked device-manager "$DEVMGR"
(
    cd "$DEVMGR"
    # Upstream lacks go.sum. The Lindows package layer carries the audited
    # lock, then forces readonly resolution instead of mutating upstream files.
    install -m 0644 "$ROOT/vendor/lindows-device-manager.go.sum" go.sum
    go mod download
    CGO_ENABLED=1 go build -mod=readonly -trimpath -ldflags="-s -w" -o devmgr ui.go
    go build -mod=readonly -trimpath -ldflags="-s -w" -o devmgr-cli cli.go
)
STAGE="$WORK/pkg-lindows-devmgr"
install -Dm755 "$DEVMGR/devmgr" "$STAGE/usr/local/bin/devmgr"
install -Dm755 "$DEVMGR/devmgr-cli" "$STAGE/usr/local/bin/devmgr-cli"
install -Dm644 /dev/stdin "$STAGE/usr/share/applications/lindows-device-manager.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Device Manager
Name[zh_CN]=设备管理器
Comment=View Linux hardware in a Windows-style device manager
Exec=devmgr
Icon=computer
Terminal=false
Categories=System;Settings;HardwareSettings;
DESKTOP
install -Dm644 "$DEVMGR/LICENSE" "$STAGE/usr/share/doc/lindows-device-manager/copyright"
make_deb "lindows-device-manager" "0.1.0+lindows1" "libgl1, libx11-6, libxrandr2, libxinerama1, libxcursor1, libxi6, policykit-1, pciutils, usbutils" "$STAGE" "Windows-style Linux device manager"

log "building Lindows Store from locked source"
STORE="$WORK/linux-store"
source_locked linux-store "$STORE"
python3 "$ROOT/scripts/patch-lindows-component-sources.py" store "$STORE"
[ -f "$STORE/native/linux-store" ] || die "Linux Store launcher is missing"
[ -f "$STORE/native/linux_store.py" ] || die "Linux Store Python source is missing"
[ -d "$STORE/native/assets" ] || die "Linux Store visual assets are missing"
STAGE="$WORK/pkg-lindows-store"
install -Dm755 "$STORE/native/linux_store.py" "$STAGE/usr/lib/lindows-store/linux_store.py"
install -Dm755 /dev/stdin "$STAGE/usr/bin/lindows-store" <<'LAUNCH'
#!/bin/sh
exec python3 /usr/lib/lindows-store/linux_store.py "$@"
LAUNCH
install -Dm644 "$STORE/native/linux-store.desktop" "$STAGE/usr/share/applications/lindows-store.desktop"
sed -i -e 's/^Name=Linux Store$/Name=Lindows Store/' \
       -e 's/^Exec=.*/Exec=lindows-store/' \
       -e 's/^Icon=.*/Icon=lindows-store/' "$STAGE/usr/share/applications/lindows-store.desktop"
install -d "$STAGE/usr/share/lindows-store"
install -m 0644 "$STORE/native/assets/"* "$STAGE/usr/share/lindows-store/"
install -Dm644 "$STORE/LICENSE" "$STAGE/usr/share/doc/lindows-store/copyright"
make_deb "lindows-store" "2.3.0+lindows2" "python3, python3-gi, gir1.2-gtk-3.0, apt, polkitd, pkexec" "$STAGE" "Windows-style Lindows Store backed by configured APT repositories"

log "downloading fixed release DEBs described by the binary lock"
fetch_binary_locked copilot-for-linux
fetch_binary_locked peazip

(
    cd "$PKGS"
    sha256sum *.deb > SHA256SUMS
)
log "built local packages"
ls -lh "$PKGS"
