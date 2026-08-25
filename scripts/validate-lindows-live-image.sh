#!/usr/bin/env bash
# Verify the finished Lindows 2.0 ISO, not merely the source configuration.
# This is intentionally read-only: it extracts selected files from the final
# squashfs and checks installer-critical paths, package entry points and the
# narrow Live-session sudo rule.
set -euo pipefail

# Full squashfs verification must recreate device nodes and security xattrs;
# run as root so permission warnings are not mistaken for data corruption.
[ "$(id -u)" = 0 ] || {
    echo 'run final ISO validation as root (sudo) for full squashfs integrity checking' >&2
    exit 2
}

[ "$#" -eq 1 ] || {
    echo "usage: $0 Lindows-2.0-amd64-livecd.iso" >&2
    exit 2
}

ISO="$1"
[ -s "$ISO" ] || {
    echo "ISO is missing or empty: $ISO" >&2
    exit 1
}
for command in xorriso unsquashfs lsinitramfs grep; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "required command is unavailable: $command" >&2
        exit 1
    }
done

WORK="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT
FS="$WORK/filesystem.squashfs"
LIST="$WORK/squashfs.list"

INITRD="$WORK/initrd.img"
xorriso -osirrox on -indev "$ISO" \
    -extract /live/filesystem.squashfs "$FS" \
    -extract /live/initrd.img "$INITRD" >/dev/null 2>&1
[ -s "$FS" ] || {
    echo "final ISO lacks /live/filesystem.squashfs" >&2
    exit 1
}
[ -s "$INITRD" ] || {
    echo "final ISO lacks /live/initrd.img" >&2
    exit 1
}
# A kernel panic reporting "No working init found" is detectable without a VM.
# Fully enumerate the archive to force decompression, then require its init entry.
INITRD_LIST="$WORK/initrd.list"
if ! lsinitramfs "$INITRD" > "$INITRD_LIST" || ! grep -qx 'init' "$INITRD_LIST"; then
    echo 'final ISO contains an invalid Live initrd or lacks its /init entry' >&2
    exit 1
fi

# Listing the directory tree is insufficient: a damaged compressed data block
# can leave names visible while applications fail at runtime. Fully expand the
# squashfs before any path-level inspection so a corrupt ISO cannot pass CI.
FULL_ROOT="$WORK/full-root"
if ! unsquashfs -d "$FULL_ROOT" "$FS" >/dev/null; then
    echo 'final ISO contains a corrupt or unreadable squashfs data block' >&2
    exit 1
fi
unsquashfs -l "$FS" > "$LIST"

require_path() {
    local path="$1"
    grep -q -E "(^|/)${path//./\\.}$" "$LIST" || {
        echo "missing path in final squashfs: /$path" >&2
        exit 1
    }
}

cat_image_file() {
    local path="$1" output="$2"
    unsquashfs -cat "$FS" "$path" > "$output"
}

# Calamares unpackfs must contain these executables and functional modules.
require_path 'usr/bin/unsquashfs'
require_path 'usr/bin/rsync'
require_path 'usr/bin/chvt'
require_path 'etc/calamares/branding/lindows/show.qml'
require_path 'etc/calamares/branding/lindows/stylesheet.qss'
require_path 'etc/calamares/modules/lindows-postinstall.conf'
require_path 'usr/local/libexec/lindows-target-postinstall.sh'
require_path 'usr/local/bin/lindows-installer'
require_path 'usr/local/sbin/lindows-live-session-init'
require_path 'usr/local/sbin/lindows-elevende-display'
require_path 'usr/local/bin/lindows-power-action'
require_path 'usr/local/bin/lindows-logout'
require_path 'usr/local/libexec/lindows-privileged-action'
require_path 'usr/share/polkit-1/actions/im.system-intel-mic.lindows.privileged-action.policy'
require_path 'etc/systemd/system/lindows-elevende-display.service'
require_path 'etc/systemd/system/graphical.target.wants/lindows-elevende-display.service'
require_path 'usr/local/share/elevende-shell/icons/64x64/apps/lindows-installer.svg'

# The system must use ElevenDE's native display/session chain, never LightDM.
if grep -qE '/(usr/sbin/)?lightdm|/etc/lightdm' "$LIST"; then
    echo 'final ISO still contains LightDM files' >&2
    exit 1
fi
DISPLAY_SERVICE="$WORK/lindows-elevende-display.service"
cat_image_file 'etc/systemd/system/lindows-elevende-display.service' "$DISPLAY_SERVICE"
grep -q '^ExecStart=/usr/local/sbin/lindows-elevende-display$' "$DISPLAY_SERVICE"
grep -q '^Conflicts=display-manager.service lightdm.service$' "$DISPLAY_SERVICE"
LIVE_INIT="$WORK/lindows-live-session-init"
cat_image_file 'usr/local/sbin/lindows-live-session-init' "$LIVE_INIT"
! grep -qE 'chpasswd|lightdm|nopasswdlogin' "$LIVE_INIT"
SESSION_SCRIPT="$WORK/elevende-session"
cat_image_file 'usr/local/bin/elevende-session' "$SESSION_SCRIPT"
grep -q 'LINDOWS-SESSION-POLICY' "$SESSION_SCRIPT"
grep -q 'Live session bypasses the login gate' "$SESSION_SCRIPT"
grep -q 'single long-lived process' "$SESSION_SCRIPT"
! grep -q 'lindows-elevende-logout' "$SESSION_SCRIPT"
DISPLAY_LAUNCHER="$WORK/lindows-elevende-display"
cat_image_file 'usr/local/sbin/lindows-elevende-display' "$DISPLAY_LAUNCHER"
! grep -q 'while :' "$DISPLAY_LAUNCHER"
! grep -q 'lindows-elevende-logout' "$DISPLAY_LAUNCHER"
POWER_BRIDGE="$WORK/lindows-power-action"
cat_image_file 'usr/local/bin/lindows-power-action' "$POWER_BRIDGE"
grep -q '^exec pkexec /usr/local/libexec/lindows-privileged-action "\$action"$' "$POWER_BRIDGE"
LOGOUT_HELPER="$WORK/lindows-logout"
cat_image_file 'usr/local/bin/lindows-logout' "$LOGOUT_HELPER"
grep -q 'elevende-lock --login' "$LOGOUT_HELPER"
! grep -q 'openbox --exit' "$LOGOUT_HELPER"
PRIVILEGED_ACTION="$WORK/lindows-privileged-action"
cat_image_file 'usr/local/libexec/lindows-privileged-action' "$PRIVILEGED_ACTION"
grep -q -- '--restore' "$PRIVILEGED_ACTION"
grep -q -- '--no-reboot' "$PRIVILEGED_ACTION"
! grep -q '\$@' "$PRIVILEGED_ACTION"
POLKIT_POLICY="$WORK/lindows-privileged-action.policy"
cat_image_file 'usr/share/polkit-1/actions/im.system-intel-mic.lindows.privileged-action.policy' "$POLKIT_POLICY"
grep -q 'id="im.system-intel-mic.lindows.privileged-action"' "$POLKIT_POLICY"
grep -q '<allow_active>auth_self</allow_active>' "$POLKIT_POLICY"
LIVE_POLKIT_RULE="$WORK/49-lindows-calamares.rules"
cat_image_file 'etc/polkit-1/rules.d/49-lindows-calamares.rules' "$LIVE_POLKIT_RULE"
grep -q 'im.system-intel-mic.lindows.privileged-action' "$LIVE_POLKIT_RULE"
grep -q 'subject.isInGroup("sudo")' "$LIVE_POLKIT_RULE"
grep -q 'polkit.Result.AUTH_SELF' "$LIVE_POLKIT_RULE"
! grep -q 'org.freedesktop.policykit.exec' "$LIVE_POLKIT_RULE"

# Verify the installed, hook-mutated Calamares settings rather than source
# templates. A missing sequence entry recreates the historical module-load
# failure, so both the instance and the sequence reference are mandatory.
SETTINGS="$WORK/settings.conf"
cat_image_file 'etc/calamares/settings.conf' "$SETTINGS"
grep -q -E '^[[:space:]]*branding:[[:space:]]*lindows[[:space:]]*$' "$SETTINGS"
grep -q -E '^[[:space:]]*-[[:space:]]*id:[[:space:]]*lindows-postinstall[[:space:]]*$' "$SETTINGS"
grep -q -E '^[[:space:]]*module:[[:space:]]*shellprocess[[:space:]]*$' "$SETTINGS"
grep -q -E '^[[:space:]]*config:[[:space:]]*lindows-postinstall\.conf[[:space:]]*$' "$SETTINGS"
grep -q -E '^[[:space:]]*-[[:space:]]*shellprocess@lindows-postinstall[[:space:]]*$' "$SETTINGS"

# The passwordless exception belongs only to the disposable Live user and only
# to the Calamares binary. Broad NOPASSWD rules are explicitly rejected.
SUDOERS="$WORK/lindows-installer.sudoers"
cat_image_file 'etc/sudoers.d/lindows-installer' "$SUDOERS"
grep -q -E '^user ALL=\(root\) NOPASSWD: SETENV: /usr/bin/calamares$' "$SUDOERS"
if grep -q -E 'NOPASSWD:[[:space:]]*(ALL|ALL[[:space:]]*$)' "$SUDOERS"; then
    echo 'Live installer sudoers rule is broader than Calamares only' >&2
    exit 1
fi

DESKTOP="$WORK/lindows-installer.desktop"
cat_image_file 'usr/share/applications/lindows-installer.desktop' "$DESKTOP"
grep -q -E '^Exec=(/usr/local/bin/)?lindows-installer([[:space:]]|$)' "$DESKTOP"
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$DESKTOP"
fi

# ElevenDE and every audited, user-facing extra component must appear in the
# final filesystem. These checks catch package staging regressions that package
# metadata alone cannot see.
for path in \
    usr/local/bin/elevende-session \
    usr/local/libexec/lindows-component-launch \
    usr/share/themes/ElevenDE/gtk-3.0/gtk.css \
    usr/bin/lindows-store \
    usr/bin/lindows-troubleshooting \
    usr/bin/lindows-uac-preview \
    usr/bin/lindows-defender \
    usr/bin/lindows-sticky-keys \
    usr/bin/lindows-widgets \
    usr/bin/lindows-windowshit \
    usr/bin/winsat \
    usr/bin/lindows-update-preview \
    usr/bin/winver \
    usr/bin/feedbackhub \
    usr/bin/lindows-activation-watermark \
    usr/bin/lindows-ipconfig \
    usr/local/bin/sas-screen; do
    require_path "$path"
done

# SAS footer power actions must share Start's fixed-function bridge rather
# than attempting unprivileged systemctl calls that silently fail after install.
if ! strings "$FULL_ROOT/usr/local/bin/sas-screen" | grep -q '/usr/local/bin/lindows-power-action'; then
    echo 'final ISO SAS binary does not route power actions through Lindows bridge' >&2
    exit 1
fi

# All Lindows third-party components resolve to curated Windows 11 aliases in
# the ElevenDE icon theme.  Checking the final squashfs catches both package
# staging omissions and upstream icon-generation overwrites.
for icon in \
    linux-pcmanager linux-regedit lindows-bsod lindows-device-manager \
    microsoft-edge lindows-store copilot-for-linux peazip lindows-activation-watermark \
    lindows-troubleshooting lindows-uac-preview lindows-defender \
    lindows-sticky-keys lindows-widgets lindows-windowshit \
    lindows-winsat lindows-update-preview lindows-winver feedbackhub; do
    require_path "usr/local/share/elevende-shell/icons/64x64/apps/${icon}.png"
done

# The generated override must route through the shared ElevenDE adapter and
# refer to the matching icon alias rather than an upstream generic fallback.
COMPONENT_DESKTOP="$WORK/lindows-store.desktop"
cat_image_file 'usr/local/share/applications/lindows-store.desktop' "$COMPONENT_DESKTOP"
grep -q '^Exec=/usr/local/libexec/lindows-component-launch lindows-store$' "$COMPONENT_DESKTOP"
grep -q '^Icon=lindows-store$' "$COMPONENT_DESKTOP"
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$COMPONENT_DESKTOP"
fi

# All Apps must not surface session/power helpers as regular applications.  This
# validates the fully installed filesystem rather than trusting the source hook.
for desktop_file in "$FULL_ROOT"/usr/share/applications/*.desktop "$FULL_ROOT"/usr/local/share/applications/*.desktop; do
    [ -f "$desktop_file" ] || continue
    if grep -Eqi \
        '^(Name|Name\[zh_CN\]|GenericName|Comment)=.*(Shutdown|Shut Down|Power Off|Restart|Reboot|Log ?Out|Logoff|Logout|Suspend|Sleep|Hibernate|Lock Screen|Lock Session|关机|重启|重新启动|注销|登出|睡眠|挂起|休眠|锁屏|锁定)' \
        "$desktop_file" || \
       grep -Eqi \
        '^Exec=.*(systemctl[[:space:]]+(poweroff|reboot|suspend|hibernate)|loginctl[[:space:]]+(poweroff|reboot|suspend|hibernate|terminate-session|lock-session)|lxqt-leave|xfce4-session-logout|mate-session-save|openbox[[:space:]]+--exit|gnome-session-quit|(^|[[:space:]])(poweroff|reboot|shutdown|logout|logoff|xscreensaver-command|dm-tool)[[:space:]])' \
        "$desktop_file"; then
        echo "final ISO still exposes a forbidden system-command desktop entry: ${desktop_file#$FULL_ROOT/}" >&2
        exit 1
    fi
done

printf 'Lindows 2.0 final ISO content validation passed: %s\n' "$ISO"
