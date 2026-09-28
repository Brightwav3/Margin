# Část 4: Pravidla práce (aby se plán dal držet)

Tento soubor je „smlouva“ mezi námi a projektem. Když se pravidlo nedá dodržet, změní se tady a zapíše se do `DECISIONS.md`, ne potichu obejde.

## 1. Živé dokumenty

| Soubor | Účel | Kdo aktualizuje | Kdy |
|---|---|---|---|
| `docs/plan/STATUS.md` | Stav každého milestone a úkolu (tabulka) | agent | po každém dokončeném úkolu |
| `docs/plan/DECISIONS.md` | Log rozhodnutí (ADR-lite): co, proč, alternativy | agent, schvaluje uživatel | při každé volbě, která se dá jen draho vzít zpět |
| `docs/plan/RISKS.md` | Registr rizik, pravděpodobnost, dopad, mitigace | agent | při startu milestone a když se riziko změní |
| `docs/checks/<Mx>.md` | Vizuální/funkční kontrola milestone | agent vyplní, uživatel schválí | konec milestone |
| `CHANGELOG.md` | Co se změnilo po milestone | agent | konec milestone |

Pravidlo: **plán se nikdy nepřepisuje zpětně.** Změny rozsahu jdou přes záznam v `DECISIONS.md` a řádek „Změna“ u milestone.

## 2. Životní cyklus milestone

```
Ready → In progress → In review (vizuální kontrola) → Accepted
```

- **Definition of Ready** (než se začne):
  1. Předchozí milestone v závislostech je Accepted.
  2. Otevřené otázky pro milestone jsou zodpovězené (nebo je zapsaný výchozí předpoklad).
  3. Úkoly mají ID, akceptační kritéria a váhu.
  4. Fixture data a mockupy potřebné pro kontrolu jsou k dispozici.
- **Definition of Done** (úkol):
  1. Kód sestaven bez varování (Swift 6 strict concurrency).
  2. Logika v `MarginCore` má unit testy; UI má alespoň snapshot nebo záznam v galerii.
  3. Akceptační kritéria odškrtnutá v `STATUS.md`.
  4. Žádný nový `TODO` bez odkazu na úkol.
- **Definition of Done** (milestone): všechny úkoly hotové + `docs/checks/<Mx>.md` schválený uživatelem + `CHANGELOG.md` + tag `mX-accepted`.

## 3. Práce s gitem
> Kanonický a **vynucený** popis je v `docs/git-workflow.md` (Conventional Commits, větve `<type>/<scope>-<slug>`, PR + squash merge, autonomie AUTO/ASK; git hooky `.githooks/`, `scripts/lint-commit.py`, guard, CI). Níže je jen přehled; při rozporu platí `git-workflow.md`.

- Větev na PR: `feat/ui-course-card`. `main` je vždy sestavitelný; slučuje se squash mergem přes PR (nebo lokálně `scripts/land.sh`).
- Commity: `feat(ui): add course card banner` + patička `Task: M3-01`. Jedna logická změna na commit.
- Tag po přijetí milestonu: `m3-accepted` (jen `land.sh --milestone` po schválení člověkem). Verze aplikace: SemVer tagy `v0.x.y`.
- Žádné binární balíky v gitu kromě písma Inter, ikon a referenčních snímků (`docs/checks/reference/`).

## 3a. Dvě větve
- **Backend** (`backend/README.md`) a **UI** (`ui/README.md`) mají oddělené úkoly, ale jeden milestone se uzavírá, až jsou hotové obě větve a prošla integrační brána (`11-schedule-and-gates.md`).
- Backend (`core`) commity nesmí měnit `MarginUI` a naopak; změna smlouvy jde commitem se scope `api` (`09-contracts.md` §1).
- Kontrola: backend testy a čísla; UI vizuální schválení uživatelem.

## 4. Strategie testů

| Vrstva | Co | Nástroj | Pokrytí |
|---|---|---|---|
| Unit | parser markdownu, frontmatter, úkoly, odkazy, capture parser, výpočet známek, force layout | Swift Testing | `MarginCore` ≥ 85 % řádků |
| Property/fuzz | round-trip frontmatteru (parse → zápis → parse), parser nesmí padnout na libovolném vstupu | Swift Testing + generované vstupy | parsery |
| Snapshot | klíčové obrazovky z galerie při 1240×820 proti schváleným PNG | vlastní `SnapshotTests` (bitmapImageRep) | každá obrazovka z mockupu |
| UI smoke | spuštění, otevření vaultu, vytvoření poznámky, zaškrtnutí úkolu, ⌘K | XCUITest | 6–8 scénářů |
| Výkon | index 1000 poznámek, psaní v 10 000 slovech, graf 500 uzlů | `XCTMetric` / vlastní měření | rozpočty níže |
| Konformitní | jedna sada testů na službu proti `Fixture…` i `Vault…` | Swift Testing | každý protokol z `09-contracts.md` |
| Agentní | eval sada 20 úloh, 30 injekčních útoků, stres 5 agentů | Swift Testing | MA4 |
| Manuální | vizuální kontrola, globální zkratka, notifikace | checklist `docs/checks/` | každý milestone |

Snapshoty: tolerance 0.5 % pixelů, aktualizace jen vědomě (`SNAPSHOT_RECORD=1`) a vždy s komentářem v commitu.

## 5. Rozpočty výkonu (platí od M5, hlídají se v M12, ale porušení se řeší hned)
- Studený start s vaultem 1000 poznámek: **< 1,0 s** do první vykreslené obrazovky, plný index do 3 s na pozadí.
- Psaní v poznámce 10 000 slov: **< 8 ms** na stisk klávesy (bez zahazování snímků).
- Inkrementální přeindexování jednoho souboru: **< 30 ms**.
- Graf: **60 fps** při 500 uzlech, použitelný (≥ 30 fps) při 5000.
- Paměť po startu s 1000 poznámkami: **< 250 MB**.
- Rychlý zápis: od stisku zkratky do viditelného overlaye **< 120 ms**.
- Volání nástroje agenta (`read`): **p95 < 200 ms**; zápis s `ChangeSet`: **p95 < 300 ms**.
- 5 souběžných agentů + uživatel píše: **0 ztracených zápisů**.

## 6. Závislosti a nástroje
- Výchozí postoj: **žádné třetí strany**, dokud nejsou nutné. Kandidáty k posouzení: `swift-markdown` (Apple) pro parsování, `GRDB` nebo systémové SQLite pro FTS5, `Yams` pro YAML.
- Každá závislost = záznam v `DECISIONS.md` (co, licence, proč ne vlastní řešení, jak se odstraní).
- Verze zamknout v `Package.resolved`, commit.
- Xcode/Swift verze zapsaná v `README` (nyní Xcode 27.0, Swift 6.4).

## 7. Sledování rozsahu
- **Změna rozsahu** (přidání obrazovky/funkce): zapíše se do `DECISIONS.md` s dopadem na váhu, počet bran a co se odsouvá.
- **Vědomé odchylky od mockupu** se sbírají v `docs/checks/DEVIATIONS.md` (co, proč, schválil).
- **Parkoviště nápadů**: `docs/plan/BACKLOG.md`. Nápady se nedělají mimo plán, dokud neprojdou zápisem.
- **Rozpočet chyb**: chyby nalezené při kontrole = úkoly `Mx-BUGn` v tomtéž milestone, blokují jeho přijetí, pokud jsou označené jako „viditelné“.

## 8. Kontrolní body s uživatelem
| Bod | Kdy | Co se ukáže | Rozhodnutí |
|---|---|---|---|
| CP0 | po M1 | Shell a animace panelů | Potvrdit titulkovou lištu (vlastní vs. systémová) |
| CP1 | po M4 | „Vypadá jako mockup“ s fixture daty | Schválit vzhled Today/Upcoming a záložek předmětu |
| CP2 | po M6 | Použitelný editor | Zvolit: dokončit live režim, nebo jít dál |
| CP3 | po M8 | Jádro zadání end-to-end | Rozhodnout rozsah M10–M11 (stuby vs. reálné funkce) |
| CP5 | po MA1 | Claude Code přes MCP přidá úkol → Today → `undo` | Výchozí režim oprávnění agentů, soukromí |
| CP4 | po M11 | Všechny obrazovky | Revize odchylek, příprava vydání |

## 9. Měření práce (bez lidských hodin)
Práci dělají AI agenti, takže se neodhaduje ani nevykazuje čas psaní kódu. Sleduje se to, co skutečně určuje průběh:

- **Váha úkolu** (`backend/`, `ui/`): relativní složitost a riziko, ne čas.
- **Kola kontroly** na milestone (kolikrát se vrátil k opravě po lidské kontrole) — hlavní ukazatel kvality zadání a mockupu.
- **Čekání na člověka** (od „ke kontrole“ do „přijato“) — skutečný úzký profil.
- **Cena běhu** (tokeny/výpočet) na milestone — kvůli řízení nákladů.
- **Kalendářní doba** milestone (jen jako záznam, ne slib).

Pravidla:
- Když milestone potřebuje **víc než 3 kola kontroly**, práce se zastaví a řeší se příčina (nejasný mockup, špatná smlouva, chybějící rozhodnutí), ne se opakuje.
- Rozhodnutí Q1–Q13 se zodpovídají **před vlnou**, kterou blokují (`11-schedule-and-gates.md`), jinak agent staví na předpokladu, který se pak přepisuje.
- Souběžní agenti pracují v samostatných git worktrees, po jednom na milestone/větev; smlouvu (`09-contracts.md`) mění jen commit s prefixem `CONTRACT:`.
