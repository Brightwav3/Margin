#!/usr/bin/env bash
# Downloads Mermaid for offline diagram rendering (D-027) into Sources/MarginUI/Resources/Render/mermaid/.
# The file is 5.6 MB, over the repository's size limit, so it is not committed (.gitignore); this
# script pins the version and checks its SHA-256. Without it Mermaid blocks show an explanation.
set -euo pipefail
cd "$(dirname "$0")/.."
version="12.0.0"
sha="28fca7ae6ebc7ed7bb63bde63136a74bfef14f296a57e403657eeb8b32836073"
dest="Sources/MarginUI/Resources/Render/mermaid/mermaid.min.js"
if [ -f "$dest" ] && [ "$(shasum -a 256 "$dest" | cut -d' ' -f1)" = "$sha" ]; then echo "mermaid $version: ok"; exit 0; fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/mermaid.tgz" "https://registry.npmjs.org/mermaid/-/mermaid-$version.tgz"
tar -xzf "$tmp/mermaid.tgz" -C "$tmp" package/dist/mermaid.min.js
got="$(shasum -a 256 "$tmp/package/dist/mermaid.min.js" | cut -d' ' -f1)"
[ "$got" = "$sha" ] || { echo "mermaid $version: unexpected SHA-256 $got" >&2; exit 1; }
mkdir -p "$(dirname "$dest")"
cp "$tmp/package/dist/mermaid.min.js" "$dest"
echo "mermaid $version: installed"
