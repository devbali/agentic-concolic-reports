# autolab

The lab that drives a real Rails application concolically, one endpoint at a
time, and turns the traces into a policy. 161 endpoints, 164 runs.

This file is the **only document at the top level**, and it is a map: what is
here, what is finished, what may not move, and one line per longer document in
[`docs/`](docs/). Nothing below is a completeness claim — see
[What this corpus does not say](#what-this-corpus-does-not-say).

---

## The deliverable

```
endpoints/<endpoint>/
├── stats.json                       rollup for this endpoint
├── cloud.json                       what this endpoint's CLOUD ATTEMPTS used:
│                                     VMs, box hours, tokens, money (GENERATED
│                                     -- tools/cost.py; absent when no box was
│                                     ever launched for it)
└── <provenance>/<run-id>/           provenance is local/ or cloud/, never merged
    ├── policy/
    │   ├── policy.txt               the policy IR, text  (as printed upstream)
    │   └── policy.json              the policy IR, JSON  (GENERATED --
    │                                 dumps_to_policy.syntax.policy_json)
    ├── traces/
    │   ├── json/dump_*.json         the dump IR, JSON    (as produced)
    │   └── text/dump_*.run.txt      the dump IR, text    (GENERATED)
    ├── rendered.sql                 the SQL the domain layer renders from
    │                                 policy/policy.txt  (GENERATED at build
    │                                 time, NOT copied -- see below)
    ├── evidence/                    everything else the store holds for this
    │                                run: result.json, exploration_summary.json,
    │                                and for a cloud box its packet.json,
    │                                assumptions.json, assumption_manifest.json,
    │                                shim_tests.rb, box.json -- plus
    │                                upstream_provenance.json (sha256 per file)
    └── stats.json                   provenance + every verification verdict

stats/INDEX.md  stats/INDEX.json            the corpus rollup
stats/EXCEPTIONS.md  stats/EXCEPTIONS.json  what was seen and NOT shipped
blockaid/                                   the blockaid/subsume artefact
```

**Both IRs are present in both forms, and the forms were checked against each
other before anything was written.** 860 dumps (782 whose text form is
equivalent to its JSON, 78 whose text is equivalent to `to_text_domain(JSON)`
and therefore the poorer of the pair), 164 policies, all 164 parsing verbatim
and re-printing byte-identically. Per-artefact verdicts are in each run's
`stats.json`.

**Nine of those dumps were re-driven on 2026-10-05.** `src_new` `3c3aa88` fixed
reversed `Contains` operands in both symbolic runtimes, which invalidated 8
dumps under `diaspora_federation_h_card_hcard` and 1 under
`status_messages_new`. Both endpoints were re-driven against the fixed runtimes
and the evidence store refreshed. **The path set did not move** — same dump set,
same per-dump path-condition count, same distinct path signatures, byte-identical
policy; exactly one path-condition atom per endpoint changed, and only in its
operand order. Measurements, controls and what was deliberately left carrying the
old text: [`redrive_contains_20261005/README.md`](redrive_contains_20261005/README.md).

**`rendered.sql` is generated, not copied (2026-10-01).** It used to be copied
out of the evidence store, which froze it at whatever
`domains/ruby_rails_sql/render.py` did on the day that run's pipeline ran —
and after two bind-resolution fixes, 120 of the 164 copies were describing a
renderer that no longer existed. The build now renders from the run's own
stored `policy/policy.txt`. The policy IR round-trips verbatim, so the
IR → SQL hook is the only thing that can move, and a rebuild can no longer
silently revert a refresh. `tools/rerender.py` does the same in place without
a full rebuild.

Rebuild (idempotent, ~45 s):

```bash
venvs/queries_from_runs/bin/python3 reports/autolab/tools/build_store.py
```

`--endpoint EP` restricts the rebuild to one endpoint; it then clears only
that subtree and refuses to write `stats/`, because a partial walk cannot make
a corpus-level claim.

## What each endpoint cost

`endpoints/<endpoint>/cloud.json`, and a summary under `cloud` in that
endpoint's `stats.json`. **80 cloud attempts across 68 endpoints, 6.87 box
hours, $0.70 of cloud compute and $19.20 of API spend** — the sweep's cost was
tokens, not VMs, by a factor of 27.

Three files each held a third of this and none of them is keyed by endpoint, so
nothing joined them and the store could not say what anything cost:
`entrypoints/sweep_out_*/workers.jsonl` (time, tokens, API cost),
`entrypoints/sweep_out_*/queue/entries/*.json` (the box: cluster name, the
instance type SkyPilot's optimizer actually chose, region) and
`src_new/sweep/console/api.py` (the price catalog, with a fallback table).
`tools/cost.py` joins them on the worker id and `build_store.py` writes the
result, so a rebuild reproduces it rather than deleting it.

```bash
python3 reports/autolab/tools/cost.py                 # the rollup
python3 reports/autolab/tools/cost.py --endpoint EP   # one endpoint
```

Two things it is careful about, because both were wrong before:

* **An attempt is a box launched FOR an endpoint, not the provenance of that
  endpoint's artefacts.** 159 of 161 endpoints here were produced by the local
  round, and a cloud attempt on the same endpoint may have been torn down
  having produced nothing. `attempts_that_produced_a_stored_run` is the only
  field that connects the two, and across the whole corpus it is **3**.
* **An unknown price is `null`, never 0.** `workers.jsonl` carries a
  `cloud_usd` field that is `0.0` on every record ever written, because nothing
  computed it while the sweep ran — which is why the console showed "unknown
  cloud burn". That zero is kept under its own key so it can never be read as
  "free", and `*_unknown_for` counts the attempts a figure could not be
  computed for. API cost travels as the envelope the sweep recorded
  (`provenance: "derived"`), because `entrypoints/PRICES.md` measured the
  client-side table as understating real billing by 24 %.

## What this corpus does not say

**No endpoint here is certified complete, and none can be as the corpus
stands.** No endpoint config under `entrypoints/scaffold/*/config.json`
carries a `completion` block, so every completeness gate reports NOT
CONFIGURED and every certificate line reads `report=none outcome=UNDECIDED`.
`stats/INDEX.md` prints the certified-complete count as its own row, fixed at
**0**.

A policy here is evidence that a policy was produced and is internally
consistent. It is **not** evidence that the endpoint's execution tree was
explored, that any branch was proved covered or unreachable, or that the
endpoint is done.

## The documents

| | |
|---|---|
| [`docs/TARGETS.md`](docs/TARGETS.md) | **the targets half**: the library of mocks a run installs before it drives an endpoint — the core/local split, the override mechanism and its known defect, the property every mock body must have, and how to trust any of it |
| [`docs/CONFLICTS.md`](docs/CONFLICTS.md) | the disagreement inventory: every place the sources behind the library disagree about the same target, and what this lab ruled. Machine-readable form: `inventory/conflicts.json` |
| [`docs/LAUNCH_SWEEP.md`](docs/LAUNCH_SWEEP.md) | how to start the cloud sweep — the exact command, every precondition, what to watch, what means stop, what is left undone. **Read it before launching anything.** |
| [`docs/PILOT.md`](docs/PILOT.md) | the 2026-09-28 pilot: an agent on a real GCP VM, with its evidence, its cost against OpenRouter's own billing, and the two defects it found |
| [`docs/QUEUE_RUNBOOK.md`](docs/QUEUE_RUNBOOK.md) | driving the sweep with the durable queue — work is entries in a directory and nothing runs between invocations, so nothing can crash and lose the run |
| [`docs/briefs_addendum.md`](docs/briefs_addendum.md) | corrections a box's agent brief needs that are not yet in `src_new/sweep/briefs/`; named absolutely by `entrypoints/queue_w4.json` |
| [`blockaid/README.md`](blockaid/README.md) | what the blockaid artefact is, what it can and cannot say, and the two render defects that emptied its quarantine |
| [`redrive_contains_20261005/README.md`](redrive_contains_20261005/README.md) | the 2026-10-05 re-drive of the two endpoints whose traces carried the reversed `Contains` operands: what moved (one path-condition atom per endpoint, and nothing else), what deliberately did not, which corpora still carry the old text, and the re-sync trap that would put it back |

## The layout

```
reports/autolab/
├── README.md                 you are here  (the only top-level document)
├── docs/                     the six documents above
│
│   THE DELIVERABLE
│   (endpoints/ and evidence_store/ were CLEARED 2026-10-07 — see below)
├── stats/                    INDEX + EXCEPTIONS, the corpus rollup
├── blockaid/                 the blockaid/subsume artefact  (README.md first)
│
│   THE TARGETS HALF  (docs/TARGETS.md documents all of this)
├── autolab_targets.rb        the loader:  Autolab::Targets.install!("<endpoint>")
├── targets/
│   ├── registry.json         endpoint -> files, modules, install order
│   ├── core.rb               THE SHARED CORE  (87 maximal / 86 in the app)
│   ├── shared_shims.rb       app-wide shims lifted out of an endpoint layer, in GROUPS
│   └── endpoints/*.rb        one endpoint's own layer
├── inventory/
│   ├── manifest.json         every declaration: kind, type, layer, source, line
│   ├── partition.json        the core/local ruling, per target, with rationale
│   ├── conflicts.json        every cross-source disagreement + the ruling taken
│   └── candidates.json       target NAMES a lower-trust source declares and this
│                             library does not -- discovery leads, not declarations
├── tools/                    the measurement instruments, plus build_store.py,
│                             rerender.py, cost.py and blockaid_artefact.py
└── test/                     run ./test/run_tests.sh
│
│   THE SWEEP
├── entrypoints/              which endpoints exist, what they cost, the 161
│                             scaffolds, the queue configs, the sweep_out_* records
├── box/                      what goes in a box, and $DSH_HOME
├── pilot_evidence/           the artefacts docs/PILOT.md cites
│
│   CORPORA AND HISTORY
├── e2e/                      round 2. `runs/` is a LIVE sweep corpus -- pinned
├── shakedown/                round 1. `runs/` is the lab suite's corpus -- pinned
├── redrive_contains_20261005/  the two endpoints re-driven after the `Contains`
│                             operand fix, with the pre-fix artefacts they
│                             replaced  (README.md first)
└── local_cc/                 a live agent's working tree, not an artefact store
        (the retired stores live at
         _trash/autolab_history_20260930/ -- read its _RETIRED.md)
```

The lab had accreted **five stores of the same artefacts** — `shakedown/`
(round 1), `e2e/` (round 2), `e2e_round3/` (round 3), `results/` and
`finished/`. They were consolidated into one, `endpoints/`, under
`_trash/autolab_history_20260930/` with its `_RETIRED.md`.

### `endpoints/` and `evidence_store/` ARE GONE (cleared 2026-10-07)

Both are under `_trash/autolab_endpoints_cleared_20261007/`, intact, with a
`_CLEARED.md` giving the four reasons. The short form: the shape predicate
carried no statement kind and its predicate comparison ran backwards (so a
per-principal note covered a cross-principal read), the `destroy` mock skipped
the after_destroy chain, and the gates stopped answering PASS without a proof
or a launched probe. **No result produced before 2026-10-07 is evidence about
this application**, so re-driving is the only way back.

Nothing was certified complete before the clear: all 161 carried
`certified_complete: false`, and the domain half had never returned an empty
`domain_blocking` — the only two domain rounds that ever ran
(`local_cvd4/state/concrete-1*.json`) blocked with 2 items and 1.

`endpoints/` is a BUILD PRODUCT (`tools/build_store.py --store <path>`), so a
new store rebuilds it; `entrypoints/` was NOT cleared and still holds the
roster and every endpoint's config.

### One name to be careful with

`endpoints/` and `entrypoints/` are different directories and neither is a
typo for the other. **`entrypoints/`** is the sweep's input side: the 161
scaffolds and their `config.json`, the sweep specs, the queue configs, and the
`sweep_out_*` run records — it is still here. **`endpoints/`** was the output
side, the finished policy and traces per endpoint, and it is the one that was
cleared. The endpoint *names* were the same in both, which is exactly why the
distinction matters when reading a path: a surviving
`entrypoints/scaffold/comments_index/` does not mean a result survived.

## Pinned in place — do not move these

Each is at a path something hardcodes. The path, not the contents, is the
constraint.

| | pinned by |
|---|---|
| `e2e/runs/` | `corpus_root` in **four live queue configs** (`entrypoints/queue{,_w2,_w3,_w4}.json`) and in `tools/queue_context.py`'s own error message. A running sweep stages dumps from here. |
| `shakedown/runs/` | the default corpus of `tools/reconcile_with_app.py` (`DEFAULT_GLOB`) and of `tools/build_inventory.py` — **step 3 of `test/run_tests.sh`**. Move it and the lab's own suite reports "no shakedown dumps on disk". |
| `targets/`, `entrypoints/`, `box/dshhome`, `box/manifest.json` | `src_new/sweep/box/dist/bundle.json` names all three absolutely |
| `tools/` | **eight** `src_new` documents (four READMEs and the four `DESIGN.md`) and `src_new/tests/sweep_e2e/test_cloud_chain_composes.py` cite `reports/autolab/tools/{check_doc_links,check_section_citations,run_real_sweep,check_live_vm,concrete_live_vm}.py`. `check_doc_links.py` is the citation check in force since 2026-10-05 and is the one the documents link; `check_section_citations.py` is superseded and kept only for the numbered backlog |
| `inventory/` | written by `tools/{build_inventory,build_partition,build_conflicts,check_citations}.py`; read by `test/test_install.rb` and checked for staleness by `test/test_inventory.py` |
| `test/` | `test/run_tests.sh` resolves `$LAB/{tools,targets,inventory,test}` from its own location |
| `autolab_targets.rb` | `require_relative "../autolab_targets"` in `test/test_install.rb` |
| `README.md`, `docs/CONFLICTS.md` | `tools/check_citations.py` reads exactly these two |
| `docs/briefs_addendum.md` | named absolutely by `entrypoints/queue_w4.json` |
| `pilot_evidence/` | cited eight times by `docs/PILOT.md` and `docs/LAUNCH_SWEEP.md` |

**`shakedown/` and `e2e/` were left whole, and that is deliberate.** It looks
as though only `runs/` is pinned and each round's report layer could be
archived. It cannot, and the reason is measured rather than guessed:

- **all 161** `entrypoints/scaffold/*/config.json` cite
  `reports/autolab/e2e/fixes/apply_fix10_config_limits.py` in the note
  explaining where their run limits came from;
- `entrypoints/lib/autolab_dse.rb` — **the runner the live sweep loads** —
  cites `reports/autolab/e2e/probes/probe_principal.out` twice, as the
  measurement behind its principal handling;
- each round's tooling lives in its own `tools/` and reaches for its siblings
  (`e2e/tools/sweep.py` hardcodes `BASE = ".../reports/autolab/e2e"`), so
  splitting corpus from report layer leaves it half-resolved.

So archiving `e2e/fixes/` or `e2e/probes/` alone would rot 163 citations, two
of them in a file a running sweep reads. They were **superseded by
`endpoints/` as result stores** and should be read as dump corpora plus their
own round's history, nothing more. With `endpoints/` cleared they are not a
fallback either: they are older artefacts under the same four defects.

`shakedown` also appears throughout `src_new` — but there it is the **name of
the 161-endpoint pass**, not a path, so it constrains nothing here.

## Reorganised 2026-10-01

The top level held **six markdowns** (`README.md`, `LAUNCH_SWEEP.md`,
`CONFLICTS.md`, `PILOT.md`, `QUEUE_RUNBOOK.md`, `briefs_addendum.md`, 2,089
lines between them). All but this file moved into `docs/` **under their own
names**, so a reference needs only a `docs/` prefix, and this README's own
targets half became `docs/TARGETS.md`. Nothing was rewritten in the move;
`tools/check_citations.py` and `entrypoints/queue_w4.json` were repointed, and
`tools/check_citations.py` still checks every section citation in this file and
in `docs/CONFLICTS.md`.
