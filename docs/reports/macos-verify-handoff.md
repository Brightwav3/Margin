# Handoff: opravy pro macOS (2026-09-29)

Větev `fix/core-macos-verify` byla lokálně sloučena do `main` jako `31dc0c9` (`feat(api): integrate core backend and vault`). Změny nebyly pushnuty.
**Stav: macOS ověření dokončeno; tento report je poslední dokumentační změna k integraci.**

## Kontext
Noční běh psal jádro na Linuxu. Na macOS 27 (arm64) mělo první `swift test` 76 problémů za 29 minut. Příčiny byly hlavně v macOS chování, ne v testech, a žádný test jsem neoslabil.

## Co je opraveno (commity od nejstaršího)
| Commit | Oprava |
|---|---|
| `1156a5f` | Watcher: kořen přes `realpath` (`/private/var` vs `/var` posouvalo všechny cesty) |
| `e49165b` | Testy používají `PortableTrash`, ne Finder koš |
| `d992b26` | CRLF: kontroly řádků přes unicode scalar (`"\r\n"` je jeden `Character`) |
| `3f055a1` | Nové soubory přes `renamex_np(RENAME_EXCL)`; FSEvents nehlásí smazání souborů z `link`+`unlink` |
| `7f9fc47` | Limit délky jména se měří v NFC (macOS vrací NFD) |
| `4c032ae` | Watcher hlásí vlastní zápis vrácený zvenku (později nahrazeno v `5b7f2c6`) |
| `2fbc666` | Zrušení FSEvents streamu na jeho frontě (use-after-free, 3 crash reporty) |
| `a651e09` | `POSIXFileSystem(durability:)`, testy `.ordinary`, produkce `.full` (F_FULLFSYNC) |
| `5b7f2c6` | Záznamy watcheru z jedné verze souboru (stat, hash, stat); jakýkoli přepis je změna |
| `5006d5d` | Po chybě `notFound` obnovit celý index, katalog kurzů a úkoly |
| `44ed8cb` | Při selhání kontroly restartu vypsat oba modely pro diagnostiku |

## Výsledek ověření na macOS 27 (arm64)
- `scripts/check.sh` prošel před landingem: lint plánu i commitů, build, testy.
- Plný běh po opravách: 719 testů v 95 suites a 293 konformitních testů v 26 suites prošlo.
- Test archivace semestru prošel bez změny jeho očekávání.
- Souběh `notes.delete` + smazání nadřazené složky odhalil zastaralý index/katalog po chybě `notFound`. `VaultBackend` nyní při této chybě znovu načte index, katalog kurzů i úkoly z disku; oprava je v `31dc0c9`.
- Při případném budoucím timeoutu `matchesRestart` testy vypíšou oba modely pro diagnostiku.
- Výpisy `DBG` nejsou ve `Sources/` ani `Tests/`.
- Schválení specifikace vaultu a API je zaznamenáno jako D-017 a D-018.

## Pomocné skripty (scratchpad session)
`.../scratchpad/repeat.sh "<filtr>" <N>` opakuje test do prvního selhání. `full-repeat.sh N` opakuje celou sadu. `ips.py <report>` vytáhne zásobník z crash reportu (`~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-*.ips`).

## Stav ostatních worktrees
- `Margin-verify` zůstává čistý, odpojený na starším základu `origin/feat/core-finish-leftovers`; jeho výchozí kódový stav je součástí squash integrace na `main`.
- Worktree `Margin-macos-fix` zůstává odpojený na výsledném kódu; tento report je samostatná dokumentační změna čekající na landing.
- Změny jsou pouze lokálně na `main`; push nebyl proveden.
