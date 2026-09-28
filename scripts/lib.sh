#!/usr/bin/env bash
# Sdílené funkce pro git hooky a skripty. Změny jen člověk (viz docs/git-workflow.md).

repo_root() { git rev-parse --show-toplevel; }
current_branch() { git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(detached)"; }

# Cesty patří do větve UI / backend (core) / smlouvy. Pravidla commitů drží scripts/lint-commit.py.
UI_RE='^(Sources/MarginUI/|App/Margin/|Tests/MarginUITests/|Tests/Snapshots/)'
BE_RE='^(Sources/MarginCore/|App/Platform/|Tests/MarginCoreTests/|Tests/Conformance/|Tests/Fixtures/)'
API_RE='^Sources/MarginCore/API/'

staged_files() { git diff --cached --name-only --diff-filter=ACMRD; }
staged_added_files() { git diff --cached --name-only --diff-filter=ACMR; }

die() { echo "" >&2; echo "✗ $*" >&2; echo "  Pravidla: AGENTS.md a docs/git-workflow.md" >&2; echo "" >&2; exit 1; }
