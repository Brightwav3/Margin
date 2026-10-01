# STATUS — živý stav projektu

Poslední aktualizace: 2026-10-01 · Aktivní milestone: **UI ke kontrole (M0–M11)**; agentní vrstva (MA1–MA4) odložena

Legenda: ⬜ nezačato · 🟦 rozpracováno · 🟨 ke kontrole · ✅ přijato · ⛔ blokováno

## Milestony

Legenda: ⬜ nezačato · 🟦 rozpracováno · 🟨 ke kontrole · ✅ přijato · ⛔ blokováno

| M | Název | BE váha | UI váha | Σ | Kol kontroly | Kalendářně | Stav | Kontrola | Tag | Poznámka |
|---|---|---|---|---|---|---|---|---|---|---|
| M0 | Kostra, tokeny, komponenty, galerie | 5 | 18 | 23 | 1 | — | 🟨 | `checks/M0.md` | | UI hotovo, čeká na schválení |
| M1 | Shell | 0 | 28 | 28 | 1 | — | 🟨 | `checks/M1.md` | | CP0 |
| M2 | Model a fixtures | 12 | 2 | 14 | — | — | 🟦 | (testy) | |  |
| M3 | Přehled předmětů (1a, 1b) | 5 | 29 | 34 | 1 | — | 🟨 | `checks/M3.md` | | UI hotovo, čeká na schválení |
| M4 | Detail předmětu (2c) | 3 | 27 | 30 | 1 | — | 🟨 | `checks/M4.md` | | CP1 |
| M5 | Vault a index | 35 | 1 | 36 | — | — | 🟦 | `checks/M5.md` | | před startem odsouhlasit spec (§12) |
| MA0 | Agent: základy (provenance, ID, undo, souběh) | 32 | 0 | 32 | — | — | 🟦 | (testy) | | brána před M6 |
| M6a | Editor: source + reading | 11 | 33 | 44 | 1 | — | 🟨 | `checks/M6a.md` | | CP2 |
| M6b | Editor: live | 5 | 25 | 30 | 1 | — | 🟨 | `checks/M6b.md` | | UI hotovo, čeká na schválení |
| M7 | Úkoly | 16 | 22 | 38 | 1 | — | 🟨 | `checks/M7.md` | | před startem schválit návrh |
| MA1 | Agent: povrch nástrojů (MCP, CLI) | 83 | 0 | 83 | — | — | ⬜ | `checks/MA1.md` | | CP5 |
| M8 | Rychlý zápis a Inbox | 25 | 19 | 44 | 1 | — | 🟨 | `checks/M8.md` | | CP3 |
| MA2 | Agent: oprávnění, audit, schvalování | 19 | 43 | 62 | — | — | ⬜ | `checks/MA2.md` | |  |
| M9 | Graf | 17 | 27 | 44 | 1 | — | 🟨 | `checks/M9.md` | | UI hotovo, čeká na schválení |
| M10a | Popupy: navigace a psaní | 12 | 28 | 40 | 1 | — | 🟨 | `checks/M10a.md` | | UI hotovo, čeká na schválení |
| MA3 | Agent v aplikaci | 30 | 25 | 55 | — | — | ⬜ | `checks/MA3.md` | |  |
| M10b | Popupy: data a organizace | 12 | 18 | 30 | 1 | — | 🟨 | `checks/M10b.md` | | UI hotovo, čeká na schválení |
| M10c | Popupy: dialogy a oznámení | 12 | 22 | 34 | 1 | — | 🟨 | `checks/M10c.md` | | UI hotovo, čeká na schválení |
| M10d | Menu, dropdowny a tooltipy | 0 | 45 | 45 | 1 | — | 🟨 | `checks/M10d.md` | | menu se zapojují k obrazovkám průběžně |
| M11 | Obrazovky a stavy | 21 | 37 | 58 | 1 | — | 🟨 | `checks/M11.md` | | CP4 |
| MA4 | Agent: odolnost | 32 | 3 | 35 | — | — | ⬜ | `checks/MA4.md` | |  |
| M12 | Dokončení a vydání | 18 | 22 | 40 | 1 | — | 🟦 | `checks/M12.md` | | M12-04 zrušeno; výkon splněn; zbývá audit přístupnosti, revize uživatelem |
| | **Σ** | **405** | **474** | **879** | | | | | | |

Metriky (viz `04-engineering-rules.md` §9): průměr kol kontroly na milestone — · průměrné čekání na schválení — · cena běhu celkem —

## Otevřená rozhodnutí (blokují start)

| # | Otázka | Blokuje | Stav | Výchozí předpoklad |
|---|---|---|---|---|
| Q1 | Umístění vaultu a kompatibilita s Obsidianem | M5 | ✅ | **schváleno 2026-09-29**: `~/Documents/Margin`, kompatibilní; D-017 |
| Q2 | Rychlý zápis i bez okna aplikace | M8 | ✅ | **schváleno 2026-09-29**: ano, přes menu bar; D-019 |
| Q3 | Rozsah stubů (sdílení, PDF sylabus, sync); Agent už stub není | M10–M11 | ⬜ | jen UI, funkce později |
| Q4 | Vzhled Today/Upcoming a záložek předmětu | M4, M7 | ⬜ | návrh v M4/M7, schválení v CP1 |
| Q5 | Identita úkolu: hash vs. `^id` | M5 | ✅ | **rozhodnuto: stabilní `^id`** (D-012) |
| Q6 | Ikony: Lucide (jako Obsidian) | M0 | ✅ | **rozhodnuto: Lucide** (D-006) |
| Q7 | Developer ID pro notarizaci | M12 | ⬜ | zjistit před M11 |
| Q8 | Výchozí model a poskytovatel vnitřního agenta, klíč v Keychainu, lokální modely | MA3 | ✅ | **rozhodnuto 2026-09-30**: lokální CLI agent (Claude Code, Codex, …) jako Claudian, bez vlastního API klíče; D-023 |
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
- 2026-09-29: Uživatel schválil doporučený formát vaultu (D-017) a aktuální backend/UI smlouvu (D-018) pro postupnou integraci do `main`.
- 2026-09-29: Dokončeno M0-02: Xcode projekt pro arm64, sandbox a hardened runtime; ověřen build na macOS 27.
- 2026-09-29: Uživatel rozhodl Q2: rychlý zápis bude dostupný bez okna aplikace přes menu bar; implementace M8-05 zůstává samostatným úkolem (D-019).
- 2026-09-30: Opraveny nestabilní testy jádra (index po undo přesunu složky, AG-03/M5-07; sweep externích zápisů, AG-04), SHA-256 přes CryptoKit (M5-06), konformitní vaulty bez F_FULLFSYNC. Nový `scripts/test.sh` (quick ~25 s, full ~3 min místo ~5 min).
- 2026-09-30: Uživatel dodal mockupy menu (`Margin Menus.dc.html`, `Margin Menu.dc.html`) a schválil jejich zařazení do plánu UI: nový milestone M10d (M10-24…M10-33, váha 37), celkem 871 (BE 405 / UI 466).
- 2026-10-01: Uživatel dodal mockup menu baru (`Margin Menu Bar.dc.html`, v `Margin Menus` sekce 5a–5k) a zadal ho k realizaci: M10-34…M10-36 v M10d (+8), celkem 879 (UI 474).
- 2026-09-30: Uživatel rozhodl podobu vnitřního agenta (Q8): lokální CLI nad vaultem jako Claudian (D-023, R-22). Důsledek: aplikace bez App Sandboxu; MA3 se přepracuje zvlášť.
- 2026-09-30: M0-03–M0-09 (UI) implementováno na `feat/ui-design-system`: tokeny, Inter, celá sada Lucide (D-020), komponenty, galerie `--screen`, `scripts/snap.sh` (D-021). Návrh generátoru ikon předmětů v galerii (`course-icons`, 6 nových barev palety) čeká na schválení. M0-10 (referenční PNG) a vizuální kontrola `docs/checks/M0.md` zbývají.
- 2026-09-30: M1-01–M1-08 a M2-06 (UI) implementováno na `feat/ui-shell` (navazuje na `feat/ui-design-system`): lišta se záložkami (smrštitelné, přetažení, semafory 16 px / střed 44 px lišty), rail, sidebar s Notes (420 ms), inspektor 300 px, `AppModel`; galerie `shell`, `shell-notes`, `shell-course`, `shell-collapsed`. Ověřeno v živém okně: klik na záložky, přepínání inspektoru, sbalení sidebaru. Neověřeno: přetažení záložky myší (syntetické tažení nástroje gesto nespustilo). M1-09 a `docs/checks/M1.md` zbývají.
- 2026-09-30: M3-01–M3-03, M3-06–M3-08 (UI) implementováno na `feat/ui-courses-overview` nad smlouvou (`CourseCatalog`, `NoteRepository`, `GradeService`, `TaskService`, `CourseListQuery`); galerie `1a`, `1b`, snímky a `docs/checks/M3.md`. Shell: záložky jen mezi sidebarem a inspektorem, tenčí písmo a ikony (pokyn uživatele). Zbývá: schválení hlavičky skupiny a zalomení, M3-05.U blokováno (`BannerStore` mimo API), doplnit fixture (M2-04) pro shodu s mockupem.
- 2026-09-30: UI na stohu větví `feat/ui-course-detail` → `feat/ui-editor` → `feat/ui-tasks-capture` → `feat/ui-graph` → `feat/ui-popups` (nad `feat/ui-courses-overview`, rebase na `main` #31): Workspace s trasami záložek; M4 detail předmětu; M6a/M6b editor (TextKit 1, D-022); M7 Today/Upcoming (návrh); M8 rychlý zápis + Inbox; M9 graf; M10 paleta ⌘K, dialogy, menu předmětu, připomínky. 77 UI testů zelených. Zbývá: M11 (známky 1e, onboarding 1a, hledání 1b, archiv 1f, nastavení 1g/2g, načítání 2c), M10d zbytek (tooltipy, hover karty, výběrová lišta 1d), M12 a napojení aplikace na vault (M5-10.U). Backend: parser nerozpozná „before wed“, fixture neplní `summary.date` z vlastností.
- 2026-10-01: Dokončeno UI plánu mimo agentní vrstvu na `feat/ui-screens` a `feat/ui-app-vault`: M11 (známky, hledání, archiv, nastavení, onboarding, načítání), výběrová lišta 1d, oprava pádu grafu. Aplikace běží na skutečném vaultu: výběr složky se záložkou pro sandbox (D-017 `~/Documents/Margin`), průběh indexu, notifikace, globální rychlý zápis ⌘⇧Space v plovoucím panelu, menu Go; galerie přes `--gallery`. Integrační test prošel první použití na skutečném vaultu a znovuotevření. 85 UI testů zelených, výkon editoru 10 000 slov ~1 ms/úhoz. Zbývá ke schválení: návrhy M4-05, M7-01, hlavička skupiny; neudělané: M10d tooltipy 3b–3i a hover karty, ikona aplikace (M12-05), audit VoiceOver (M12-01), XCUITest (M12-04 jen jako integrační test).
- 2026-10-01: M10d na `feat/ui-app-vault`: tooltipy a hover karty (3a–3h), menu bar podle `Margin Menu Bar.dc.html` (M10-34 File/Edit/View/Window/Help, M10-35 Insert/Format nad editorem, M10-36 Go s historií Zpět/Vpřed a posledními poznámkami; Agent jen vypnutý). Uživatel zadal nový model záložek: v záložkách žijí jen poznámky, místa (předměty, Today, rozvrh…) se ukazují bez záložky a vše se otevírá do jedné záložky, pokud uživatel nechce novou (⌘‑klik, „Open in new tab“, `+`). Opraven pád AppKitu (smyčka aktualizace constraintů v panelu tooltipu a rychlého zápisu). 87 UI testů zelených. Zbývá: audit VoiceOver (M12-01), XCUITest (M12-04).
- 2026-10-01: Uživatel zrušil XCUITest (M12-04 se nedělá); z auditu přístupnosti opraveny skryté zkratkové prvky přes celé okno. Na `feat/ui-course-styles`: paleta 18 barev, ikona předmětu i jako emoji, nový výběr barvy/ikony/emoji s hledáním v celé sadě Lucide a českými návrhy (D-024). Uživatelův vault `~/Margin/Škola` (podzim 2026, 9 předmětů z IS MUNI, 118 poznámek přednášek a seminářů, materiály v `_files/`) ověřen přes služby jádra.
- 2026-10-01: Na `feat/ui-course-settings`: kontextové menu předmětu pravým kliknutím všude (sidebar, titulek stránky předmětu, rozvrh), dialog Nastavení předmětu (kód, vyučující, místnost, fakulta, kredity, rozvrh s libovolnou délkou a druhem hodiny, zkoušky), archivace a obnova jednoho předmětu, smazání do koše, nový semestr (sidebar, Settings, File, ⌘K), import markdown souborů. Smlouva rozšířena (D-025), konformitní testy fixture i vault. Referenční PNG mockupů (`scripts/ref-mockups.sh`, M0-10).
- 2026-10-01: Mockup `Margin Account v3.dc.html` (uživatel, místo serverové v1): na `feat/ui-account-local` popup u avataru (profil, vault, obnova souborů, sync vypnutý, přepnutí vaultu, přihlášení volitelné), nové okno nastavení (Account: Profile, Vault and files, Sync, Sign-in; Options: General, Editor, Appearance, Keyboard shortcuts, Semesters, Notifications, Flashcards/Agent/Plugins vypnuté), dialogy Manage vaults, Remove from list, Restore snapshot. Funkční volby: motiv, velikost písma, stránka po spuštění, potvrzení mazání, globální rychlý zápis, párování závorek, chytré seznamy, sledování změn zvenku. Smlouva rozšířena (D-026).
- 2026-10-01: Editor víc jako Obsidian (M6-13): obrázky `![[…]]` i `![](…)` ze souborů vaultu, tabulky jako mřížka, callouty jako barevné boxy s ikonou, citace s pruhem, zvýraznění, komentáře, matematika (zatím jen jako text), poznámky pod čarou, odkazy na nadpis a `^blok`. Záložky: vše v aktivní záložce, nová jen z kontextového menu nebo `+`. Menu z `Margin Menus` (M10-24…M10-31): obrázek 1h (plná velikost, kopie, uložit, velikost, popisek, text z obrázku přes Vision), styl textu 2i, výběr semestru 2c, přesun s archivovanými předměty 2d, vícenásobný filtr hledání 2h.
- 2026-10-01: M12-02 výkon: snímek grafu s 1030 uzly z ~7 s na 12 ms (cache hranic a stupňů, jedna cesta hran, ořez mimo plátno); start 0,88 s, paměť 111 MB, rychlý zápis 8 ms. Test `AppPerformanceTests` v pomalé vrstvě.
