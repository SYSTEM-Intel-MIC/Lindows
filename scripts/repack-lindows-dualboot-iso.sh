#!/usr/bin/env bash
# Add a standalone x86_64 EFI boot image to the final live-build ISO while
# retaining the matching ISOLINUX BIOS tree. This is used identically locally
# and in GitHub Actions to prevent BIOS/UEFI drift.
set -euo pipefail

[ "$#" -eq 1 ] || {
    echo "usage: $0 INPUT.iso" >&2
    exit 2
}

ISO="$1"
[ -s "$ISO" ] || {
    echo "ISO is missing or empty: $ISO" >&2
    exit 1
}
for command in grub-mkstandalone mkfs.vfat mmd mcopy xorriso truncate; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "required command is unavailable: $command" >&2
        exit 1
    }
done

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BINARY_TREE="${LINDOWS_BINARY_TREE:-$ROOT/binary}"
[ -d "$BINARY_TREE" ] || {
    echo "live-build binary tree is missing: $BINARY_TREE" >&2
    exit 1
}
for path in isolinux/isolinux.bin isolinux/ldlinux.c32 isolinux/vesamenu.c32; do
    [ -s "$BINARY_TREE/$path" ] || {
        echo "required BIOS boot asset is missing from binary tree: $path" >&2
        exit 1
    }
done

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
EFI_CFG="$WORK/grub.cfg"
EFI_BIN="$WORK/BOOTX64.EFI"
EFI_IMG="$WORK/efi.img"
REPACKED="$ISO.dualboot"

cat > "$EFI_CFG" <<'EOF'
set timeout=12
set default=0
insmod iso9660
insmod search
insmod linux
insmod normal
search --no-floppy --file --set=root /live/vmlinuz
menuentry "Start Lindows Live" {
  linux /live/vmlinuz boot=live config components
  initrd /live/initrd.img
}
menuentry "Lindows Live (safe graphics)" {
  linux /live/vmlinuz boot=live config components nomodeset
  initrd /live/initrd.img
}
EOF

grub-mkstandalone -O x86_64-efi -o "$EFI_BIN" \
    --modules="iso9660 search linux normal" \
    "boot/grub/grub.cfg=$EFI_CFG"
truncate -s 16M "$EFI_IMG"
mkfs.vfat -F 16 "$EFI_IMG" >/dev/null
mmd -i "$EFI_IMG" ::/EFI ::/EFI/BOOT
mcopy -i "$EFI_IMG" "$EFI_BIN" ::/EFI/BOOT/BOOTX64.EFI

xorriso -as mkisofs -r -J -V "LINDOWS 2.0" \
    -o "$REPACKED" \
    -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e efi.img -no-emul-boot \
    -isohybrid-gpt-basdat "$BINARY_TREE" "$EFI_IMG"
mv -f "$REPACKED" "$ISO"
printf 'Repacked dual BIOS/UEFI Lindows ISO: %s\n' "$ISO"
