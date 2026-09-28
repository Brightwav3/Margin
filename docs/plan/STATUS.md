# STATUS — živý stav projektu

Poslední aktualizace: 2026-09-28 · Aktivní milestone: **žádný (plánovací fáze)**

Legenda: ⬜ nezačato · 🟦 rozpracováno · 🟨 ke kontrole · ✅ přijato · ⛔ blokováno

## Milestony

Legenda: ⬜ nezačato · 🟦 rozpracováno · 🟨 ke kontrole · ✅ přijato · ⛔ blokováno

| M | Název | BE váha | UI váha | Σ | Kol kontroly | Kalendářně | Stav | Kontrola | Tag | Poznámka |
|---|---|---|---|---|---|---|---|---|---|---|
| M0 | Kostra, tokeny, komponenty, galerie | 5 | 18 | 23 | — | — | 🟦 | `checks/M0.md` | |  |
| M1 | Shell | 0 | 28 | 28 | — | — | ⬜ | `checks/M1.md` | | CP0 |
| M2 | Model a fixtures | 12 | 2 | 14 | — | — | 🟦 | (testy) | |  |
| M3 | Přehled předmětů (1a, 1b) | 5 | 29 | 34 | — | — | ⬜ | `checks/M3.md` | |  |
| M4 | Detail předmětu (2c) | 3 | 27 | 30 | — | — | ⬜ | `checks/M4.md` | | CP1 |
| M5 | Vault a index | 35 | 1 | 36 | — | — | 🟦 | `checks/M5.md` | | před startem odsouhlasit spec (§12) |
| MA0 | Agent: základy (provenance, ID, undo, souběh) | 32 | 0 | 32 | — | — | 🟦 | (testy) | | brána před M6 |
| M6a | Editor: source + reading | 11 | 33 | 44 | — | — | 🟦 | `checks/M6a.md` | | CP2 |
| M6b | Editor: live | 5 | 25 | 30 | — | — | 🟦 | `checks/M6b.md` | |  |
| M7 | Úkoly | 16 | 22 | 38 | — | — | 🟦 | `checks/M7.md` | | před startem schválit návrh |
| MA1 | Agent: povrch nástrojů (MCP, CLI) | 83 | 0 | 83 | — | — | ⬜ | `checks/MA1.md` | | CP5 |
| M8 | Rychlý zápis a Inbox | 25 | 19 | 44 | — | — | 🟦 | `checks/M8.md` | | CP3 |
| MA2 | Agent: oprávnění, audit, schvalování | 19 | 43 | 62 | — | — | ⬜ | `checks/MA2.md` | |  |
| M9 | Graf | 17 | 27 | 44 | — | — | 🟦 | `checks/M9.md` | |  |
| M10a | Popupy: navigace a psaní | 12 | 28 | 40 | — | — | 🟦 | `checks/M10a.md` | |  |
| MA3 | Agent v aplikaci | 30 | 25 | 55 | — | — | ⬜ | `checks/MA3.md` | |  |
| M10b | Popupy: data a organizace | 12 | 18 | 30 | — | — | 🟦 | `checks/M10b.md` | |  |
| M10c | Popupy: dialogy a oznámení | 12 | 22 | 34 | — | — | ⬜ | `checks/M10c.md` | |  |
| M11 | Obrazovky a stavy | 21 | 37 | 58 | — | — | 🟦 | `checks/M11.md` | | CP4 |
| MA4 | Agent: odolnost | 32 | 3 | 35 | — | — | ⬜ | `checks/MA4.md` | |  |
| M12 | Dokončení a vydání | 18 | 22 | 40 | — | — | ⬜ | `checks/M12.md` | |  |
| | **Σ** | **405** | **429** | **834** | | | | | | |

Metriky (viz `04-engineering-rules.md` §9): průměr kol kontroly na milestone — · průměrné čekání na schválení — · cena běhu celkem —

## Otevřená rozhodnutí (blokují start)

| # | Otázka | Blokuje | Stav | Výchozí předpoklad |
|---|---|---|---|---|
| Q1 | Umístění vaultu a kompatibilita s Obsidianem | M5 | ⬜ | `~/Documents/Margin`, kompatibilní |
| Q2 | Rychlý zápis i bez okna aplikace | M8 | ⬜ | ano, přes menu bar agenta |
| Q3 | Rozsah stubů (sdílení, PDF sylabus, sync); Agent už stub není | M10–M11 | ⬜ | jen UI, funkce později |
| Q4 | Vzhled Today/Upcoming a záložek předmětu | M4, M7 | ⬜ | návrh v M4/M7, schválení v CP1 |
| Q5 | Identita úkolu: hash vs. `^id` | M5 | ✅ | **rozhodnuto: stabilní `^id`** (D-012) |
| Q6 | Ikony: Lucide (jako Obsidian) | M0 | ✅ | **rozhodnuto: Lucide** (D-006) |
| Q7 | Developer ID pro notarizaci | M12 | ⬜ | zjistit před M11 |
| Q8 | Výchozí model a poskytovatel vnitřního agenta, klíč v Keychainu, lokální modely | MA3 | ⬜ | Claude API, jen adaptér |
| Q9 | Výchozí profil nové identity | MA2 | ⬜ | `propose` |
| Q10 | Soukromí: co smí do modelu odejít | MA3 | ⬜ | jen zvolené předměty, výslovný souhlas |
| Q11 | MCP server i při zavřené aplikaci (pomocný démon) | MA1 | ⬜ | jen za běhu aplikace |
| Q12 | Výchozí politika převzetí identity (`auto` vs. `ask`) | MA1 | ⬜ | auto pro read/propose, ask pro zápisové |
| Q13 | Zapnout lokální HTTP API, nebo jen CLI + MCP | MA1 | ⬜ | ve výchozím stavu vypnuté |

## Aktuální blokery
_(žádné)_

## Log
- 2026-09-28: Napsán plán (části 0–8), rizika, rozhodnutí, tento STATUS. Kód zatím nezačat.
- 2026-09-28: Plán rozdělen na backend a UI (`backend/`, `ui/`, `09-contracts.md`, D-010). Přidána agentní část (`10-agent-native.md`, MA0–MA4, D-011/012), celkem 790 h.
- 2026-09-28: Přidán model klient × identita (D-013): AG-31…36, celkem váha 834 (BE 405 / UI 429).
- 2026-09-28: Hodinové odhady nahrazeny váhou, vlnami a lidskými bránami (D-014).
- 2026-09-28: Repo připraveno pro agenty: `AGENTS.md`, `CLAUDE.md`, `docs/WORKFLOW.md`, git hooky, guard, `scripts/` (D-015).
- 2026-09-28: Převzat git workflow uživatele (D-016): `docs/git-workflow.md`, `.github/` (CI, šablony, ruleset), `scripts/lint-commit.py`, `scripts/land.sh`; nové hooky čekají v `docs/proposed-hooks/` na aplikaci člověkem.
- 2026-09-28: Vytvořeno soukromé repo Brightwav3/Margin a 53 štítků. Ruleset nelze na free plánu soukromého repa (403) — viz `docs/git-workflow.md`. První push `main` čeká na člověka.
