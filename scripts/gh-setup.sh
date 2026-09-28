#!/usr/bin/env bash
# Jednorázové nastavení GitHub repozitáře: štítky + ruleset pro main. SPOUŠTÍ ČLOVĚK po `gh auth login`.
# Použití: scripts/gh-setup.sh owner/repo [labels|ruleset|all]     (výchozí: all)
# Ruleset (a branch protection) vyžaduje na soukromém repozitáři placený plán (GitHub Pro) nebo veřejné repo; na free plánu selže.
# Nic z toho se neprovede automaticky; skript vyžaduje výslovné potvrzení.
set -eu
REPO="${1:-}"; MODE="${2:-all}"
[ -n "$REPO" ] || { echo "Použití: scripts/gh-setup.sh owner/repo [labels|ruleset|all]" >&2; exit 1; }
case "$MODE" in labels|ruleset|all) ;; *) echo "Režim musí být labels, ruleset nebo all." >&2; exit 1;; esac
command -v gh >/dev/null || { echo "Chybí gh (GitHub CLI)." >&2; exit 1; }
gh auth status >/dev/null || { echo "Nejdřív: gh auth login" >&2; exit 1; }
echo "Režim '$MODE' v repozitáři $REPO. Pokračovat? [ano/ne]"; read -r A; [ "$A" = "ano" ] || exit 0

if [ "$MODE" = "labels" ] || [ "$MODE" = "all" ]; then
lbl() { gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force; }
# Typy
lbl "type:bug" D73A4A "Bug report"; lbl "type:feat" A2EEEF "Feature request"; lbl "type:chore" FEF2C0 "Maintenance / tooling"
lbl "type:docs" 0075CA "Documentation"; lbl "type:test" BFDADC "Tests only"
# Oblasti
for a in core ui api agent vault docs ci; do lbl "area:$a" 1D76DB "Area: $a"; done
# Priorita
lbl P0 B60205 "Critical / production down"; lbl P1 D93F0B "High"; lbl P2 FBCA04 "Medium"; lbl P3 0E8A16 "Low"
# Triage
lbl needs-triage EDEDED "Awaiting triage"; lbl ready 0E8A16 "Ready to implement"; lbl blocked B60205 "Blocked on dependency"
# Autonomie agentů
lbl "auto:ok" 0E8A16 "Agent may merge when CI green"; lbl "ask:required" B60205 "Human approval before merge"
# Ostatní
lbl breaking B60205 "Breaking change — extra review"; lbl duplicate C5DEF5 "Duplicate of another issue"; lbl "good first issue" 7057FF "Good starter task"
# Milestony (PR dokončující milestone spouští gate schválení v CI)
for m in M0 M1 M2 M3 M4 M5 M6a M6b M7 M8 M9 M10a M10b M10c M11 M12 MA0 MA1 MA2 MA3 MA4; do
  lbl "milestone:$m" 5319E7 "PR completes milestone $m (requires docs/checks/$m.md approval)"
done

fi

# Ruleset pro main (jen když CI job "check" už aspoň jednou proběhl a první push do main je hotový)
if [ "$MODE" = "ruleset" ] || [ "$MODE" = "all" ]; then
  gh api "repos/$REPO/rulesets" -X POST --input .github/rulesets/protect-main.json >/dev/null || { echo "Ruleset se nepodařilo vytvořit (soukromé repo na free plánu?). Štítky jsou hotové." >&2; exit 1; }
  echo "Ruleset Protect main vytvořen."
fi
echo "Hotovo ($MODE). Ručně ještě: GitHub Project board (Backlog → Ready → In PR → Done), Dependabot alerts, secret scanning."
