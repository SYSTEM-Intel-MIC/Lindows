#!/usr/bin/env python3
"""Write a reproducible-input manifest for a Lindows 2.0 build artifact."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(os.environ.get("ROOT", Path(__file__).resolve().parents[1])).resolve()
pkg_dir = Path(os.environ.get("PKGS", root / "artifacts" / "packages")).resolve()
out = Path(os.environ.get("OUT", pkg_dir / "LINDOWS-2.0-BUILD-MANIFEST.json")).resolve()

if not pkg_dir.is_dir():
    raise SystemExit(f"package directory does not exist: {pkg_dir}")
packages = []
for path in sorted(pkg_dir.glob("*.deb")):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    packages.append({"file": path.name, "sha256": digest, "bytes": path.stat().st_size})
if not packages:
    raise SystemExit("no Debian packages found")

try:
    commit = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
except subprocess.CalledProcessError:
    commit = "unavailable"

component_lock = pkg_dir / "LINDOWS-2.0-COMPONENTS.txt"
source_lock = root / "packages" / "sources.lock.tsv"
binary_lock = root / "packages" / "binaries.lock.tsv"
icon_map = root / "packages" / "elevende" / "icon-map.tsv"
icon_overlay = root / "packages" / "elevende" / "icons"
icon_files = []
for icon in sorted(icon_overlay.rglob("*.png")) if icon_overlay.is_dir() else []:
    icon_files.append({
        "file": str(icon.relative_to(root)),
        "sha256": hashlib.sha256(icon.read_bytes()).hexdigest(),
    })
manifest = {
    "schema": 1,
    "product": "Lindows",
    "version": "2.0",
    "source_commit": commit,
    "generated_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
    "packages": packages,
    "component_lock": component_lock.read_text(encoding="utf-8").splitlines()
    if component_lock.exists()
    else [],
    "package_layer": {
        "sources_lock": source_lock.read_text(encoding="utf-8").splitlines()
        if source_lock.exists()
        else [],
        "binaries_lock": binary_lock.read_text(encoding="utf-8").splitlines()
        if binary_lock.exists()
        else [],
        "elevende_icon_map": icon_map.read_text(encoding="utf-8").splitlines()
        if icon_map.exists()
        else [],
        "elevende_icon_overlay": icon_files,
    },
}
out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(out)
