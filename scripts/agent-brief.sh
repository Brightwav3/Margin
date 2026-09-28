#!/usr/bin/env bash
# Startovní přehled pro agenta (SessionStart hook). Vypíše stav projektu a pravidla.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$ROOT"
[ "$(git config core.hooksPath)" = ".githooks" ] || { git config core.hooksPath .githooks && echo "(git hooky zapnuty automaticky)"; }
BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo '(detached)')"
echo "=== MARGIN — přehled pro agenta ==="
echo "Větev: $BRANCH"
case "$BRANCH" in main|master) echo "⚠ Jsi na $BRANCH: commity sem jsou zakázané. Vytvoř větev <type>/<scope>-<slug> (git switch -c feat/ui-course-card) podle docs/git-workflow.md.";; esac
echo "Stav git: $(git status --short | wc -l | tr -d ' ') změněných souborů; posledních 5 commitů:"; git log --oneline -5 2>/dev/null | sed 's/^/  /'
if [ -f docs/plan/STATUS.md ]; then
  echo ""; echo "--- STATUS.md: milestony, které nejsou ⬜ (rozpracované/ke kontrole/přijaté) ---"
  ACTIVE="$(grep -E '^\| M[A0-9a-c]+ \|' docs/plan/STATUS.md | grep -Ev '\| ⬜ \|' | cut -c1-140 || true)"
  if [ -n "$ACTIVE" ]; then echo "$ACTIVE"; else echo "  (žádný milestone ještě nezačal — další je M0/M2, vlna 1)"; fi
  echo ""; echo "--- Otevřená rozhodnutí (⬜), která mohou blokovat práci ---"
  grep -E '^\| Q[0-9]+ \|.*\| ⬜ \|' docs/plan/STATUS.md | cut -c1-150
fi
echo ""
cat <<'RULES'
--- PRAVIDLA (vynucená hooky a CI; detail v AGENTS.md a docs/git-workflow.md) ---
1. Nejdřív přečti docs/plan/STATUS.md, potom README své větve (docs/plan/backend/ nebo ui/) a docs/plan/09-contracts.md.
2. Větev <type>/<scope>-<slug> (feat/ui-course-card); nikdy commit na main. Souběžní agenti = git worktree. Přepnutí větve a commit jsou dvě samostatná volání.
3. Conventional Commits: "feat(ui): add course card banner" + patička "Task: M3-01" (u kódu). Types: feat fix docs style refactor perf test build ci chore revert.
4. Backend (core) a UI (ui) se v jednom commitu nemíchají (výjimka: scope api). Změna Sources/MarginCore/API = scope api + konformitní testy.
5. UI nesahá na úložiště; MarginCore neimportuje SwiftUI/AppKit. Žádný holý TODO: TODO(M3-05): …
6. Po dokončeném úkolu aktualizuj docs/plan/STATUS.md (docs(plan): commit). Rozhodnutí zapiš do DECISIONS.md.
7. Před "hotovo" spusť scripts/check.sh. Slučování: PR (squash) nebo scripts/land.sh. Smlouva, formát vaultu, model agentů, breaking změny a milestony = ASK (člověk).
8. Nikdy: --no-verify, holý force push, force do main, reset --hard, úpravy hooků/guardu, zápis schválení do docs/checks. Když tě hook zastaví, oprav příčinu.
RULES
