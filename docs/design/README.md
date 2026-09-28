# Design: zdroje pravdy pro vzhled

Sem patří vizuální zdroje pro implementaci. **Vzhled se nepíše z hlavy**, ale podle těchto souborů a checklistů v `docs/plan/`.

## Mockupy (`mockups/`)
Export z Claude Design (HTML prototypy, ne produkční kód). Čti přímo zdroj: rozměry, barvy a rozložení jsou v inline stylech. Není potřeba je renderovat.

| Soubor | Obsah |
|---|---|
| `Margin.dc.html` | hlavní plátno: sekce **System** (typy, barvy, dlaždice, ovládací prvky), **1a** mřížka předmětů, **1b** rozvrh, **2c** detail předmětu, **3a** editor (live/source/reading, menu), **4a** graf, **5a** rychlý zápis, **5b** třídění Inboxu. Na konci datový skript (`C`, `DUE`, `SES`, uzly grafu, galerie) = zdroj **fixture dat** |
| `Margin-Screens.dc.html` | onboarding (1a), výsledky hledání (1b), známky (1e), archiv (1f), Settings › Semesters (1g), prázdné stavy a načítání (2a–2c), historie verzí (2e) |
| `margin-popups.dc.html` | popupy 1a–1i (paleta ⌘K, quick capture, `[[`, výběrová lišta, vlastnosti, termín, nový předmět, mazání, toasty), 2a–2g (slash, náhled odkazu, přesun, import sylabu, známka, menu předmětu, Settings › Editor), 3a–3d (archivace, sdílení, přesunutí hodiny, návrhy agenta) |
| `Sidebar.dc.html` | rail 56 px + panel (navigace a Notes), záložky v titulkové liště, sbalení |
| `Inspector.dc.html` | pravý panel: záložky course/note, řádky Outline, Backlinks, Outgoing, Properties, Coming up, Course info, Files |
| `margin-tokens.css` | **tokeny** (barvy, písmo, rádiusy); má přednost před `_ds/` (D-004) |
| `_ds/` | design systém Fidelio (komponenty Icon, Checkbox, Badge, Switch); jen kontext, tokeny jsou přepsané |
| `support.js`, `image-slot.js` | runtime prototypového nástroje (šablonovací značky `sc-for`, `sc-if`, `dc-import`), **do aplikace nepatří** |

Šablonovací značky v HTML: `sc-for list="{{ x }}"` = cyklus, `sc-if` = podmínka, `dc-import name="Sidebar"` = vložení komponenty, `{{ … }}` = hodnota z datového skriptu na konci souboru.

## Reference (`references/`)
Snímky, ze kterých vznikl vizuální směr (Things 3, Obsidian, karty předmětů, pastelové dlaždice). Slouží k porovnání „jak to má působit“, ne jako přesná specifikace. Přesná specifikace je v mockupech.

## Jak s tím pracovat
1. Najdi ID obrazovky v `docs/plan/01-03-*` (např. `3a`) a ten blok v `mockups/*.dc.html`.
2. Rozměry a barvy přepiš do tokenů (`docs/plan/00-overview.md` §2) a komponent, nekopíruj inline styly.
3. Checklist milestonu (`docs/checks/<M>.md`) uvádí konkrétní čísla (rádius, mezery, výšky); u pochybností vyhrává mockup.
4. Odchylky (např. Lucide místo Material Symbols, D-006) zapiš do `docs/checks/DEVIATIONS.md`.
