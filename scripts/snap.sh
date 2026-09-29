#!/usr/bin/env bash
# Renders one gallery screen to a PNG: scripts/snap.sh <screen-id> [out.png]
# Default output: docs/checks/snapshots/<id>.png. Runs outside the app sandbox via `margin-snap`.
set -euo pipefail
cd "$(dirname "$0")/.."
id="${1:?usage: scripts/snap.sh <screen-id> [out.png]}"
out="${2:-docs/checks/snapshots/${id//\//-}.png}"
mkdir -p "$(dirname "$out")"
swift build --product margin-snap -q
"$(swift build --show-bin-path)/margin-snap" "$id" "$out"
echo "$out"
