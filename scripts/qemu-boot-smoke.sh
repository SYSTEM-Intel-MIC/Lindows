#!/bin/bash
# Bounded BIOS/UEFI boot smoke for the finished Lindows ISO.  A menu that
# merely renders is insufficient: send Return to select the default Live item,
# then retain a final graphical frame and fail on QEMU-level diagnostics.
set -euo pipefail

usage() {
    echo "usage: $0 ISO_PATH bios|uefi [seconds]" >&2
    exit 2
}

[ "$#" -ge 2 ] || usage
ISO="$1"
MODE="$2"
SECONDS="${3:-75}"
RENDER_WAIT="${LINDOWS_QEMU_RENDER_WAIT:-55}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
VISUAL_VALIDATOR="$SCRIPT_DIR/validate-qemu-visual-frame.py"
[ -s "$ISO" ] || { echo "ISO is missing or empty: $ISO" >&2; exit 1; }
case "$MODE" in bios|uefi) ;; *) usage ;; esac
for command in qemu-system-x86_64 timeout socat python3; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "required command is unavailable: $command" >&2
        exit 1
    }
done

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
MONITOR="$WORK/monitor.sock"
FRAME="${LINDOWS_QEMU_SMOKE_FRAME:-${ISO}.${MODE}.ppm}"
LOG="$WORK/qemu.log"
rm -f "$FRAME"

# virtio-vga is the supported automated graphics test adapter. Standard VGA
# is retained as a documented compatibility follow-up rather than being used
# to infer whether the ElevenDE session has visibly rendered.
QEMU=(qemu-system-x86_64 -m 2048 -smp 2 -accel tcg -no-reboot -no-shutdown \
      -vga virtio -display none -monitor "unix:${MONITOR},server=on,wait=off" -serial none \
      -cdrom "$ISO" -boot d)
if [ "$MODE" = uefi ]; then
    if [ -n "${OVMF_CODE:-}" ]; then
        OVMF_IMAGE="$OVMF_CODE"
    elif [ -s /usr/share/OVMF/OVMF_CODE.fd ]; then
        OVMF_IMAGE=/usr/share/OVMF/OVMF_CODE.fd
    else
        OVMF_IMAGE=/usr/share/ovmf/OVMF.fd
    fi
    [ -s "$OVMF_IMAGE" ] || { echo "OVMF firmware not found: $OVMF_IMAGE" >&2; exit 1; }
    QEMU+=(-machine q35 -bios "$OVMF_IMAGE")
fi

set +e
timeout --foreground "${SECONDS}s" "${QEMU[@]}" 2>"$LOG" &
TIMEOUT_PID=$!
set -e

# Give firmware/ISOLINUX a bounded opportunity to render, then confirm the
# default Live entry.  This avoids treating a static boot menu as a success.
for _ in $(seq 1 20); do
    [ -S "$MONITOR" ] && break
    sleep 1
done
[ -S "$MONITOR" ] || {
    cat "$LOG" >&2 || true
    echo "QEMU $MODE did not expose a monitor socket" >&2
    exit 1
}
sleep 8
printf 'sendkey ret\n' | socat - UNIX-CONNECT:"$MONITOR" >/dev/null 2>&1 || {
    cat "$LOG" >&2 || true
    echo "QEMU $MODE could not select the default Live entry" >&2
    exit 1
}
# Preserve a frame only after the bounded Live/Xorg/session startup window.
# This is deliberately later than the boot menu check because ElevenDE starts
# after the Live environment has created its user and consoles.
sleep "$RENDER_WAIT"
printf 'screendump %s\n' "$FRAME" | socat - UNIX-CONNECT:"$MONITOR" >/dev/null 2>&1 || true

set +e
wait "$TIMEOUT_PID"
rc=$?
set -e
cat "$LOG"
[ -s "$FRAME" ] || {
    echo "QEMU $MODE did not produce a post-selection graphical frame" >&2
    exit 1
}
python3 "$VISUAL_VALIDATOR" "$FRAME"
# Timeout means the guest remained alive past the bounded post-selection boot
# interval; immediate exits or host-visible firmware errors fail the job.
if [ "$rc" -ne 124 ]; then
    echo "QEMU $MODE boot smoke failed with exit status $rc" >&2
    exit 1
fi
if grep -qiE 'could not open|failed to load|no bootable device|fatal' "$LOG"; then
    echo "QEMU $MODE emitted a boot failure diagnostic" >&2
    exit 1
fi
echo "QEMU $MODE boot smoke passed after ${SECONDS}s (frame: $FRAME)"
