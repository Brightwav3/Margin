#!/usr/bin/env bash
# Plná kontrola: konzistence plánu, build, testy. Spouští ji pre-push i agent před dokončením úkolu.
set -u
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
FAIL=0
python3 scripts/lint-plan.py || FAIL=1
BASE="$(git rev-parse --verify -q origin/main || git rev-parse --verify -q main || true)"
if [ -n "$BASE" ] && [ "$(git rev-parse HEAD)" != "$BASE" ] && git merge-base --is-ancestor "$BASE" HEAD 2>/dev/null; then
  python3 scripts/lint-commit.py --range "$BASE"..HEAD || FAIL=1
fi
if [ -f Package.swift ]; then
  echo "== swift build"; swift build 2>&1 | tail -30; [ "${PIPESTATUS[0]}" -eq 0 ] || FAIL=1
  echo "== swift test";  swift test  2>&1 | tail -40; [ "${PIPESTATUS[0]}" -eq 0 ] || FAIL=1
  if ls App/*.xcodeproj >/dev/null 2>&1; then
    echo "== xcodebuild (arm64)"
    xcodebuild -project App/Margin.xcodeproj -scheme Margin -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -20
    [ "${PIPESTATUS[0]}" -eq 0 ] || FAIL=1
  fi
else
  echo "check: Package.swift zatím neexistuje (fáze M0), build a testy přeskočeny."
fi
[ "$FAIL" -eq 0 ] && echo "check: OK" || { echo "check: SELHALO" >&2; exit 1; }
