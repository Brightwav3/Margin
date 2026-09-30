#!/usr/bin/env bash
# Vrstvený spouštěč testů jádra (rychlé ladění, `scripts/check.sh` zůstává plnou bránou).
#
#   scripts/test.sh [režim] [volby]
#
# Režimy:
#   quick    (výchozí) vše kromě pomalých vrstev ze scripts/test-tiers.txt
#   changed  jen testy k souborům změněným proti main (+ pracovní strom); při nejasnosti quick
#   failed   jen testy, které selhaly v posledním běhu
#   slow     jen pomalé vrstvy (výkon, robustnost, souběh, injekce chyb, fuzz)
#   full     vše (jako scripts/check.sh)
#   tiers    vypíše počty testů v jednotlivých vrstvách (nic nespouští)
# Volby:
#   -f, --filter REGEX   jen testy, jejichž ID `Modul.Suite/test()` vyhovuje regexu (lze opakovat;
#                        bez režimu se pomalé testy nevynechávají)
#   -s, --skip REGEX     vynechá testy vyhovující regexu (lze opakovat)
#   -r, --repeat N       vybraný výběr spustí až N× po sobě, zastaví se na prvním selhání (flaky testy)
#   -n, --dry-run        jen vypíše výběr (suity a regexy), nic nespustí
#   --no-build           přeskočí `swift build --build-tests` (výsledky předchozího buildu)
#   -h, --help
# Plný log je v .build/test-logs/last.log, na terminál jde jen shrnutí.
set -u
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT" || exit 2
STATE=".build/test-logs"; mkdir -p "$STATE"
LOG="$STATE/last.log"; FAILED="$STATE/failed.txt"; XUNIT="$STATE/xunit.xml"
XUNIT_ST="$STATE/xunit-swift-testing.xml"; LIST="$STATE/list.txt"
TIERS="scripts/test-tiers.txt"

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }
die() { echo "test: $*" >&2; exit 2; }
join_stdin() { local out="" p; while IFS= read -r p; do [ -n "$p" ] && out="${out:+$out|}($p)"; done; printf '%s' "$out"; }
join_or() { local out="" p; for p in "$@"; do out="${out:+$out|}($p)"; done; printf '%s' "$out"; }

MODE=""; USER_FILTERS=(); USER_SKIPS=(); REPEAT=1; BUILD=1; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    quick|changed|failed|slow|full|tiers) [ -z "$MODE" ] || die "režim už je zadán ($MODE)"; MODE="$1" ;;
    -f|--filter) [ $# -ge 2 ] || die "$1 chce regex"; USER_FILTERS+=("$2"); shift ;;
    -s|--skip)   [ $# -ge 2 ] || die "$1 chce regex"; USER_SKIPS+=("$2"); shift ;;
    -r|--repeat) [ $# -ge 2 ] || die "$1 chce číslo"; REPEAT="$2"; shift ;;
    --no-build) BUILD=0 ;;
    -n|--dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "neznámý argument: $1 (viz --help)" ;;
  esac
  shift
done
case "$REPEAT" in ''|*[!0-9]*|0) die "--repeat chce kladné celé číslo" ;; esac
[ -n "$MODE" ] || { if [ ${#USER_FILTERS[@]} -gt 0 ]; then MODE="filter"; else MODE="quick"; fi; }
command -v swift >/dev/null 2>&1 || die "swift není nainstalován"
[ -f Package.swift ] || die "Package.swift neexistuje"

# --- vrstvy -------------------------------------------------------------------------------------
# Regexy pomalých vrstev (řádky `tier regex` z test-tiers.txt), jeden na řádek.
tier_lines() { [ -f "$TIERS" ] && grep -Ev '^[[:space:]]*(#|$)' "$TIERS"; }
slow_regexes() { tier_lines | sed -E 's/^[^[:space:]]+[[:space:]]+//'; }

# --- build a seznam testů -------------------------------------------------------------------------
do_build() {
  local t0=$SECONDS
  if ! swift build --build-tests >"$STATE/build.log" 2>&1; then
    echo "== build SELHAL (plný log: $STATE/build.log)"; grep -E "error:" "$STATE/build.log" | sort -u | head -20
    exit 1
  fi
  echo "== build OK ($((SECONDS - t0)) s)"
}
do_list() { swift test --skip-build list 2>/dev/null | grep -E '^[A-Za-z0-9_]+\.' >"$LIST" || die "nelze načíst seznam testů"; }

# --- režim changed: soubory -> suity -------------------------------------------------------------
# Názvy suit v souboru: typy s @Suite nebo s názvem končícím Tests/Test/Perf.
suites_of() {
  awk '
    /@Suite/ { f = 1 }
    match($0, /(struct|class|enum|actor)[ \t]+[A-Za-z_][A-Za-z0-9_]*/) {
      s = substr($0, RSTART, RLENGTH); sub(/^[a-z]+[ \t]+/, "", s)
      if (f || s ~ /(Tests?|Perf)$/) print s
      f = 0
    }' "$1" | sort -u
}
# Vypíše regex části `[./]Suite/` jen pro suity, které opravdu existují v seznamu testů.
suite_regexes() { local s; for s in "$@"; do grep -Eq "[./]$s/" "$LIST" && printf '%s\n' "[./]$s/"; done; }

# Služby, jejichž konformitní testy se týkají dané oblasti Sources/MarginCore/<Oblast>.
# ALL = oblast leží pod všemi službami (vault, API, prostředí) -> všechny konformitní testy,
# NONE = bez konformitních testů, jinak prefix(y) názvu souboru v Tests/Conformance.
conformance_for() {
  case "$1" in
    API|Services|Vault|Environment|Fixtures|Concurrency|Index|Platform) echo ALL ;;
    Tasks) echo "Task" ;;          Courses) echo "Course" ;;      Search) echo "Search" ;;
    Graph) echo "Graph" ;;         History) echo "History" ;;     Grades) echo "Grade" ;;
    Export) echo "Export" ;;       Capture) echo "Capture|Inbox" ;;
    Properties) echo "Property" ;; Reminders) echo "Reminder" ;;
    Editor|Merge|Commands|Markdown) echo NONE ;;
    *) echo UNKNOWN ;;
  esac
}

CHANGED_NOTES=(); CHANGED_UNCLEAR=""; SEL_PARTS=(); DIRECT_PARTS=()
add_suites() { # $1 = direct|derived, ostatní = soubory
  local kind="$1" f s r found=0; shift
  for f in "$@"; do
    [ -f "$f" ] || continue
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      SEL_PARTS+=("$r"); found=1; [ "$kind" = direct ] && DIRECT_PARTS+=("$r")
    done <<EOT
$(suite_regexes $(suites_of "$f"))
EOT
  done
  [ "$found" -eq 1 ]
}
select_changed() {
  local base
  base="$(git rev-parse --verify -q origin/main || git rev-parse --verify -q main || true)"
  [ -n "$base" ] || { CHANGED_UNCLEAR="chybí větev main"; return; }
  local files f rel area b conf
  # TEST_CHANGED_FILES (soubory oddělené novým řádkem) přebíjí git; slouží k ověření mapování.
  files="${TEST_CHANGED_FILES:-$( { git diff --name-only "$base"...HEAD; git diff --name-only HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u )}"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      Sources/MarginCore/*/*)
        rel="${f#Sources/MarginCore/}"; area="${rel%%/*}"; b="$(basename "$f" .swift)"; conf="$(conf_or_unknown "$area")"
        [ "$conf" = UNKNOWN ] && { CHANGED_UNCLEAR="neznámá oblast Sources/MarginCore/$area"; continue; }
        local units=() found=0
        [ -d "Tests/MarginCoreTests/$area" ] && units+=(Tests/MarginCoreTests/$area/*.swift)
        # shellcheck disable=SC2046
        units+=($(find Tests -name "$b*.swift" 2>/dev/null))
        [ ${#units[@]} -gt 0 ] && add_suites derived "${units[@]}" && found=1
        case "$conf" in
          ALL) SEL_PARTS+=('^ConformanceTests\.'); found=1 ;;
          NONE) ;;
          *) # shellcheck disable=SC2046
             add_suites derived $(ls Tests/Conformance/*.swift | grep -E "/($conf)[A-Za-z]*\.swift$") && found=1 ;;
        esac
        [ "$found" -eq 1 ] || CHANGED_UNCLEAR="k $f nenalezen žádný test"
        ;;
      Sources/MarginCore/*) CHANGED_UNCLEAR="změna $f v kořeni MarginCore" ;;
      Tests/Conformance/*.swift)
        if ! add_suites direct "$f"; then SEL_PARTS+=('^ConformanceTests\.'); fi ;;
      Tests/MarginCoreTests/*.swift|Tests/MarginCoreTests/*/*.swift)
        add_suites direct "$f" || CHANGED_UNCLEAR="v $f nejsou suity (pomocný soubor)" ;;
      Tests/Fixtures/*|Package.swift|Package.resolved) CHANGED_UNCLEAR="změna $f ovlivňuje vše" ;;
      Sources/MarginUI/*|App/*) CHANGED_NOTES+=("$f (mimo SPM testy, přeskočeno)") ;;
      *) ;; # docs, scripts, .github, ... testy neovlivňují
    esac
  done <<EOF
$files
EOF
}
conf_or_unknown() { conformance_for "$1"; }

# --- sestavení výběru -----------------------------------------------------------------------------
FILTER_RE=""; SKIP_RE=""; SELECT_LABEL=""
SLOW_LIST=(); while IFS= read -r l; do [ -n "$l" ] && SLOW_LIST+=("$l"); done <<EOF
$(slow_regexes)
EOF

build_selection() {
  case "$MODE" in
    quick)  [ ${#SLOW_LIST[@]} -gt 0 ] && SKIP_RE="$(join_or "${SLOW_LIST[@]}")"; SELECT_LABEL="quick" ;;
    slow)   [ ${#SLOW_LIST[@]} -gt 0 ] || die "$TIERS je prázdný"; FILTER_RE="$(join_or "${SLOW_LIST[@]}")"; SELECT_LABEL="slow" ;;
    full)   SELECT_LABEL="full" ;;
    filter) SELECT_LABEL="filter" ;;
    failed)
      [ -s "$FAILED" ] || { echo "Žádné neúspěšné testy z posledního běhu."; exit 0; }
      local rs=() r; while IFS= read -r r; do [ -n "$r" ] && rs+=("$r"); done <"$FAILED"
      FILTER_RE="$(join_or "${rs[@]}")"; SELECT_LABEL="failed (${#rs[@]})" ;;
    changed)
      select_changed
      if [ -n "$CHANGED_UNCLEAR" ]; then
        echo "changed: $CHANGED_UNCLEAR, spouštím quick."
        MODE=quick; [ ${#SLOW_LIST[@]} -gt 0 ] && SKIP_RE="$(join_or "${SLOW_LIST[@]}")"; SELECT_LABEL="quick (záloha za changed)"
      elif [ ${#SEL_PARTS[@]} -eq 0 ]; then
        local n; for n in ${CHANGED_NOTES[@]+"${CHANGED_NOTES[@]}"}; do echo "  - $n"; done
        echo "changed: žádná změna neovlivňuje SPM testy, není co spouštět."; exit 0
      else
        FILTER_RE="$(printf '%s\n' "${SEL_PARTS[@]}" | sort -u | join_stdin)"
        # Pomalé vrstvy vynech, pokud je nezměnil přímo změněný testovací soubor.
        local direct_ids="" sk=() re
        [ ${#DIRECT_PARTS[@]} -gt 0 ] && direct_ids="$(grep -E "$(printf '%s\n' "${DIRECT_PARTS[@]}" | sort -u | join_stdin)" "$LIST")"
        for re in ${SLOW_LIST[@]+"${SLOW_LIST[@]}"}; do
          printf '%s\n' "$direct_ids" | grep -Eq "$re" || sk+=("$re")
        done
        [ ${#sk[@]} -gt 0 ] && SKIP_RE="$(join_or "${sk[@]}")"
        SELECT_LABEL="changed"
        local n; for n in ${CHANGED_NOTES[@]+"${CHANGED_NOTES[@]}"}; do echo "  - $n"; done
      fi ;;
  esac
  local uf us
  [ ${#USER_FILTERS[@]} -gt 0 ] && { uf="$(join_or "${USER_FILTERS[@]}")"; FILTER_RE="${FILTER_RE:+($FILTER_RE)|}$uf"; }
  # Ruční --filter přebíjí vrstvu (jinak by šlo vyžádat pomalý test a hned ho vynechat).
  [ "$MODE" = filter ] && SKIP_RE=""
  if [ ${#USER_SKIPS[@]} -gt 0 ]; then us="$(join_or "${USER_SKIPS[@]}")"; SKIP_RE="${SKIP_RE:+($SKIP_RE)|}$us"; fi
}

# Kolik testů výběr obsáhne (podle seznamu ID; jen orientační, spouští se swift test se stejnými regexy).
count_selected() {
  local ids; ids="$(cat "$LIST")"
  [ -n "$FILTER_RE" ] && ids="$(printf '%s\n' "$ids" | grep -E "$FILTER_RE")"
  [ -n "$SKIP_RE" ] && ids="$(printf '%s\n' "$ids" | grep -Ev "$SKIP_RE")"
  printf '%s\n' "$ids" | grep -c .
}

# --- běh a shrnutí --------------------------------------------------------------------------------
run_once() {
  local args=(test --skip-build --xunit-output "$XUNIT")
  [ -n "$FILTER_RE" ] && args+=(--filter "$FILTER_RE")
  [ -n "$SKIP_RE" ] && args+=(--skip "$SKIP_RE")
  rm -f "$XUNIT" "$XUNIT_ST"
  swift "${args[@]}" >"$LOG" 2>&1
  RC=$?
  write_failed
}

# ID selhavších testů jako regexy (jeden na řádek) -> $FAILED. Zdroj: xunit, záloha: log.
write_failed() {
  : >"$FAILED"
  if [ -f "$XUNIT_ST" ]; then
    awk '
      / <testcase / || /<testcase / {
        match($0, /classname="[^"]*"/); cls = substr($0, RSTART + 11, RLENGTH - 12)
        match($0, / name="[^"]*"/);     nm  = substr($0, RSTART + 7,  RLENGTH - 8)
        pending = 1
      }
      /<failure/ && pending {
        n = index(cls, "."); mod = substr(cls, 1, n - 1); rest = substr(cls, n + 1); gsub(/\./, "/", rest)
        p = index(nm, "("); base = (p > 0) ? substr(nm, 1, p - 1) : nm
        print "^" mod "\\." rest "/" base "\\("
        pending = 0
      }' "$XUNIT_ST" | sort -u >"$FAILED"
  fi
  if [ ! -s "$FAILED" ] && [ "$RC" -ne 0 ]; then
    grep -E '^✘ Test .* (recorded an issue|failed after)' "$LOG" | sed -E 's/^✘ Test (.*) (recorded an issue|failed after).*/\1/' \
      | sed -E 's/\(.*$//; s/ with [0-9]+ test cases//' | sort -u | sed -E 's/^(.*)$/\/\1\\(/' >"$FAILED"
  fi
}

summary() { # $1 = uplynulé sekundy testů
  # `swift test` spouští každý testovací target zvlášť (víc řádků "Test run with"), tak je sečteme.
  local runs n suites nf
  runs="$(grep -E 'Test run with [0-9]+ tests?' "$LOG")"
  if [ -n "$runs" ]; then
    n="$(printf '%s\n' "$runs" | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | awk '{s += $1} END {print s + 0}')"
    suites="$(printf '%s\n' "$runs" | sed -E 's/.* in ([0-9]+) suites?.*/\1/' | awk '{s += $1} END {print s + 0}')"
    nf="$(printf '%s\n' "$runs" | grep -c '^✘')"
    if [ "$nf" -eq 0 ] && [ "$RC" -eq 0 ]; then echo "✔ Prošlo $n testů v $suites suitách."; else echo "✘ Běh selhal ($n testů v $suites suitách)."; fi
  else
    echo "(v logu chybí řádek 'Test run with', viz $LOG)"
  fi
  if [ "$RC" -ne 0 ]; then
    local fails; fails="$(grep -E '^✘ Test .* recorded an issue' "$LOG" \
      | sed -E 's/^✘ Test (.*) recorded an issue( with .*)? at ([A-Za-z0-9_+.-]+\.swift:[0-9]+):[0-9]+: (.*)$/  \3  \1: \4/' | sort -u)"
    if [ -n "$fails" ]; then
      echo "Selhalo:"; printf '%s\n' "$fails" | head -40
      local c; c="$(printf '%s\n' "$fails" | wc -l | tr -d ' ')"; [ "$c" -gt 40 ] && echo "  ... a dalších $((c - 40)) (viz log)"
    else
      echo "Běh skončil chybou bez zaznamenaného selhání testu (pád procesu?):"
      grep -Ei 'fatal error|crash|signal|error:' "$LOG" | head -10
    fi
    [ -s "$FAILED" ] && echo "Zopakovat jen selhané: scripts/test.sh failed"
  fi
  echo "Čas testů: $1 s | log: $LOG"
}

# --- režim tiers ---------------------------------------------------------------------------------
if [ "$MODE" = tiers ]; then
  [ "$BUILD" -eq 1 ] && do_build
  do_list
  echo "Celkem: $(grep -c . "$LIST") testů (MarginCoreTests $(grep -c '^MarginCoreTests\.' "$LIST"), ConformanceTests $(grep -c '^ConformanceTests\.' "$LIST"))"
  tier_lines | while read -r tier re; do printf '  %-11s %4d  %s\n' "$tier" "$(grep -Ec "$re" "$LIST")" "$re"; done
  if [ ${#SLOW_LIST[@]} -gt 0 ]; then
    slow=$(grep -Ec "$(join_or "${SLOW_LIST[@]}")" "$LIST"); echo "  pomalé celkem $slow, quick $(($(grep -c . "$LIST") - slow))"
  fi
  exit 0
fi

# --- hlavní tok ------------------------------------------------------------------------------------
[ "$BUILD" -eq 1 ] && do_build
do_list
build_selection
SEL_COUNT="$(count_selected)"
echo "== testy: režim $SELECT_LABEL, vybráno $SEL_COUNT z $(grep -c . "$LIST")"
if [ "$DRY" -eq 1 ]; then
  echo "filter: ${FILTER_RE:-(žádný)}"; echo "skip:   ${SKIP_RE:-(žádný)}"; echo "suity:"
  { [ -n "$FILTER_RE" ] && grep -E "$FILTER_RE" "$LIST" || cat "$LIST"; } | { [ -n "$SKIP_RE" ] && grep -Ev "$SKIP_RE" || cat; } \
    | sed -E 's#/[^/]*$##' | sort | uniq -c | sed 's/^/  /'
  exit 0
fi
[ "$SEL_COUNT" -gt 0 ] || { echo "test: výběr je prázdný, není co spouštět."; exit 0; }

T0=$SECONDS; PASSED=0; i=1
while [ "$i" -le "$REPEAT" ]; do
  t1=$SECONDS; run_once
  if [ "$REPEAT" -gt 1 ]; then
    if [ "$RC" -eq 0 ]; then echo "  [$i/$REPEAT] OK ($((SECONDS - t1)) s)"; PASSED=$((PASSED + 1)); else echo "  [$i/$REPEAT] SELHALO"; fi
  fi
  [ "$RC" -ne 0 ] && break
  i=$((i + 1))
done
[ "$REPEAT" -gt 1 ] && echo "Opakování: $PASSED/$REPEAT prošlo$([ "$RC" -ne 0 ] && echo ", selhalo v běhu $i")"
summary "$((SECONDS - T0))"
exit "$RC"
