#!/usr/bin/env python3
"""Build the Lindows ElevenDE icon overlay from a WindowsIcons checkout.

The package layer stores only the selected, converted assets required by the
component mapping table. The upstream icon repository is not vendored in full.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

SIZES = (16, 22, 24, 32, 48, 64, 96, 128)


def load_map(path: Path) -> list[tuple[str, str, str]]:
    entries: list[tuple[str, str, str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 3:
            raise SystemExit(f"invalid mapping row {line_number}: expected three tab-separated columns")
        entries.append((fields[0], fields[1], fields[2]))
    if not entries:
        raise SystemExit("icon mapping table has no entries")
    return entries


def convert(ico: Path, destination: Path, size: int) -> None:
    with Image.open(ico) as image:
        frames: list[Image.Image] = []
        for index in range(getattr(image, "n_frames", 1)):
            image.seek(index)
            frames.append(image.convert("RGBA").copy())
    source = max(frames, key=lambda frame: frame.width * frame.height)
    source.thumbnail((size, size), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(source, ((size - source.width) // 2, (size - source.height) // 2))
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", type=Path, required=True)
    parser.add_argument("--icons-root", type=Path, required=True)
    parser.add_argument(
        "--local-icons-root",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "packages" / "elevende" / "local-icon-sources",
        help="repository-local icon sources selected with @local/ in the mapping table",
    )
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()

    entries = load_map(args.map)
    if not args.icons_root.is_dir():
        raise SystemExit(f"WindowsIcons root does not exist: {args.icons_root}")
    if any(source.startswith("@local/") for _, source, _ in entries) and not args.local_icons_root.is_dir():
        raise SystemExit(f"local icon root does not exist: {args.local_icons_root}")
    args.destination.mkdir(parents=True, exist_ok=True)
    count = 0
    for alias, relative_source, _component in entries:
        if relative_source.startswith("@local/"):
            source = args.local_icons_root / relative_source.removeprefix("@local/")
        else:
            source = args.icons_root / relative_source
        if not source.is_file():
            raise SystemExit(f"mapped icon is missing: {source}")
        for size in SIZES:
            convert(source, args.destination / f"{size}x{size}" / "apps" / f"{alias}.png", size)
            count += 1
    print(f"generated {count} Windows 11 icon overlay PNGs for {len(entries)} Lindows component aliases")


if __name__ == "__main__":
    main()
