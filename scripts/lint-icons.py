#!/usr/bin/env python3
"""Every icon name written in the UI sources resolves to a Lucide glyph: directly, through a Lucide
alias or through the Material → Lucide table in `Sources/MarginUI/Theme/Icons.swift`. An unknown
name draws nothing, so a typo hides an icon."""
import glob, json, re, sys

data = json.load(open("Sources/MarginUI/Resources/lucide-icons.json", encoding="utf-8"))
icons, aliases = data["icons"], data.get("aliases", {})
table = dict(re.findall(r'"([a-z0-9_]+)": "([a-z0-9-]+)"', open("Sources/MarginUI/Theme/Icons.swift", encoding="utf-8").read()))

def resolves(name):
    n = table.get(name, name)
    return n in icons or aliases.get(n) in icons

patterns = [r'Icon\("([a-z0-9_\-]+)"', r'icon: "([a-z0-9_\-]+)"', r'MenuItem\("[^"]*", "([a-z0-9_\-]+)"',
            r'MenuIcons\.(?:nsImage|image)\("([a-z0-9_\-]+)"', r'\badd\("[^"]*", "([a-z0-9_\-]+)"',
            r'submenu\("[^"]*", "([a-z0-9_\-]+)"', r'square\("([a-z0-9_\-]+)"', r'ChromeButton\(icon: "([a-z0-9_\-]+)"',
            r'row\("[^"]*", "([a-z0-9_\-]+)"']
missing = []
for path in sorted(glob.glob("Sources/MarginUI/**/*.swift", recursive=True) + glob.glob("App/Margin/**/*.swift", recursive=True)):
    text = open(path, encoding="utf-8").read()
    for p in patterns:
        for m in re.finditer(p, text):
            if not resolves(m.group(1)):
                missing.append(f"{path}:{text[:m.start()].count(chr(10)) + 1}: {m.group(1)}")
for line in missing:
    print(line)
print(f"lint-icons: {'OK' if not missing else f'{len(missing)} neznámých ikon'}")
sys.exit(1 if missing else 0)
