# Část 3: M10–M12 — popupy, zbylé obrazovky a stavy, dokončení

Zdroj: `margin-popups.dc.html` (ID 1a–1i, 2a–2g, 3a–3d), `Margin Menus.dc.html` (menu a tooltipy, M10d) a `Margin Screens.dc.html` (1a, 1b, 1e, 1f, 1g, 2a, 2b, 2c, 2e).

---

## M10 — Popupy a překryvy

Společný základ: `PopoverHost` (AppKit `NSPopover`/`NSPanel` podle případu), stín `0 12 32 .16`, rádius 10–16, klávesnice (šipky, Enter, Esc), vnitřní stav testovatelný bez UI.

### Skupina A — navigace a psaní
| ID | Popup | Poznámky |
|---|---|---|
| 1a | **Command palette ⌘K** | Hledání poznámek a příkazů, skupina „Notes“, `esc`. Napojit na **SQLite FTS5 index** (text + titulky). |
| 1c | **Autocomplete po `[[`** | Návrhy z `NoteIndex`, vložení `[[Cíl]]`, možnost vytvořit novou. |
| 2a | **Slash příkazy po `/`** | Sekce Blocks: Task `- [ ]`, nadpis, odrážka, … vloží markdown. |
| 2b | **Náhled odkazu při najetí** | Kartička s úryvkem cílové poznámky. |
| 1d | **Výběrová lišta** | Explain, Flashcards… V M10 zástupná akce, reálně napojená v MA3 (AG-23). |
| 3d | **Agent navrhuje odkazy** | UI se zástupnými návrhy (M10), reálně napojené v MA3 (AG-24). |

### Skupina B — vlastnosti, data, organizace
| ID | Popup | Poznámky |
|---|---|---|
| 1e | **Add property – výběr typu** | date / text / tags / number / checkbox; zapisuje frontmatter (M5). |
| 1f | **Výběr termínu u úkolu** | Kalendář + rychlé volby (Today, Tomorrow, Before next lecture), zapíše `@ …` do řádku. |
| 2c | **Move note to…** | Strom Semestr › Předmět; přesun souboru. |
| 2f | **Kontextové menu předmětu** (pravý klik) | Archivovat, přejmenovat, barva, …. |
| 3a | **Archive semester** | Potvrzení „Archive Fall 2026?“ (končí posledním exámem). |
| 3c | **Reschedule / cancel session** | Změna času/místnosti, zrušení jedné hodiny. |

### Skupina C — dialogy a oznámení
| ID | Popup | Poznámky |
|---|---|---|
| 1g | **New course** | Název, kód, vyučující, barva/ikona, fakulta, rozvrh; vytvoří složku v vaultu. |
| 1h | **Delete confirmation** | „Delete “Lecture 8 — Cell membrane”?“ → do koše macOS, ne nevratně. |
| 1i | **Toasty a připomínka přednášky** | „Cell Biology · in 10 min“; napojení na `UNUserNotificationCenter` (lokální notifikace 10 min před hodinou). |
| 2d | **Import z sylabu** | „Found 16 sessions“; výběr PDF a kontrola nalezených termínů; **parsování PDF je stub** (viz otázka 3) — UI + ruční úpravy, automatické rozpoznání později. |
| 2e | **Enter a grade** | „Add grade · 10 %“, ukládá do `Grade` (M11 známky). |
| 2g | **Settings › Editor** | Readable line length, písmo, tabulátory; napojit na skutečná nastavení editoru. |
| 3b | **Share / Export** | Export do PDF a Markdown funguje, „Add classmates by…“ jen UI (sdílení je mimo rozsah). |

### Skupina D — menu, dropdowny a tooltipy (`Margin Menus.dc.html`)
Jeden povrch pro všechna menu (4a: řádky, zkratky, podmenu, zaškrtnutí, destruktivní a vypnuté položky); dropdowny jsou ukotvené ke spouštěči, kontextová menu u kurzoru. Tooltipy tmavé pro krátké popisky, bílé hover karty pro obsah.

| ID | Co | Poznámky |
|---|---|---|
| 1a–1r | **Kontextová menu** (pravý klik) | Poznámka a složka v sidebaru, editor (bez výběru, s výběrem, odkaz, úkol, nadpis, obrázek, tabulka), záložka, hodina v rozvrhu, kartička, tag, prázdné místo sidebaru, odpověď agenta, známka, výsledek hledání, více poznámek. Menu předmětu zůstává 2f z popupů. |
| 2a–2i | **Dropdowny** | Řazení, `⋯` poznámky, výběrové pole, výběr s hledáním, oprávnění, split button, účet, vícenásobný filtr, styl textu. |
| 3a–3i | **Tooltipy a hover karty** | Popisek + zkratka (4 umístění), vysvětlení, celý název zkráceného textu, proč je tlačítko vypnuté, karta předmětu, tip z onboardingu, validace, hodnota v grafu, zdroj agenta. |
| 4a | **Stavy a rozměry řádků** | Základ `MarginMenu` (M10-24). |
| 5a–5k | **Menu bar** (`Margin Menu Bar.dc.html`) | Systémová lišta nabídek jen s textem: Margin, File, Edit, View, Insert, Format, Note, Go, Agent (šedé do MA3), Window, Help se zkratkami; Help hledá příkazy. |

Akce bez hotové služby jsou vypnuté s tooltipem 3d; zapnou se s milestonem, který službu dodá.

**Funguje**: ⌘K najde poznámku a otevře ji; `[[` nabídne návrhy; `/task` vloží úkol; datum u úkolu se propíše do souboru; nový předmět se objeví v railu; smazání jde do koše; notifikace přijde 10 min před hodinou.

**Vizuální kontrola** — každý popup jako samostatný snímek přes `popups/<id>`:
- [ ] Všechny popupy 1a–1i, 2a–2g, 3a–3d v galerii, velikost, rádius a stín podle mockupu.
- [ ] Klávesové ovládání každého (šipky/Enter/Esc) — checklist v `docs/checks/M10.md`.
- [ ] Kontrola v kontextu: popup nad správnou obrazovkou (např. 1c nad editorem, 1f nad úkolem).
- [ ] M10d: všechna menu 1a–1r, dropdowny 2a–2i a tooltipy 3a–3i v galerii (`menus/<id>`), řádky podle 4a; pravý klik v kontextu otevře správné menu.

**Rozdělení**: čtyři pod-milestony M10a/b/c/d podle skupin, každý s vlastní kontrolou.

---

## M11 — Zbylé obrazovky a stavy

Zdroj `Margin Screens.dc.html`.

| ID | Obrazovka | Obsah |
|---|---|---|
| 1a | **Onboarding: první semestr** | Průvodce: název semestru, začátek/konec, předměty (i import ze sylabu z M10/2d), umístění vaultu. Vytvoří `Vault/.margin/semesters`. |
| 1b | **Výsledky hledání s filtry** | Plnohodnotná stránka (ne popup): filtry předmět/typ/datum/tag, zvýrazněné shody, úryvky. Rozšíření FTS5 z M10. |
| 1e | **Grades** | Známky napříč semestrem: tabulka předmětů se složkami (Problem sets 20 %, Lab reports 25 %, Midterm 25 %, Final 30 %), průběžná známka `A− 91 %`, progress s váhou. Výpočet váženého průměru v `MarginCore` s testy. |
| 1f | **Past semesters (archive)** | Seznam uzavřených semestrů, znovuotevření (jen čtení). |
| 1g | **Settings › Semesters** | Správa semestrů (přidat, archivovat, upravit termíny), přepnutí aktivního. |
| 2a | **Prázdný předmět** | Právě vytvořený: nápověda „Import syllabus / Create first note“. |
| 2b | **Prázdný Inbox** | „Inbox zero“ stav. |
| 2c | **Načítání: první sync na novém zařízení** | Skeleton/spinner. Skutečný sync mimo rozsah, obrazovka je pro indexaci a první načtení vaultu (M5) — použít při prvním indexování. |
| 2e | **Version history** | Seznam verzí poznámky s diffem. Implementace přes `Vault/.margin/history/` (snapshot při uložení, max N), obnovení verze. |

Navíc: nastavení aplikace (zkratky, vault, vzhled editoru) jako jedna okna Settings s tématy podle mockupu 2g.

**Funguje**: nový uživatel projde onboardingem, vytvoří semestr a předmět, zapíše grade, uvidí průměr; historie verzí obnoví starý text; archivovaný semestr je jen pro čtení.

**Vizuální kontrola** — `screens/1a…2e`:
- [ ] Všech 9 obrazovek v galerii odpovídá mockupům podle checklistu (rozměry, barvy, mezery).
- [ ] Grades: proužky s váhou, zarovnání čísel (tabular numerals).
- [ ] Prázdné stavy a načítání se opravdu zobrazí (vynutit testovacím přepínačem `--state empty|loading` v galerii).

---

## M12 — Dokončení a vydání

- **Přístupnost**: VoiceOver popisky, focus ring `0 0 0 3 #CFDDFB`, kontrast textu (terciární `#9A9DA6` na bílé je < 4.5:1 — použít jen pro meta, ne pro nutné texty), plná klávesnice, respekt k „Reduce motion“ (posuv sidebaru).
- **Výkon**: start < 1 s s vaultem 1000 poznámek, index inkrementální, psaní bez lagu, graf 60 fps.
- **Robustnost**: chyby souborového systému (plný disk, oprávnění), poškozený frontmatter, ztráta vaultu (odpojený disk), autosave a ochrana proti ztrátě textu.
- **Testy**: `MarginCoreTests` (parser, index, capture, známky), snapshot testy klíčových obrazovek proti schváleným snímkům z `docs/checks/`, UI smoke test.
- **Balení**: ikona aplikace, jméno, podpis a notarizace (potřeba Developer ID — otázka pro vás), `.dmg`, jen `arm64`.
- **Dokumentace**: README (spuštění, struktura vaultu, klávesové zkratky), `docs/checks/` archiv.
- Závěrečná **vizuální revize všech obrazovek** proti mockupům, seznam vědomých odchylek.

---

## Souhrn: pořadí a závislosti

| Milestone | Obsah | Závisí na |
|---|---|---|
| M0 | Kostra, tokeny, komponenty, galerie | — |
| M1 | Shell (okno, rail, sidebar, inspektor) | M0 |
| M2 | Model a fixture data | M0 |
| M3 | Předměty: mřížka + rozvrh (1a, 1b) | M1, M2 |
| M4 | Detail předmětu (2c) | M3 |
| M5 | Vault, frontmatter, index | M2 |
| M6 | Editor (3a) | M1, M5, MA0 |
| M7 | Úkoly: Today, Upcoming | M5, M6 |
| M8 | Rychlý zápis + Inbox (5a, 5b) | M5, M7 |
| M9 | Graf (4a) | M5 |
| M10 | Popupy (a/b/c) | M6, M8 |
| M11 | Screens a stavy | M7, M10 |
| M12 | Dokončení, balení | vše |

Agentní milestony MA0–MA4 a přesné vlny: `10-agent-native.md`, `11-schedule-and-gates.md`.

Po M4 lze poprvé ukázat „aplikace vypadá jako mockup“ (fixture data). Po M6 je použitelný editor. Po M8 aplikace splňuje jádro zadání (úkoly z poznámek, rychlý zápis, Inbox). M9–M11 doplňují zbytek.

## Rizika
1. **Editor (M6)**: TextKit 2 a styling v živém režimu. Mitigace: nejdřív source + reading, live později.
2. **Vlastní titulková lišta se záložkami (M1)** v AppKit — vyžaduje `NSTitlebarAccessoryViewController` nebo skrytý titulek s vlastním pohledem. Ověřit prototypem v M1 hned první den.
3. **Globální zkratka a sandbox (M8)** — sandbox může omezit; řešení: zkratka přes `RegisterEventHotKey` (nevyžaduje oprávnění přístupnosti).
4. **Rozsah funkcí naznačených jen v UI** (sdílení, sylabus PDF, sync): držet jako stuby. Agent stub není — je řešen v milestonech MA0–MA4 (`10-agent-native.md`).
5. **Nejednoznačnosti mockupu**: Today/Upcoming a záložky předmětu (Tasks, Exam prep, Grades) nejsou nakreslené — před M4 a M7 schválit rychlý návrh.
