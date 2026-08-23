#!/usr/bin/env python3
"""Fail a QEMU graphical smoke check when the captured PPM is effectively blank.

The check is intentionally conservative: it is not a UI snapshot test.  It
only distinguishes a rendered graphical scene from the all-black frame observed
when the Live session stayed off the active VT.  A text console occupies too
few pixels to satisfy the threshold.
"""
from __future__ import annotations

import sys
from pathlib import Path


def read_ppm(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if not data.startswith(b"P6"):
        raise ValueError("expected binary P6 PPM")

    cursor = 2
    tokens: list[bytes] = []
    while len(tokens) < 3:
        while cursor < len(data) and data[cursor] in b" \t\r\n":
            cursor += 1
        if cursor < len(data) and data[cursor] == ord("#"):
            while cursor < len(data) and data[cursor] not in b"\r\n":
                cursor += 1
            continue
        start = cursor
        while cursor < len(data) and data[cursor] not in b" \t\r\n":
            cursor += 1
        if start == cursor:
            raise ValueError("truncated PPM header")
        tokens.append(data[start:cursor])

    while cursor < len(data) and data[cursor] in b" \t\r\n":
        cursor += 1
    width, height, max_value = map(int, tokens)
    if max_value != 255:
        raise ValueError(f"unsupported PPM max value {max_value}")
    pixels = data[cursor:]
    expected = width * height * 3
    if len(pixels) != expected:
        raise ValueError(f"PPM payload has {len(pixels)} bytes; expected {expected}")
    return width, height, pixels


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} FRAME.ppm", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        width, height, pixels = read_ppm(path)
    except (OSError, ValueError) as exc:
        print(f"invalid QEMU graphical frame: {exc}", file=sys.stderr)
        return 1

    sample_step = 8
    sampled = 0
    nonblack = 0
    sampled_colors: set[tuple[int, int, int]] = set()
    for offset in range(0, len(pixels), 3 * sample_step):
        red, green, blue = pixels[offset : offset + 3]
        sampled += 1
        sampled_colors.add((red, green, blue))
        if red > 8 or green > 8 or blue > 8:
            nonblack += 1

    ratio = nonblack / sampled if sampled else 0.0
    color_count = len(sampled_colors)
    print(
        f"QEMU visual frame {width}x{height}: "
        f"non-black samples {nonblack}/{sampled} ({ratio:.2%}); "
        f"sampled colors {color_count}"
    )
    if ratio < 0.12:
        print(
            "QEMU frame is effectively blank or a sparse text console; "
            "the Live graphical desktop was not visibly rendered",
            file=sys.stderr,
        )
        return 1
    # A running X server's untouched root window is often a uniform gray. It is
    # non-black, but it is not an ElevenDE desktop. Text consoles also expose
    # only a tiny palette. A rendered desktop, login or installer scene has
    # substantial color variation after the same sparse sampling.
    if color_count < 32:
        print(
            "QEMU frame has too little color variation; it is a uniform X root "
            "window or sparse console rather than a rendered Live desktop",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
