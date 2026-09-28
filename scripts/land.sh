#!/usr/bin/env bash
# Lokální náhrada za "squash merge PR do main" (dokud není GitHub remote; potom se merguje přes PR).
#
# Použití:  scripts/land.sh <větev> "<type>(<scope>): <popis>" [--milestone M3]
#
# Rutinní větev (bez smlouvy a bez breaking change) smí slučovat i agent, když je scripts/check.sh zelený
# (odpovídá štítku auto:ok). Slučování smlouvy (scope api), breaking change a přijetí milestonu je hard gate:
# dělá člověk s MARGIN_HUMAN=1 (odpovídá štítku ask:required). Milestone navíc vyžaduje schválení v docs/checks/<M>.md.
set -eu
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"; . scripts/lib.sh

BR="${1:-}"; TITLE="${2:-}"; MS=""
[ -n "$BR" ] && [ -n "$TITLE" ] || die "Použití: scripts/land.sh <větev> \"<type>(<scope>): <popis>\" [--milestone M3]"
shift 2
if [ "${1:-}" = "--milestone" ]; then MS="${2:-}"; [ -n "$MS" ] || die "--milestone vyžaduje id (M3, M6a, MA1)"; fi

git rev-parse --verify -q "$BR" >/dev/null || die "Větev $BR neexistuje."
case "$BR" in main|master) die "Nelze slučovat main do main.";; esac
python3 scripts/lint-commit.py --title "$TITLE" || exit 1
python3 scripts/lint-commit.py --check-branch "$BR" || exit 1
[ -z "$(git status --porcelain)" ] || die "Pracovní strom není čistý. Nejdřív commit."
git merge-base --is-ancestor main "$BR" || die "Větev $BR není postavená na aktuálním main. Nejdřív: git switch $BR && git rebase main"

COMMITS="$(git log --no-merges --format='%H' main.."$BR")"
[ -n "$COMMITS" ] || die "Větev $BR nemá žádné nové commity oproti main."

# Hard gates: smlouva, breaking, milestone => jen člověk
GATE=""
git log --no-merges --format='%s' main.."$BR" | grep -Eq '^[a-z]+(\(api\))?!?:' && true
git log --no-merges --format='%s' main.."$BR" | grep -Eq '^[a-z]+\(api\)' && GATE="změna smlouvy (scope api)"
git log --no-merges --format='%s%n%b' main.."$BR" | grep -Eq '^[a-z]+(\([a-z0-9-]+\))?!:|^BREAKING CHANGE:' && GATE="breaking change"
[ -n "$MS" ] && GATE="přijetí milestonu $MS"
if [ -n "$GATE" ] && [ "${MARGIN_HUMAN:-}" != "1" ]; then
  die "Hard gate ($GATE): slučuje člověk (MARGIN_HUMAN=1 scripts/land.sh …). Agent ať požádá uživatele."
fi

if [ -n "$MS" ]; then
  DOC="docs/checks/$MS.md"
  git show "$BR:$DOC" >/dev/null 2>&1 || die "Na větvi $BR chybí $DOC (záznam kontroly)."
  CONTENT="$(git show "$BR:$DOC")"
  echo "$CONTENT" | grep -Eq '^Stav: Schváleno[[:space:]]*$' || die "$DOC: chybí řádek \"Stav: Schváleno\" (píše člověk po kontrole)."
  echo "$CONTENT" | grep -Eq '^Schválil: [^[:space:]].+$' || die "$DOC: chybí řádek \"Schválil: <jméno>\"."
  echo "$CONTENT" | grep -Eq '^Datum: [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$' || die "$DOC: chybí řádek \"Datum: RRRR-MM-DD\"."
  echo "$CONTENT" | grep -Eq '^- \[ \]' && die "$DOC obsahuje neodškrtnuté položky checklistu."
fi

START="$(current_branch)"
git switch -q "$BR"
bash scripts/check.sh || { git switch -q "$START"; die "scripts/check.sh selhal na větvi $BR."; }
git switch -q main
git merge --squash "$BR" >/dev/null
[ -n "$(git diff --cached --name-only)" ] || { git reset -q --hard; die "Squash nevytvořil žádné změny."; }

# Patičky z commitů větve (Task, Closes/Fixes/Refs, Co-Authored-By) zůstanou v squash commitu
TRAILERS="$(git log --no-merges --format='%B' main.."$BR" | grep -E '^(Tasks?: |Closes #|Fixes #|Refs #|Resolves #|Co-Authored-By: )' | awk '!seen[$0]++' || true)"
MSG="$TITLE"
[ -n "$TRAILERS" ] && MSG="$TITLE

$TRAILERS"
MARGIN_LANDING=1 git commit -q -m "$MSG"
if [ -n "$MS" ]; then
  LC="$(echo "$MS" | tr 'A-Z' 'a-z')"
  git tag -a "${LC}-accepted" -m "Milestone $MS přijat ($(date +%F))"
  echo "Tag ${LC}-accepted vytvořen."
fi
echo "Hotovo: $BR sloučen do main jako squash commit:"; git log -1 --format='  %h %s'
echo "Dál: push dělá člověk (MARGIN_LANDING=1 git push origin main --follow-tags); větev smaž: git branch -D $BR"
