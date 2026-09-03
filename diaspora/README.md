# Diaspora concolic experiment

Extract, for each Rails endpoint, the **set of SQL queries it can issue** —
its access policy — by running the real app under a concolic (concrete +
symbolic) engine, and prove the set is complete **without any reference
policy**. The app runs for real on JRuby; ActiveRecord query methods are
intercepted at the framework boundary and return symbolic values, so the
app's own branches on query results record path conditions, and each
intercepted call records a NOTE: the statement it stands for, with `$(VAR)`
binds. The corpus of runs (`dump_*.json`) is the evidence; the policy is
folded out of it.

There is no oracle. Completeness is a property we have to establish
ourselves — that is what everything below is for.

---

## Where things are

```
reports/diaspora/
├── README.md              ← this file: what the project is, state, how to run it
├── docs/                  ← the live process documentation
│   ├── RUNBOOK.md         ← THE PROCESS: actors, the loop, every tool, ops
│   ├── DISCIPLINE.md      ← the rules: Class S/B, D1–D3, Rule T (shared boundary)
│   ├── CHECKS.md          ← each check in detail, with examples
│   ├── TARGET_FUNCTIONS.md← what the target functions ARE (the query boundary)
│   ├── ADVERSARY_WINS.md  ← ledger of every gap a real run found + patterns
│   └── history/           ← superseded plans, audits and reports (kept, not live)
├── tools/                 ← project-specific scripts (SQL/extraction level)
│   ├── hardening_lint.py  ← past adversary wins as a mechanical pre-check
│   ├── note_fidelity_audit.py, statement_diff.py, complement_audit.py
├── results3/              ← the live batches, one directory per endpoint
│   ├── <endpoint>/        ← runner, targets, shims, manifests, dumps, reports
│   └── queries_from_runs/ ← extracted policies (`<endpoint>.sql`)
├── results/, results2/    ← earlier generations (historical)
└── trash/                 ← retired scripts and artifacts
```

Engine code lives outside this tree:
`src/concolic_engine/` (coverage + completion), `src/end_to_end_completion_checker/`
(assumption gate, note check, the adversary brief), `src/ruby_runtime/completion_checker/`
(Ruby probes), `src/queries_from_runs/` (the fold, plus its five dump audits).

## How an endpoint is declared done

Three independent checks, on the same corpus — see `docs/RUNBOOK.md` for the
full flow:

1. **the completion engine** — `coverage_summary.json` ends with
   `"complete": true`: every branch combination covered or exempted by a
   declared assumption, every declared assumption tested by replay, every
   shim mock reaching zero targets at 100% line coverage, every target's real
   statements matching a corpus note;
2. **the five SQL-consumer audits** (`src/queries_from_runs/audits/`) — the
   dumps survive what the fold will do with them (binds resolve, PCs parse,
   principal binds are symbolic, notes are well-shaped, compared columns are
   PC-visible);
3. **the adversary** — a sub-agent that reads the real code and tries to make
   a REAL run (sqlite fixtures, no mocks) issue a target call the corpus does
   not have. A round with zero wins closes the endpoint; any win reopens (1).

A defect in a **target declaration** (the shared boundary) voids every
endpoint and forces a from-scratch regeneration — `docs/DISCIPLINE.md` §8,
Rule T.

## State (2026-09-01 03:40)

Sequential, one endpoint at a time. Standard for "done": engine
`complete: true` (0 FAIL / 0 NOT-TESTABLE) + the coordinator's audit sweep +
an adversary round with zero wins + the multiset matrix green — all on ONE
corpus. Scope is DISCIPLINE §15: post-auth entrypoint, symbolic principal;
the auth stages are the shared `results3/_auth_boundary/BOUNDARY_POLICY.md`,
unioned into every endpoint's policy.

| endpoint | standing | next |
|---|---|---|
| **conversations_index** | **CLOSED 2026-09-01** — engine complete (105 nodes, 0 missing, 18,623 dumps, 5,877 assumption probes PASS, shims 15/23/0); 8 audits + lint + census + boundary green; adversary R7 **zero wins** with entrypoint-frame proof; multiset matrix 7/7. **Correction 2026-09-01:** one of those checks (`cardinality_consistency`) judged 0 events here — its rule's subject does not occur on this endpoint — so the closure rests on ten checks with evidence, not eleven; no verdict retracted (see REPORT.md). Policy extracted: `queries_from_runs/conversations_index.sql`, **58 views** | done |
| **comments_index** | **CLOSED 2026-09-01** — engine complete (84 nodes, 0 missing, 26 528 dumps, 928 746 PCs, assumptions 3 648/3 648 PASS, shims 19/11/0, **zero waivers**); coordinator's 11 checks green (cardinality 123 974 pairs judged / 52 282 explained); adversary **R10 zero wins** over 37 real requests, all four attacks refuted with evidence; count matrix 0 under / 0 over under BOTH plain and executor-wrapped ground truth. Policy: `queries_from_runs/comments_index.sql`, **79 views** (413 594 raw → 79 distinct). Declared gap: the discovery-success arm is unreachable here and DECLARED UNMODELLED — see POLICY_HEADER | done |
| notifications_index | **BLOCKED 2026-09-01 by account weekly limit (resets Sep 4, 20:00 UTC)** — not a defect. Cycle-7 corpus regenerated on a repaired model (4 938 dumps): layout un-pinned (7 previously-absent shapes now present), discovery wall relocated to `Person#fix_profile` (`reload` over-emission 1 906 → 0), `sum`/`size` aggregate projections and a singular-association memo repaired. Coverage-only pass: 151 nodes, 7 681 missing, truncated. Handoff: `PAUSED_C7.md` | resume: clique profile → demand rounds → engine → sweep → adversary |
| people_show / people_stream / posts_show | not started (pre-hardening targets, 0 dumps) | queued in that order |

Shared assets every later endpoint inherits: the auth-boundary policy (§8 of
that file says what is verified and what is NOT claimed), the post-auth scope,
`tools/slot` 2-slot parallelism, the rig-crash census, the DML-aware judges,
the repaired hand-seeder, and the multiset matrix protocol.

Extracted policies to date: `results3/queries_from_runs/notifications_index.sql`
(83 views, pre-engine corpus) and `comments_index.sql` (26 views). Extraction
is the last step of a closed endpoint, not a checkpoint.

The reference policies that once lived in `ruby_examples/dse-apps/policies/`
are deliberately quarantined and unreadable; no agent may look for them.

## Running things

```bash
# one JRuby at a time, machine-wide; always unset JAVA_TOOL_OPTIONS
flock /tmp/concolic-slot.lock scripts/diaspora-concolic /abs/path/runner.rb

# the engine report for a batch (needs ~5.5-6.3 GB at 20k dumps; run it alone)
systemd-run --user --pipe --wait -p MemoryMax=6300M -p MemorySwapMax=0 \
  --working-directory=/home/dev/project bash -c \
  'unset JAVA_TOOL_OPTIONS; MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src \
   python3 reports/diaspora/results3/<endpoint>/coverage_report.py'

# the five SQL audits (coordinator)
PYTHONPATH=src venvs/queries_from_runs/bin/python \
  src/queries_from_runs/audits/<audit>.py reports/diaspora/results3/<endpoint> [...]

# the hardening lint, before any adversary round
PYTHONPATH=src python3 reports/diaspora/tools/hardening_lint.py \
  reports/diaspora/results3/<endpoint> --sample 400
```

Cost model: a concolic run is ~30 ms, but a JRuby launch is ~60–90 s, so
wall-clock is dominated by the number of launches (rounds, probes, concrete
scenarios) and by the assumption gate's replays — not by the runs themselves.

## Infrastructure

Java 21 + JRuby 9.3 (`/home/dev/tools/`), Rails 5.2.4.3 with a minimal
Gemfile, the app at `ruby_examples/dse-apps/apps/diaspora/`, Z3 via the
`venvs/queries_from_runs` virtualenv, sqlite (bundled JDBC adapter) for the
real fixture runs. Source-code discipline: `src/**` and the app are
coordinator-only; batch directories are write-freely.
