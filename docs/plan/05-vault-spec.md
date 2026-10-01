# Část 5: Specifikace vaultu (formát dat)

Formát souborů je nejtrvalejší rozhodnutí v projektu — uživatelovy poznámky přežijí aplikaci. Proto se navrhuje předem. Cíl: **čitelné čisté markdown soubory, otevřitelné v Obsidianu, bez zámku na aplikaci.**

Stav: **návrh k odsouhlasení před M5.** Změny po M5 jen s migrací a záznamem v `DECISIONS.md`.

## 1. Struktura složek

```
<Vault>/
├─ Fall 2026/                      ← semestr (složka)
│  ├─ Cell Biology/                ← předmět (složka)
│  │  ├─ _course.md                ← metadata předmětu (frontmatter)
│  │  ├─ Lecture 8 — Cell membrane.md
│  │  ├─ Membrane transport summary.md
│  │  ├─ Glossary.md
│  │  └─ _files/                   ← přílohy (PDF, obrázky, banner.png)
│  └─ Organic Chemistry/ …
├─ _inbox/                         ← nezatříděné zápisy
├─ _archive/                       ← uzavřené semestry
└─ .margin/                        ← data aplikace (bezpečné smazat = přestaví se)
   ├─ index.sqlite                 ← cache: FTS5, úkoly, odkazy
   ├─ history/                     ← verze poznámek
   ├─ semesters.json               ← semestry, týdny, svátky
   └─ settings.json
```

Pravidla:
- Vše mimo `.margin/` je zdroj pravdy a čitelné člověkem. `.margin/` je odvozené (kromě `history/` a `settings.json`).
- Názvy souborů = titulek poznámky (včetně pomlček a mezer). Nepovolené znaky (`/ : \`) se nahradí, titulek zůstane v `# H1`.
- Přejmenování souboru **aktualizuje wikilinky** v celém vaultu (volitelně, výchozí zapnuto).

## 2. Frontmatter poznámky

```yaml
---
date: 2026-09-24
class: "[[Cell Biology]]"
type: lecture          # lecture | lab | seminar | tutorial | study | note
session: 2026-09-24T10:00   # navázání na hodinu v rozvrhu (volitelné)
tags:
  - membranes
  - midterm
due: 2026-10-01        # volitelné (pro poznámky typu assignment)
weight: 25%            # volitelné
---
```

- Neznámé klíče se **zachovají** a nezmění pořadí.
- Datum ve formátu ISO; zobrazení `24.09.2026` je jen prezentace.
- `class` je wikilink na předmět; tolerantní parsování (`class: Cell Biology`, `class: "[[Cell Biology]]"`).

## 3. Úkoly v textu

```markdown
- [ ] Ask about the osmosis question in office hours @ Tue
- [ ] Redraw the bilayer diagram from memory @before-midterm
- [x] Read chapter 6 @2026-09-30
```

Rozpoznání termínu (za znakem `@`, pořadí priorit):
1. ISO datum `@2026-10-02`
2. Den v týdnu `@Tue`, `@tuesday` (nejbližší budoucí; v pondělí `@Mon` = příští pondělí, dnešek se zapisuje `@today`)
3. Relativní `@today`, `@tomorrow`, `@next-week`
4. Událost předmětu `@before-midterm`, `@before-exam`, `@before-lecture` (vyhodnocuje se z rozvrhu/zkoušek předmětu)
5. Bez termínu = jen úkol předmětu (Inbox → později).

Úkol má **stabilní ID** (`^t-4f2a` na konci řádku, Obsidian block ID). **Rozhodnuto kvůli agentům** (`10-agent-native.md`): musí adresovat úkol napříč úpravami textu. Řádek bez ID dostane ID při prvním zpracování aplikací; v Obsidianu zůstává čitelný.

## 4. Odkazy

- `[[Note]]`, `[[Note|alias]]`, `[[Note#Heading]]`, `[[Cell Biology/Glossary]]` pro nejednoznačnost.
- Rozlišení: nejdřív stejný předmět, pak celý vault; při shodě se ptát.
- Neexistující cíl je platný odkaz („Not created yet“), zobrazí se v Outgoing links s „+“.

## 5. Předmět (`_course.md`)

```yaml
---
name: Cell Biology
code: BIO 201
professor: Dr. Okafor
room: Sci 204
faculty: Sciences
icon: eco                  # název ikony (Lucide nebo Material alias) nebo jedno emoji, např. 🎬
color: bio                 # klíč z palety (18 klíčů, viz níže)
credits: 5
sessions:
  - {day: Tue, time: "10:00", length: 1.5, kind: Lecture, room: "Sci 204"}
  - {day: Thu, time: "10:00", length: 1.5, kind: Lecture, room: "Sci 204"}
exams:
  - {title: Midterm, date: 2026-10-01, weight: 25%}
grading:
  - {label: Problem sets, weight: 20%}
  - {label: Lab reports, weight: 25%}
  - {label: Midterm, weight: 25%}
  - {label: Final exam, weight: 30%}
---
```

Klíče palety: `bio chem math hist econ phil` (z mockupů) a `teal orange pink sky olive slate indigo rose lime cyan brown gold` (D-024). Neznámý klíč = neutrální šedá, soubor zůstává platný.

## 6. Inbox položka (`_inbox/2026-09-28 0912 Email Dr. Okafor.md`)

```yaml
---
captured: 2026-09-28T09:12
source: phone | quick-capture | share
kind: task | note | link | image
---
Email Dr. Okafor about lab partner
```
Po zatřídění se soubor **přesune** do složky předmětu (a `_inbox/` se vyčistí).

## 7. Známky (`_grades.md` v předmětu)

Markdown tabulka nebo frontmatter seznam `{item, group, score, max, date}`. Výpočet váženého průměru z `_course.md → grading`. Ručně editovatelné.

## 8. Index a cache

- `.margin/index.sqlite`: tabulky `notes`, `links`, `tasks`, `tags`, `fts` (FTS5). Přestavitelný na 100 % z markdown souborů.
- Verze schématu v `PRAGMA user_version`; při změně schématu přestavba (ne migrace), protože je to cache.
- Detekce změny: mtime + velikost + hash obsahu; při shodě přeskočit.

## 9. Historie verzí

- Snapshot při uložení, nejvýš jednou za 5 min a při zavření poznámky.
- Držet posledních 50 verzí nebo 30 dní (co je víc), formát: zlib komprimovaný celý text + časová značka.
- Obnova = zápis staré verze jako nové (nic se nemaže).

## 10. Kompatibilita a bezpečnost dat
- Zápis vždy atomicky (`write to temp` + `rename`), zachovat oprávnění a čas vytvoření.
- Při externí změně otevřeného souboru: trojcestné slučování, jinak banner „Soubor se změnil“ s volbou, ne přepsání.
- Nikdy nemazat uživatelský soubor napevno — koš macOS.
- Testovací sada `Tests/Fixtures/vaults/`: prázdný vault, ukázkový week5, vault z Obsidianu se zvláštnostmi (aliasy, vnořené složky, callouty, tabulky, kód s `- [ ]` uvnitř bloku kódu, který úkolem **není**).

## 11. Otevřené k odsouhlasení
1. ~~Identita úkolu~~ — **rozhodnuto: stabilní `^id`** (viz §12).
2. Semestr jako složka (doporučeno) vs. plochá struktura s frontmatterem.
3. Rozvrh a zkoušky v `_course.md` (doporučeno, jde ručně editovat) vs. jen v `.margin/`.
4. Sdílení vaultu s Obsidianem: musí zůstat čistý (žádné vlastní syntaxe), ano/ne. Doporučeno **ano**; dvě rozšíření (`@ termín`, `session:`) jsou textově bezpečná.

## 12. Rozšíření pro agenty

Zdroj: `10-agent-native.md`. Nutné před M6 (milestone MA0).

```
.margin/
├─ audit.jsonl          ← append-only log zápisů (čas, původce, nástroj, ChangeSet)
├─ proposals/           ← navržené změny čekající na schválení (JSON s diffem)
├─ changesets/          ← inverzní patche pro undo
├─ identities.json      ← agentní identity: id, název, popis, profil, rozsah, limity, soukromí, politika převzetí
├─ connections.json     ← spárovaní klienti: id, název, allowlist identit, hash tokenu (token sám v Keychainu)
├─ run/                 ← lokální socket
└─ agent/
   ├─ conversations/    ← historie chatu vnitřního agenta
   └─ skills/           ← *.md definice postupů
```

- **Stabilní ID poznámky:** `id: n-9c1e` ve frontmatteru (vloží aplikace při prvním otevření; existující se nemění).
- **Stabilní ID úkolu:** `^t-…` na konci řádku, viz §3.
- **Provenance:** není v souborech (nezanášet poznámky), jen v `audit.jsonl`; UI značka „změnil agent“ se odvozuje z auditu.
- **`baseVersion`:** hash obsahu souboru, se kterým agent pracoval; zápis s jiným hashem = `.conflict`.
- **ChangeSet:** drží se 30 dní nebo 500 kusů.
- **Kompatibilita s Obsidianem:** přidává se jen `id:` do frontmatteru a `^id` za úkol; oboje je platný Obsidian.
