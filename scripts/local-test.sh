#!/usr/bin/env bash
# Build and smoke-test Lindows 2.0 locally with the same component containers
# and input staging model as GitHub Actions.  Run from the repository root.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
for cmd in lb xorriso sha256sum qemu-system-x86_64 unsquashfs; do need "$cmd"; done
if [ -n "${OVMF_CODE:-}" ]; then
    OVMF_TEST_CODE="$OVMF_CODE"
elif [ -s /usr/share/OVMF/OVMF_CODE.fd ]; then
    OVMF_TEST_CODE=/usr/share/OVMF/OVMF_CODE.fd
else
    OVMF_TEST_CODE=/usr/share/ovmf/OVMF.fd
fi
[ -s "$OVMF_TEST_CODE" ] || {
    echo "missing OVMF firmware" >&2
    exit 1
}

if [ "$(id -u)" = 0 ]; then
    echo "run as an unprivileged user with sudo access" >&2
    exit 1
fi

if [ "${LINDOWS_USE_PREBUILT_PACKAGES:-0}" = "1" ]; then
    echo "==> Using already-built Lindows 2.0 component packages"
    [ -f artifacts/packages/SHA256SUMS ] || {
        echo "prebuilt package checksum manifest is missing" >&2
        exit 1
    }
else
    echo "==> Lindows 2.0 component build"
    need docker
    rm -rf artifacts
    # Core components are built in the fixed Go/Bookworm image.
    docker run --rm -v "$ROOT:/workspace" -w /workspace \
        golang:1.24-bookworm bash ./scripts/build-lindows-components.sh
    # Modern Rust is required by the audited Cargo.lock files.
    docker run --rm -v "$ROOT:/workspace" -w /workspace \
        rust:1.95-bookworm bash ./scripts/build-lindows2-extra-components.sh
    (
        cd artifacts/packages
        sha256sum *.deb > SHA256SUMS
    )
fi
python3 scripts/write-lindows-build-manifest.py
(
    cd artifacts/packages
    sha256sum -c SHA256SUMS
)
bash scripts/validate-lindows-component-packages.sh

echo "==> Staging verified packages and chroot hooks"
sudo ROOT="$ROOT" PKGS="$ROOT/artifacts/packages" bash scripts/stage-lindows-live-inputs.sh

# Remove only generated live-build output; source configuration remains intact.
sudo rm -rf lb .build stage cache auto chroot binary binary.tmp *.iso build.log 2>/dev/null || true

echo "==> Configuring Bookworm Live ISO"
sudo lb config \
    --ignore-system-defaults \
    --mode debian \
    --initramfs live-boot \
    --initsystem systemd \
    --distribution bookworm \
    --architectures amd64 \
    --linux-packages linux-image \
    --archive-areas "main contrib non-free non-free-firmware" \
    --mirror-bootstrap "http://deb.debian.org/debian" \
    --parent-mirror-bootstrap "http://deb.debian.org/debian" \
    --mirror-chroot "http://deb.debian.org/debian" \
    --parent-mirror-chroot "http://deb.debian.org/debian" \
    --mirror-chroot-security "http://security.debian.org/debian-security" \
    --parent-mirror-chroot-security "http://security.debian.org/debian-security" \
    --mirror-binary "http://deb.debian.org/debian" \
    --parent-mirror-binary "http://deb.debian.org/debian" \
    --mirror-binary-security "http://security.debian.org/debian-security" \
    --security false \
    --mirror-debian-installer "http://deb.debian.org/debian" \
    --keyring-packages "debian-archive-keyring" \
    --binary-images iso-hybrid \
    --compression gzip \
    --bootappend-live "components splash" \
    --iso-application "Lindows Live" \
    --iso-publisher "SYSTEM-Intel-MIC" \
    --iso-volume "Lindows 2.0" \
    --source false \
    --zsync false \
    --firmware-chroot false \
    --apt-recommends false \
    --debian-installer false

sudo bash scripts/prepare-lindows-live-build-compression.sh

sudo mkdir -p config/archives
cat <<'EOF' | sudo tee config/archives/lindows.list.chroot >/dev/null
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF
cat <<'EOF' | sudo tee config/archives/lindows.list.binary >/dev/null
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

sudo chmod 755 config/hooks/*.chroot \
    config/includes.chroot/usr/local/bin/lindows-installer \
    config/includes.chroot/usr/local/sbin/lindows-live-session-init \
    config/includes.chroot/usr/local/sbin/lindows-elevende-display \
    config/includes.chroot/usr/local/libexec/lindows-component-launch
sudo cp -f /usr/lib/ISOLINUX/isolinux.bin config/bootloaders/isolinux/isolinux.bin
sudo cp -f /usr/lib/syslinux/modules/bios/*.c32 config/bootloaders/isolinux/

echo "==> Building Lindows 2.0 Live ISO"
sudo lb build 2>&1 | tee build.log
ISO="$(find . -maxdepth 2 -type f \( -name '*Lindows*.iso' -o -name '*.hybrid.iso' \) | head -n1)"
[ -n "$ISO" ] && [ -s "$ISO" ] || { echo "ISO was not generated" >&2; exit 1; }
chmod 755 scripts/repack-lindows-dualboot-iso.sh scripts/validate-lindows-live-image.sh scripts/qemu-boot-smoke.sh
LINDOWS_BINARY_TREE="$ROOT/binary" bash scripts/repack-lindows-dualboot-iso.sh "$ISO"
sudo bash scripts/validate-lindows-live-image.sh "$ISO"
bash scripts/qemu-boot-smoke.sh "$ISO" bios 75
bash scripts/qemu-boot-smoke.sh "$ISO" uefi 75
sha256sum "$ISO" | tee "${ISO}.sha256"
echo "Lindows 2.0 local ISO passed BIOS/UEFI smoke tests: $ISO"
