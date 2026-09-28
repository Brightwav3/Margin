# Část 2: M6–M9 — editor, úkoly, rychlý zápis, graf

---

## M6 — Markdown editor: 3a, tři panely (nejrizikovější)

**Technika**: AppKit `NSTextView` na **TextKit 2** zabalený do `NSViewRepresentable`. Zvýraznění syntaxe přes atributovaný řetězec počítaný nad `MarkdownParser` (jen pro viditelný rozsah, inkrementálně). Žádný WebView.

**Co se staví**
- **Live režim** (výchozí): syntaxe zůstává vidět, ale ztlumená (`#C4C7CF`): `##` před nadpisem, `- [ ]` jako klikací checkbox, `[[odkaz]]` modře s ztlumenými závorkami. Blok pod kurzorem ukazuje zdroj, ostatní bloky stylované.
- **Source režim**: monospace 14 px, řádek 1.75, zvýraznění klíčů frontmatteru (`#2457D6`), `---` šedé.
- **Reading režim**: vykreslený text bez zdroje, vlastnosti nahoře, checkboxy klikací.
- Nadpis 30/700 (H1), 20/600 (H2), tělo 17/1.6, odrážky s tečkou šedé, kurzor modrý 2 px.
- **Vlastnosti** (panel „Properties“): řádky s ikonou a hodnotou — date (dd.mm.yyyy s tečkami `#C4C7CF`), class (`+Cell Biology` odkaz), tags (chipy `#E6EDFD`), „Add property“; editace přímo v řádku (typový picker je v M10/1e).
- **Horní lišta editoru**: „Edited 10:24“, drobečky „• Cell Biology / Lecture 8“, ikony (text_fields, link, přepínač režimu, menu `…`).
- **Menu `…`** (250 px, 25 položek ze `noteMenu`): Reading view, Source mode, Readable line length (700 px vs. plná šířka), Split right/down, Rename…, Move file to…, Export to PDF…, Find/Replace, Copy path, Version history, Reveal in Finder, Delete file (červeně). Položky, které patří jiným milestonům, se zapojí tam a do té doby jsou vypnuté s tooltipem.
- **Stavový řádek** vpravo dole: „3 backlinks · 3 properties · 412 words · 2 open tasks → Today“.
- **Inspektor `view=note`**: Outline (klik skočí na nadpis), Backlinks s kontextem, Outgoing links (i nevytvořené s „+“), All properties (počty napříč vaultem).
- Undo/redo, uložení s debouncingem 400 ms, čtení externích změn (M5).
- Typografie: `ui-monospace` → SF Mono, Inter pro tělo.

**Funguje**: otevřít Lecture 8, psát, přepnout tři režimy, zaškrtnout úkol (změní se `- [ ]` na `- [x]` v souboru), přidat vlastnost, kliknout na `[[Membrane transport]]` a otevřít cíl v nové záložce, backlinky se aktualizují.

**Vizuální kontrola** — `3a` ve třech režimech + menu otevřené:
- [ ] Editor uprostřed, max 700 px při zapnuté „Readable line length“, jinak celá šířka; padding 18/32.
- [ ] Živý režim: `##` šedé před „Fluid mosaic model“, modrý kurzor za nadpisem.
- [ ] Panel Properties: sloupec názvů 160 px, řádek min. 32 px, „Add property“.
- [ ] Úkolové řádky: štítek „Tue“ šedý na `#F3F4F6`, „Before midterm“ červený na `#FCECEC`.
- [ ] Zdrojový režim: přesně obsah ze snímku (frontmatter, `- [ ]`, `@ Tue`).
- [ ] Menu 250 px, položka 30 px, oddělovače, „Delete file“ červeně.
- [ ] Spodní stavový pruh: rádius 10 vlevo nahoře, okraj `#E9EAEE`.
- Chování: složitý zdroj (10 000 slov, tabulky, kód) bez laggu psaní; kurzor se nepřeskočí při přepisu stylů.

**Riziko a odbytí**: pokud live režim potřebuje víc než 3 kola iterace, dodat nejdřív source + reading, live jako druhé kolo. Rozhodnout po prvních 3 iteracích.

---

## M7 — Úkoly z poznámek: Today, Upcoming, úkoly předmětu

Mockup tyto pohledy **nemá** (jen zmínka v zadání a `DUE` seznam v datech, vzhled Today je odvozený z Things 3 a řádků `dueWeek`). Před stavbou udělat rychlý návrh jedné obrazovky a nechat schválit.

**Co se staví**
- `TasksStore` nad `NoteIndex`: každé `- [ ]` v jakékoli poznámce = úkol. Zaškrtnutí kdekoli (seznam, editor, inspektor) přepíše zdrojový soubor.
- **Today**: úkoly s termínem dnes + po termínu (červeně) + dnešní sessions z rozvrhu; sekce „Overdue / Today / This evening“ (je-li čas).
- **Upcoming**: seskupení po dnech, tento týden, později; **exams** jako karty (měsíc + den, „25 %“) z `exams` v datech.
- **Úkoly předmětu**: Assignments (váha %, termín, „Graded 18/20“), Exam prep (`from: Lecture 7`, Exam prep) — data `bioAssign`, `bioPrep`.
- Řádek úkolu: checkbox 16, text 15, čip předmětu (dot + kód), termínový štítek („Due Fri“ warning, „Exam“ danger, „Today/Tomorrow“ červeně), zdroj „from Lecture 8“, klik = přechod na řádek v poznámce.
- Parsování termínů: `@ Tue`, `@ tomorrow`, `@2026-10-02`, `@before-midterm` → navázání na exam předmětu.
- Zaškrtnutí s jemnou animací (přeškrtnutí, zešednutí, přesun do „Completed“).

**Funguje**: napsat `- [ ] Odevzdat lab @ Fri` do poznámky → za ≤1 s je v Today/Upcoming a v úkolech předmětu; odškrtnutí v Today změní soubor.

**Vizuální kontrola**: navržené obrazovky Today, Upcoming, Course tasks (nový návrh; porovnat s referencemi Things 3 v původních screenshotech v `uploads/`). Přesné body z mockupu: `dueWeek` řádky (dot, kód, titulek, den červeně pro Today/Tomorrow), čip „Exam“ červený, „Due Fri“ oranžový, hotové přeškrtnuté `#9A9DA6`.

---

## M8 — Rychlý zápis a Inbox: 5a, 5b, popup 1b

**Před startem**: rozhodnout otázku 2 (běží i bez okna?).

**Co se staví**
- **`QuickCaptureParser`** (`MarginCore/Capture`, testy): vstup jednoho řádku, výstup `{text, course?, date?, tags[], kind}`. Rozpoznání: `@bio` / `+Cell Biology` / kód předmětu / klíčová slova předmětu; data „wed“, „tomorrow“, „Fri“, „2 Oct“, „before next lecture“; `#tag`. Příklad z mockupu: „Read ch. 6 before wed for @bio #reading“ → předmět Cell Biology, Wed 30 Sep, tag reading, „Attach to Lecture 9“.
- **Overlay** (`NSPanel`, nonactivating, střed horní třetiny): karta 620 px, rádius 16, zvýrazněné tokeny v textu (datum modře, předmět zeleně, tag šedě), řada čipů (předmět, datum, tag, „Attach to Lecture 9“ čárkovaně), přepínač Task/Note, patička „⌘⇧Space from anywhere · ⌘↵ Inbox“, modré „Add to Cell Biology ↵“.
- **Globální zkratka** ⌘⇧Space (`Carbon RegisterEventHotKey` nebo `KeyboardShortcuts`-styl vlastní wrapper), funguje i při skryté aplikaci; nastavení změny zkratky v M11.
- **Inbox 5a**: seznam (ikona typu, titulek, meta „Task · 9:12“), řádky s dolní čárou.
- **Inbox 5b**: dvě sloupce — seznam 400 px vlevo, detail vpravo: „Captured 9:12 from your phone“, výběr **Course** (mřížka 3 sloupce, vybraný s rámečkem 1.5 modrým), **When** (Today/Tomorrow/Before next lecture · Tue/Someday), **Keep as** (Task/Note/Add to lecture note), Delete a „Move to Cell Biology“. Pole „Capture something…“ dole.
- „Add to lecture note“: přidá řádek do poznámky nejbližší přednášky předmětu.
- Ukládání: nezatříděné položky do `Vault/_inbox/`.

**Funguje**: ⌘⇧Space z jiné aplikace → napsat → Enter → v Inboxu; přesun do předmětu vytvoří úkol nebo poznámku; „Add to Cell Biology“ přímo založí úkol.

**Vizuální kontrola** — `5a`, `5b`:
- [ ] 5a: overlay 620 px, padding 22/24/16, rádius 16, tmavá clona `rgba(28,30,38,.32)`, top 170.
- [ ] Tokeny v textu mají pozadí a rádius 4, kurzor 2×22 modrý.
- [ ] 5b: sidebar sbalený (56), seznam 400 px s podkladem `#FCFCFD`, vybraná položka `#E6EDFD`.
- [ ] Pill „Task“ v segmentovaném přepínači s jemným stínem.
- Chování: parser odpovídá do 16 ms při psaní (bez lagu), ⌘⇧Space z Xcode, Safari, Finderu.

---

## M9 — Graf propojení: 4a a lokální graf

**Co se staví**
- `GraphBuilder`: uzly = poznámky a předměty (huby), hrany = wikilinky + příslušnost k předmětu, volitelně úkoly; počty „71 notes · 118 links“.
- `ForceLayout` (Verlet/Barnes-Hut), deterministický seed, uložení pozic; při 23 uzlech statický rozvržený jako v mockupu jako výchozí, při změně dat dopočítat.
- `Canvas` (SwiftUI): kruhy (hub r=10, poznámka r=5, vybraná r=7 s prstencem 5 px `#CFDDFB`), popisky 12/13, hrany `#D5D7DD` 1 px, hrany vybraného uzlu `#8FB0F3` 1.5 px; zoom (± a pinch), posun, fit-to-screen (ikona `center_focus_weak`), hover zvýrazní sousedy, klik vybere.
- **Filtry** (plovoucí karta 220 px): checkboxy předmětů s barevnou tečkou, Show tasks, Orphan notes.
- **Náhled poznámky** (karta 300 px vpravo dole): předmět · typ, titulek, úryvek, „4 links · 2 open tasks“, modré „Open“.
- **Lokální graf** kolem jedné poznámky (`lNodes`/`lEdges`, průhlednost vzdálených uzlů 0.6) — dostupný z inspektoru poznámky a záložky.
- Pohled na celý semestr vs. jedna poznámka přepíná segment v hlavičce.

**Funguje**: graf z reálného vaultu, klik na uzel ukáže náhled, „Open“ otevře poznámku, filtr předmětu skryje uzly, plynulý zoom 60 fps při 500 uzlech.

**Vizuální kontrola** — `4a` (fixture) + graf z vaultu:
- [ ] Rozložení uzlů a barvy odpovídají mockupu (pozice z `nodes` pole; 1:1 pro fixture).
- [ ] Vybraný uzel `Lecture 8` modrý s prstencem, jeho hrany světle modré.
- [ ] Karty: filtry (left 32, top 120, šířka 220), náhled (right 32, bottom 32, šířka 300), zoom tlačítka (right 32, top 32).
- [ ] Titulek „Graph map“ a „71 notes · 118 links“ vlevo nahoře.
- Výkon: 500 uzlů plynulé, 5000 uzlů nezamrzne (omezit vykreslení popisků při oddálení).
