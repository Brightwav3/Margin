# Část 9: Smlouva mezi backendem a UI

Backend (`MarginCore`) a UI (`MarginUI`) se potkávají **jen tady**. Díky tomu se dají vyvíjet nezávisle: UI běží na fixture implementacích, backend se testuje bez oken.

## 1. Pravidla

0. **Zápisy nesou kontext:** každá zapisovací metoda přijímá `Actor`, `baseVersion?`, `dryRun`, `idempotencyKey?` a vrací `ChangeSet` (viz `10-agent-native.md`).
1. **UI importuje jen `MarginCore/API`** (protokoly a hodnotové typy). Nikdy nesahá na soubory, SQLite, FSEvents ani `NoteIndex` přímo.
2. **Každý protokol má dvě implementace**: `Fixture…` (v paměti, data z `Fixtures.week5`) a `Vault…` (skutečná, nad soubory). UI se přepíná mezi nimi v `AppEnvironment`.
3. **Konformitní testy**: jedna sada testů na protokol běží proti oběma implementacím. Fixture, která se chová jinak než vault, je chyba.
4. **Souběžnost**: backend jsou `actor`y nebo `Sendable` služby; UI je `@MainActor`. Změny se doručují přes `AsyncStream` nebo `Observation`, ne přes callbacky.
5. **Hodnotové typy**: přes hranici jdou jen `Sendable` `struct`/`enum` (`Course`, `TaskItem`, …), žádné reference na objekty backendu.
6. **Chyby**: backend hází typované `MarginError` (`.io`, `.conflict`, `.notFound`, `.invalid`, `.readOnly`); UI je mapuje na banner/toast. Žádné `fatalError` v jádru.
7. **Čas**: vše přes `Clock` z API, nikdy `Date()`.
8. **Změna smlouvy** = záznam v `DECISIONS.md` a úprava obou implementací + konformitních testů v jednom commitu.

## 2. Služby (`MarginCore/API`)

| Protokol | Odpovědnost | Hlavní metody / proudy | Používají (UI) |
|---|---|---|---|
| `Clock` | „Teď“, dnes, týden semestru | `now`, `today`, `weekOfSemester` | vše |
| `CourseCatalog` | Předměty, semestry, rozvrh | `courses(query:)`, `course(id)`, `archivedCourses()`, `sessions(week:)`, `updates: AsyncStream` | 1a, 1b, sidebar, rail |
| `CourseCatalogWriter` | Vytvoření/úprava předmětu | `create`, `rename`, `setStyle`, `update` (nastavení: kód, vyučující, místnost, fakulta, kredity, rozvrh, zkoušky), `setArchived(semester:)`, `setArchived(course:)`, `delete` (do koše), `override(session:)` | 1g, 2f, 3a, 3c |
| `NoteRepository` | Poznámky (čtení/zápis) | `notes(course:filter:)`, `open(id)`, `attachment(named:near:)` (vložené obrázky, PDF), `save(id, text)`, `create`, `rename(id, to:)` (soubor, titulek, odkazy), `filePath(id)`, `move`, `delete → koš`, `externalChanges` | 2c, editor |
| `NoteAnalysis` | Odvozené údaje z textu | `outline`, `backlinks`, `outgoing`, `stats`, `properties(id)` | editor, inspektor |
| `PropertyService` | Vlastnosti (frontmatter) | `types`, `set(key, value, on:)`, `remove` | Properties, 1e |
| `TaskService` | Úkoly z poznámek | `today()`, `upcoming()`, `tasks(course:)`, `toggle(id)`, `location(of:)`, `setDue(id, …)` | Today, Upcoming, editor |
| `CaptureService` | Rychlý zápis | `parse(String) → CaptureDraft`, `commit(draft)` | 5a, popup 1b |
| `InboxService` | Inbox | `items`, `triage(item, course, when, kind)`, `delete` | 5a, 5b |
| `GraphService` | Graf | `graph(scope:filter:)`, `ego(note, depth)`, `layout(graph) → AsyncStream<positions>` | 4a |
| `SearchService` | Hledání | `search(query, filter) → [Hit]`, `suggestLinks(prefix)`, `excerpt(note)` | ⌘K, `[[`, 1b, hover |
| `CommandRegistry` | Příkazy palety a slash | `commands(matching:)`, `run(id)` | 1a, 2a |
| `GradeService` | Známky | `grades(course)`, `average(course)`, `add(grade)` | 1e, 2e |
| `HistoryService` | Verze poznámek | `versions(note)`, `recentVersions(limit)` (File recovery), `diff(a,b)`, `restore(version)` | 2e, Settings › Vault and files |
| `SettingsStore` | Nastavení a lokální profil | typované klíče (`Settings.profile`, obecné, editor, vzhled, soubory, semestry), `changes: AsyncStream` | 2g, Settings, účet (Account v3) |
| `ReminderService` | Notifikace | `schedule(for:)`, `cancel`, `permission` | 1i |
| `ExportService` | Export | `export(note, format)` (`pdf`, `md`) | 3b |
| `IndexStatus` | Stav indexace a velikost vaultu | `progress: AsyncStream<IndexProgress>`, `vaultStats()` | 2c loading, Settings › Vault and files |
| `AgentService` | Vnitřní agent (reálný, MA3) | `converse(context) → AsyncStream`, `suggestions(for:)`, `runSkill(id)` | Agent tab, 1d, 3d |
| `ToolRegistry` | Katalog nástrojů generovaný ze služeb | `tools`, `call(tool, args, actor, dryRun, idempotencyKey)` | MCP, CLI, vnitřní agent |
| `IdentityService` | Agentní identity (role, profil, rozsah, limity, politika převzetí) | `identities`, `create`, `update`, `templates` (jen UI/člověk) | správa identit |
| `ConnectionService` | Párování klientů a allowlist identit | `pair(code)`, `connections`, `revoke`, `allowlist(client)` (jen UI) | dialog párování |
| `SessionService` | Session klienta pod identitou | `start(identity, purpose)`, `end`, `active`, `authorize(call) → Decision` | dialog převzetí, indikátor aktivity |
| `PermissionService` | Vynucení profilu identity | `authorize(call, session)` (profil mění jen UI) | správa identit |
| `ReviewQueue` | Navržené změny | `proposals`, `approve`, `reject`, `approveAll(agent)` | review UI |
| `ChangeSetStore` | Skupiny zápisů s inverzí | `changes`, `undo(id)`, `undo(agent, since)` | undo v UI, audit |
| `AuditLog` | Append-only log zápisů | `entries(filter)`, `updates` | aktivitní log, značky původu |

`AppEnvironment` drží všechny služby jako `let`. Preview a galerie dostávají `AppEnvironment.fixture`.

## 3. Datové typy přes hranici (`MarginCore/API/Types`)

`Semester`, `Course`, `CourseStyle`, `Session`, `SessionOverride`, `Exam`, `NoteSummary`, `Note`, `NoteProperty`, `OutlineItem`, `Backlink`, `TaskItem` (`id`, `text`, `due`, `label`, `done`, `source: TaskLocation`), `DueLabel`, `InboxItem`, `CaptureDraft` (`text`, `course?`, `due?`, `tags`, `kind`, `attachTo?`), `Graph`/`GraphNode`/`GraphEdge`, `Grade`, `NoteVersion`, `SearchHit`, `MarginError`.

Všechny jsou `Codable`, `Sendable`, `Hashable`, `Identifiable` (kde to dává smysl) a mají `Fixtures` instanci.

## 4. Pořadí dodání (kdo koho čeká)

| Kdy | Backend dodá | UI to potřebuje pro |
|---|---|---|
| M2 | typy (vč. `Actor`, `ChangeSet`) + `Clock` + fixture implementace všech protokolů kromě těch dodaných později | celé M3–M4 (běží na fixture) |
| M5 | `VaultStore`, `NoteRepository`, `NoteIndex` (skutečné) | přepnutí M3/M4 na vault (M5-10) |
| MA0 (před M6) | `Actor`, provenance, stabilní ID, `ChangeSet`+undo, `baseVersion` | zapisovací UI od M6 |
| M6 | `NoteAnalysis`, `PropertyService`, `MarkdownTokenizer`, `BlockModel` | editor, inspektor |
| M7 | `TaskService` | Today, Upcoming, úkoly předmětu |
| M8 | `CaptureService`, `InboxService`, globální zkratka | overlay, Inbox |
| M9 | `GraphService`, `ForceLayout` | graf |
| M10 | `SearchService` (FTS5), `CommandRegistry`, `CourseCatalogWriter`, `ReminderService`, `ExportService` … | popupy |
| MA1–MA4 | `ToolRegistry`, `IdentityService`, `ConnectionService`, `SessionService`, MCP/CLI/HTTP, `PermissionService`, `ReviewQueue`, `AuditLog`, `AgentService` | agentní UI (AG-15…36) |
| M11 | `GradeService`, `HistoryService`, `SettingsStore`, `IndexStatus` | Screens a stavy |

**Pravidlo:** UI část úkolu (`.U`) smí začít, až je hotové **rozhraní** jeho backendové části (`.B`) a existuje `Fixture…` implementace. Nemusí čekat na skutečnou implementaci.

## 5. Konformitní testy

Pro každý protokol jeden soubor `Tests/Conformance/<Service>ConformanceTests.swift`. Generická funkce `runSuite(make: () -> Service)` se volá s `FixtureX` i `VaultX` (nad dočasným vaultem ze `Fixtures/vaults`). Kontroluje se stejné pozorovatelné chování: pořadí, hranice dnů, chybové stavy, doručení `updates`.

## 6. Kdo co vlastní

| | Backend | UI |
|---|---|---|
| Modul | `MarginCore` (+ malé platformní služby v `App/Platform`) | `MarginUI` (+ `App/Margin`) |
| Testy | Swift Testing, fuzz, výkon, konformitní | snapshoty, XCUITest |
| Kontrola | čísla a testy (bez očí) | vizuální kontrola proti mockupu |
| Nesmí | importovat SwiftUI/AppKit (kromě `App/Platform`: hotkey, notifikace) | importovat soubory, SQLite, `NoteIndex` |
