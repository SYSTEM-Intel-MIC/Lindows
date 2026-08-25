#!/bin/sh
set -eu

# This script runs inside the newly installed target through Calamares
# shellprocess. It must be safe to run more than once.
TARGET=/

# The Live image starts a temporary `user` session directly. The installed
# system must never preserve that identity or bypass authentication: ElevenDE's
# own Win11-style login gate authenticates the Calamares-created account.
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable lindows-live-session-init.service >/dev/null 2>&1 || true
fi
rm -f /etc/systemd/system/lindows-live-session-init.service \
      /etc/systemd/system/multi-user.target.wants/lindows-live-session-init.service \
      /usr/local/sbin/lindows-live-session-init
rm -rf /etc/lightdm /etc/systemd/system/lightdm.service.d
rm -f /etc/xdg/autostart/lindows-desktop-trust.desktop
# The Live account is created at boot and must never be selected should its
# passwd entry happen to be visible while Calamares runs. Clear the image's
# Live session file first, then require the account created by Calamares.
rm -f /etc/lindows/session-user
human_accounts=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" && $1 != "user" && $1 != "live" {print $1}' /etc/passwd)
installed_account=$(printf '%s\n' "$human_accounts" | sed '/^$/d' | tail -n1)
if [ -z "$installed_account" ]; then
    echo 'Lindows: Calamares did not create an installed session account' >&2
    exit 1
fi
install -Dm644 /dev/stdin /etc/lindows/session-user <<EOF
$installed_account
EOF
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable lindows-elevende-display.service >/dev/null 2>&1 || true
fi

# Installed systems must not keep the Live-only installer entry.
find /home /root /etc/skel -type f \( -iname '*install*lindows*.desktop' -o -iname 'install-debian.desktop' -o -iname 'debian-installer.desktop' -o -iname 'debian-installer-launcher.desktop' \) -delete 2>/dev/null || true
# Keep one Widgets process: Lindows supplies the system XDG autostart entry.
# Remove an upstream per-user copy which older media created after a settings
# save and which then duplicated edge strips on every subsequent login.
find /home /root /etc/skel -type f -path '*/.config/autostart/widget-panel.desktop' -delete 2>/dev/null || true
rm -f /usr/share/applications/lindows-installer.desktop \
      /usr/share/applications/debian-installer.desktop \
      /usr/share/applications/debian-installer-launcher.desktop \
      /usr/share/applications/install-system.desktop \
      /etc/xdg/autostart/calamares-desktop-icon.desktop \
      /etc/xdg/autostart/lindows-desktop-trust.desktop
for entry in /usr/share/applications/*.desktop; do
    [ -f "$entry" ] || continue
    if grep -qiE '^Name(\[[^]]+\])?=.*(Install Lindows|Install System|安装 Lindows|安装系统)' "$entry" 2>/dev/null; then
        rm -f "$entry"
    fi
done

# Keep the Lindows GRUB theme self-contained in the installed target. Copy
# both the theme and its relative desktop-image asset before running grub-mkconfig.
THEME_SRC=/usr/share/lindows/branding/theme.txt
[ -f "$THEME_SRC" ] || THEME_SRC=/boot/grub/themes/lindows/theme.txt
WALL_SRC=/usr/share/lindows/branding/lindows-aurora-wallpaper.png
[ -f "$WALL_SRC" ] || WALL_SRC=/boot/grub/themes/lindows/lindows-aurora-wallpaper.png
if [ -f "$THEME_SRC" ] && [ -f "$WALL_SRC" ]; then
    install -Dm644 "$THEME_SRC" /boot/grub/themes/lindows/theme.txt
    install -Dm644 "$WALL_SRC" /boot/grub/themes/lindows/lindows-aurora-wallpaper.png
    mkdir -p /etc/default/grub.d
    cat > /etc/default/grub.d/00-lindows.cfg <<'EOF'
GRUB_DISTRIBUTOR="Lindows"
GRUB_THEME="/boot/grub/themes/lindows/theme.txt"
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=6
GRUB_DEFAULT=0
GRUB_DISABLE_OS_PROBER=false
EOF
else
    # Never leave a dangling GRUB_THEME which produces a boot-time error.
    rm -f /etc/default/grub.d/00-lindows.cfg
fi

# Use ElevenDE's own lock program for installed sessions.  xss-lock observes
# idle/DPMS state without requiring LightDM or a second locker implementation.
if command -v xss-lock >/dev/null 2>&1 && [ -x /usr/local/bin/elevende-lock ]; then
    install -Dm644 /dev/stdin /etc/xdg/autostart/lindows-lock.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Lindows Screen Lock
Name[zh_CN]=Lindows 锁屏
Exec=sh -c 'xset s 600 600; xset +dpms; xset dpms 0 0 900; exec xss-lock --transfer-sleep-lock -- /usr/local/bin/elevende-lock --lock'
OnlyShowIn=ElevenDE;Openbox;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
fi

# Ensure a display change is restored on the next login when saved by Settings.
install -Dm755 /dev/stdin /usr/local/bin/lindows-restore-display <<'EOF'
#!/bin/sh
set -eu
[ -n "${DISPLAY:-}" ] || exit 0
[ -f "$HOME/.config/lindows/display.conf" ] || exit 0
mode=$(sed -n '1p' "$HOME/.config/lindows/display.conf")
[ -n "$mode" ] || exit 0
output=$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')
[ -n "$output" ] || exit 0
# The Shell handles root ConfigureNotify and polls root geometry itself.  Do
# not signal it after RandR: elevende-shell intentionally has no SIGUSR1
# handler, so the default signal action kills the desktop and leaves gray root.
xrandr --output "$output" --mode "$mode" >/dev/null 2>&1 || true
EOF
install -Dm644 /dev/stdin /etc/xdg/autostart/lindows-restore-display.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Lindows Display Restore
Exec=/usr/local/bin/lindows-restore-display
OnlyShowIn=ElevenDE;LXDE;Openbox;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

# Preserve the password entered in Calamares and make the created human user
# eligible for sudo without changing or resetting its password.
if getent group sudo >/dev/null 2>&1; then
    if [ -n "$installed_account" ]; then
        usermod -aG sudo "$installed_account" >/dev/null 2>&1 || true
    fi
fi

# Refresh device state and initramfs so firmware already present in the target
# is discovered without requiring a second manual driver step.
command -v udevadm >/dev/null 2>&1 && udevadm trigger --action=add || true
command -v depmod >/dev/null 2>&1 && depmod -a || true
command -v update-initramfs >/dev/null 2>&1 && update-initramfs -u -k all || true

# Regenerate GRUB only after the target theme and defaults are present.
command -v update-grub >/dev/null 2>&1 && update-grub || true

# Perform one more hardware/firmware probe at first boot, when the installed
# kernel and target udev database are active. Optional firmware never blocks
# graphical login.
install -Dm644 /dev/stdin /etc/systemd/system/lindows-driver-probe.service <<'EOF'
[Unit]
Description=Lindows hardware and firmware probe
After=local-fs.target systemd-udev-settle.service
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'udevadm trigger --action=add; depmod -a; update-initramfs -u -k all; if command -v fwupdmgr >/dev/null 2>&1; then fwupdmgr get-devices || true; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable lindows-driver-probe.service >/dev/null 2>&1 || true
fi
