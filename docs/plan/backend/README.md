# Backend — plán úkolů (`MarginCore` + platformní služby)

Větev **backend**: doménový model, soubory na disku, parsery, indexy, dotazy, služby (`09-contracts.md`) a celá agentní vrstva (`10-agent-native.md`). Bez oken a bez SwiftUI/AppKit (výjimka: `App/Platform` — globální zkratka, notifikace, socket).

**Jak se kontroluje:** čísly a testy, ne očima. Každý úkol má unit test, kde to jde; služby mají konformitní testy proti `Fixture…` i `Vault…`. Výkon se hlídá podle rozpočtů v `04-engineering-rules.md`.

**Vztah k UI:** backend nejdřív dodá **rozhraní + `Fixture…` implementaci**, UI (`ui/README.md`) na ní staví. Skutečná implementace se zapojí později (M5-10.B). Úkoly `.B` jsou backendové poloviny úkolů rozdělených podle `M?-??` původního plánu; jejich `.U` protějšek je v UI větvi.

Značení: `M?-??` čistý backend úkol · `M?-??.B` backendová část sdíleného úkolu · `AG-??` agentní úkol.

**Váha není čas.** Je to relativní složitost a riziko úkolu pro agenta (původní hodinové odhady pro člověka zachované jen jako měřítko). Orientace: **1–2** jeden agentní běh · **3–5** běh + iterace po testech · **6–8** víc iterací, rizikové místo · **10+** rozdělit. Skutečné omezení jsou lidské brány (schválení obrazovek, rozhodnutí), viz `11-schedule-and-gates.md`.

## Souhrn váhy (relativní složitost, ne čas)

| Milestone | Název | Váha |
|---|---|---|
| M0 | Kostra, tokeny, komponenty, galerie | 5 |
| M1 | Shell | 0 |
| M2 | Model a fixtures | 12 |
| M3 | Přehled předmětů (1a, 1b) | 5 |
| M4 | Detail předmětu (2c) | 3 |
| M5 | Vault a index | 35 |
| MA0 | Agent: základy (provenance, ID, undo, souběh) | 32 |
| M6a | Editor: source + reading | 11 |
| M6b | Editor: live | 5 |
| M7 | Úkoly | 16 |
| MA1 | Agent: povrch nástrojů (MCP, CLI) | 83 |
| M8 | Rychlý zápis a Inbox | 25 |
| MA2 | Agent: oprávnění, audit, schvalování | 19 |
| M9 | Graf | 17 |
| M10a | Popupy: navigace a psaní | 12 |
| MA3 | Agent v aplikaci | 30 |
| M10b | Popupy: data a organizace | 12 |
| M10c | Popupy: dialogy a oznámení | 12 |
| M11 | Obrazovky a stavy | 21 |
| MA4 | Agent: odolnost | 32 |
| M12 | Dokončení a vydání | 18 |
| **Σ** | | **405** |

## M0 — Kostra, tokeny, komponenty, galerie (váha 5)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M0-01 | Swift Package `Margin` s targety `MarginCore`, `MarginUI`, testy | `swift build` a `swift test` projdou; Swift 6 strict concurrency zapnuto | 2 |  |
| M0-02 | Xcode projekt `App/Margin.xcodeproj`, arm64, sandbox, hardened runtime | `xcodebuild -destination 'platform=macOS,arch=arm64'` projde; žádná x86_64 slice v binárce (`lipo -archs`) | 3 |  |

## M2 — Model a fixtures (váha 12)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M2-01 | Typy: `Semester`, `Course`, `Session`, `Note`, `TaskItem`, `Grade`, `InboxItem`, `Exam` | `Codable`, `Sendable`, `Identifiable`; dokumentované invarianty | 3 |  |
| M2-02 | `Clock` protokol + `FixedClock` (28. 9. 2026 13:24) | všechny „dnes/zítra“ výpočty přes `Clock` | 1 |  |
| M2-03 | `Fixtures.week5`: 6 předmětů, 11 sessions, 6 due, 3 exams | test ověří počty a datumy | 3 |  |
| M2-04 | Fixtures: galerie Bio (6 karet), poznámky, inbox (5), známky | odpovídá `Margin.dc.html` | 3 |  |
| M2-05 | Fixtures: graf (23 uzlů, hrany) s pozicemi z mockupu | 1:1 pozice | 2 |  |

## M3 — Přehled předmětů (1a, 1b) (váha 5)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M3-04 | Řazení a filtrování nad daty | jednotkové testy `CourseListQuery` | 3 |  |
| M3-05.B | `BannerStore`: uložení banneru do `_files/` a čtení | obrázek přežije restart, omezená velikost, round-trip test | 2 |  |

## M4 — Detail předmětu (2c) (váha 3)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M4-08 | Generování karet z rozvrhu (dny bez souboru = „Not started“) | test: karta pro Lecture 9 vznikne z `Session` | 3 |  |

## M5 — Vault a index (váha 35)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M5-01 | Odsouhlasení `05-vault-spec.md` (otevřené body §11) | zapsáno v `DECISIONS.md` | 1 |  |
| M5-02 | `Frontmatter` parse + zápis, zachování neznámých klíčů | fuzz round-trip 10 000 vstupů bez ztráty | 5 |  |
| M5-03 | `MarkdownScanner`: nadpisy, bloky kódu, úkoly, odkazy (ignorovat kód) | test: `- [ ]` v bloku kódu není úkol | 5 |  |
| M5-04 | `TaskExtractor` + parsování termínů (`@ Tue`, `@2026-10-02`, `@before-midterm`) | tabulka 40 vstupů → očekávané datum | 4 |  |
| M5-05 | `WikilinkExtractor`, aliasy, nevytvořené cíle, backlinky s kontextem | test 25 případů | 3 |  |
| M5-06 | `VaultStore`: čtení, atomický zápis, přejmenování s aktualizací odkazů, koš | žádná ztráta v testech násilného přerušení zápisu | 6 |  |
| M5-07 | `FileWatcher` (FSEvents) + ošetření vlastních zápisů | změna zvenčí ≤ 1 s v UI, bez smyčky | 4 |  |
| M5-08 | `NoteIndex` (paměť) + rozpočty výkonu | 1000 poznámek: start < 1 s, reindex 1 souboru < 30 ms | 4 |  |
| M5-09 | Generátor ukázkového vaultu z fixtures + tlačítko | vault otevřitelný v Obsidianu bez chyb | 2 |  |
| M5-10.B | Přepnutí služeb z `Fixture…` na `Vault…` v `AppEnvironment` | konformitní testy zelené pro fixture i vault | 1 |  |

## MA0 — Agent: základy (provenance, ID, undo, souběh) (váha 32)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| AG-01 | `Actor` a provenance: každý zápis přes služby nese původce; append-only `.margin/audit.jsonl` | každý zápis vytvoří řádek auditu; test 20 zápisů od 3 původců | 6 |  |
| AG-02 | Stabilní ID poznámek a úkolů (`id:` ve frontmatteru, `^id` u úkolů) + migrace z hashe; nahrazuje hash identitu v M5-03/04 | ID přežije přejmenování, přesun i úpravu textu; 30 testů | 8 |  |
| AG-03 | `ChangeSet`: více zápisů atomicky s inverzí, `undo(changeSet)` | undo vrátí stav bit po bitu; 30 scénářů | 10 |  |
| AG-04 | Souběh: `baseVersion` u zápisů, `.conflict` + trojcestné slučování | stres 2 zapisovatelé × 1000 zápisů bez ztráty | 8 |  |

## M6a — Editor: source + reading (váha 11)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M6-02.B | `MarkdownTokenizer`: tokeny se spany (nadpis, odrážka, kód, odkaz, frontmatter) | inkrementální tokenizace změněného rozsahu; testy na 50 vstupech | 3 |  |
| M6-05.B | `PropertyService`: čtení/zápis vlastností do frontmatteru | pořadí a neznámé klíče zachovány | 2 |  |
| M6-08.B | `NoteStats` (backlinky, vlastnosti, slova, otevřené úkoly) | aktualizace ≤ 200 ms po psaní | 1 |  |
| M6-09.B | `NoteAnalysis`: outline, backlinky s kontextem, outgoing, statistiky vlastností | dotazy < 30 ms na 1000 poznámek | 2 |  |
| M6-11 | Zaškrtnutí úkolu v editoru/reading přepíše `- [ ]` ↔ `- [x]` | test round-trip | 3 |  |

## M6b — Editor: live (váha 5)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M6-12.B | `BlockModel`: dělení na bloky a určení aktivního bloku | testy na 40 dokumentech vč. kódu a tabulek | 3 |  |
| M6-16.B | Výkon `MarkdownTokenizer` na 10 000 slovech | < 3 ms na změnu | 2 |  |

## M7 — Úkoly (váha 16)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M7-02 | `TasksStore` nad `NoteIndex`, sledování změn | úkol z poznámky ve všech pohledech ≤ 1 s | 5 |  |
| M7-03 | Zápis zaškrtnutí zpět do zdrojového souboru (atomicky) | test: 2 rychlé odškrtnutí nepoškodí soubor | 4 |  |
| M7-05.B | `TodayQuery` (Overdue/Today + dnešní sessions) přes `Clock` | testy hranic (půlnoc, časové pásmo) | 3 |  |
| M7-06.B | `UpcomingQuery` (dny, týden, později, zkoušky) | seskupení otestováno | 2 |  |
| M7-08.B | `DueLabel` pravidla (Due Fri, Exam, červená) | tabulka 20 případů | 1 |  |
| M7-09.B | `TaskLocation`: určení řádku úkolu ve zdroji | přežije úpravy nad úkolem | 1 |  |

## MA1 — Agent: povrch nástrojů (MCP, CLI) (váha 83)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| AG-05 | `ToolRegistry`: nástroje generované ze služeb (jméno, popis, JSON Schema, riziko read/write/destructive) | snapshot katalogu; test „každá metoda služby je nástroj nebo vyňata“ | 10 |  |
| AG-06 | Dry-run (vrací diff) a `idempotencyKey` u zápisových nástrojů | opakované volání neduplikuje; diff sedí se skutečným zápisem | 6 |  |
| AG-07 | Strojově čitelné odpovědi: stránkování (`limit`, `cursor`), `fields`, stabilní řazení, chyby jako data | JSON Schema validace všech odpovědí | 5 |  |
| AG-08 | MCP server (stdio) `margin-mcp`: tools + resources (`margin://note/<id>`) + prompts (skills); nástroje `identities.list` (jen povolené klientovi) a `session.start(identity, purpose)` | připojí se Claude Code/Desktop; `tools/list` odpovídá katalogu | 12 |  |
| AG-09 | CLI `margin` s JSON výstupem: `connect`, `identities`, `session start --identity … --purpose …`, `task list --today`, `note read`, `capture` | dokumentované příkazy a exit kódy; bez session odmítnuto | 6 |  |
| AG-10 | Lokální transport: Unix socket (práva jen pro uživatele); autentizace connection/session tokenem z AG-32/33 (bez vlastní identity klienta) | bez tokenu odmítnuto; socket jen pro uživatele | 8 |  |
| AG-11 | App Intents a URL `margin://` (capture, open, přidat úkol) | 3 intents fungují ze Shortcuts | 6 |  |
| AG-31 | `IdentityService`: agentní identity vytvářené v aplikaci (název, popis „k čemu je“, profil read/propose/write-scoped/full, rozsah předmětů, limity, soukromí, politika převzetí auto/ask) + šablony (Studijní asistent, Třídič inboxu, Zapisovatel přednášek, Plánovač, Auditor) | CRUD identit; šablony; identita nese veškerá oprávnění (klient/agent žádná vlastní nemá) | 6 |  |
| AG-32 | `ConnectionService`: párování klienta (CLI/MCP/HTTP) s aplikací kódem schváleným v UI; connection token v Keychainu; **allowlist identit**, které klient smí převzít | klient bez schválení nemá přístup; odvolání je okamžité; 10 scénářů | 8 |  |
| AG-33 | `SessionService`: klient si zvolí identitu a **účel** (`purpose`), dostane session token s TTL; identity s politikou `ask` vyžadují schválení v UI; každý zápis nese identitu + session + účel | eskalace mimo allowlist odmítnuta; TTL a odvolání fungují; audit obsahuje `purpose` | 8 |  |
| AG-34 | Lokální HTTP API (loopback, jen s tokenem, ve výchozím stavu vypnuté): OpenAPI generované z `ToolRegistry`, stejné session jako CLI/MCP | schéma odpovídá katalogu; port zavřený, dokud není zapnut | 8 |  |

## M8 — Rychlý zápis a Inbox (váha 25)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M8-01 | `QuickCaptureParser` (předmět, datum, tagy, druh) + 60 testovacích vět | ≥ 95 % správně; latence < 5 ms | 8 |  |
| M8-04 | Globální zkratka ⌘⇧Space (`RegisterEventHotKey`) | funguje nad Xcode, Safari, Finderem | 4 |  |
| M8-05 | Rozhodnutí a implementace: běh bez okna (login item / menu bar) | dle rozhodnutí z otázky 2 | 6 |  |
| M8-06 | Uložení do `_inbox/` a do předmětu (Task/Note) | soubor odpovídá spec | 3 |  |
| M8-08.B | `InboxService.triage`: přesun, převod na úkol/poznámku | výsledný soubor odpovídá spec | 2 |  |
| M8-09.B | `LectureNoteResolver`: nejbližší přednáška předmětu + vložení řádku | test hranic dnů | 2 |  |

## MA2 — Agent: oprávnění, audit, schvalování (váha 19)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| AG-12 | Vynucování oprávnění identity: matice scope × nástroj, potvrzení destruktivních; oprávnění identity nejde měnit nástrojem (schéma profilu je v AG-31) | matice testů scope × nástroj; oprávnění nejde měnit nástrojem | 8 |  |
| AG-13 | Review fronta: `ProposedChange` (`.margin/proposals/`), approve/reject, vypršení při změně `baseVersion` | schválení zapíše přes ChangeSet; zamítnutí nic nemění | 8 |  |
| AG-14 | Rate limit a rozpočet zápisů (počet/min, velikost) | test překročení vrátí `.rateLimited` | 3 |  |

## M9 — Graf (váha 17)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M9-01 | `GraphBuilder` (uzly, hrany, počty) | test na fixtures: 23 uzlů | 4 |  |
| M9-02 | `ForceLayout` (Barnes-Hut), deterministický seed | 500 uzlů stabilizace < 2 s | 8 |  |
| M9-06.B | `GraphFilter` model | testy filtrace | 1 |  |
| M9-08.B | `EgoGraph`: okolí poznámky do hloubky N | test na fixtures | 2 |  |
| M9-09.B | Optimalizace `ForceLayout` (kvadrantový strom, hrubší kroky) | 5000 uzlů stabilizace < 5 s | 2 |  |

## M10a — Popupy: navigace a psaní (váha 12)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M10-01 | SQLite FTS5 index (poznámky, titulky) | dotaz na 1000 poznámek < 30 ms | 6 |  |
| M10-02.B | `CommandRegistry` + řazení výsledků | relevance testy na 20 dotazech | 2 |  |
| M10-03.B | `LinkSuggester`: návrhy + vytvoření cíle | < 20 ms | 2 |  |
| M10-04.B | `SlashCommandRegistry` | každý příkaz vrací text a pozici kurzoru | 1 |  |
| M10-05.B | `NoteExcerpt` provider | < 20 ms | 1 |  |

## MA3 — Agent v aplikaci (váha 30)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| AG-19 | `AgentService` (provider-agnostic) + adaptér Claude API: kontext builder, streaming, tool-use smyčka nad `ToolRegistry` | agent zvládne „shrň Lecture 8“ a „přidej úkol na středu“ | 14 |  |
| AG-20 | Konverzace a paměť (`.margin/agent/`), ohraničený kontext (token budget), citace `[[…]]` | konverzace přežije restart; kontext nepřekročí rozpočet | 8 |  |
| AG-21 | Skills: definice postupů v `.margin/agent/skills/*.md` (kartičky, plán učení, týdenní přehled) | 3 skills běží a zapisují do fronty | 8 |  |

## M10b — Popupy: data a organizace (váha 12)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M10-09.B | `PropertyType` registr (date/text/tags/number/checkbox) + validace | testy validace | 1 |  |
| M10-10.B | `DueDateWriter`: zápis `@…` do řádku, přepis stávajícího | test 15 řádků | 2 |  |
| M10-11.B | `NoteRepository.move` + přepis odkazů | žádný nefunkční odkaz po přesunu | 3 |  |
| M10-12.B | Přejmenování/barva/ikona předmětu do `_course.md` | perzistence, testy | 1 |  |
| M10-13.B | `SemesterArchiver`: přesun do `_archive/`, příznak read-only | testy, vratné | 3 |  |
| M10-14.B | `SessionOverride`: změna času/místnosti, zrušení jedné hodiny | rozvrh a karty změnu reflektují | 2 |  |

## M10c — Popupy: dialogy a oznámení (váha 12)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M10-16.B | `CourseFactory`: složka, `_course.md`, výchozí rozvrh | vytvořený předmět projde validací | 2 |  |
| M10-18.B | `ReminderService` (`UNUserNotificationCenter`, 10 min před hodinou) | test s posunutými hodinami | 3 |  |
| M10-19.B | `SyllabusDraft` model + zápis do `_course.md` | úprava a uložení | 2 |  |
| M10-20.B | `GradeService.add` (zápis `_grades.md`); sdílí kód s M11-01.B | round-trip | 2 |  |
| M10-21.B | `SettingsStore`: typované perzistentní nastavení | změna se propaguje | 1 |  |
| M10-22.B | `ExportService`: PDF a Markdown | PDF a MD export ověřen | 2 |  |

## M11 — Obrazovky a stavy (váha 21)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M11-01.B | `GradeCalculator` + `GradeStore` | 10 testovacích případů | 4 |  |
| M11-02.B | `SemesterFactory` + inicializace vaultu | nový vault je platný | 3 |  |
| M11-03.B | `SearchService` filtry (předmět/typ/datum/tag) nad FTS | < 50 ms | 3 |  |
| M11-04.B | Čtení archivovaných semestrů (read-only) | zápis je odmítnut | 1 |  |
| M11-05.B | `SemesterStore` a nastavení aplikace | perzistence | 3 |  |
| M11-07.B | Průběh indexace (`AsyncStream<IndexProgress>`) | 0–100 %, doručeno do UI | 1 |  |
| M11-08.B | `HistoryService`: snapshoty, diff, obnovení | test 20 verzí, nic se nemaže | 6 |  |

## MA4 — Agent: odolnost (váha 32)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| AG-26 | Obrana proti prompt injection: obsah jako data (obálka), potvrzení hromadných akcí, sada 30 útoků v CI | žádná neautorizovaná změna v 30 útocích | 10 |  |
| AG-27 | Eval sada: 20 agentních úloh s očekávaným stavem vaultu, deterministický běh s mockem modelu | 20/20 zelené v CI | 10 |  |
| AG-28 | Stres: 5 agentů souběžně + uživatel píše; latence nástroje | bez ztráty dat; p95 < 200 ms | 6 |  |
| AG-29 | Snapshot před hromadnými zápisy a „panic button“ (pozastavit všechny agenty) v jádru | po panice jsou všechna volání odmítnuta | 6 |  |

## M12 — Dokončení a vydání (váha 18)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M12-02.B | Výkon jádra a indexu proti rozpočtům | rozpočty splněny | 4 |  |
| M12-03 | Robustnost: plný disk, oprávnění, odpojený vault, poškozený frontmatter | testy chybových scénářů | 6 |  |
| M12-06 | Podpis, notarizace, `.dmg` (podle Developer ID) | instalovatelné čistým Macem | 6 |  |
| M12-07 | README, uživatelská příručka, zkratky | hotovo | 2 |  |

