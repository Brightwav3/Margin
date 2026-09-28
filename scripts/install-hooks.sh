#!/usr/bin/env bash
# Zapne git hooky z .githooks (jednou po klonu; agent-brief.sh to dělá sám).
set -e
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
git config core.hooksPath .githooks
chmod +x .githooks/* scripts/*.sh scripts/*.py 2>/dev/null || true
echo "Hooky zapnuty: core.hooksPath=$(git config core.hooksPath)"
