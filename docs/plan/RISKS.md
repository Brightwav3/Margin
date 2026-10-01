# Registr rizik

P = pravděpodobnost (N/S/V), D = dopad (N/S/V). Skóre = P×D (1–9). Přehodnocuje se při startu každého milestone.

| ID | Riziko | P | D | Skóre | Mitigace | Spouštěč (kdy eskalovat) | Milestone |
|---|---|---|---|---|---|---|---|
| R-01 | Živý režim editoru (TextKit 2) je mnohem pracnější, kurzor „skáče“ při přepisu stylů | V | V | 9 | Nejdřív source + reading; live jako druhé kolo; prototyp po 3 dnech | > 3 dny bez stabilního kurzoru | M6 |
| R-02 | Vlastní titulková lišta se záložkami nejde čistě v SwiftUI | S | S | 4 | Prototyp v den 1 M1; AppKit `NSTitlebarAccessoryViewController` / skrytý titulek | prototyp selže | M1 |
| R-03 | Globální zkratka a sandbox | S | S | 4 | `RegisterEventHotKey`; testovat v sandboxu ve 2. dni M8 | zkratka nechodí v sandboxu | M8 |
| R-04 | Rozsah „jen naznačených“ funkcí (agent, sdílení, PDF sylabus, sync) se rozroste | V | V | 9 | Stub-only, zápis v `DECISIONS.md`, CP3 řez | jakýkoli úkol označený „reálná funkce“ bez ADR | M10–M11 |
| R-05 | Nejednoznačné mockupy (Today, Upcoming, záložky předmětu) | V | S | 6 | Návrh + schválení před stavbou (CP1) | přepracování > 1× | M4, M7 |
| R-06 | Ztráta uživatelských dat (bug v zápisu, konflikt s externí změnou) | N | V | 3 | Atomický zápis, historie verzí, fuzz testy, koš | jakákoli ztráta v testech | M5–M6 |
| R-07 | Výkon indexu/grafu na velkém vaultu | S | S | 4 | Rozpočty výkonu od M5, měření ve CI skriptu | rozpočet překročen o > 50 % | M5, M9 |
| R-08 | Lucide ikony se tvarově liší od Material Symbols v mockupu | V | N | 3 | `DEVIATIONS.md`; mapování v `Icons.swift`, kde chybí přesný ekvivalent, nejbližší Lucide | uživatel zamítne při kontrole | M0 |
| R-09 | Písmo Inter (licence, hinting) | N | N | 1 | OFL licence, přibalit | — | M0 |
| R-10 | Nové API macOS 27 (SDK beta chyby) | S | S | 4 | Držet se stabilních API, izolovat AppKit | build padá po updatu Xcode | všechny |
| R-11 | Notarizace / podpis bez Developer ID | S | S | 4 | Zjistit včas; alternativa: lokální spuštění bez distribuce | před M12 nezjištěno | M12 |
| R-12 | Zdržení na lidských bránách a opakovaná kola kontroly (ne rychlost psaní kódu) | V | S | 6 | Rozhodnutí Q předem, checklisty s předpočítanými odchylkami od mockupu, dávkové schvalování, jasné akceptační kritérium | milestone má > 3 kola kontroly | průběžně |
| R-13 | Dlouhodobé opuštění projektu (kontext se ztratí) | S | V | 6 | `STATUS.md`, ADR, kontrolní seznam, běhavé demo po každém milestone | pauza > 2 týdny | průběžně |
| R-15 | Prompt injection: obsah poznámek/PDF přinutí agenta provést nechtěnou akci | V | V | 9 | Obsah jako data, potvrzení destruktivních/hromadných akcí, sada 30 útoků v CI (AG-26) | jakákoli neautorizovaná změna v testu | MA3–MA4 |
| R-16 | Souběžné zápisy agentů a člověka poškodí nebo ztratí data | S | V | 6 | `baseVersion`, ChangeSet+undo, snapshot před hromadnou akcí, stres test (AG-03, 04, 28, 29) | jakákoli ztráta v testu | MA0, MA4 |
| R-17 | Soukromí: obsah poznámek odchází do API modelu bez vědomí uživatele | S | V | 6 | Nastavení soukromí po předmětech, výslovný souhlas, režim „jen lokálně“ (Q10) | před MA3 nerozhodnuto | MA3 |
| R-18 | Rozsah agentní části (váha 267) se rozroste (autonomní workflow, více modelů) | V | S | 6 | Provider-agnostic jádro, jen Claude adaptér v MA3, skills jen 3; řez v CP5 | úkol mimo MA katalog bez ADR | MA1–MA4 |
| R-19 | Zneužití nebo záměna identit (klient převezme silnější roli, než potřebuje; uživatel schvaluje „naslepo“) | S | V | 6 | Allowlist per klient, politika `ask` u zápisových identit, `purpose` v dialogu i auditu, TTL, srozumitelný dialog (AG-36) | schvalování bez čtení účelu v testech použitelnosti | MA1–MA2 |
| R-20 | Souběžní agenti staví ve worktrees a rozbijí smlouvu nebo se špatně sloučí | S | S | 4 | Jedna větev na milestone, commity se scope `api`, pořadí slučování podle závislostí, integrační brána, konformitní testy | konformitní test padá po sloučení | všechny |
| R-21 | Pravidla nejsou na serveru vynucená (ruleset vyžaduje GitHub Pro nebo veřejné repo); merge do `main` lze mimo lokální hooky provést přes web | S | S | 4 | Lokální hooky + CI jako informativní kontrola; upgrade na Pro nebo zveřejnění repa, potom `gh-setup.sh … ruleset` | první commit na `main` mimo PR/landing | všechny |
| R-22 | Vnitřní agent (CLI jako v Claudianu, D-023) zapisuje do vaultu mimo oprávnění, schvalování a undo Marginu; chybný nebo injekcí zmanipulovaný příkaz může poškodit poznámky | S | V | 6 | Historie verzí a koš pro externí změny, jasné označení „změněno agentem“ podle file watcheru, CLI se spouští jen na výslovnou akci uživatele, doporučené nastavení oprávnění CLI (ask před zápisem) | jakákoli nevratná ztráta dat po běhu agenta | MA3 |
| R-14 | Vault s cizími syntaxemi z Obsidianu (callouty, dataview, embedy) rozbije parser | S | S | 4 | Tolerantní parser, neznámé bloky prošlé beze změny, testovací vault | ztráta/deformace obsahu | M5–M6 |

## Vyřešená rizika
_(zatím žádná)_
