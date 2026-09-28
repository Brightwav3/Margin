# UI — plán úkolů (`MarginUI` + `App/Margin`)

Větev **UI**: design systém, komponenty, shell, obrazovky, editor jako pohled, popupy, stavy a celá agentní část viditelná uživateli (nastavení agentů, review fronta, původ změn, chat).

**Jak se kontroluje:** vizuálně proti mockupům (`00-overview.md` §4): galerie `ScreenGallery`, `--screen <id>`, snapshoty v `docs/checks/`. Milestony se uzavírají až po schválení uživatelem.

**Vztah k backendu:** UI používá **jen protokoly z `09-contracts.md`**. Dokud není hotová skutečná služba, běží na `Fixture…` implementaci. `.U` úkol smí začít, až je hotové rozhraní jeho `.B` protějšku (sloupec „Závisí na“).

Značení: `M?-??` čistý UI úkol · `M?-??.U` UI část sdíleného úkolu · `AG-??` agentní úkol.

**Váha není čas.** Je to relativní složitost a riziko úkolu pro agenta (původní hodinové odhady pro člověka zachované jen jako měřítko). Orientace: **1–2** jeden agentní běh · **3–5** běh + iterace po testech · **6–8** víc iterací, rizikové místo · **10+** rozdělit. Skutečné omezení jsou lidské brány (schválení obrazovek, rozhodnutí), viz `11-schedule-and-gates.md`.

## Souhrn váhy (relativní složitost, ne čas)

| Milestone | Název | Váha |
|---|---|---|
| M0 | Kostra, tokeny, komponenty, galerie | 18 |
| M1 | Shell | 28 |
| M2 | Model a fixtures | 2 |
| M3 | Přehled předmětů (1a, 1b) | 29 |
| M4 | Detail předmětu (2c) | 27 |
| M5 | Vault a index | 1 |
| MA0 | Agent: základy (provenance, ID, undo, souběh) | 0 |
| M6a | Editor: source + reading | 33 |
| M6b | Editor: live | 25 |
| M7 | Úkoly | 22 |
| MA1 | Agent: povrch nástrojů (MCP, CLI) | 0 |
| M8 | Rychlý zápis a Inbox | 19 |
| MA2 | Agent: oprávnění, audit, schvalování | 43 |
| M9 | Graf | 27 |
| M10a | Popupy: navigace a psaní | 28 |
| MA3 | Agent v aplikaci | 25 |
| M10b | Popupy: data a organizace | 18 |
| M10c | Popupy: dialogy a oznámení | 22 |
| M11 | Obrazovky a stavy | 37 |
| MA4 | Agent: odolnost | 3 |
| M12 | Dokončení a vydání | 22 |
| **Σ** | | **429** |

## M0 — Kostra, tokeny, komponenty, galerie (váha 18)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M0-03 | `Tokens.swift`: barvy, velikosti písma, rádiusy, stíny podle `00-overview.md` | hodnoty se shodují s `margin-tokens.css` (test porovná hex hodnoty se seznamem) | 2 |  |
| M0-04 | Přibalení a registrace Inter (400/500/600/700), `Font.margin(size, weight)` | v galerii se vykreslí Inter, ne SF (kontrola tvaru „a“); OFL licence v repozitáři | 2 |  |
| M0-05 | `Icons.swift` + `scripts/gen-icons.sh`: Swift `Shape` generované z pinované verze Lucide (SVG), mapování Material názvů (60+) na Lucide, `Icon(name, size, weight)` | každé jméno použité v mockupu (skript vytáhne z HTML) má mapování nebo záznam v `DEVIATIONS.md`; ISC licence v repozitáři; ikony ostré při 16–30 px | 3 |  |
| M0-06 | Komponenty: `MarginButton` (primary/secondary/icon), `FilterChip`, `Badge`, `CheckboxView`, `SwitchView` | stavy: normal/hover/pressed/disabled/focus; rozměry podle mockupu | 4 |  |
| M0-07 | Komponenty: `CourseTile`, `Card`, `Segmented`, `PropertyRow`, `Divider` | vizuálně odpovídají sekci System | 2 |  |
| M0-08 | `ScreenGallery` (debug okno) a `--screen <id>` argument | seznam ID, klik otevře obrazovku 1240×820, argument funguje | 2 |  |
| M0-09 | `scripts/snap.sh` a `SnapshotTests` základ | `snap.sh M0-system` vytvoří PNG; test porovná s referencí | 2 |  |
| M0-10 | Uložit mockupy: `docs/checks/reference/` + `README` jak se vygenerují | referenční PNG pro sekci System jsou v repozitáři | 1 |  |

## M1 — Shell (váha 28)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M1-01 | **Prototyp titulkové lišty** (skrytý titulek, vlastní pohled, semafory) | okno s vlastní 44px lištou, semafory na místě, přetahování okna funguje, fullscreen OK | 4 |  |
| M1-02 | `WindowChrome`: šipky zpět/vpřed, tlačítko sbalení, tlačítko pravého panelu | tlačítka mají hover `#E9EAEE` rádius 6 | 3 |  |
| M1-03 | Záložky: model, vykreslení (188 px, rádius 9), zavírání, `+`, přetažení pro změnu pořadí | otevření/zavření/přeuspořádání; aktivní záložka splývá s obsahem | 5 |  |
| M1-04 | `Rail` 56 px: ikony s počty, kolečka předmětů, aktivní proužek, avatar | odpovídá `Sidebar.dc.html` (rozměry z kódu) | 3 |  |
| M1-05 | `SidebarPanel` navigace: hlavička, akční tlačítko, sekce a položky | aktivní položka `#E6EDFD`, počty vpravo, meta 12 px | 4 |  |
| M1-06 | Sidebar Notes: zpět-odkaz, hledání, filtry, skupiny; animovaný posuv (420 ms) | křivka odpovídá `cubic-bezier(.2,.8,.2,1)`; respektuje Reduce Motion | 3 |  |
| M1-07 | Sbalený sidebar (56 px) a stav v `AppModel` | přepínání ikonou i klávesou (⌘⌥S), stav se pamatuje | 2 |  |
| M1-08 | `InspectorPanel` 300 px + záložky `course`/`note` + generický řádek | přepínání záložek; prázdné záložky mají zástup | 3 |  |
| M1-09 | Snapshot shellu (bez obsahu) ve 4 konfiguracích | 4 PNG schváleny | 1 |  |

## M2 — Model a fixtures (váha 2)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M2-06 | `AppModel` kostra (`@Observable`), předání do galerie | galerie přepíná fixture ↔ prázdný stav | 2 |  |

## M3 — Přehled předmětů (1a, 1b) (váha 29)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M3-01 | `CourseCard` (banner 92, dlaždice 52 s prstencem, texty, další hodina, menu) | dle checklistu 1a | 5 |  |
| M3-02 | `CoursesGridView`: hlavička, Group by / Sort / New course, filtry | 3 sloupce, gap 16; layout se zalomí při zúžení | 5 |  |
| M3-03 | Seskupení podle fakulty (hlavičky skupin — návrh) | funguje; vzhled hlavičky schválen | 3 |  |
| M3-05.U | Výběr banneru (obrázek) a jeho uložení | banner se zobrazí a přežije restart | 2 | rozhraní `M3-05.B` + fixture |
| M3-06 | `TimetableView`: mřížka Po–Pá, osa hodin, bloky sessions | výška bloku = délka×56−6 | 6 |  |
| M3-07 | Čára „teď“, dnešní pozadí, navigace týdnů | čára přesně na fixture čase 13:24 | 3 |  |
| M3-08 | Napojení sidebaru (grid/timetable) a klik → otevřít předmět v záložce | funguje | 3 |  |
| M3-09 | Snapshoty 1a, 1b + `docs/checks/M3.md` | schváleno | 2 |  |

## M4 — Detail předmětu (2c) (váha 27)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M4-01 | Hlavička předmětu + Newest + New note | dle 2c | 3 |  |
| M4-02 | Filtry All/Lectures/Labs/Study notes | funguje | 2 |  |
| M4-03 | `LectureCard` (datum, druh, téma, meta, badge) + tři stavy okrajů | dle checklistu 2c | 5 |  |
| M4-04 | Galerie s `auto-fill minmax(260,1fr)` | reflow při změně šířky | 3 |  |
| M4-05 | **Návrh** přepínače stránek předmětu (Notes / Tasks / Exam prep / Grades) — mockup | schválený návrh (CP1) | 3 |  |
| M4-06 | Stránky Tasks a Exam prep (z fixtures `bioAssign`, `bioPrep`) | zobrazují váhu, termín, zdroj | 5 |  |
| M4-07 | Inspektor `course`: Coming up, Course info, Files | dle mockupu | 4 |  |
| M4-09 | Snapshot 2c + `docs/checks/M4.md` | schváleno | 2 |  |

## M5 — Vault a index (váha 1)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M5-10.U | Přepnutí galerie a M3/M4 z fixtures na vault + regresní snapshoty | pixelově shodné s M3/M4 snapshoty | 1 | rozhraní `M5-10.B` + fixture |

## M6a — Editor: source + reading (váha 33)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M6-01 | Prototyp `NSTextView` (TextKit 2) v `NSViewRepresentable`, načtení/uložení souboru | píše se, undo/redo, uložení 400 ms debounce | 5 |  |
| M6-02.U | `SyntaxStyler`: styly pro nadpisy, odrážky, kód, odkazy, frontmatter | inkrementální styling jen změněného rozsahu | 3 | rozhraní `M6-02.B` + fixture |
| M6-03 | **Source režim** (monospace 14, 1.75, barvy klíčů) | shodný s mockupem 3a source | 3 |  |
| M6-04 | **Reading režim** (vykreslený text, klikací checkboxy) | shodný s mockupem 3a reading | 6 |  |
| M6-05.U | Panel Properties (řádky, hodnoty, tagy, „Add property“) | zápis do frontmatteru; pořadí zachováno | 3 | rozhraní `M6-05.B` + fixture |
| M6-06 | Horní lišta (drobečky, ikony, přepínač režimu) | dle mockupu | 3 |  |
| M6-07 | Menu `…` (25 položek) a jejich zapojení (které jdou) | položky z jiných milestonů vypnuté s tooltipem | 4 |  |
| M6-08.U | Stavový řádek (backlinky, vlastnosti, slova, úkoly) | čísla se aktualizují ≤ 200 ms po psaní | 1 | rozhraní `M6-08.B` + fixture |
| M6-09.U | Inspektor `note`: Outline, Backlinks, Outgoing, All properties | klik v Outline skáče; nevytvořený odkaz má „+“ | 4 | rozhraní `M6-09.B` + fixture |
| M6-10 | Readable line length (700 px) přepínač | funguje a pamatuje se | 1 |  |

## M6b — Editor: live (váha 25)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M6-12.U | Model „aktivního bloku“ (blok pod kurzorem ukazuje zdroj) | přechod mezi bloky bez skoku kurzoru | 5 | rozhraní `M6-12.B` + fixture |
| M6-13 | Ztlumená syntaxe (`##`, `- [ ]` jako checkbox, `[[ ]]`) | dle 3a live | 8 |  |
| M6-14 | Klikací checkbox uvnitř textu bez ztráty výběru | test s výběrem přes více řádků | 4 |  |
| M6-15 | Kurzor a výběr při přepisu atributů (regresní sada 30 scénářů) | žádný skok kurzoru | 6 |  |
| M6-16.U | Výkon 10 000 slov | < 8 ms na klávesu | 2 | rozhraní `M6-16.B` + fixture |

## M7 — Úkoly (váha 22)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M7-01 | **Návrh** Today, Upcoming, Course tasks (mockupy) | schválený návrh (CP1) | 6 |  |
| M7-04 | `TaskRow` (checkbox, text, čip předmětu, termín, zdroj) | dle `dueWeek` | 4 |  |
| M7-05.U | Today: Overdue / Today + dnešní sessions | logika s `Clock`, testy | 2 | rozhraní `M7-05.B` + fixture |
| M7-06.U | Upcoming: dny, týden, později, zkoušky (`exams`) | seskupení testováno | 3 | rozhraní `M7-06.B` + fixture |
| M7-07 | Course tasks (Assignments, Exam prep) | váha %, „Graded 18/20“ | 4 |  |
| M7-08.U | Štítky termínů („Due Fri“, „Exam“) | pravidla: red = dnes/zítra/po termínu | 1 | rozhraní `M7-08.B` + fixture |
| M7-09.U | Klik na zdroj → skok na řádek v poznámce | otevře záložku a označí řádek | 2 | rozhraní `M7-09.B` + fixture |

## M8 — Rychlý zápis a Inbox (váha 19)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M8-02 | `NSPanel` overlay (nonactivating, střed), stavový model | otevře se < 120 ms | 5 |  |
| M8-03 | Zvýraznění tokenů v textu a čipy pod ním | dle 5a | 5 |  |
| M8-07 | Inbox 5a (seznam) | dle mockupu | 3 |  |
| M8-08.U | Inbox 5b (triage: Course, When, Keep as, Delete/Move) | přesun vytvoří úkol/poznámku ve správném místě | 5 | rozhraní `M8-08.B` + fixture |
| M8-09.U | „Add to lecture note“ (nejbližší přednáška) | řádek vložen do správné poznámky | 1 | rozhraní `M8-09.B` + fixture |

## MA2 — Agent: oprávnění, audit, schvalování (váha 43)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| AG-15 | Správa připojení: seznam spárovaných klientů, jejich povolené identity, poslední aktivita, odvolání | návrh schválen; odvolání okamžité | 8 |  |
| AG-16 | Review fronta (UI): seznam změn s diffem, Approve/Reject/Approve all from agent, filtry | návrh schválen; schválení se projeví v souboru | 10 |  |
| AG-17 | Původ změn v UI: značka u poznámek/úkolů změněných agentem, filtr „Změnil agent“, undo z UI | navrženo a schváleno; undo funguje | 6 |  |
| AG-18 | Aktivitní log (audit) jako obrazovka s filtry | zobrazuje `audit.jsonl`, filtr agent/předmět/čas | 5 |  |
| AG-35 | Správa identit: seznam, editor (název, popis, barva/avatar, profil, rozsah, limity, soukromí), šablony, statistiky aktivity | návrh schválen; vytvoření a úprava identity funguje | 8 |  |
| AG-36 | Schvalovací dialogy: párování klienta („Claude Code chce přístup“) a převzetí identity („chce převzít *Třídič inboxu*, účel: …“ → Povolit jednou / vždy pro tuto identitu / Zamítnout) | návrh schválen; volba se projeví v `ConnectionService`/`SessionService` | 6 |  |

## M9 — Graf (váha 27)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M9-03 | `Canvas` vykreslení uzlů/hran/popisků | dle 4a | 6 |  |
| M9-04 | Zoom, posun, fit-to-screen, pinch | plynulé, 60 fps @ 500 uzlů | 5 |  |
| M9-05 | Hover/klik, zvýraznění sousedů | dle mockupu | 3 |  |
| M9-06.U | Filtry (předměty, Show tasks, Orphan notes) | funkční | 3 | rozhraní `M9-06.B` + fixture |
| M9-07 | Náhled poznámky + Open | dle mockupu | 3 |  |
| M9-08.U | Lokální graf kolem poznámky + přepínač rozsahu | dle `lNodes` | 4 | rozhraní `M9-08.B` + fixture |
| M9-09.U | Optimalizace pro 5000 uzlů (LOD popisků) | ≥ 30 fps | 3 | rozhraní `M9-09.B` + fixture |

## M10a — Popupy: navigace a psaní (váha 28)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M10-00 | `PopoverHost` + klávesnice (šipky/Enter/Esc), společný stín a rádius | základ použitelný všemi popupy | 5 |  |
| M10-02.U | **1a** Command palette ⌘K | najde poznámku a příkazy, Esc zavře | 4 | rozhraní `M10-02.B` + fixture |
| M10-03.U | **1c** Autocomplete po `[[` | vloží odkaz, umí vytvořit novou poznámku | 3 | rozhraní `M10-03.B` + fixture |
| M10-04.U | **2a** Slash příkazy | `/task` vloží `- [ ]` | 3 | rozhraní `M10-04.B` + fixture |
| M10-05.U | **2b** Náhled odkazu při najetí | zobrazí úryvek cíle do 150 ms | 3 | rozhraní `M10-05.B` + fixture |
| M10-06 | **1d** Výběrová lišta (stub agent) | tlačítka mají zástupnou akci | 4 |  |
| M10-07 | **3d** Agent navrhuje odkazy (stub) | „Vložit odkaz“ funguje | 4 |  |
| M10-08 | Snapshoty a kontrola M10a | schváleno | 2 |  |

## MA3 — Agent v aplikaci (váha 25)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| AG-22 | Záložka Agent v inspektoru (chat, streamování, citace, tlačítka návrhů) | dle mockupu; funguje se streamem | 12 |  |
| AG-23 | Výběrová lišta 1d reálně: Explain, Flashcards, Summarize → výsledek jako návrh do fronty | akce vytvoří `ProposedChange` | 6 |  |
| AG-24 | „Agent navrhuje odkazy“ 3d reálně | návrhy jdou vložit jedním klikem | 4 |  |
| AG-25 | ⌘K: „Zeptat se agenta“ a spuštění skills | skills jsou v paletě | 3 |  |

## M10b — Popupy: data a organizace (váha 18)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M10-09.U | **1e** Add property – výběr typu | zapíše do frontmatteru | 4 | rozhraní `M10-09.B` + fixture |
| M10-10.U | **1f** Výběr termínu u úkolu | zapíše `@ …` do řádku | 4 | rozhraní `M10-10.B` + fixture |
| M10-11.U | **2c** Move note to… | přesun souboru + aktualizace odkazů | 2 | rozhraní `M10-11.B` + fixture |
| M10-12.U | **2f** Kontextové menu předmětu | akce fungují (přejmenovat, barva, archivovat) | 3 | rozhraní `M10-12.B` + fixture |
| M10-13.U | **3a** Archive semester | přesun do `_archive/`, jen čtení | 2 | rozhraní `M10-13.B` + fixture |
| M10-14.U | **3c** Reschedule/cancel session | změna se propíše do rozvrhu a karty | 2 | rozhraní `M10-14.B` + fixture |
| M10-15 | Snapshoty a kontrola M10b | schváleno | 1 |  |

## M10c — Popupy: dialogy a oznámení (váha 22)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M10-16.U | **1g** New course dialog | vytvoří složku + `_course.md`, objeví se v railu | 4 | rozhraní `M10-16.B` + fixture |
| M10-17 | **1h** Delete confirmation | do koše macOS | 2 |  |
| M10-18.U | **1i** Toasty + notifikace 10 min před hodinou | `UNUserNotificationCenter`, testováno posunutými hodinami | 3 | rozhraní `M10-18.B` + fixture |
| M10-19.U | **2d** Import ze sylabu — UI a ruční úpravy (parsování PDF stub) | seznam sessions lze upravit a uložit | 4 | rozhraní `M10-19.B` + fixture |
| M10-20.U | **2e** Enter a grade | zapíše do `_grades.md` | 2 | rozhraní `M10-20.B` + fixture |
| M10-21.U | **2g** Settings › Editor napojené | změny se projeví v editoru | 3 | rozhraní `M10-21.B` + fixture |
| M10-22.U | **3b** Share/Export (export PDF+MD reálně, sdílení UI) | PDF a MD export ověřen | 2 | rozhraní `M10-22.B` + fixture |
| M10-23 | Snapshoty a kontrola M10c | schváleno | 2 |  |

## M11 — Obrazovky a stavy (váha 37)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M11-01.U | Grades (1e): model, vážený průměr, obrazovka | testy výpočtu (10 případů), dle mockupu | 4 | rozhraní `M11-01.B` + fixture |
| M11-02.U | Onboarding (1a): průvodce, vytvoření semestru | nový uživatel dojde k prázdnému předmětu | 7 | rozhraní `M11-02.B` + fixture |
| M11-03.U | Search results (1b) s filtry | filtry předmět/typ/datum/tag; zvýraznění shod | 5 | rozhraní `M11-03.B` + fixture |
| M11-04.U | Past semesters (1f) | otevření archivu jen čtení | 3 | rozhraní `M11-04.B` + fixture |
| M11-05.U | Settings › Semesters (1g) + okno Settings (zkratky, vault, vzhled) | změny se ukládají | 5 | rozhraní `M11-05.B` + fixture |
| M11-06 | Empty course (2a) a Empty inbox (2b) | zobrazí se při prázdných datech | 4 |  |
| M11-07.U | Loading (2c) při prvním indexování | zobrazí se při studeném indexu | 2 | rozhraní `M11-07.B` + fixture |
| M11-08.U | Version history (2e): snapshoty, diff, obnovení | obnovení nic nemaže; test 20 verzí | 4 | rozhraní `M11-08.B` + fixture |
| M11-09 | Snapshoty a kontrola M11 | schváleno | 3 |  |

## MA4 — Agent: odolnost (váha 3)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| AG-30 | Indikátor aktivity agentů v liště a panic button v UI | stav viditelný; obnova jen člověkem | 3 |  |

## M12 — Dokončení a vydání (váha 22)

| ID | Úkol | Akceptační kritérium | Váha | Závisí na |
|---|---|---|---|---|
| M12-01 | Přístupnost: VoiceOver popisky, focus ring, klávesnice, Reduce Motion | audit projde bez kritických nálezů | 8 |  |
| M12-02.U | Výkon: měření proti rozpočtům, opravy | všechny rozpočty splněny | 4 | rozhraní `M12-02.B` + fixture |
| M12-04 | UI smoke testy (XCUITest, 6–8 scénářů) | zelené | 5 |  |
| M12-05 | Ikona aplikace, název, About | hotovo | 3 |  |
| M12-08 | Závěrečná revize proti mockupům, `DEVIATIONS.md` | schváleno uživatelem | 2 |  |

