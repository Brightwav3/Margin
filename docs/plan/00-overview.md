# Margin — plán přepisu do Swiftu (část 0: přehled a pravidla)

Zdroj: handoff z Claude Design (`School markdown manager UI mockups`), soubory `Margin.dc.html`, `Margin Screens.dc.html`, `margin-popups.dc.html`, `Sidebar.dc.html`, `Inspector.dc.html`, `Margin Menus.dc.html` (+ komponenta `Margin Menu.dc.html`, dodáno 2026-09-30), `margin-tokens.css`.
Cíl: fungující macOS aplikace, každý milestone končí **vizuální kontrolou** proti konkrétním mockupům.

**Pro agenty:** začněte v `AGENTS.md` (kořen repozitáře) a `docs/git-workflow.md`. Pravidla jsou vynucená git hooky, guardem a CI, viz D-015 a D-016.

Části plánu (čtěte v tomto pořadí):
- `00-overview.md` — tento soubor: rozhodnutí, architektura, jak se dělá vizuální kontrola
- `01-milestones-foundation.md` — M0–M5: co se staví a jak se kontroluje
- `02-milestones-features.md` — M6–M9: editor, úkoly, rychlý zápis + Inbox, graf
- `03-milestones-surfaces.md` — M10–M12: popupy, zbylé obrazovky a stavy, dokončení
- `04-engineering-rules.md` — pravidla práce: DoR/DoD, git, testy, rozpočty výkonu, kontrolní body
- `05-vault-spec.md` — formát dat (nejtrvalejší rozhodnutí; odsouhlasit před M5)
- `09-contracts.md` — smlouva mezi backendem a UI (protokoly, fixture implementace, konformitní testy)
- `10-agent-native.md` — **aplikace pro AI agenty**: nástroje, oprávnění, schvalování, audit, bezpečnost, milestony MA0–MA4
- `11-schedule-and-gates.md` — pořadí milestonů, integrační brány, vlny práce, lidské brány, rozhodnutí před vlnou
- `backend/README.md` a `ui/README.md` — **dvě větve úkolů** (ID, kritéria, váha); backend se kontroluje testy, UI vizuálně

Dvě větve práce: **backend** (`MarginCore`, testy) a **UI** (`MarginUI`, vizuální kontrola); potkávají se jen přes `09-contracts.md`.

Živé dokumenty, které se průběžně aktualizují: `STATUS.md`, `DECISIONS.md`, `RISKS.md`.

## 1. Rozhodnutí

| Téma | Rozhodnutí |
|---|---|
| Jazyk / UI | Swift 6.4, SwiftUI pro obrazovky, AppKit pro editor, titulkovou lištu a overlaye |
| Architektury CPU | **Jen Apple Silicon** (`ARCHS = arm64`, žádný universal binary) |
| Minimální macOS | Bez zvláštního požadavku na zpětnou kompatibilitu. Deployment target = aktuální SDK (macOS 27), aby se nemusely psát `#available` větve. Jde kdykoli snížit. |
| Data | Markdown soubory ve složce (vault) + index v paměti; hledání přes SQLite FTS5 (M10) |
| Projekt | Swift Package (`MarginCore`, `MarginUI`) + tenká Xcode aplikace `Margin`. Bez xcodegen/tuist. |
| Písmo | Inter (400/500/600/700) přibalené v aplikaci |
| Ikony | **Lucide** (stejná sada jako Obsidian), ISC licence. Ve Swiftu jako vygenerované vektorové `Shape` z SVG v pevné verzi, bez závislosti za běhu. Mapování z Material názvů mockupu v jednom souboru `Icons.swift`. |
| Design | Pravdou je `margin-tokens.css`, ne `_ds` tokeny (ty jsou přepsané). Viz tabulka tokenů níže. |
| Tmavý režim | Mockup ho nemá. Není v rozsahu; tokeny ale psát jako semantické, aby šel přidat. |
| Agenti | **Agenti jsou plnohodnotní klienti aplikace** (vnější přes MCP/CLI/App Intents i vnitřní chat), ne UI stub. Parita s člověkem: nástroje se generují ze služeb. Viz `10-agent-native.md`. |

## 2. Tokeny (z `margin-tokens.css`)

Barvy: ink `#1C1E26`, sekundární `#686C78`, terciární `#9A9DA6`, okraj `#DFE1E6`, jemný okraj `#E9EAEE`, sidebar `#F6F6F8`, sunken `#F3F4F6`, modrá `#2F6BEB` (hover `#2457D6`, soft `#E6EDFD`, ring `#CFDDFB`), termín `#D93F33` (soft `#FCECEC`), pozadí plátna `#E4E5E9`.
Písmo: 12 / 13 / 15 (UI) / 17 (editor) / 20 (titulky) / 30 (stránka), tracking −0.2 pt.
Rádiusy: 6 (chip), 8 (ovládací prvek), 10–12 (karta), 14–16 (okno, dialog).
Stíny: karta `0 12 40 rgba(28,30,38,.10)`, popover `0 12 32 .16`, modal `0 24 64 .24`.
Předměty (bg / fg / dot):

| id | název | bg | fg | dot | ikona |
|---|---|---|---|---|---|
| bio | Cell Biology | `#D8EFD9` | `#2F7D3E` | `#6FBF7A` | eco |
| chem | Organic Chemistry | `#D9E7DC` | `#2F5D3A` | `#7FA88A` | science |
| math | Linear Algebra | `#D6E2FA` | `#274FA8` | `#6E97EC` | change_history |
| hist | Modern Europe | `#FBE8C4` | `#8F5D0E` | `#E8B85C` | account_balance |
| econ | Macroeconomics | `#E5DEF8` | `#5B41B0` | `#9A86DE` | trending_up |
| phil | Philosophy of Mind | `#FADAD6` | `#B3372B` | `#EC8A80` | psychology |

## 3. Architektura

```
Margin/
├─ Package.swift
├─ Sources/
│  ├─ MarginCore/        (bez UI, testovatelné)
│  │  ├─ Model/          Course, Session, Note, TaskItem, InboxItem, Semester, Grade
│  │  ├─ Markdown/       Frontmatter, MarkdownParser, TaskExtractor, WikilinkExtractor
│  │  ├─ Vault/          VaultStore (soubory), FileWatcher, NoteIndex
│  │  ├─ Capture/        QuickCaptureParser (předmět + datum z jednoho řádku)
│  │  └─ Graph/          GraphBuilder, ForceLayout
│  └─ MarginUI/
│     ├─ Theme/          Tokens, Fonts, Icons
│     ├─ Components/     Chip, Badge, MarginButton, CheckboxView, SwitchView, CourseTile, Card
│     ├─ Shell/          WindowChrome (AppKit), Rail, SidebarPanel, InspectorPanel
│     ├─ Courses/  Editor/  Tasks/  Capture/  Graph/  Popups/  Screens/
│     └─ Debug/          ScreenGallery
├─ App/                  Xcode projekt Margin.app
├─ Tests/                MarginCoreTests, snapshoty
└─ docs/  plan/  checks/
```

Pravidla:
- Logika (parsování, index, parser rychlého zápisu, graf) žije v `MarginCore` bez importu SwiftUI a má unit testy.
- Jeden zdroj pravdy: `AppModel` (`@Observable`) drží vybrané okno, záložky, panely; `VaultStore` drží soubory.
- Každá obrazovka se dá otevřít samostatně s fixture daty (viz galerie níže).

## 4. Jak se dělá vizuální kontrola

Každý milestone má sekci **Vizuální kontrola** se seznamem ID mockupů a bodů k porovnání. Mechanismus:

1. **Galerie obrazovek (`ScreenGallery`)** vzniká v M0. Debug okno se seznamem všech obrazovek pod ID z mockupu (`1a`, `1b`, `2c`, `3a`, …, `popups/1a`, `screens/1e`). Klik otevře obrazovku ve velikosti mockupu (1240×820) s fixture daty.
2. **Spuštění z příkazové řádky**: `Margin --screen 3a --size 1240x820` otevře rovnou konkrétní obrazovku.
3. **Snímky**: skript `scripts/snap.sh <id>` vyrenderuje obrazovku do `docs/checks/<milestone>/<id>.png` (přes `NSView.bitmapImageRepForCachingDisplay`).
4. **Referenční snímky**: mockupy se otevřou v prohlížeči (`Margin.dc.html` atd.) a uloží se vedle do `docs/checks/reference/<id>.png`. Dělá to člověk nebo agent na pokyn, bez toho se kontrola dělá očima vedle sebe.
5. **Checklist**: u každého milestone jsou body typu „rádius karty 12, okraj 1 px `#E4E5E9`, banner výška 92“. Odškrtává se ve `docs/checks/<milestone>.md`.
6. **Brána**: milestone se uzavírá až po schválení kontroly uživatelem. Odchylky se zapíšou jako úkoly, ne potichu přeskočí.

## 5. Definice hotovo (pro každý milestone)
- Sestaví se bez varování (`xcodebuild -scheme Margin -destination 'platform=macOS,arch=arm64'`).
- Unit testy `MarginCore` projdou.
- Obrazovky z milestone jsou v galerii a odpovídají mockupu podle checklistu.
- Kde to milestone slibuje „funguje“, prošel se ruční scénář popsaný v sekci **Funguje**.

## 6. Otevřené otázky (nutno rozhodnout před danými milestony)
1. **Před M5**: kde vault bydlí (výchozí `~/Documents/Margin`), a smí se do něj psát i z Obsidianu (potom je nutný file watcher a tolerance k cizím změnám)?
2. **Před M8**: má rychlý zápis jet i při zavřeném okně (login item / menu bar agent), nebo stačí, když aplikace běží?
3. **Před M10/M11**: co s funkcemi, které mockup jen naznačuje (sdílení se spolužáky, import ze sylabu z PDF, synchronizace mezi zařízeními). Agent už stub není — viz `10-agent-native.md` a otázky Q8–Q11 v `STATUS.md`.
4. **Today / Upcoming** mockup neobsahuje (jen v textu „add Today and Upcoming views“). M7 je navrhne v duchu Things 3; nutné odsouhlasit vzhled.
