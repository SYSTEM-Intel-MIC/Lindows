#!/usr/bin/env bash
# Stage already-verified local packages and chroot hooks for live-build.
# The source hooks remain under config/hooks/normal for review; live-build
# receives a generated execution directory only during a build.
set -euo pipefail

ROOT="${ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
PKGS="${PKGS:-$ROOT/artifacts/packages}"
DEST="$ROOT/config/includes.chroot/opt/lindows/packages"
HOOK_SOURCE="$ROOT/config/hooks/normal"
HOOK_DEST="$ROOT/config/hooks"

[ "$(id -u)" = 0 ] || { echo "run staging as root" >&2; exit 1; }
[ -f "$PKGS/SHA256SUMS" ] || { echo "missing package checksum manifest: $PKGS/SHA256SUMS" >&2; exit 1; }
compgen -G "$PKGS/*.deb" >/dev/null || { echo "no local component packages in $PKGS" >&2; exit 1; }

rm -rf "$DEST"
install -d -m 0755 "$DEST"
install -m 0644 "$PKGS"/*.deb "$PKGS/SHA256SUMS" "$DEST/"
for metadata in \
    "$PKGS/LINDOWS-2.0-COMPONENTS.txt" \
    "$PKGS/LINDOWS-2.0-BUILD-MANIFEST.json" \
    "$ROOT/packages/sources.lock.tsv" \
    "$ROOT/packages/binaries.lock.tsv"; do
    [ -f "$metadata" ] || continue
    install -m 0644 "$metadata" "$DEST/$(basename "$metadata")"
done

rm -f "$HOOK_DEST"/*.chroot
for hook in "$HOOK_SOURCE"/*.hook.chroot; do
    [ -f "$hook" ] || continue
    install -m 0755 "$hook" "$HOOK_DEST/$(basename "${hook%.hook.chroot}").chroot"
done

chown -R root:root "$DEST" "$HOOK_DEST"
printf 'Staged %s packages and %s hooks.\n' \
    "$(find "$DEST" -maxdepth 1 -name '*.deb' -type f | wc -l)" \
    "$(find "$HOOK_DEST" -maxdepth 1 -name '*.chroot' -type f | wc -l)"
