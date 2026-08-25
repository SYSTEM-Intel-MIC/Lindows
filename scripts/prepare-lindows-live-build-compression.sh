#!/bin/sh
# Debian Bookworm's live-build lb_binary_rootfs hard-codes `-comp xz` for
# Debian mode after parsing LB_COMPRESSION.  Lindows verifies the entire
# squashfs and therefore applies a small, checked host-tool compatibility
# patch so the configured gzip compressor is genuinely used.
set -eu

TARGET=${LINDOWS_LIVE_BUILD_ROOTFS:-/usr/lib/live/build/lb_binary_rootfs}
[ -f "$TARGET" ] || {
    echo "live-build rootfs implementation is unavailable: $TARGET" >&2
    exit 1
}

if grep -q 'MKSQUASHFS_OPTIONS="${MKSQUASHFS_OPTIONS} -comp gzip"' "$TARGET"; then
    echo "live-build rootfs compressor already set to gzip: $TARGET"
    exit 0
fi

grep -q 'MKSQUASHFS_OPTIONS="${MKSQUASHFS_OPTIONS} -comp xz"' "$TARGET" || {
    echo "unsupported live-build rootfs compressor stanza in $TARGET" >&2
    exit 1
}

sed -i 's/MKSQUASHFS_OPTIONS="${MKSQUASHFS_OPTIONS} -comp xz"/MKSQUASHFS_OPTIONS="${MKSQUASHFS_OPTIONS} -comp gzip"/' "$TARGET"
grep -q 'MKSQUASHFS_OPTIONS="${MKSQUASHFS_OPTIONS} -comp gzip"' "$TARGET"
echo "live-build rootfs compressor set to gzip: $TARGET"
