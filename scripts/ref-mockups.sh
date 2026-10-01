#!/usr/bin/env bash
# Renders every Claude Design mockup (docs/design/mockups/*.dc.html) to a reference PNG in
# docs/checks/reference/ with WebKit (M0-10). Needs network for the Google Fonts the mockups load.
set -euo pipefail
cd "$(dirname "$0")/.."
bin="$(mktemp -d)/webshot"
swiftc -O scripts/tools/webshot.swift -o "$bin"
mkdir -p docs/checks/reference
for f in docs/design/mockups/*.dc.html; do
  name="$(basename "$f" .dc.html | tr ' ' '-')"
  "$bin" "$f" "docs/checks/reference/$name.png" 1600 1000
done
