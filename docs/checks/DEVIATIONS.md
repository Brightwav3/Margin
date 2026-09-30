# Vědomé odchylky od mockupu

| Datum | Obrazovka | Odchylka | Důvod | Schválil |
|---|---|---|---|---|
| 2026-09-28 | všechny ikony | Lucide místo Material Symbols (tvar některých ikon se liší) | D-006 | Šimon |
| 2026-09-30 | 3a (vlastnosti), System | Hodnota `class` bez úvodního `+` („Cell Biology“, ne „+Cell Biology“) | pokyn uživatele | Šimon |
| 2026-09-30 | rail, všechny ikony | Aktivní položka bez vyplněné ikony (Lucide nemá `fill` varianty); zvýraznění barvou a tloušťkou | D-020 | |
| 2026-09-30 | sidebar Notes (hledání) | Pole „Search notes…“ jako Liquid Glass kapsle (`glassEffect`) místo bílého obdélníku s okrajem | pokyn uživatele | Šimon |
| 2026-09-30 | shell (lišta) | Záložky jen nad obsahem: začínají u pravé hrany sidebaru a končí u levé hrany inspektoru (nad sidebarem jen semafory, šipky a přepínač) | pokyn uživatele | Šimon |
| 2026-09-30 | všechny obrazovky | Tenčí písmo a ikony (jako aplikace ChatGPT): Inter `wght` 400→370, 500→460, 600→540, 700→620; tah ikon 1.5 místo 1.75; v sidebaru položky 14 px, sekce 13 px, titulek 15 px | pokyn uživatele | Šimon |
| 2026-09-30 | 2c (stránky předmětu) | **Návrh M4-05:** stránky předmětu (Gallery, Tasks, Exam prep, Grades) přepíná sekce Views v sidebaru předmětu (jako `Sidebar.dc.html`), ne segmentovaný přepínač pod titulkem; záložka Agent v inspektoru je skrytá, dokud agent nemá obsah (MA3) | návrh ke schválení | |
| 2026-09-30 | 3a (source) | Source režim ukazuje tělo poznámky; frontmatter je v panelu Properties (smlouva: `Note.text` je bez frontmatteru), ne jako `---` řádky | smlouva `Note` | |
| 2026-09-30 | 3a (live) | Panel Properties je nad titulkem `# …` (v mockupu mezi titulkem a textem), protože titulek je součást textu poznámky | technické | |
| 2026-09-30 | Today, Upcoming | **Návrh M7-01** (mockup chybí): Today = hodiny dne jako barevné karty + Overdue / Today; Upcoming = Tomorrow, dny týdne, Later; sidebar s filtrem předmětů. Schválit v CP1 | návrh ke schválení | |
