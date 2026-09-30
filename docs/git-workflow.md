# Git workflow — Margin

Základ: **GitHub + Conventional Commits + pull requesty**, upravený pro projekt s více AI agenty. Kanonický popis; pravidla jsou vynucená (git hooky `.githooks/`, `scripts/lint-commit.py`, guard pro Claude Code, CI). Původní obecný workflow je přizpůsoben v bodech označených **Margin:**.

## Principy
- **`main` je vždy sestavitelný a spustitelný.** Merguje se jen při zelené CI (`scripts/check.sh`, dokud není CI na GitHubu).
- **Jedna funkce nebo oprava na větev.** Malé revize, snadný revert.
- **Větev z `main`, zpět do `main`.** Žádné dlouhodobé integrační větve.
- **Nikdy žádná tajemství v gitu** (`.env`, klíče, tokeny, certifikáty). Klíče patří do Keychainu.
- **Margin:** backend (`MarginCore`) a UI (`MarginUI`) se míchají jen přes smlouvu (`Sources/MarginCore/API`), viz níže.

## Životní cyklus
```
úkol z docs/plan (nebo issue) → větev → PR → review → oprava → squash merge → smazání větve
```
| Krok | Akce |
|---|---|
| Start | `git switch main && git pull`, `git switch -c <type>/<scope>-<slug>` |
| Práce | commity v Conventional Commits, `git push -u origin HEAD` |
| Hotovo | PR do `main` (draft při WIP) |
| Review | opravy na téže větvi |
| Konec | squash merge při zelené CI, smazat větev |

**Souběžní agenti:** každý ve vlastním worktree, např. `git worktree add ../Margin-ui-card -b feat/ui-course-card`.

### Strategie merge: squash
Jeden commit na PR v `main`; název PR = hlavička commitu (Conventional Commits). Patičky z commitů větve (`Task:`, `Closes #`, `Co-Authored-By`) se zachovají v squash commitu.

Před merge rebase na aktuální `main` (vlastní větev; force jen `--force-with-lease`):
```bash
git fetch origin && git rebase origin/main
git push --force-with-lease
```

**Margin – lokálně bez GitHubu:** dokud neexistuje remote, slučuje `scripts/land.sh <větev> "<type>(<scope>): <popis>"` (squash do `main`, spustí `scripts/check.sh`). Až vznikne GitHub, nahradí ho PR; `land.sh` zůstane pro offline použití.

## Názvy větví
```
<type>/<scope>-<slug>          slug: malá písmena, pomlčky, krátké podstatné jméno
```
`type` = typ commitu (`feat fix docs style refactor perf test build ci chore revert`). Volitelný prefix `wip/`.

```
feat/ui-course-card       fix/core-frontmatter-crlf     docs/plan-status
feat/api-task-toggle      refactor/core-extract-index   chore/tooling-hooks
feat/agent-session-service   ci/add-macos-job
```

## Commity
Formát: `<type>(<scope>): <popis>`, hlavička ≤ 72 znaků, popis malým písmenem v rozkazovacím způsobu, bez tečky. **Jedna logická změna na commit.**

| Type | Použití |
|---|---|
| `feat` | nová funkce | 
| `fix` | oprava chyby |
| `docs` | jen dokumentace (i `docs/plan`) |
| `style` | formátování bez změny logiky |
| `refactor` | změna kódu, ne funkce ani oprava |
| `perf` | výkon |
| `test` | jen testy (`Tests/`) |
| `build` | build systém, závislosti |
| `ci` | konfigurace CI |
| `chore` | údržba bez dopadu na produkční kód |
| `revert` | vrácení commitu |

### Scopes (Margin)
| Scope | Oblast | Track |
|---|---|---|
| `ui` | `MarginUI`, `App/Margin` (obrazovky, komponenty) | UI |
| `core` | `MarginCore`, `App/Platform`, testy jádra | backend |
| `api` | `Sources/MarginCore/API` (smlouva backend ↔ UI) | smlouva |
| `agent`, `vault`, `editor`, `tasks`, `capture`, `graph` | funkční oblasti (commit smí jen jeden track) | dle souborů |
| `plan` | `docs/plan`, `docs/checks` | dokumentace |
| `docs` | ostatní dokumentace | dokumentace |
| `ci` | `.github/` | infra |
| `deps` | závislosti | infra |
| `tooling` | hooky, skripty, guard, nastavení agentů | infra (chráněné) |

### Pravidla vynucená `commit-msg` (`scripts/lint-commit.py`)
- Formát, malé písmeno, žádná tečka, ≤ 72 znaků, známý scope.
- **Margin – backend a UI se nemíchají:** commit měnící `Sources/MarginUI`/`App/Margin` i `Sources/MarginCore`/`App/Platform` je zakázán, kromě scope `api`. Scope `ui` nesmí měnit backend a `core`/`vault` nesmí měnit UI.
- **Margin – smlouva:** změna `Sources/MarginCore/API` = scope `api` + ve stejném commitu `Tests/Conformance/` nebo `docs/plan/09-contracts.md`.
- **Margin – stopa úkolu:** commit se Swift kódem typu `feat|fix|refactor|perf|test` má patičku `Task: M3-05` (ID z `docs/plan/backend|ui/README.md`, i více: `Task: M5-03, M5-04.B`) **nebo** `Closes|Fixes|Refs #123`.
- `docs|ci|chore|style` nesmí měnit Swift kód v `Sources/`, `App/`, `Tests/`; `test` smí měnit jen `Tests/`.
- Chráněné soubory (`.githooks/`, `scripts/lib.sh`, `claude-guard.*`, `land.sh`, `lint-commit.py`, `.claude/settings.json`) jen `chore(tooling)` a jen člověk.
- **Breaking change:** `!` za type/scope **nebo** patička `BREAKING CHANGE: …`.

### Příklady
```
feat(ui): add course card banner

Task: M3-01
```
```
feat(core): parse frontmatter with unknown keys preserved

Task: M5-02
```
```
feat(api)!: require actor on every write method

BREAKING CHANGE: write services take an Actor and return a ChangeSet
Task: AG-01
```
```
docs(plan): mark m3 ready for review
chore(tooling): forbid bare TODO in swift files
```

### Patičky (issues)
`Closes #123` zavře issue při merge, `Fixes #123` stejně, `Refs #123` jen odkaz. Jeden issue na PR, kde to jde.

## Issues
Plán (`docs/plan/`) je **zdroj úkolů** s ID (`M3-05`, `AG-04`). GitHub issues jsou volitelný pohled: netriviální práce (> ~1 den, nejasný rozsah, chyba s reprodukcí) → issue s akceptačními kritérii, jinak rovnou větev a PR.

```
plán / backlog → triage → issue (šablona) → větev + PR → merge (Closes #N)
```
Šablony: `.github/ISSUE_TEMPLATE/{bug_report,feature_request,task}.yml`. Triage stavy `needs-triage → ready | blocked | duplicate | wontfix`; SLA 48 h (solo: týdenní dávka).

### Štítky
Vytvoří je `scripts/gh-setup.sh` (spouští člověk po `gh auth login`):
| Štítek | Použití |
|---|---|
| `type:bug|feat|chore|docs|test` | druh |
| `area:core|ui|api|agent|vault|docs|ci` | část kódu |
| `P0`–`P3` | priorita |
| `needs-triage`, `ready`, `blocked` | stav |
| `auto:ok` / `ask:required` | autonomie agenta (viz níže) |
| `milestone:M3`, `milestone:MA1`, … | PR dokončující milestone (spouští gate schválení v CI) |
| `breaking`, `duplicate`, `good first issue` | ostatní |

### GitHub Project
Board **Margin backlog**: Backlog → Ready → In PR → Done. Pohledy: podle priority, `auto:ok` + Ready (práce pro agenty), podle `area:`, podle milestonu. Nastavuje se v UI; git a issues zůstávají zdrojem pravdy.

## Pull requesty
Název PR = hlavička commitu (kontroluje CI): `feat(ui): add course card banner`. `[WIP]` u rozpracovaných (nebo draft). Šablona: `.github/pull_request_template.md` (Summary, Changes, Testing, Breaking changes, Task/Closes).

Review: otevřít PR → počkat na CI → review (solo: kontrolní seznam) → opravy → merge při zelené → smazat větev. Stará PR (14+ dní bez aktivity) → komentář nebo zavřít; nahrazená → zavřít s odkazem.

## CI a brány
CI (`.github/workflows/ci.yml`), job **`check`** (název musí odpovídat rulesetu):
- `scripts/lint-plan.py` (konzistence plánu),
- `scripts/lint-commit.py` (commity v PR, název PR, název větve),
- `swift build` + `swift test` (od M0, když existuje `Package.swift`),
- job **`milestone-gate`**: PR se štítkem `milestone:<M>` musí mít `docs/checks/<M>.md` se schválením člověka.

Minimum před merge: PR míří do `main`, `check` zelený, žádná tajemství, breaking změny označené a schválené, issue v Ready/In PR.

**Ruleset `main`** (`.github/rulesets/protect-main.json`, aplikuje `scripts/gh-setup.sh`): PR povinný, required check `check`, zákaz force push a mazání `main`.

## Rychlé testy během vývoje (`scripts/test.sh`)
Plný `swift test` (~1000 testů, výkonové rozpočty, robustnost, souběh) trvá několik minut. Při práci proto používej vrstvy; **plná brána zůstává `scripts/check.sh`** (pre-push a CI ji pouštějí beze změny).

| Kdy | Příkaz | Co běží |
|---|---|---|
| Při psaní kódu | `scripts/test.sh changed` nebo `scripts/test.sh -f NázevSuity` | jen testy k souborům změněným proti `main` (mapování podle složek, u nejasností `quick`) / jen vybraná suita |
| Před commitem | `scripts/test.sh quick` (výchozí) | vše kromě pomalých vrstev |
| Po pádu testu | `scripts/test.sh failed` | jen testy, které selhaly naposledy |
| Podezření na flaky test | `scripts/test.sh -f NázevSuity --repeat 20` | opakuje výběr, zastaví se na prvním selhání |
| Po změně souběhu, zápisu, výkonu | `scripts/test.sh slow` | jen pomalé vrstvy |
| Před PR / v CI | `scripts/check.sh` (= `full`) | úplně vše |

Pomalé vrstvy (výkon, robustnost, souběh, injekce chyb, fuzz) definuje `scripts/test-tiers.txt` (regexy ID testů; `swift test` neumí filtrovat podle tagů, proto seznam). V kódu jim odpovídá tag `.slow` (`Tests/MarginCoreTests/TestTags.swift`); nový pomalý test = řádek v seznamu + tag. `scripts/test.sh tiers` vypíše počty testů ve vrstvách, `-n` jen ukáže výběr. Plný log je v `.build/test-logs/last.log`, na terminál jde shrnutí (selhané testy se `soubor:řádek`, čas).

## Releasy a verze
[SemVer](https://semver.org/): MAJOR = zpětně nekompatibilní změna veřejného API/formátu dat (vault!), MINOR = nová funkce, PATCH = oprava. Před 1.0 `0.x.y`. Zdroj verze: `Package.swift`/`Info.plist` aplikace; tag `v0.3.0` odpovídá.

1. `main` zelený, changelog hotový.
2. PR se zvýšením verze → merge.
3. `git checkout main && git pull && git tag -a v0.3.0 -m "v0.3.0" && git push origin v0.3.0`.
4. CI z tagu sestaví artefakty (volitelný `release.yml`); GitHub Release s poznámkami.

Tagy nikdy z feature větve. **Margin – tagy milestonů:** `m3-accepted` (vytvoří `land.sh --milestone` po schválení člověkem) jsou oddělené od SemVer tagů.

## Hotfix
Stejná pravidla jako běžná práce (PR + CI). `fix/<scope>-<slug>` z `main`, minimální diff + regresní test, štítek `P0`, rychlé review. Po merge patch release a tag. Udržuje-li se release větev, cherry-pick squash commitu.

## Autonomie (lidé i agenti)

### AUTO — bez ptaní
| Akce | Podmínky |
|---|---|
| Formát, lint, opravy testů | feature větev |
| Push větve | bez tajemství |
| Otevřít PR | lokální kontroly prošly, míří do `main` |
| Merge PR / `land.sh` | CI zelené, nebreaking, bez smlouvy, štítek `auto:ok` nebo rutinní |
| Rebase, opravy review | ta samá PR |
| Zavřít nahrazená PR | komentář proč |
| Merge Dependabot | zelené, jen minor/patch |

Kontrolní seznam merge: CI zelené → nebreaking → není hard gate → dodržené pořadí závislostí.

### ASK — hard gate (nutný člověk, štítek `ask:required`)
| Téma | Proč |
|---|---|
| Force push do `main`; smazání repa; přepis remote | nevratné |
| Breaking změny | konzumenti se musí přizpůsobit |
| **Margin: smlouva backend ↔ UI** (`scope api`) | mění obě větve najednou |
| **Margin: formát vaultu** (`docs/plan/05-vault-spec.md`) | data uživatele přežijí aplikaci |
| **Margin: bezpečnostní model agentů** (identity, oprávnění, `ToolRegistry`, prompt injection) | velký dopad |
| **Margin: přijetí milestonu** | vizuální schválení dělá jen člověk (`docs/checks/<M>.md`) |
| Skutečné klíče/přihlašovací údaje v repu nebo logu | únik |
| Práce mimo plán (`docs/plan/`) | potvrdit směr |
| Změny tohoto workflow, hooků a guardu | meta-pravidla |

### MILESTONES — informovat, neblokovat
Označený release · první E2E · dokončený velký refaktor.

## Komentářové tagy
```
// TAG(kontext): popis
```
`TODO` práce, `FIXME` známá chyba, `HACK` obejití (vysvětli proč), `NOTE`, `WARNING`, `OPTIMIZE`, `REVIEW`, `DEPRECATED`.
**Pravidlo (vynucené):** žádný holý `TODO`/`FIXME`/`HACK` — vždy kontext v závorce: `// TODO(#234): …`, `// TODO(M3-05): …`, `// HACK(core): …`.

## Lokální vynucení
| Vrstva | Co hlídá |
|---|---|
| `commit-msg` | formát, scope, oddělení backend/UI, smlouva, `Task:` patička, typ vs. cesty, chráněné soubory |
| `pre-commit` | ne na `main`; název větve `<type>/<scope>-<slug>`; zakázané soubory a tajemství; bare TODO; vrstvy (UI nesahá na úložiště, jádro neimportuje SwiftUI); `lint-plan`; `swift build` |
| `pre-merge-commit` | ruční merge do `main` zakázán (jen PR / `land.sh`) |
| `pre-push` | `main` jen přes PR/landing; force jen `--force-with-lease` na vlastní větvi; mazání remote zakázáno; kód ⇒ aktualizovaný `STATUS.md`; `scripts/check.sh` |
| Guard (`scripts/claude-guard.py`) | agent nemůže: `--no-verify`, holý force push, force do `main`, `reset --hard`, úpravy hooků/guardu, nastavit `MARGIN_LANDING`/`MARGIN_HUMAN`, zapsat schválení milestonu |
| CI | totéž na serveru + ruleset `main` |

**Chráněné soubory** (`.githooks/`, `scripts/lib.sh`, `claude-guard.*`, `land.sh`, `lint-commit.py`, `.claude/settings.json`) mění jen člověk, jako `chore(tooling)`.

### Když hook zastaví commit
| Hláška | Řešení |
|---|---|
| „Commit přímo na main“ | `git switch -c feat/ui-…` a commit znovu |
| „Špatný formát hlavičky“ | oprav hlavičku (`git commit --amend` jen u neodeslaného commitu) |
| „mění backend i UI zároveň“ | `git reset`, staguj zvlášť, dva commity; smlouva = scope `api` |
| „musí mít patičku Task:“ | přidej `Task: M3-05` (ID z plánu) nebo `Refs #N` |
| „TODO musí mít kontext“ | `TODO(M3-05): …` |
| „UI nesmí přímo používat úložiště“ | použij službu ze `Sources/MarginCore/API` |
| „Plán je nekonzistentní“ | `python3 scripts/lint-plan.py` řekne kde |
| Guard: „chráněný soubor“ | řekni uživateli |

## Rychlý přehled příkazů
```bash
git switch main && git pull && git switch -c feat/ui-course-card
git add -p && git commit -m "feat(ui): add course card banner" -m "Task: M3-01"
git push -u origin HEAD && gh pr create --fill          # až bude GitHub
scripts/land.sh feat/ui-course-card "feat(ui): add course card banner"   # offline náhrada PR
git fetch origin && git rebase origin/main && git push --force-with-lease
git switch main && git pull && git branch -d feat/ui-course-card
```

## Stav nastavení GitHubu
- [x] Pravidla, hooky, guard, CI workflow, šablony PR/issue, štítky (skript), ruleset (JSON), Dependabot — připraveno v repozitáři
- [x] Vzdálené repo: `Brightwav3/Margin` (**private**), `origin` přidán
- [x] Štítky (53, vč. `type:*`, `area:*`, `P0–P3`, `auto:ok`, `ask:required`, `milestone:*`) — `scripts/gh-setup.sh Brightwav3/Margin labels`
- [ ] První push `main` (dělá člověk: `MARGIN_LANDING=1 git push -u origin main`, ve staré verzi hooků `MARGIN_ACCEPTING=1`)
- [ ] **Ruleset / branch protection: na soukromém repu vyžaduje GitHub Pro (nebo veřejné repo).** Na free plánu API vrací 403. Do té doby vynucují pravidla jen lokální hooky a CI (bez blokace merge na serveru). Po upgradu nebo zveřejnění: `scripts/gh-setup.sh Brightwav3/Margin ruleset` (až po prvním pushi a jednom běhu CI, jinak ruleset zablokuje první push do `main`)
- [ ] GitHub Project board, Dependabot alerts, secret scanning (ručně; secret scanning na soukromém repu je placená funkce)
- Poznámka: `.github/workflows`, `dependabot.yml` a šablony issue/PR začnou fungovat až po sloučení do výchozí větve `main`.
