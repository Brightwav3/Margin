#!/usr/bin/env bash
# Tenký wrapper: Claude Code hook -> scripts/claude-guard.py (JSON ze stdin).
exec python3 "$(cd "$(dirname "$0")" && pwd)/claude-guard.py"
