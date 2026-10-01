# Kontrola milestonu M6a — Editor: source + reading

Milestone: M6a  ·  Větev: sloučeno do `main` (#34, #35)  ·  Vyplňuje: agent (checklist a snímky), schvaluje: člověk

## Checklist (z `docs/plan/ui/README.md`)
- [x] M6-01 Prototyp `NSTextView` (TextKit 2) v `NSViewRepresentable`, načtení/uložení souboru — píše se, undo/redo, uložení 400 ms debounce
- [x] M6-02.U `SyntaxStyler`: styly pro nadpisy, odrážky, kód, odkazy, frontmatter — inkrementální styling jen změněného rozsahu
- [x] M6-03 **Source režim** (monospace 14, 1.75, barvy klíčů) — shodný s mockupem 3a source
- [x] M6-04 **Reading režim** (vykreslený text, klikací checkboxy) — shodný s mockupem 3a reading
- [x] M6-05.U Panel Properties (řádky, hodnoty, tagy, „Add property“) — zápis do frontmatteru; pořadí zachováno
- [x] M6-06 Horní lišta (drobečky, ikony, přepínač režimu) — dle mockupu
- [x] M6-07 Menu `…` (25 položek) a jejich zapojení (které jdou) — položky z jiných milestonů vypnuté s tooltipem
- [x] M6-08.U Stavový řádek (backlinky, vlastnosti, slova, úkoly) — čísla se aktualizují ≤ 200 ms po psaní
- [x] M6-09.U Inspektor `note`: Outline, Backlinks, Outgoing, All properties — klik v Outline skáče; nevytvořený odkaz má „+“
- [x] M6-10 Readable line length (700 px) přepínač — funguje a pamatuje se

## Snímky
| Obrazovka (ID) | Mockup (`reference/`) | Aplikace | Odchylka |
|---|---|---|---|
| 3a-source | reference/*.png | snapshots/3a-source.png | viz `DEVIATIONS.md` |
| 3a-reading | reference/*.png | snapshots/3a-reading.png | viz `DEVIATIONS.md` |

## Odchylky od mockupu
Zapsané v `docs/checks/DEVIATIONS.md` (tenčí písmo a ikony, zónovaná lišta, model záložek jen pro poznámky, data fixture).

## Výsledky automatických kontrol
- `scripts/check.sh`: zelené (2026-10-01, `main` f84f5e3)
- UI testy: 89 zelených; jádro 293 + 722 zelených
- Kol kontroly: 1

## Schválení (píše výhradně člověk)
Stav: Čeká
