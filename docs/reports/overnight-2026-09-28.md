# Overnight run 2026-09-28

**Environment:** Ubuntu x86_64 cloud container. No native `swift`. Docker daemon started manually (`dockerd`), image `swift:latest` = **Swift 6.4-RELEASE (x86_64-unknown-linux-gnu)** pulled from Docker Hub (one 429 rate-limit, second pull succeeded). A session-local wrapper `/usr/local/bin/swift` (outside the repo) runs `docker run swift:latest swift "$@"`, so `scripts/check.sh` and hooks really build and test. Verification ladder level: **2 (Docker)**. node 22 / npm available. download.swift.org blocked by proxy (403). Linux only: nothing is compiled for macOS/arm64.

**Workers:** Sonnet 5.5 subagents (user instruction mid-run); effort chosen by task weight (1–2 low, 3–5 medium, 6–8 high) but the Agent tool exposes no effort parameter, so the level is stated in each worker prompt only. Orchestrator: this session. The human's extended fault-tolerance table (retry provisioning 2x, 45 min worker limit, 2 medium + 1 high fix rounds, breaker >25 % or 3 consecutive failures, zero tolerance for data loss/injection/foundation failures) applies.

**Provisional assumptions:** see `docs/agents/overnight.md` §4 (Q1–Q13 defaults from STATUS.md). Every PR carries **PROVISIONAL**. Additional self-made decisions are listed below.

**Summary:** started 0 / DONE 0 / BLOCKED 0 / SKIPPED 0. Circuit breaker: no.

| Task | Slice/branch | PR | State | Verified | Note |
|---|---|---|---|---|---|
| M0-01 | S1 feat/core-foundation | | DONE (branch pushed) | swift build + test (Docker) | Package.swift, MarginUI only on macOS |
| M2-01 | S1 | | todo | | |
| M2-02 | S1 | | todo | | |
| M2-03 | S1 | | todo | | |
| M2-04 | S1 | | todo | | |
| M2-05 | S1 | | todo | | |
| M5-02..M5-10.B | S2 feat/core-vault | | todo | | |
| AG-01..AG-04 | S3 feat/agent-foundations | | todo | | |
| M6-*.B | S4 feat/editor-core | | todo | | |
| M7-* | S5 feat/tasks-core | | todo | | |
| S6–S12, Phase 2 UI | | | todo | | |

## Errors
_(none yet)_

## Questions for the human
_(none yet)_

## Proposals for approval
_(none yet)_

## Recommended morning steps
_(filled at the end)_

## Metrics
_(filled at the end)_
