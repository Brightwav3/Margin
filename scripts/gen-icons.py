#!/usr/bin/env python3
"""Bundle the pinned Lucide icon set into MarginUI (D-006, D-020).

Usage: scripts/gen-icons.sh <path to extracted lucide-static package>
Get the package with: npm pack lucide-static@<LUCIDE_VERSION> && tar -xzf lucide-static-*.tgz

Writes Sources/MarginUI/Resources/lucide-icons.json:
  {"version": "...", "icons": {name: [[tag, {attr: value}], ...]}, "aliases": {alias: name}}
and copies the ISC licence to Sources/MarginUI/Resources/LICENSE-lucide.txt.
"""
import json
import pathlib
import re
import sys

LUCIDE_VERSION = "1.49.0"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources/MarginUI/Resources"


def body(svg: str) -> str:
    """The drawing part of an SVG file, whitespace-normalised."""
    inner = svg[svg.index(">", svg.index("<svg")) + 1 : svg.rindex("</svg>")]
    return re.sub(r"\s+", " ", inner).strip()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    pkg = pathlib.Path(sys.argv[1])
    meta = json.loads((pkg / "package.json").read_text())
    if meta["version"] != LUCIDE_VERSION:
        print(f"expected lucide-static {LUCIDE_VERSION}, got {meta['version']}")
        return 1
    icons = json.loads((pkg / "icon-nodes.json").read_text())

    # SVG files that are not in icon-nodes.json are aliases (renamed icons); map them by content.
    by_body = {body((pkg / "icons" / f"{name}.svg").read_text()): name for name in icons}
    aliases = {}
    for svg in sorted((pkg / "icons").glob("*.svg")):
        name = svg.stem
        if name in icons:
            continue
        target = by_body.get(body(svg.read_text()))
        if target:
            aliases[name] = target
        else:
            print(f"warning: alias {name} has no matching icon")

    OUT.mkdir(parents=True, exist_ok=True)
    data = {"version": LUCIDE_VERSION, "icons": dict(sorted(icons.items())), "aliases": aliases}
    (OUT / "lucide-icons.json").write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False))
    (OUT / "LICENSE-lucide.txt").write_text((pkg / "LICENSE").read_text())
    print(f"lucide {LUCIDE_VERSION}: {len(icons)} icons, {len(aliases)} aliases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
