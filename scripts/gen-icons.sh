#!/usr/bin/env bash
# Regenerates Sources/MarginUI/Resources/lucide-icons.json from a pinned lucide-static package.
set -euo pipefail
exec python3 "$(dirname "$0")/gen-icons.py" "$@"
