# Overnight run 2026-09-28

**Environment:** Ubuntu x86_64 cloud container. No native `swift`. Docker daemon started manually (`dockerd`), image `swift:latest` = **Swift 6.4-RELEASE (x86_64-unknown-linux-gnu)** pulled from Docker Hub (one 429 rate-limit, second pull succeeded). A session-local wrapper `/usr/local/bin/swift` (outside the repo) runs `docker run swift:latest swift "$@"`, so `scripts/check.sh` and hooks really build and test. Verification ladder level: **2 (Docker)**. node 22 / npm available. download.swift.org blocked by proxy (403). Linux only: nothing is compiled for macOS/arm64.

**Workers:** Sonnet 5.5 subagents (user instruction mid-run); effort chosen by task weight (1–2 low, 3–5 medium, 6–8 high) but the Agent tool exposes no effort parameter, so the level is stated in each worker prompt only. Orchestrator: this session. The human's extended fault-tolerance table (retry provisioning 2x, 45 min worker limit, 2 medium + 1 high fix rounds, breaker >25 % or 3 consecutive failures, zero tolerance for data loss/injection/foundation failures) applies.

**Provisional assumptions:** see `docs/agents/overnight.md` §4 (Q1–Q13 defaults from STATUS.md). Every PR carries **PROVISIONAL**. Additional self-made decisions are listed below.

**Summary:** started 20 / DONE 19 / BLOCKED 0 / SKIPPED 0. Circuit breaker: no.

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
| M5-09, M5-10.B | S2 | | in progress | | service protocols + Actor/ChangeSet skeleton (api) |
| M6-02.B, M6-12.B, M6-16.B | S4 (early, branch feat/editor-tokenizer) | | DONE | swift test (Docker) | UTF-16 offsets; typing 0.008 ms release / 0.04 ms debug per change (budget 3 ms) |
| M9-02, M9-09.B, M9-06.B | S7 (early, branch feat/graph-layout) | | DONE | swift test (Docker) | 500 nodes 0.04 s / 5000 nodes 0.5 s release; tags passed separately (GraphNode has none) |
| M8-01 | S7 (early, branch feat/capture-parser) | | in progress | | |
| AG-01..AG-04 | S3 feat/agent-foundations | | todo | | |
| M6-*.B | S4 feat/editor-core | | todo | | |
| M7-* | S5 feat/tasks-core | | todo | | |
| S6–S12 | | | todo | | |
| Phase 2 UI | | | SKIPPED (human: UI later on Mac) | | |

## Human instructions received mid-run
- Full autonomy granted, except: nothing is merged to `main` (explicit rule kept).
- CI emails: `ci.yml` was invalid (`hashFiles()` in a job-level `if`), so every push produced a failed "No jobs were run" run. Fix in PR [#24](https://github.com/Brightwav3/Margin/pull/24) (green), cherry-picked into slice branches so PR CI runs.
- **UI must stay fully replaceable**: UI depends only on `MarginCore/API` + `AppEnvironment`; deleting `Sources/MarginUI*`/`App/Margin` must keep core build and tests green. Added to every worker brief.
- **Stop rule:** finish cleanly when ~$5 of cloud session credits remain; everything must be resumable elsewhere (see *How to resume*). The session cannot read the credit balance, so work is checkpointed after every task.
- **Scope change: backend only.** Later extended: complete *all* planned backend with Sonnet workers, macOS-only tasks as protocol + `#if os(macOS)` (UNVERIFIED).
- **Scope change: backend only.** Phase 2 (UI drafts, `MarginUILogic` target) is dropped from this run by the human; UI will be built later on a Mac against `MarginCore/API` + fixtures.
- UI screenshots from Docker were requested: SwiftUI does not run on Linux, so real UI screenshots are impossible here (see Phase 2 notes).

## How to resume
State lives entirely in git: slice branches `feat/core-foundation` (PR #23) → `feat/core-vault` → … are stacked; worker branches `feat/core-<slug>` are merged into their slice with `--no-ff`. To continue: read this ledger's task table, check out the last slice branch, pick the first `todo` row, follow `docs/agents/overnight.md` §5. Swift on Linux: `docker run --rm -v "$PWD":"$PWD" -w "$PWD" swift:latest swift test`.

## Errors
- Integration (task class): parallel branches both defined `ContentHash` and `SplitMix64`; fixed by unifying on SHA-256 (fix/core-vault-integration) and renaming test RNGs. Not counted as a task failure.
- Flaky `FileWatcherTests` under load (timing): hardened with settle-waits, no test weakened or skipped; 12 consecutive green full runs.

## Questions for the human
1. Grade weights: Grades screen item weights (Bio 5/5/15/5/30/40) vs `_course.md` grading parts (20/25/25/30). Which is authoritative? Both transcribed as-is (PR #23).
2. Lab 2 date: gallery says Mon 21 Sep, lecture list Mon 14 Sep. Fixture uses 21 Sep.
3. Semester Fall 2026 start/end invented (2026-08-31 .. 2026-12-13) so that 28 Sep = week 5. Confirm.

## Proposals for approval
1. **Agent routines and triggers (out of plan, new task).** Human wants agents to feel like Grok Bot / Notion Custom Agents: named teammates that act on their own on a schedule (e.g. nightly inbox triage, Sunday weekly review) or on events (new inbox item, lecture ended, exam approaching), with per-identity memory, an activity feed, and hand-offs between identities. Current plan covers identities, scoped permissions, approvals, memory, skills (AG-31, AG-12, AG-13, AG-20, AG-21) but has no triggers/routines and runs agents only while the app runs (Q2/Q11). Proposal: new task `AG-37 Routines` (schedule + event triggers over `Clock` and vault events, each run = session under an identity with purpose, results via ReviewQueue/audit), weight ~8, depends on AG-31/AG-33/AG-13; background execution needs Q2/Q11 revisited. Meanwhile AG-31's identity model is designed to carry job description, per-identity memory and triggers as data so this needs no format change later.

## Recommended morning steps
_(filled at the end)_

## Metrics
_(filled at the end)_
