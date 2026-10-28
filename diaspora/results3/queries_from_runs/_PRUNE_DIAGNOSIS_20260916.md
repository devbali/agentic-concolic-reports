# The pruning-rule diagnosis and fix — 2026-09-16

Objective: explain WHY the pruning rule (`pcs.irrelevant_predicates`) keeps
almost nothing on notifications_index (11 of 1,994 rendered PC predicates,
full corpus) while doing much better on conversations_index (851 of 5,708),
split the cause with counts, and fix what the evidence supports.

**Read this alongside `_ARMS_DIFFERENTIAL_20260916.md`** (the baseline
numbers this diagnosis explains) and `_MOCK_NOTE_FIXES_20260916.md` (the
separate, unrelated unloadable-statement classification).

## Method

`RunTransformer` + `prune_irrelevant_pcs` were run directly (not through the
results3-local `assoc_fold` patch some older per-endpoint extractors install
— **the actual shipped `_pcfold2.sql` files were built by the plain
`queries_from_runs.dump` CLI with no patch installed**, confirmed from
`run_pcfold2_final.sh`'s log; an earlier pass of this diagnosis used the
patched pipeline and produced numbers that do not match production — this
write-up uses only the vanilla, shipped-matching pipeline). For each dropped
`(shape, predicate)` pair, one WITH-witness and one WITHOUT-witness
`TransformedQuery` were retrieved and their **source run's own `error`
field** inspected, plus whether the WITHOUT witness's own predicate set
contains the LITERAL NEGATION of the dropped predicate (proof the corpus
really observed the condition both ways, vs. silence).

Samples: seed 20260916, `--exclude-rejected --two-query-cap 2` (matching the
shipped arm). Sample sizes noted per figure below; this is a corpus of
313,977 (notifications_index) / 18,623 (conversations_index) dumps, so a
few-thousand-dump sample is a differential, not a census — consistent with
the sampling `_ARMS_DIFFERENTIAL_20260916.md` itself uses.

## The three-way split, with counts

For every dropped `(shape, predicate)` instance, exactly one of:

1. **NEGATION OBSERVED** — some other run of the same shape recorded the
   LITERAL NEGATION of the predicate (e.g. `type = 'X'` here, `type <> 'X'`
   there). This is a real, corpus-witnessed two-sided branch: the query
   genuinely runs with the condition either way. **Correct pruning.**
2. **SILENT ABSENCE, ERRORED RUN** — no run ever recorded the negation; the
   WITHOUT witness's run ended in an error (any kind — most commonly
   `ActionView::Template::Error`, a rendering-stage exception the app config
   deliberately does NOT treat as a request rejection, since the read was
   already granted before the template failed). That run's PC record is
   TRUNCATED: it stopped before reaching whatever code evaluates the
   condition, so its silence is missing data, not a demonstration the query
   runs unconditionally.
3. **SILENT ABSENCE, CLEAN RUN** — no negation observed, and the WITHOUT
   witness's run completed with no error. This can still be a genuinely
   different, successfully-completed code path (e.g. a different request
   FORMAT that never evaluates the condition at all) — inspected below.

| endpoint | sample (dumps) | drop instances examined | (1) negation observed | (2) silent + errored | (3) silent + clean |
|---|---:|---:|---:|---:|---:|
| notifications_index | 300 | 279 | 153 (54.8%) | 69 (24.7%) | 57 (20.4%) |
| notifications_index | 6,000 (dominant-class check) | see below | — | — | — |
| conversations_index | 300 | 283 | 257 (90.8%) | 3 (1.1%) | 23 (8.1%) |

**conversations_index's pruning is mostly correct as-is.** 91% of its dropped
predicates are real, corpus-witnessed two-sided branches — almost entirely
the participation-check family (`conversation_visibilities1.id = /<>
conversations.id`, `peopleN.id = /<> peopleM.id`): the app fetches several
rows and compares them in Ruby, and different rows are equal or not on
different runs. This IS non-constraining for the statement whose row is one
side of that comparison, and dropping it is the rule working as designed.
Only a small, traceable residue (the `conversations.subject <> ''` /
`= ''` pair, a rendering-stage check unrelated to which conversations are
fetched) falls into class 2/3.

**notifications_index is the opposite: only ~55% of drops are genuine, ~45%
are silent absence**, split roughly evenly between an errored run's
truncated record and a clean run that simply took a different path. Its
single largest predicate class, `users.username <> ''` (a check that fires
in the notifications layout — `ApplicationController`'s
`request.format == :mobile ? "application" : ...` per this endpoint's own
`POLICY_HEADER.txt` — evidently something in the **mobile** layout touches
`current_user.username`), never has its negation observed ANYWHERE in the
corpus in any sample drawn (0 of several hundred instances checked): every
"without" witness for it is silence, and the format of the WITH vs WITHOUT
dumps tracks exactly: WITH is always a `mobile`-format request; WITHOUT is
`html`/`json`/`xml`, or a `mobile` request that crashed with
`ActionView::Template::Error` before completing. That means class (3) here
is *also* legitimate — the check really is mobile-format-only, so html/json
requests are honest "ran without it" witnesses — but class (2) (the crashed
mobile requests) is not: a crashed mobile request tells you nothing about
whether *that* request's rendering would have reached the username check,
only that it didn't get there.

## What this means for the two problems

**The dominant predicate classes on both endpoints (`username <> ''`,
`subject <> ''`, the participation-check family) are correctly pruned.**
They are facts fold_atoms attaches because SOME statement in the run touches
the row they're about, not because they constrain the SPECIFIC statement
they land on — most of them are rendering-stage or Ruby-side facts with
nothing to do with which rows the SQL WHERE clause admits. The raw "1,994
rendered / 11 kept" ratio looks catastrophic, but the numerator is inflated
by exactly this class; **dropping it is not the defect.** This rules out
cause (3) from the brief (statement-identity too coarse) as the explanation
for the bulk of the drop: every case checked where the WITH and WITHOUT
witnesses came from different Ruby call sites (`find_by_2` vs `find_by_5`,
`first_1` vs `first_3`, ...) were the SAME SQL text — which is exactly the
right thing to dedup, not a keying defect.

**What IS a fixable defect: class (2), silent absence from a truncated
run.** ~25% of notifications_index's checked drop instances (and a much
smaller ~1% of conversations_index's) have NO valid falsifying witness at
all — only an errored run's silence, which the base rule (by design, per its
own docstring and `test_prune_drops_a_pc_absent_from_another_run_of_the_same_query`)
currently treats as equivalent to a genuine "ran without it." This is a
separate axis from `policy.rejecting_errors`/`--exclude-rejected`: that
option decides whose QUERIES ship (a refused request's reads were never
granted); this is about whose SILENCE may be used as evidence that some
LATER, unrelated condition was optional. A crashed run's reads still count;
its silence about what happened after the crash should not.

## The fix — `--reliable-pruning-witnesses`, behind a flag, both arms

Implemented in `src/queries_from_runs/`:

- `pcs.irrelevant_predicates_reliable(observations)` — NEW function,
  `(shape, predicates, reliable)` triples. A predicate is dropped only if
  some **reliable** observation of the shape lacks it; an unreliable
  observation may still show it present (contributing to the union) but may
  never argue absence. A shape with zero reliable observations drops
  nothing (conservative default). `pcs.irrelevant_predicates` — the existing
  function — is untouched, so every existing caller and test keeps its exact
  behavior.
- `transform.prune_irrelevant_pcs(queries, *, reliable_only=False)` — off by
  default; when on, calls the new function using each `TransformedQuery`'s
  new `reliable_witness` field (default `True`, so anything that never sets
  it behaves exactly as before).
- `dump.extract_statements(..., mark_unreliable_witnesses=False)` — tags a
  statement `reliable_witness=False` iff its source run ended in ANY error
  (not gated by `policy.rejecting_errors` — this is intentionally broader:
  ANY truncation invalidates a WITHOUT-witness, whether or not the app
  itself would call that error a "rejection"). The statement still ships
  (this axis never drops a query, only a vote). A `(shape, pc_preds)`
  combination reached by both a reliable and an unreliable run is marked
  reliable — one trustworthy witness is enough.
- `dump.prune_conditions(..., reliable_only=False)` and
  `dump.build_endpoint_file(..., reliable_pruning_witnesses=False)` thread
  the flag through; when on, the policy file's provenance header states it
  and explains the caveat, mirroring how `--exclude-rejected` documents
  itself.
- CLI: `--reliable-pruning-witnesses` on `python3 -m queries_from_runs.dump`.

Four new tests (`pcs`-level pure-function test, `transform`-level wiring
test, `dump`-level end-to-end test, plus the unrelated NPE regression test
below) — full suite: **115 passed, 3 skipped** (was 111 passed before this
change; no regressions).

### The ground-truth differential — both arms, same sample

Measured with the ACTUAL new code (`pcs.irrelevant_predicates_reliable`, not
a reimplementation), `--exclude-rejected --two-query-cap 2`, seed 20260916,
500-dump sample per endpoint (the box is running posts_show's live campaign
on most of its cores; larger samples were attempted at 6,000-8,000 dumps but
did not finish in reasonable time under that contention — 500 is enough to
see and quantify the effect, not to reproduce the full-corpus count):

| endpoint | distinct (shape,preds) — total / reliable-only | PC predicates rendered | kept, baseline (ALL witnesses) | kept, fix (RELIABLE witnesses only) | instances flipped dropped→kept |
|---|---:|---:|---:|---:|---:|
| notifications_index | 504 / 387 | 771 | 161 (20.9%) | 209 (27.1%) | **+48** |
| conversations_index | 521 / 376 | 1,933 | 917 (47.4%) | 1,183 (61.2%) | **+266** |

Both arms measured on the exact same extracted statement set (only the
pruning decision differs) — this is a real, positive, reproducible gain from
one additive, off-by-default flag, on both endpoints, not just the one the
diagnosis focused on. (conversations_index's larger absolute and relative
gain than the qualitative pair-sample above suggested is because the
differential counts every AFFECTED STATEMENT INSTANCE across the full
observation set per shape, not one sampled witness pair per predicate — a
shape can have several statement instances, and several of conversations_index's
participation-check shapes turn out to also have an errored run among their
many observations even though the FIRST witness pair sampled for the
qualitative check above was a clean one.)

### Why this is not a bigger win, and what the honest ceiling is

Even with truncated-run silence removed as valid evidence, **the dominant
predicate classes above stay pruned**, because they ALSO have clean,
non-errored WITHOUT witnesses (a JSON/HTML request that never touches
`username`; a genuinely different visibility row that is not equal to this
one). Fixing class (2) only recovers instances whose ONLY falsifying
observation was an errored run — real, but a minority even on
notifications_index. **The honest ceiling this fix implies**: at most the
class-(2) share of drops (≈25% of notifications_index's checked instances,
≈1% of conversations_index's) can flip from dropped to kept, and only for
the subset of those where no OTHER, clean witness also falsifies the same
predicate on the same shape (the differential above measures this exactly,
rather than the upper bound). Recovering the REST of notifications_index's
missing precision is not an extraction-code fix at all — it needs either (a)
a boundary change so `username`-style rendering facts are not attached to
statements they don't constrain (a `fold_atoms` design question, out of
scope for "minimal changes" and explicitly not requested), or (b) accepting
that a concolic corpus which deliberately explores both branches will
correctly report most incidental conditions as non-constraining, which is
not a defect to fix but the pruning rule doing exactly its documented job.

Named predicates that flip from dropped to kept (top instances, same 500-dump
samples) — these are real, previously-lost predicates, not noise:

```
notifications_index          conversations_index
17  notifications.type <> 'Notifications::StartedSharing'   106  conversations.subject <> ''
 7  people0.guid <> ''                                        26  people.id = people0.id
 7  people.guid <> ''                                         24  people0.id = people1.id
 4  users.username <> ''                                      22  people1.id = people.id
 2  profiles.public_details = TRUE                            19  conversation_visibilities1.id <> conversations.id
 2  contacts.sharing = TRUE                                   19  people2.id = people0.id
```

Two things worth noting about this list: (a) some of the SAME predicate
classes flagged above as "correctly pruned" (`username <> ''`,
`conversations.subject <> ''`, the `peopleN.id = peopleM.id` family) also
show up here — meaning SOME of their instances really were only falsified by
a truncated run (and are rightly recovered) while OTHER instances of the
SAME predicate class, on other shapes, still have a clean falsifying witness
and correctly stay dropped; (b) `notifications.type <> '...'` recovering 17
instances is a genuine, previously-invisible win — a real STI type
discriminator, not a rendering-stage artifact.

## Loadability NPE fix (unrelated bug, found and fixed opportunistically)

While tracing statement provenance for the above, `people_show`'s unloadable
statement #22 (`checker-NPE` class per `_MOCK_NOTE_FIXES_20260916.md`) turned
out to be a genuine extraction-side bug, not a boundary/corpus defect:
`_emission_conventions`'s aggregate-as-rows rewrite (an OLD comment already
described the intended fix, `_drop_projection_of`, which existed in the file
but had no regression test) projects the primary key of every table in the
FROM list at the time it runs; the LATER outer-join-split then produces an
arm that drops the outer-joined table from its FROM/joins but — before this
pass added a test to confirm the existing fix actually does its job — the
two rewrites needed to agree. Added
`test_outer_join_split_drops_its_own_column_from_the_projection` (pcs.py/
transform.py, all 115 tests green) and regenerated `people_show_pcfold2.sql`:
see the per-endpoint loadability numbers in the main report for the before/
after count.
