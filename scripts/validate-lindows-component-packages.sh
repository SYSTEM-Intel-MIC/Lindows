#!/usr/bin/env bash
# Validate Lindows component packages before staging them into a Live ISO.
set -euo pipefail

ROOT="${ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
PKGS="${PKGS:-$ROOT/artifacts/packages}"
[ -f "$PKGS/SHA256SUMS" ] || { echo "missing SHA256SUMS" >&2; exit 1; }
compgen -G "$PKGS/*.deb" >/dev/null || { echo "no component DEBs" >&2; exit 1; }

(
    cd "$PKGS"
    sha256sum -c SHA256SUMS
)
for required in elevende_3.5.1_amd64.deb lindows-store_2.3.0+lindows2_amd64.deb feedbackhub_1.0.0+lindows2_amd64.deb; do
    [ -f "$PKGS/$required" ] || { echo "missing required component package: $required" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for deb in "$PKGS"/*.deb; do
    pkg="$(dpkg-deb -f "$deb" Package)"
    ver="$(dpkg-deb -f "$deb" Version)"
    arch="$(dpkg-deb -f "$deb" Architecture)"
    [ "$arch" = amd64 ] || { echo "$deb has unexpected architecture: $arch" >&2; exit 1; }
    root="$TMP/$pkg"
    dpkg-deb -x "$deb" "$root"
    # Enforce a package-local license text wherever upstream licensing is
    # explicit.  LinuxPCManager and linux-regedit remain documented exceptions
    # because their current upstream repositories do not provide a license.
    case "$pkg" in
        lindows-bsod|lindows-device-manager|feedbackhub|lindows-*)
            if [ "$pkg" != linux-pcmanager ] && [ "$pkg" != linux-regedit ]; then
                [ -s "$root/usr/share/doc/$pkg/copyright" ] || {
                    echo "$pkg lacks /usr/share/doc/$pkg/copyright" >&2; exit 1;
                }
            fi
            ;;
    esac
    while IFS= read -r -d '' desktop; do
        desktop-file-validate "$desktop"
        grep -q '^Exec=' "$desktop" || { echo "$desktop has no Exec" >&2; exit 1; }
        ! grep -qE '^Exec=.*(explorer\.exe|nautilus[[:space:]]+%[fFuUdD])' "$desktop" || {
            echo "$desktop contains an invalid file-manager launch fallback" >&2; exit 1;
        }
    done < <(find "$root/usr/share/applications" -type f -name '*.desktop' -print0 2>/dev/null)
    printf 'validated %s %s\n' "$pkg" "$ver"
done

[ -f "$PKGS/LINDOWS-2.0-COMPONENTS.txt" ] || {
    echo "missing component lock manifest" >&2; exit 1;
}
[ -f "$PKGS/LINDOWS-2.0-BUILD-MANIFEST.json" ] || {
    echo "missing JSON build manifest" >&2; exit 1;
}
echo "Lindows 2.0 component package validation passed"
