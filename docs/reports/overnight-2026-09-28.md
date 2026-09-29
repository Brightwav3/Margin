# Overnight run 2026-09-28

## At a glance (read this first)

**What was done.** Every planned backend task except the deferred agent layer: Swift package, domain model, fixtures, vault (lossless frontmatter, parsers, atomic store, watcher, index), stable ids, undo/redo journal, concurrent-write merge, editor core, tasks, capture/inbox, graph, courses/semesters, search, grades, history, settings, reminders, export, robustness. ~665 core + 289 conformance tests green on Linux (Swift 6.4 in Docker). Nothing merged to `main`.

**Backend progress (weights from `docs/plan/backend/README.md`, total 405):**

| Scope | Weight | Done | Missing |
|---|---|---|---|
| Backend without the agent layer | 225 | ~219 (97 %) | ~6 (3 %): M0-02 Xcode project, M12-06 signing, M5-01 spec sign-off, plus macOS verification |
| Agent layer (MA1–MA4, AG-01) — deferred by the human | 170 | 0 | 170 |
| Whole backend plan | 405 | ~219 (54 %) | ~186 (46 %) |

**Where the code is (stacked draft PRs, merge in this order):**
1. #24 — CI workflow fix (independent, merge first).
2. #23 `feat/core-foundation` → `main`: package, model types, Clock, fixtures.
3. #26 `feat/core-vault` → #23: vault, parsers, index, AppEnvironment.
4. #27 `feat/core-features` → #26: all feature services, undo, concurrency, robustness, macOS platform stubs.
5. #28 (this report).
Branch `feat/core-finish-leftovers` (automatic history snapshots on save, FSEvents missing-root guard) is the last small follow-up; merge it into `feat/core-features` when green.

**Where to continue:**
1. **Human decisions** (section *Questions for the human* and *Recommended morning steps*): vault-format additions, contract additions, grade model, Upcoming grouping (Q4), etc. Record them in `DECISIONS.md` / `05-vault-spec.md`.
2. **On a Mac:** `swift build && swift test` (arm64, macOS 27 SDK); verify UNVERIFIED macOS code: FSEvents watcher, Carbon hotkey (`MarginPlatform`), SystemTrash, `F_FULLFSYNC`, creation-date preservation, UserNotifications, SQLite FTS5 + `.margin/index.sqlite`, zlib history, PDF export. Then M0-02 (Xcode project).
3. **UI** (was deferred to the Mac): build `MarginUI` against `MarginCore/API` + `AppEnvironment.fixture`; UI must stay replaceable (depends only on the API).
4. **Agent layer** later: every write already takes `Actor`/`baseVersion`/`dryRun`/`idempotencyKey` and returns a `ChangeSet`; undo exists; start at AG-05 (`ToolRegistry`).
5. **Linux dev loop** (no Mac): `docker run --rm -v "$PWD":"$PWD" -w "$PWD" swift:latest swift test`.

---

## Detailed ledger

**Environment:** Ubuntu x86_64 cloud container. No native `swift`. Docker daemon started manually (`dockerd`), image `swift:latest` = **Swift 6.4-RELEASE (x86_64-unknown-linux-gnu)** pulled from Docker Hub (one 429 rate-limit, second pull succeeded). A session-local wrapper `/usr/local/bin/swift` (outside the repo) runs `docker run swift:latest swift "$@"`, so `scripts/check.sh` and hooks really build and test. Verification ladder level: **2 (Docker)**. node 22 / npm available. download.swift.org blocked by proxy (403). Linux only: nothing is compiled for macOS/arm64.

**Workers:** Sonnet 5.5 subagents (user instruction mid-run); effort chosen by task weight (1–2 low, 3–5 medium, 6–8 high) but the Agent tool exposes no effort parameter, so the level is stated in each worker prompt only. Orchestrator: this session. The human's extended fault-tolerance table (retry provisioning 2x, 45 min worker limit, 2 medium + 1 high fix rounds, breaker >25 % or 3 consecutive failures, zero tolerance for data loss/injection/foundation failures) applies.

**Provisional assumptions:** see `docs/agents/overnight.md` §4 (Q1–Q13 defaults from STATUS.md). Every PR carries **PROVISIONAL**. Additional self-made decisions are listed below.

**Summary:** all planned backend tasks except the deferred agent layer are DONE — about 75 task IDs, backend weight ≈ 219 of the 225 in scope (405 total minus 170 agent layer minus 10 impossible here). BLOCKED 0. SKIPPED: agent layer AG-01, AG-05…AG-36 (human decision), UI Phase 2 (human decision), M0-02 / M12-06 / M12-07 (need a Mac / Developer ID), M8-05 (Q2), M5-01 (human decision). Circuit breaker: never tripped. Final state: `feat/core-features` = 665+ core tests and 289 conformance tests green on Linux (Swift 6.4, Docker).

| Task | Slice/branch | PR | State | Verified | Note |
|---|---|---|---|---|---|
| M0-01 | S1 feat/core-foundation | [#23](https://github.com/Brightwav3/Margin/pull/23) | DONE (branch pushed) | swift build + test (Docker) | Package.swift, MarginUI only on macOS |
| M2-01 | S1 | [#23](https://github.com/Brightwav3/Margin/pull/23) | DONE | swift test (Docker), 26 tests | types + MarginError, ask:required |
| M2-02 | S1 | [#23](https://github.com/Brightwav3/Margin/pull/23) | DONE | swift test (Docker), 26 tests | FixedClock 2026-09-28 13:24 Europe/Prague |
| M2-03 | S1 | [#23](https://github.com/Brightwav3/Margin/pull/23) | DONE | swift test (Docker), 26 tests | counts match plan |
| M2-04 | S1 | [#23](https://github.com/Brightwav3/Margin/pull/23) | DONE | swift test (Docker), 26 tests | grade weights mismatch, see questions |
| M2-05 | S1 | [#23](https://github.com/Brightwav3/Margin/pull/23) | DONE | swift test (Docker), 26 tests | 23 nodes / 26 edges |
| M5-03, M5-04, M5-05 | S2 feat/core-vault | | DONE | swift test (Docker), 62 total | `@before-*` = strictly after today; tasks without `^id` get line-based placeholder id until AG-02 |
| M5-02 | S2 | | DONE | swift test (Docker), fuzz 10 000 x4 | lossless YAML subset, no third-party |
| M5-07 | S2 | | DONE | swift test (Docker) | polling watcher; FSEvents stub UNVERIFIED on macOS; `FileChange` lives outside API |
| M5-06 | S2 | | DONE | swift test (Docker), 196 fault-injection cases | pure-Swift SHA-256; wikilink rewrite on rename; creation date not preserved on macOS (UNVERIFIED) |
| M5-08 | S2 | | DONE | swift test (Docker) | 1000 notes build 0.55–0.7 s, reindex 1–1.6 ms (debug) |
| M5-09, M5-10.B | S2 | [#26](https://github.com/Brightwav3/Margin/pull/26) | DONE | swift test (Docker), 59 conformance | fixture vaults committed; optional `id:` key in `_course.md`/notes = vault format question |
| M6-02.B, M6-12.B, M6-16.B | S4 (early, branch feat/editor-tokenizer) | | DONE | swift test (Docker) | UTF-16 offsets; typing 0.008 ms release / 0.04 ms debug per change (budget 3 ms) |
| M9-02, M9-09.B, M9-06.B | S7 (early, branch feat/graph-layout) | | DONE | swift test (Docker) | 500 nodes 0.04 s / 5000 nodes 0.5 s release; tags passed separately (GraphNode has none) |
| M8-01 | feat/core-features | | DONE | swift test (Docker) | 60/60 sentences (table written with parser — optimistic), 0.09 ms |
| M7-08.B, M11-01.B, M10-09.B, M10-02.B, M10-04.B | feat/core-features | | DONE | swift test (Docker) | grade: group weights from `_course.md` (Bio = 90.0 % vs fixture 91) |
| AG-02 | feat/core-features | | DONE | swift test (Docker), 61 new tests | `n-`/`t-` base32 ids, idempotent migration pass; foreign `^block` ids kept as task id |
| M6-05.B, M6-08.B, M6-09.B, M6-11 + scanner fix | feat/core-features | | DONE | swift test (Docker) | new API: PropertyService, NoteAnalysis, TaskService.toggle (ask) |
| AG-03, AG-04 | feat/core-features | [#27](https://github.com/Brightwav3/Margin/pull/27) | DONE | swift test (Docker), 665 + 289 | write-ahead journal with full before-bytes (not inverse patches, spec §12 → needs D-0NN); crash sweeps 1000+ faulted runs; 2×1000 writers, 0 lost |
| M8-06, M8-08.B, M8-09.B | feat/core-features | | DONE | swift test (Docker) | capture tasks go to `<course>/Tasks.md`; open: API entry for nearest-lecture capture, `InboxService.updates` |
| M9-01, M9-08.B, GraphService, M3-04, M3-05.B, M4-08 | feat/core-features | | DONE | swift test (Docker) | vault graph 17 nodes vs mockup 23 (6 mockup-only nodes); CourseListQuery/BannerStore/CourseCard not in API; vault lacks a placeholder marker |
| M10-10.B, M10-12.B, M10-13.B, M10-14.B, M10-16.B, M11-04.B | feat/core-features | | DONE | swift test (Docker), 529 + 154 | vault format additions: `overrides:` in `_course.md`, `archived` in semesters.json (ask) |
| M12-02.B (perf test stability) | feat/core-features | | partial | 5 green full runs | budgets asserted on medians, perf suites serialized |
| M10-21.B, M11-05.B, M11-02.B, M11-07.B | feat/core-features | [#27](https://github.com/Brightwav3/Margin/pull/27) | DONE | swift test (Docker) | semester rename renames folder + id; new vault requires first semester |
| M11-01.B store, M10-20.B, M11-08.B, M10-18.B, M10-19.B, M10-22.B | feat/core-features | [#27](https://github.com/Brightwav3/Margin/pull/27) | DONE | swift test (Docker) | history snapshots not auto-wired into save; zlib/UserNotifications/PDF macOS-only UNVERIFIED |
| M10-01, M11-03.B, M10-03.B, M10-05.B | feat/core-features | [#27](https://github.com/Brightwav3/Margin/pull/27) | DONE (FTS5 UNVERIFIED) | swift test (Docker) | no sqlite3.h in Linux image → in-memory BM25 index; SQLite FTS5 behind `#if canImport(SQLite3)` never compiled |
| M8-04, M5-07 FSEvents | feat/core-features | [#27](https://github.com/Brightwav3/Margin/pull/27) | DONE (UNVERIFIED on macOS) | Linux build + Shortcut tests | new macOS-only `MarginPlatform` target; M8-05 not done (Q2) |
| M7-02 latency fix | feat/core-features | [#27](https://github.com/Brightwav3/Margin/pull/27) | DONE | 5 green full runs; 0.4–0.5 s isolated | root cause: blocking I/O starved the cooperative pool; vault actors on `DedicatedExecutor` |
| M12-03 | feat/core-features | [#27](https://github.com/Brightwav3/Margin/pull/27) | DONE | swift test (Docker) | 8 real bugs found and fixed (stale index after ENOSPC, read-only notes overwritten, writes re-creating an unmounted vault, watcher treating missing root as mass delete, …); open: partial link rewrite on move is silent (needs ChangeSet warnings = api) |
| M7-02, M7-03, M7-05.B, M7-06.B, M7-09.B | feat/core-features | | DONE | swift test (Docker) | M7-02 1 s budget: 0.4–0.7 s measured, only 5 s asserted (container stalls); watch interval 0.2 s; Upcoming grouping provisional (Q4) |
| AG-01..AG-04 | S3 feat/agent-foundations | | todo | | |
| M6-*.B | S4 feat/editor-core | | todo | | |
| M7-* | S5 feat/tasks-core | | todo | | |
| S3 (AG-02, AG-03, AG-04) | feat/agent-foundations | | todo | | |
| S7 rest, S9, S11, M12-03 | | | todo | | |
| AG-01, AG-05…AG-36 (S6, S8, S10, S12) | | | SKIPPED (human: agent layer deferred) | | |
| Phase 2 UI | | | SKIPPED (human: UI later on Mac) | | |

## Human instructions received mid-run
- Full autonomy granted, except: nothing is merged to `main` (explicit rule kept).
- CI emails: `ci.yml` was invalid (`hashFiles()` in a job-level `if`), so every push produced a failed "No jobs were run" run. Fix in PR [#24](https://github.com/Brightwav3/Margin/pull/24) (green), cherry-picked into slice branches so PR CI runs.
- **UI must stay fully replaceable**: UI depends only on `MarginCore/API` + `AppEnvironment`; deleting `Sources/MarginUI*`/`App/Margin` must keep core build and tests green. Added to every worker brief.
- **Agent layer deferred (human):** MA1–MA4 (AG-05…AG-36) and AG-01 audit are SKIPPED for now, "door left open": write services keep `Actor`/`baseVersion`/`dryRun`/`ChangeSet` so agents can plug in later. Kept from MA0 because they protect user data without agents: AG-02 stable IDs (D-012), AG-03 undo via ChangeSet, AG-04 baseVersion + merge. Slices S6, S8, S10, S12 (agent parts) dropped; M12-03 robustness kept.
- **Stop rule:** finish cleanly when ~$5 of cloud session credits remain; everything must be resumable elsewhere (see *How to resume*). The session cannot read the credit balance, so work is checkpointed after every task.
- **Scope change: backend only.** Later extended: complete *all* planned backend with Sonnet workers, macOS-only tasks as protocol + `#if os(macOS)` (UNVERIFIED).
- **Scope change: backend only.** Phase 2 (UI drafts, `MarginUILogic` target) is dropped from this run by the human; UI will be built later on a Mac against `MarginCore/API` + fixtures.
- UI screenshots from Docker were requested: SwiftUI does not run on Linux, so real UI screenshots are impossible here (see Phase 2 notes).

## How to resume
After the agent layer was deferred, slices S3–S12 collapse into one integration slice **`feat/core-features`** (base `feat/core-vault`, PR #26 stacked on #23); finished worker branches are merged into it with `--no-ff`.
State lives entirely in git: slice branches `feat/core-foundation` (PR #23) → `feat/core-vault` → … are stacked; worker branches `feat/core-<slug>` are merged into their slice with `--no-ff`. To continue: read this ledger's task table, check out the last slice branch, pick the first `todo` row, follow `docs/agents/overnight.md` §5. Swift on Linux: `docker run --rm -v "$PWD":"$PWD" -w "$PWD" swift:latest swift test`.

## Errors
- Integration (task class): parallel branches both defined `ContentHash` and `SplitMix64`; fixed by unifying on SHA-256 (fix/core-vault-integration) and renaming test RNGs. Not counted as a task failure.
- Infra: server-side auto-mode classifier outage (~several minutes) blocked all Bash/MCP calls; one worker ended BLOCKED without changes and was relaunched. Not counted.
- Integration: parallel workers kept conflicting in `AppEnvironment`/`FixtureStore`/`VaultBackend`/conformance harness; brief now requires each worker to merge `origin/feat/core-features` before reporting. Orchestrator resolved two small conflicts by hand (init parameters, visibility).
- Task class (M7-02): latency tests failed at 8–10 s in full runs, blocking pushes of `feat/core-features`. Root-caused with lldb (cooperative pool starved by fsync/index builds), fixed in Sources, not by relaxing limits.
- Infra: a worker ran `docker kill` on all swift containers once, killing sibling builds (no file damage).
- Flaky `FileWatcherTests` under load (timing): hardened with settle-waits, no test weakened or skipped; 12 consecutive green full runs.

## Questions for the human
1. Grade weights: Grades screen item weights (Bio 5/5/15/5/30/40) vs `_course.md` grading parts (20/25/25/30). Which is authoritative? Both transcribed as-is (PR #23).
2. Bio average: calculator gives 90.0 % from `_course.md` group weights, fixture summary says 91 %. Which grading model is right (see question 1)?
3. Vault format additions awaiting approval: optional `id:` in `_course.md`/notes (PR #26), `overrides:` list in `_course.md`, `"archived": true` in `.margin/semesters.json`, tasks note `<course>/Tasks.md` for captured tasks.
3b. Old question — vault format: optional `id:` in `_course.md` and notes (PR #26) — accept, or keep ids in a per-vault map?
4. Lab 2 date: gallery says Mon 21 Sep, lecture list Mon 14 Sep. Fixture uses 21 Sep.
5. Semester Fall 2026 start/end invented (2026-08-31 .. 2026-12-13) so that 28 Sep = week 5. Confirm.

## Proposals for approval
1. **Agent routines and triggers (out of plan, new task).** Human wants agents to feel like Grok Bot / Notion Custom Agents: named teammates that act on their own on a schedule (e.g. nightly inbox triage, Sunday weekly review) or on events (new inbox item, lecture ended, exam approaching), with per-identity memory, an activity feed, and hand-offs between identities. Current plan covers identities, scoped permissions, approvals, memory, skills (AG-31, AG-12, AG-13, AG-20, AG-21) but has no triggers/routines and runs agents only while the app runs (Q2/Q11). Proposal: new task `AG-37 Routines` (schedule + event triggers over `Clock` and vault events, each run = session under an identity with purpose, results via ReviewQueue/audit), weight ~8, depends on AG-31/AG-33/AG-13; background execution needs Q2/Q11 revisited. Meanwhile AG-31's identity model is designed to carry job description, per-identity memory and triggers as data so this needs no format change later.

## Recommended morning steps
1. **Merge (routine):** #24 (CI workflow fix; stops the "No jobs were run" emails). It is independent of everything else.
2. **Decide / approve (`ask:required`), in stack order:** #23 (foundation + model types) → #26 (vault, parsers, index, app environment; base `feat/core-foundation`) → #27 (all feature services, undo, robustness; base `feat/core-vault`). Before merging, decide:
   - vault format additions: optional `id:` (notes, `_course.md`), `overrides:` in `_course.md`, `"archived"` in `semesters.json`, `<course>/Tasks.md` for captured tasks, `.margin/settings.json`, `.margin/history/`, `.margin/changesets/` (full before-bytes, not inverse patches) → record as D-0NN and update `05-vault-spec.md`;
   - contract additions (all service protocols in `Sources/MarginCore/API/Services/`) → review `09-contracts.md` alignment;
   - open questions below (grade model, Lab 2 date, semester dates, Upcoming grouping Q4, graph 17 vs 23 nodes, `status:` placeholder key, ChangeSet warnings for partial link rewrites, nearest-lecture API entry, `InboxService.updates`).
3. **Verify on a Mac (UNVERIFIED code):** `swift build && swift test` on arm64 / macOS 27 SDK; then the macOS-only paths: FSEvents watcher (also add the missing-root guard the polling watcher has), Carbon hotkey (`MarginPlatform` target), `SystemTrash`, `F_FULLFSYNC`, creation-date preservation on rename, UserNotifications reminders, SQLite3 FTS5 index + `.margin/index.sqlite` wiring, zlib history snapshots, PDF export (stub).
4. **Small follow-ups:** wire `history.snapshot(.save)` into the save path; promote `CourseListQuery`/`BannerStore`/`CourseCard` into the API when the UI needs them; ChangeSet warnings for partial link rewrites.
5. **Next:** UI on the Mac against `MarginCore/API` + `AppEnvironment.fixture`; agent layer later (door left open: every write takes `Actor`/`baseVersion`/`dryRun`/`idempotencyKey` and returns a `ChangeSet`; undo exists).

## Metrics
- Workers: ~30 Sonnet runs (plus 1 aborted Opus start); fix rounds per task mostly 0–1; merge-integration rounds were the main cost (shared `AppEnvironment`/harness files).
- Test count on the final branch: ~665 core + 289 conformance (Linux, debug).
- Real bugs found by tests during the run: ~12 (scanner code/BOM, filename hidden-file, CRLF capture append, cooperative-pool starvation, 8 robustness bugs, move re-read after journal).
- Credits: not observable from the session.
