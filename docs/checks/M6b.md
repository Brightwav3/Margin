# Kontrola milestonu M6b — Editor: live

Milestone: M6b  ·  Větev: sloučeno do `main` (#34, #35)  ·  Vyplňuje: agent (checklist a snímky), schvaluje: člověk

## Checklist (z `docs/plan/ui/README.md`)
- [x] M6-12.U Model „aktivního bloku“ (blok pod kurzorem ukazuje zdroj) — přechod mezi bloky bez skoku kurzoru
- [x] M6-13 Ztlumená syntaxe (`##`, `- [ ]` jako checkbox, `[[ ]]`) — dle 3a live
- [x] M6-14 Klikací checkbox uvnitř textu bez ztráty výběru — test s výběrem přes více řádků
- [x] M6-15 Kurzor a výběr při přepisu atributů (regresní sada 30 scénářů) — žádný skok kurzoru
- [x] M6-16.U Výkon 10 000 slov — < 8 ms na klávesu

## Snímky
| Obrazovka (ID) | Mockup (`reference/`) | Aplikace | Odchylka |
|---|---|---|---|
| 3a | reference/*.png | snapshots/3a.png | viz `DEVIATIONS.md` |

## Odchylky od mockupu
Zapsané v `docs/checks/DEVIATIONS.md` (tenčí písmo a ikony, zónovaná lišta, model záložek jen pro poznámky, data fixture).

## Výsledky automatických kontrol
- `scripts/check.sh`: zelené (2026-10-01, `main` f84f5e3)
- UI testy: 89 zelených; jádro 293 + 722 zelených
- Kol kontroly: 1

## Schválení (píše výhradně člověk)
Stav: Čeká
