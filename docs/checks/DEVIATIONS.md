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
| 2026-10-01 | Account v3 2a | Profil je v `.margin/settings.json` (klíč `profile`), ne v `.margin/profile.json` | jeden soubor nastavení přes existující `SettingsStore`, bez nové služby; text v okně to říká | |
| 2026-10-01 | Account v3 2b, 2e–2l | Bez řádků, které nic nedělají (složka příloh, interval snímků, kanál aktualizací, šablony, LaTeX, akcentová barva, fonty) a Flashcards/Agent/Plugins jen jako vypnuté stránky | zobrazují se jen funkční volby | |
| 2026-10-01 | 3a (editor) | Bloky `$$…$$` a Mermaid se vykreslují (D-027); inline `$…$` zůstává stylovaný text a export do PDF tiskne jejich zdroj | rozsah první verze | |
| 2026-10-01 | 1h Obrázek | „Explain with agent“ vypnuté (agent MA3); „Replace…“ vypnuté (chybí služba pro přidání souboru do vaultu); „Extract text“ vloží rozpoznaný text pod obrázek jako citaci | agent odložen, smlouva | |
| 2026-10-01 | 2d Výběr předmětu | Archivované předměty jsou v seznamu jen pro čtení; předměty jiných (nearchivovaných) semestrů chybí, `CourseCatalog.courses` vrací jen aktuální semestr | smlouva | |
| 2026-10-01 | 2e Oprávnění | Sdílení a oprávnění zatím nejsou (potřebují server) | pokyn uživatele: nic serverového | |
| 2026-10-01 | 1l, 1o | Kartičky a odpověď agenta zatím nejsou | agent a kartičky odloženy | |
| 2026-10-01 | 1r | Sloučení: první poznámka zůstane, ostatní jako sekce `## Název` a jdou do koše; odkazy na ně zůstanou nevyřešené. Export = kopie / jeden `.md` soubor (PDF jen u jedné poznámky) | bez nové služby | |
| 2026-10-01 | rail | Vlastní ikony míst v railu (`RailIcons.swift`, geometrie Lucide): černé obrysy, vybrané místo plně černé se šedými vnitřními čarami (místo šedých obrysů a tučnější aktivní ikony; Lucide plné varianty nemá) | pokyn uživatele | Šimon |
