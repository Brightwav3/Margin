# Rozhodovací log

Formát: ID · datum · stav (Navrženo / Přijato / Nahrazeno) · rozhodnutí · důvod · alternativy · důsledky.

---

### D-001 · 2026-09-28 · Přijato — Jazyk a UI framework
**Rozhodnutí:** Swift 6.4, SwiftUI pro obrazovky, AppKit pro editor, titulkovou lištu a overlaye.
**Důvod:** nativní chování macOS, globální zkratky, možný pozdější port na iOS.
**Alternativy:** Tauri (Rust + web) — rychlejší převod mockupu, ale nenativní; čistě nativní Rust UI — nevyzrálé.
**Důsledky:** editor a vlastní design jsou pracnější než v CSS; Apple-only.

### D-002 · 2026-09-28 · Přijato — Jen Apple Silicon
**Rozhodnutí:** `ARCHS = arm64`, žádný universal binary, žádná podpora Intel Maců.
**Důvod:** požadavek uživatele, jednodušší build a testování.
**Důsledky:** Rosetta nepoužita; snížení velikosti balíčku.

### D-003 · 2026-09-28 · Přijato — Bez explicitního minimálního macOS
**Rozhodnutí:** deployment target = aktuální SDK (macOS 27).
**Důvod:** uživatel nechce stanovit minimum; vyhnout se `#available`.
**Důsledky:** lze snížit později, ale nové API se pak musí obalit.

### D-004 · 2026-09-28 · Přijato — Pravda pro design = `margin-tokens.css`
**Rozhodnutí:** při rozporu s `_ds` tokeny (Fidelio) vyhrává `margin-tokens.css` a mockup.
**Důvod:** `_ds` tokeny říkají 2 váhy písma a jinou modrou; mockup používá 400–700.

### D-005 · 2026-09-28 · Přijato — Markdown soubory jako zdroj pravdy
**Rozhodnutí:** vault = složka markdown souborů, index je jen cache.
**Důvod:** dlouhodobá životnost dat, kompatibilita s Obsidianem, žádný zámek.
**Alternativy:** SQLite/Core Data jako zdroj pravdy — rychlejší, ale uzavřené.
**Důsledky:** nutný file watcher, řešení konfliktů, tolerantní parser.

### D-006 · 2026-09-28 · Přijato — Ikony: Lucide
**Rozhodnutí:** sada **Lucide** (stejná jako v Obsidianu; ISC licence). Ve Swiftu vektorové `Shape` generované skriptem z SVG v pevné verzi (`scripts/gen-icons.sh`), mapování Material → Lucide v `Icons.swift`.
**Důvod:** rozhodnutí uživatele; lehké čárové ikony odpovídají zadání a Obsidianu, nezávisí na SF Symbols a jsou identické napříč platformami.
**Alternativy:** SF Symbols (nativní, ale jiný vzhled, jen Apple); Material Symbols font (věrný mockupu, +MB). Existují i hotové balíčky (`ajaxjiang96/lucide-swift`, `bring-shrubbery/lucide-swift`, `lcandy2/LucideIcon`); podle D-007 je zatím nepřidáváme, generovat vlastní je malá práce a nemá závislost.
**Důsledky:** tvar ikon se od mockupu mírně liší → `DEVIATIONS.md`; Obsidian zaostává za nejnovějším Lucide, proto pinovat verzi a neřešit shodu s ní.

### D-007 · 2026-09-28 · Navrženo — Bez třetích stran na začátku
Viz `04-engineering-rules.md` §6. Kandidáty: swift-markdown, SQLite/GRDB, Yams.

### D-008 · 2026-09-28 · Nahrazeno D-011 — Agent jen jako UI stub
Původně: záložka Agent, výběrová lišta a návrhy odkazů jen s fixture daty. Zrušeno požadavkem na intenzivní použití agenty.

### D-009 · 2026-09-28 · Navrženo — Today a Upcoming se navrhnou samostatně
Mockup je nemá; vzhled navrhne M7 a schválí se v CP1.

### D-010 · 2026-09-28 · Přijato — Plán se dělí na backend a UI
**Rozhodnutí:** úkoly jsou ve dvou větvích (`backend/README.md`, `ui/README.md`), spojených jen smlouvou `09-contracts.md`. Sdílené úkoly se dělí na `.B` a `.U`.
**Důvod:** `MarginCore` a `MarginUI` už jsou oddělené moduly; různé způsoby kontroly (testy vs. vizuální schválení); UI může běžet před backendem na fixtures.
**Důsledky:** každá služba má `Fixture…` i `Vault…` implementaci a konformitní testy; milestone se uzavírá až po obou větvích.

### D-011 · 2026-09-28 · Přijato — Aplikace je agent-native
**Rozhodnutí:** AI agenti (vnější přes MCP/CLI/App Intents, vnitřní chat) jsou plnohodnotní klienti. Parita s UI, nástroje generované ze služeb, původ změn, `ChangeSet`+undo, `baseVersion`, oprávnění a schvalovací fronta, audit, obrana proti prompt injection. Milestony MA0–MA4 (`10-agent-native.md`). Nahrazuje D-008.
**Důvod:** požadavek uživatele: aplikaci budou agenti intenzivně používat.
**Alternativy:** agent jen jako čtenář souborů (žádná garance, ztráta dat); jen chat v aplikaci (bez vnějších agentů).
**Důsledky:** +223 váhy (s D-013 celkem 267); MA0 je brána před M6, protože zapisovací služby musí být od začátku agent-safe; nová rizika R-15 až R-18.

### D-012 · 2026-09-28 · Přijato — Stabilní ID úkolů a poznámek
**Rozhodnutí:** `id:` ve frontmatteru poznámky, `^t-…` za úkolem. Nahrazuje hash identitu z původní vault spec.
**Důvod:** agenti musí adresovat objekt napříč úpravami textu.
**Důsledky:** úprava M5-03/04 a M7-03; migrace z hashe je součást AG-02; přidává se drobná změna do uživatelských souborů (kompatibilní s Obsidianem).

### D-013 · 2026-09-28 · Přijato — Klient × identita
**Rozhodnutí:** agent se připojuje jako **klient** (CLI, MCP, HTTP) spárovaný v aplikaci; oprávnění nese **identita** vytvořená v aplikaci. Klient si podle úkolu a účelu převezme identitu z allowlistu; `ask` identity vyžadují schválení. Všechny transporty vedou do jedné `SessionService`.
**Důvod:** nápad uživatele; agent si volí roli podle práce, ale nemůže si dát víc práv; audit ví „kdo, pod jakou rolí a proč“.
**Alternativy:** token přímo per agent s pevnými právy (méně flexibilní, každý agent nová konfigurace); agent si oprávnění nárokuje sám (nebezpečné).
**Důsledky:** +44 váhy (AG-31…36), celkem 834; MA1 je delší, CP5 zahrnuje párování a převzetí identity; nové riziko R-19.

### D-014 · 2026-09-28 · Přijato — Plán se neměří v lidských hodinách
**Rozhodnutí:** hodiny a dny jsou nahrazeny relativní **váhou** úkolu, **vlnami** práce a **lidskými bránami**. Sledují se kola kontroly, čekání na člověka a cena běhu (`04-engineering-rules.md` §9).
**Důvod:** práci dělají AI agenti; čas psaní kódu není úzké hrdlo, schvalování a rozhodnutí ano. Hodinové odhady byly zavádějící.
**Důsledky:** `11-schedule-and-gates.md` je přepsán na vlny a brány; sloupec „h“ je „Váha“; R-12 a R-20 popisují skutečná rizika.

### D-015 · 2026-09-28 · Přijato — Pravidla vývoje jsou vynucená, ne jen zapsaná
**Rozhodnutí:** repozitář má `AGENTS.md`/`CLAUDE.md` (čtou agenti při startu), `docs/git-workflow.md`, git hooky v `.githooks/` (`pre-commit`, `commit-msg`, `pre-merge-commit`, `pre-push`), guard pro Claude Code (`scripts/claude-guard.py` v `.claude/settings.json`) a startovní přehled (`scripts/agent-brief.sh`). Commit se nepodaří, když poruší větev, formát zprávy, oddělení backend/UI, smlouvu, vrstvy, TODO pravidlo nebo konzistenci plánu. Přijetí milestonu jen skriptem po lidském schválení.
**Důvod:** více agentů souběžně; pravidla, která nejdou vynutit, se poruší.
**Alternativy:** jen dokumentace (nevynutitelné); CI na serveru (zatím není remote; hooky fungují lokálně hned).
**Důsledky:** hooky a guard mění jen člověk; agent, kterého hook zastaví, musí opravit příčinu (`--no-verify` je blokováno guardem). Podrobnosti formátu commitů a větví nahrazuje D-016.

### D-016 · 2026-09-28 · Přijato — Git workflow: GitHub + Conventional Commits + PR
**Rozhodnutí:** převzat obecný workflow uživatele (`docs/git-workflow.md`): větve `<type>/<scope>-<slug>`, Conventional Commits, PR do `main` se squash mergem, issues/štítky/Project, CI s required checkem `check`, SemVer releasy, autonomie AUTO/ASK. Nahrazuje původní pravidla D-015 (milestone větve `m3-…`, prefixy `M3/UI:`, `accept-milestone.sh`).
**Margin-specifické úpravy (nad rámec obecného workflow):**
1. **Backend a UI se v commitu nemíchají** (kromě scope `api`); změna smlouvy = scope `api` + konformitní testy. Kontroluje `scripts/lint-commit.py` (hook, `check.sh`, CI).
2. **Stopa úkolu:** commit s kódem má patičku `Task: M3-05` (nebo `Closes/Fixes/Refs #N`), protože zdrojem úkolů je `docs/plan/`, ne issues.
3. **Hard gates (`ask:required`):** smlouva, formát vaultu, bezpečnostní model agentů, breaking změny a přijetí milestonu (vizuální schválení člověkem v `docs/checks/<M>.md`, štítek `milestone:<M>`, job `milestone-gate` v CI).
4. **Bez GitHubu (zatím):** lokální hooky a `scripts/land.sh` (squash merge do `main`) nahrazují PR; `MARGIN_HUMAN=1` značí lidské rozhodnutí u hard gates a agent ho nenastavuje.
5. Komentářové tagy: `TODO(kontext)` místo holého `TODO` (obecné pravidlo), nikoli povinné ID úkolu.
6. `--force-with-lease` na vlastní větvi je povolen (po rebase), bezpodmínečně zakázán je force do `main`.
**Důvod:** uživatel dodal ověřený workflow; jednotný standard pro lidi i agenty, čitelná historie, CI a ruleset jako vynucení na serveru.
**Alternativy:** vlastní milestone-větve a prefixy (D-015 původní) — vlastní konvence, bez GitHub ekosystému.
**Důsledky:** přepis hooků, `lib.sh` a guardu (chráněné soubory — provede člověk z `docs/proposed-hooks/`); `accept-milestone.sh` se odstraní; do GitHubu je potřeba jednorázově spustit `scripts/gh-setup.sh`.

### D-017 · 2026-09-29 · Přijato — Formát vaultu před M5
**Rozhodnutí:** schváleno doporučení v `05-vault-spec.md` §11: semestr je složka; rozvrh a zkoušky jsou v `_course.md`; vault zůstává kompatibilní s Obsidianem bez vlastní syntaxe aplikace; výchozí umístění je `~/Documents/Margin`.
**Důvod:** uživatel schválil doporučené volby před zahájením integrace backendu do `main`.
**Alternativy:** plochá struktura, metadata rozvrhu jen v `.margin/`, nebo vlastní syntaxe.
**Důsledky:** specifikace vaultu je schválena pro implementaci M5; stávající rozšíření `@` pro termíny a `^id` pro stabilní identitu zůstávají jako textově bezpečné Obsidian zápisy.

### D-018 · 2026-09-29 · Přijato — Aktuální backend/UI smlouva
**Rozhodnutí:** uživatel schválil aktuální `docs/plan/09-contracts.md` a odpovídající protokoly a hodnotové typy v `Sources/MarginCore/API` pro integraci připraveného backendu.
**Důvod:** smlouva a konformitní pokrytí jsou připravené; macOS build a celá lokální testovací sada prošly.
**Alternativy:** odložit integraci nebo před ní změnit protokoly.
**Důsledky:** je možné pokračovat v postupném slučování větví, které tuto smlouvu používají; žádná další změna API z tohoto rozhodnutí automaticky nevyplývá.

### D-019 · 2026-09-29 · Přijato — Rychlý zápis bez otevřeného okna
**Rozhodnutí:** rychlý zápis bude fungovat i bez otevřeného okna aplikace, přes menu bar.
**Důvod:** uživatel potvrdil výchozí předpoklad Q2 v `STATUS.md`.
**Alternativy:** rychlý zápis dostupný jen při otevřeném okně aplikace.
**Důsledky:** M8-05 se implementuje jako menu bar povrch; toto rozhodnutí samo o sobě jeho implementaci nedokončuje.

### D-020 · 2026-09-30 · Přijato — Celá sada Lucide jako data, cesty za běhu
**Rozhodnutí:** přibalit **celou** sadu Lucide 1.49.0 (1857 ikon + 264 aliasů) jako `Resources/lucide-icons.json` (`scripts/gen-icons.sh` z `lucide-static`) a SVG geometrii převádět na `Path` za běhu vlastním parserem (`SVGPath.swift`) s cache. Upřesňuje D-006 (místo generovaných Swift `Shape`).
**Důvod:** uživatel chce mít k dispozici všechny ikony; 1857 generovaných `Shape` by zpomalilo kompilaci. JSON má 430 kB, bez závislosti za běhu.
**Alternativy:** generované `Shape` jen pro ~90 použitých ikon (původní D-006); SVG soubory v bundlu (8 MB).
**Důsledky / riziko:** test ověřuje, že každá ikona se vykreslí uvnitř viewBoxu a každá ikona z mockupu má mapování. Lucide nemá vyplněné varianty (Material `fill`), aktivní stav řeší barva/tloušťka.

### D-021 · 2026-09-30 · Přijato — Snímky obrazovek mimo sandbox (`margin-snap`)
**Rozhodnutí:** `scripts/snap.sh <id>` volá ladicí nástroj `margin-snap` (spustitelný cíl balíčku), který vykreslí obrazovku z galerie do PNG mimo obrazovku; aplikace sama nic nefotí.
**Důvod:** aplikace je v sandboxu a nesmí zapisovat mimo svůj kontejner; spouštění aplikace je navíc pomalé.
**Alternativy:** `--snap` přímo v aplikaci (zápis jen do kontejneru), `screencapture` okna.
**Důsledky / riziko:** snímek vzniká z `NSHostingView` bez okenního rámu; AppKit pohledy, které se kreslí jen v klíčovém okně, se mohou lišit od živé aplikace.

### D-022 · 2026-09-30 · Přijato — Editor na TextKit 1 se skrytými glyfy
**Rozhodnutí:** `MarkdownTextView` je `NSTextView` na TextKit 1 (`NSLayoutManager`). Live a reading režim skrývají syntaxi Markdownu mimo aktivní blok nulovými glyfy (`NSLayoutManagerDelegate`, atribut `margin.hidden`), zaškrtávací políčka úkolů kreslí textové pole přes neviditelné `[ ]`. Styling dělá `MarkdownStyler` nad inkrementálním `MarkdownTokenizer` jen pro přetokenizované řádky a bloky, do kterých kurzor vstoupil nebo odkud odešel.
**Důvod:** TextKit 2 neumí znaky vynechat z layoutu bez vlastních fragmentů; nulové glyfy v TextKit 1 jsou ověřená cesta (Obsidian-like live preview), kurzor a výběr zůstávají v původním textu, undo je nativní.
**Alternativy:** TextKit 2 s vlastním `NSTextLayoutFragment` (výrazně složitější, riziko skoků kurzoru); WebView editor (mimo D-007).
**Důsledky / riziko:** plán M6-01 počítal s TextKit 2; výkon 10 000 slov ověřit v M6-16.U / M12-02. Text pole se nescrolluje samo (výška podle obsahu ve SwiftUI `ScrollView`), aby vlastnosti a nadpis scrollovaly s textem.

### D-023 · 2026-09-30 · Přijato — Vnitřní agent jako Claudian (lokální CLI nad vaultem)
**Rozhodnutí:** záložka Agent v inspektoru funguje jako Obsidian plugin [Claudian](https://github.com/yishentu/claudian): spouští lokální CLI agenta (Claude Code, Codex CLI, případně další) s vaultem jako pracovní složkou; agent čte, zapisuje, hledá a spouští příkazy vlastními nástroji. Margin dodává UI (chat v inspektoru, inline úprava s náhledem změn, `/` příkazy a skills, `@` zmínky souborů, víc konverzací). Nahrazuje vlastní `AgentService` nad Claude API (§8 v `10-agent-native.md`) a mění Q8.
**Důvod:** rozhodnutí uživatele (2026-09-30), zvolena varianta „čistý Claudian“ před CLI omezeným na MCP Marginu a před vlastním API adaptérem.
**Alternativy:** CLI s přímými souborovými nástroji vypnutými a zápisy jen přes MCP Marginu (zachová oprávnění/undo/audit); vlastní `AgentService` nad Claude API s klíčem v Keychainu.
**Důsledky / riziko:** aplikace nesmí běžet v App Sandboxu (spouštění `claude`/`codex`), distribuce jen mimo Mac App Store (Developer ID + notarizace, Q7). Zápisy vnitřního agenta jdou mimo `ToolRegistry`, schvalovací frontu, `ChangeSet` a undo z MA0/MA2; Margin je vidí jen jako externí změny souborů (file watcher, historie verzí). Vnější agenti přes MCP/CLI (MA1–MA2) zůstávají beze změny. Riziko R-22.

### D-024 · 2026-10-01 · Přijato — Ikona předmětu i jako emoji, paleta 18 barev
**Rozhodnutí:** `icon:` v `_course.md` smí být název ikony (celá sada Lucide, Material aliasy) nebo jedno emoji; paleta má 18 klíčů (6 z mockupů + 12 nových). Výběr v UI: barvy, záložky Ikona (návrhy podle názvu předmětu včetně českých, hledání v celé sadě) a Emoji (návrhy, skupiny, vlastní emoji, systémová paleta znaků).
**Důvod:** požadavek uživatele (2026-10-01); se 6 barvami se 9 předmětů semestru opakovalo.
**Alternativy:** jen Lucide ikony; barva jako libovolný hex.
**Důsledky / riziko:** rozšíření formátu vaultu je zpětně kompatibilní (staré soubory platí beze změny); Obsidian emoji ve frontmatteru čte jako text.

---

## Šablona
```
### D-0NN · <datum> · <stav> — <název>
**Rozhodnutí:**
**Důvod:**
**Alternativy:**
**Důsledky / riziko:**
```
