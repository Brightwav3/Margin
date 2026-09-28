# Část 1: M0–M5 — základ, shell, data, předměty

Milestony se neměří v lidských dnech. Práci dělají agenti; omezením jsou lidské schvalovací brány (viz `11-schedule-and-gates.md`).

---

## M0 — Kostra, tokeny, komponenty, galerie

**Co se staví**
- Swift Package + Xcode aplikace, `arm64`, hardened runtime, sandbox se souhlasem k výběru složky.
- `Theme`: barvy, velikosti písma, rádiusy, stíny podle `00-overview.md`. Písmo Inter přibalené a registrované (`ATSApplicationFontsPath`).
- `Icons.swift` + skript `scripts/gen-icons.sh`: z pinované verze Lucide (SVG) se vygenerují Swift `Shape` pro ~60 ikon použitých v mockupu; mapování Material názvů → Lucide (eco → `leaf`, science → `flask-conical`, event → `calendar`, …). Tloušťka čáry 1.5–2 podle velikosti, zaoblené konce jako v Lucide.
- Komponenty: `MarginButton` (primary modrá 40 px, secondary s okrajem, ikonový 40×40), `FilterChip` (aktivní `#E6EDFD`/`#2457D6`, neaktivní s okrajem, výška 34), `Badge` (danger „Exam“, warning „Due Fri“, success), `CheckboxView` 16 px, `SwitchView` 36×20, `CourseTile` (pastelová dlaždice s ikonou), `Card`, `Segmented` (Task/Note), `PropertyRow`.
- `ScreenGallery` (debug okno) a argument `--screen <id>`.

**Funguje**: aplikace se spustí, galerie zobrazí komponenty na plátně `#E4E5E9`.

**Vizuální kontrola** — `Margin.dc.html` sekce **System**:
- [ ] 4 karty: Type (30/20/17/15/13/12), Neutrals and accent (8 vzorků), Course tiles (6× 56 px, rádius 12), Controls.
- [ ] Inter se opravdu načetl (ne systémový SF): porovnat tvar „a“ a „1“.
- [ ] Modré tlačítko: výška 40, rádius 8, padding 0 16, text 15/500.

---

## M1 — Shell: okno, rail, sidebar, inspektor

**Co se staví** (`Sidebar.dc.html`, `Inspector.dc.html`)
- `WindowChrome` (AppKit): okno s vlastní 44px titulkovou lištou, semafory, šipky zpět/vpřed, tlačítko sbalení sidebaru, **záložky** (šířka 188, horní rádius 9, tečka barvy předmětu, zavření u aktivní), `+`, tlačítko pravého panelu.
- `Rail` 56 px: horní ikony (Home, Inbox s modrou tečkou, Graph, …), oddělovač, kolečka předmětů 36 px s aktivním proužkem 4×20, dole nápověda a avatar „AK“.
- `SidebarPanel`: hlavička s názvem a hledáním, tlačítko akce s klávesou, sekce s položkami (ikona nebo tečka, titulek, meta, počet). Dvě stránky: navigace a **Notes** (posuv 420 ms `cubic-bezier(.2,.8,.2,1)`), zpět-odkaz, hledání „Search notes… ⌘K“, filtry All/Lectures/Tasks, skupiny „This week / Last week“.
- Sbalený režim (56 px) pro 4a, 5b.
- `InspectorPanel` 300 px: záložky (course: Agent, Coming up, Course info, Files · note: Agent, Outline, Backlinks, Outgoing links, All properties), obsah řádků `r(title, meta, icon, count)`.
- Stav v `AppModel`: otevřené záložky, aktivní, sbalení levého a pravého panelu.

**Funguje**: sbalení/rozbalení obou panelů, přepnutí záložky, přepnutí sidebaru mezi navigací a Notes, přepínání záložek Inspektoru.

**Vizuální kontrola** — samotný shell se prázdným obsahem v rozměru 1240×820 a s rámem `.dv-card`:
- [ ] Rail 56 px, sidebar 276 (bez spaces) / 336 (se spaces), inspektor 300.
- [ ] Bílá „karta“ obsahu s okrajem `#E9EAEE` a rádiusem 12 od x=56, y=44.
- [ ] Aktivní položka sidebaru: pozadí `#E6EDFD`, text `#2457D6`; tab: tečka 7 px.
- [ ] Animace posuvu sidebaru (Notes) a sbalení: zkontrolovat vedle mockupu, ne jen statický snímek.

---

## M2 — Doménový model a fixture data

**Co se staví** (`MarginCore/Model`)
- `Semester` (Fall 2026, týden 5 z 14, pondělí 28. 9. 2026), `Faculty` (Sciences, Humanities), `Course` (id, kód, vyučující, místnost, ikona, barva, fakulta, hodnocení), `Session` (den, začátek, délka, typ Lecture/Lab/Seminar/Tutorial), `Note` (typ, titulek, datum, kurz, vlastnosti, text), `TaskItem` (text, termín, štítek, zdroj = poznámka, hotovo), `Grade`, `InboxItem`.
- `Fixtures.week5`: 6 předmětů, rozvrh (11 sessions z konstanty `SES`), `DUE` (6 úkolů), zkoušky, galerie Bio (6 karet), poznámky, inbox (5), uzly grafu (23) a hrany.
- Injektovatelné hodiny: `Clock` s pevným „teď“ = pondělí 28. 9. 2026 13:24 (čára v rozvrhu je na 13.4).

**Vizuální kontrola**: žádná; unit testy kontrolují počty a datumy (11 sessions, 5. týden, 3 zkoušky). Důležité, protože všechny další kontroly stojí na těchto datech.

---

## M3 — Přehled předmětů: 1a mřížka a 1b rozvrh

**Co se staví**
- **1a** `CoursesGridView`: titulek „Your courses“ + „Fall 2026 · Week 5 of 14“, Group by (Faculty), Sort, New course; filtry All/Sciences/Humanities; mřížka 3 sloupce, gap 16; karta: banner 92 px (barva předmětu), dlaždice 52 s bílým prstencem 3 px, název 17/600, „14 notes · A−“, `…` menu, řádek „Tue 10:00 · Lecture 9 · Membrane transport“ s hodinami; první karta má rámeček 1.5 px modrý.
- Seskupování podle fakulty, řazení, filtr — reálně funkční nad daty.
- **Banner obrázek**: slot `image-slot` z mockupu → výběr obrázku pro banner (uloží se do vaultu). Do té doby barevná plocha.
- **1b** `TimetableView`: „Week 5 / 28 Sep – 2 Oct · 11 sessions“, šipky a „This week“, 5 sloupců Po–Pá, osa 9:00–18:00 (56 px/h), bloky sessions barvou předmětu, dnešek s pozadím `#F7F9FE`, červená čára „teď“; klik na blok otevře přednášku.
- Režim „karty × rozvrh“ přepíná sidebar (`view=grid|timetable`).

**Funguje**: přepnutí mřížka/rozvrh, filtr fakulty, seskupení, řazení, přechod týdnů (data jen pro 5. týden, jiné týdny prázdné), klik na kartu otevře záložku předmětu.

**Vizuální kontrola** — `1a`, `1b`:
- [ ] 1a: 3 sloupce, banner 92, dlaždice 52 s přečnívajícím prstencem, zalomení dlouhých názvů, ellipsis na řádku „next“.
- [ ] 1a: skupinové hlavičky fakult (v mockupu Group by je jen ovládací prvek → navrhnout vzhled hlavičky skupiny a odsouhlasit).
- [ ] 1b: výška bloku = délka × 56 − 6, barvy z předmětu, čára „teď“ přesně na 13:24, popisky hodin vystředěné na čáře.
- [ ] Obě obrazovky vedle mockupu při šířce 1240 a při zúžení na 900 (mřížka se má zalomit na 2 sloupce — v mockupu nespecifikováno, odsouhlasit).

---

## M4 — Detail předmětu: 2c galerie přednášek + inspektor

**Co se staví**
- `CourseView`: titulek „Cell Biology“, řádek „BIO 201 · Dr. Okafor · 16 sessions · A− 91%“, řazení „Newest“, New note; filtry All/Lectures/Labs/Study notes.
- Galerie: `repeat(auto-fill, minmax(260, 1fr))`, karta = datum (tučně, modře u nadcházející) + „· Lecture 8“, `…`, téma 20/600, meta, badge „2 open“ (warning) / „Done“ (success); nadcházející karta s čárkovaným okrajem („vytvořeno z rozvrhu“); vybraná s modrým rámečkem.
- **Poznámky z přednášek = denní poznámky navázané na hodinu**: rozvrh (M2) při otevření dne vytvoří kartu bez souboru; soubor vznikne při prvním psaní.
- Inspektor `view=course`: Coming up (Midterm 3d, Problem set 3 4d, Lecture 9 1d), Course info (vyučující, konzultace, sessions, průběžná známka), Files.
- Záložky předmětu zmíněné v zadání: úkoly, příprava na zkoušky, poznámky, známky. Mockup 2c ukazuje jen galerii poznámek; ostatní stránky předmětu (Tasks, Exam prep, Grades) jsou v `bioAssign`/`bioPrep`/`gradeParts` datech. **Navrhnout jako segmentovaný přepínač pod titulkem a odsouhlasit vzhled** (viz Otevřené otázky).

**Funguje**: filtr karet, řazení, klik otevře poznámku (zatím prázdný editor z M6), New note vytvoří kartu, Inspektor přepíná záložky.

**Vizuální kontrola** — `2c`:
- [ ] Karta: padding 16, gap 10, rádius 12, okraje (běžný `#E4E5E9`, vybraný 1.5 modrý, nadcházející 1 čárkovaný `#C4C7CF`).
- [ ] Téma 20/600 s tracking −0.3, datum 13/600, meta 12 šedá.
- [ ] Pravý inspektor 300 px, záložka „Coming up“ aktivní, vzdálenosti „3d/4d/1d“ zarovnané vpravo.
- [ ] Hlavička s pravou akcí: „Newest“ (ohraničené) + „New note“ (modré).

---

## M5 — Soubory na disku: vault, frontmatter, index

**Před startem rozhodnout**: umístění vaultu, kompatibilita s Obsidianem (Otázka 1).

**Co se staví** (`MarginCore/Vault`, `Markdown`)
- Struktura: `Vault/Cell Biology/Lecture 8 — Cell membrane.md`, `Vault/_inbox/…`, `Vault/.margin/` (index cache, nastavení, semestry).
- `Frontmatter` čtení a zápis (YAML podmnožina: date, class `"[[Cell Biology]]"`, tags, type, due, weight), zachování neznámých klíčů a pořadí.
- `TaskExtractor`: `- [ ]` / `- [x]`, termíny `@ Tue`, `@before-midterm`, `@2026-10-02`, štítky Exam/Due; vazba na zdrojovou poznámku a řádek.
- `WikilinkExtractor`: `[[Note]]`, `[[Note|alias]]`, nevytvořené cíle (Outgoing links „Not created yet“), backlinky s kontextem řádku.
- `NoteIndex`: inkrementální index v paměti, přestavba při změně souboru.
- `FileWatcher` (FSEvents), uložení atomicky, konflikt: externí změna při otevřeném editoru → banner, ne přepsání.
- Migrace fixture dat: `Fixtures.week5` umí vygenerovat ukázkový vault na disk (tlačítko „Vytvořit ukázkový semestr“).

**Funguje**: aplikace otevře vault, karty v M3/M4 se plní ze souborů; úprava souboru v jiném editoru se projeví ≤1 s; smazání a přejmenování nerozbije odkazy.

**Vizuální kontrola**: beze změny oproti M3/M4 — přepnout galerii z fixture na vault a **ověřit, že snímky 1a/1b/2c jsou pixelově shodné** (regrese). Navíc testy: 30+ unit testů parseru (frontmatter, úkoly, odkazy, okrajové případy: prázdný soubor, CRLF, emoji, `[[a|b]]`).
