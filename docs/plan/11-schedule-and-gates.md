# Část 11: Pořadí, vlny a lidské brány

Jak se obě větve a agentní milestony skládají do sebe. **Neměří se v lidských hodinách ani dnech** (D-014): práci dělají AI agenti a omezením jsou lidská schválení a rozhodnutí. Váhy jsou z `backend/README.md` a `ui/README.md` (relativní složitost, ne čas).

## Pořadí milestonů a váha

| # | Milestone | Název | BE váha | UI váha | Σ | Integrační brána (kdy je hotovo) |
|---|---|---|---|---|---|---|
| 1 | M0 | Kostra, tokeny, komponenty, galerie | 5 | 18 | 23 | galerie běží, tokeny odpovídají CSS |
| 2 | M1 | Shell | 0 | 28 | 28 | shell v galerii; CP0 |
| 3 | M2 | Model a fixtures | 12 | 2 | 14 | testy fixtures zelené; všechny protokoly mají `Fixture…` |
| 4 | M3 | Přehled předmětů (1a, 1b) | 5 | 29 | 34 | 1a, 1b schváleny |
| 5 | M4 | Detail předmětu (2c) | 3 | 27 | 30 | 2c schválen; CP1 |
| 6 | M5 | Vault a index | 35 | 1 | 36 | konformitní testy `Vault…` zelené; M5-10 regresní snapshoty shodné |
| 7 | MA0 | Agent: základy (provenance, ID, undo, souběh) | 32 | 0 | 32 | každý zápis má původce, ID, undo, `baseVersion`; **brána před M6** |
| 8 | M6a | Editor: source + reading | 11 | 33 | 44 | editor source+reading; CP2 |
| 9 | M6b | Editor: live | 5 | 25 | 30 | live režim dle rozpočtu výkonu |
| 10 | M7 | Úkoly | 16 | 22 | 38 | úkol z poznámky v Today do 1 s |
| 11 | MA1 | Agent: povrch nástrojů (MCP, CLI) | 83 | 0 | 83 | Claude Code se spáruje, převezme identitu „Zapisovatel přednášek“, přidá úkol → Today → `undo`; **CP5** |
| 12 | M8 | Rychlý zápis a Inbox | 25 | 19 | 44 | ⌘⇧Space end-to-end; CP3 |
| 13 | MA2 | Agent: oprávnění, audit, schvalování | 19 | 43 | 62 | agent v režimu propose vytvoří návrh, člověk schválí/zamítne v UI |
| 14 | M9 | Graf | 17 | 27 | 44 | graf 60 fps @ 500 uzlů |
| 15 | M10a | Popupy: navigace a psaní | 12 | 28 | 40 | ⌘K, `[[`, `/`, hover schváleny |
| 16 | MA3 | Agent v aplikaci | 30 | 25 | 55 | in-app agent zvládne 3 skills přes frontu |
| 17 | M10b | Popupy: data a organizace | 12 | 18 | 30 | popupy 1e,1f,2c,2f,3a,3c schváleny |
| 18 | M10c | Popupy: dialogy a oznámení | 12 | 22 | 34 | popupy 1g,1h,1i,2d,2e,2g,3b schváleny |
| 19 | M11 | Obrazovky a stavy | 21 | 37 | 58 | všech 9 obrazovek schváleno; CP4 |
| 20 | MA4 | Agent: odolnost | 32 | 3 | 35 | 30 injekčních útoků + eval 20/20 + stres bez ztráty |
| 21 | M12 | Dokončení a vydání | 18 | 22 | 40 | rozpočty splněny, podpis, revize proti mockupům |
| | **Σ** | | **405** | **429** | **834** | |

## Vlny (co může běžet souběžně)

Vlna = množina milestonů, jejichž závislosti jsou splněné, takže je agenti mohou stavět **paralelně** (každý v samostatném git worktree). Vlna končí, až jsou všechny její milestony přijaté.

| Vlna | Milestony | Souběžně | Lidská schválení v této vlně | Rozhodnutí potřebná **před** vlnou |
|---|---|---|---|---|
| 1 | M0, M2 | UI základ ‖ BE typy a fixtures | galerie: System sekce (M0) | — (Q6 rozhodnuto) |
| 2 | M1, M5 | UI shell ‖ BE vault a index | **CP0** (titulková lišta, animace panelů) | Q1 (vault), schválení `05-vault-spec.md`; Q5 hotovo |
| 3 | M3, MA0 | UI přehled předmětů ‖ BE agent-základy | vizuál 1a, 1b; **brána MA0** (testy provenance, ID, undo, souběh) | — |
| 4 | M4, M6a, M9 | UI detail předmětu ‖ editor (source+reading) ‖ graf | **CP1** (2c + návrhy Today/Upcoming a záložek předmětu), vizuál 4a | Q4 (vzhled Today/Upcoming) |
| 5 | M6b, M7 | editor live ‖ úkoly | **CP2** (editor), vizuál Today/Upcoming | — |
| 6 | MA1, M8, M10a | agentní povrch ‖ rychlý zápis+Inbox ‖ popupy A | **CP3** (jádro zadání), **CP5** (agent přes MCP: párování → identita → úkol → `undo`), vizuál 5a, 5b, popupy A | Q2 (běh bez okna), Q11, Q12, Q13 |
| 7 | MA2, M10b, M10c | oprávnění a review ‖ popupy B ‖ popupy C | vizuál review fronty, správy identit, popupů B a C | Q3 (rozsah stubů), Q9 (výchozí profil) |
| 8 | MA3, M11 | agent v aplikaci ‖ zbylé obrazovky | vizuál Agent tab, Screens 1a…2e; **CP4** | Q8 (model), Q10 (soukromí) |
| 9 | MA4, M12 | odolnost ‖ dokončení | eval a útoky (číselně), revize proti mockupům | Q7 (Developer ID) |

Pozn.: M6a a M9 se dají posunout do dřívější vlny, jakmile je hotové M5 a MA0; pořadí výše je bezpečné pro jednoho člověka, který schvaluje.

## Kritická cesta

Nejdelší řetěz závislostí: **M5 → MA0 → M6a → M7 → MA1 → MA2 → MA3 → MA4 → M12**. MA0 je brána před editorem: zapisovací služby musí od začátku umět původce, `baseVersion`, `dryRun` a `ChangeSet`. Dodělat to později by znamenalo přepsat všechny zápisy.

## Co skutečně určuje tempo

1. **Počet lidských schválení na kritické cestě** (CP0–CP5 a vizuální kontroly). Agenti čekají na vás, ne naopak.
2. **Kola kontroly:** každé zbytečné kolo zdrží celou vlnu. Snižuje je jasné akceptační kritérium, předpočítané odchylky od mockupu ve snímcích a rozhodnutí zodpovězená předem.
3. **Kvalita zadání a smlouvy:** špatně specifikovaný mockup nebo protokol se projeví ve více paralelních větvích najednou.
4. **Cena běhu:** paralelní vlny stojí víc tokenů; sleduje se na milestone (`STATUS.md`).

## Jak vypadá jeden milestone

```
agent postaví (tests + snapshoty zelené)  →  ke kontrole  →  schválení člověkem  →  přijato + tag
                                              ↑                    │
                                              └── kolo opravy ←────┘   (max 3 kola, pak stop a rozbor příčiny)
```

Člověk u BE kontroluje zprávu z testů a rozpočtů; u UI vizuální porovnání proti mockupu (`docs/checks/<M>.md`). Ostatní je automatizované.
