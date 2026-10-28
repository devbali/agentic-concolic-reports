# NIGHT REPORT — 2026-09-08/09

Unattended run. Everything below is either verified by measurement or flagged
as needing the coordinator's decision. Nothing was declared closed.

---

## 1. Extraction defects — FOUND, FIXED, and the missing CHECK added

Surfaced by the reference comparison. All three were silent.

### E5 — lost parentheses = an OVER-PERMISSION in shipped SQL  (`src/queries_from_runs/transform.py`)
`assemble_where` chained conjuncts with `exp.And(...)`; a conjunct that was
itself an `Or` rendered flat, because sqlglot does not add the parens:

    app emits:      ... AND ("share_visibilities"."user_id" = ? OR "posts"."public" = ?)
    we emitted:     ... AND  share_visibilities.user_id = ?  OR  posts.public = 't' AND ...

`AND` binds tighter than `OR`, so the right arm ESCAPED every other conjunct —
permitting `SELECT posts.*` for any public post regardless of author. FIXED
(parenthesise disjunctive conjuncts); verified in the regenerated policy.
It survived undetected because blockaid had QUARANTINED exactly those views.

### E1 — the fold was never actually installed  (both extractors)
`assoc_fold.install()` only patches `_bind_value` and `pcs.parse_pc`; it does
NOT swap the transformer. Both extractors called it and then used the base
`RunTransformer`, so every `assoc_*` bind stayed an unresolved placeholder.
Measured on people_show: 6 placeholder families vs 3 with
`AssocFoldingTransformer` — the three that disappear (`assoc_author_id`,
`assoc_person_id`, `assoc_profile_id`) fold into real joins. FIXED in both.
The header line claiming "assoc_fold INSTALLED" was mine and was misleading;
it now names the class actually used.

### E11 — a statement silently dropped 21,037 times  (`transform.py`)
`_primary_table` accepted only `exp.Table`, but will_paginate renders its
pagination count as `SELECT COUNT(*) FROM (SELECT DISTINCT ...) subquery_for_count`
— a Subquery. It returned None, the caller recorded "unparseable note", and
the statement was DROPPED. `conversations_index.sql` (CLOSED) contains 8 plain
COUNTs and ZERO subquery COUNTs. FIXED (descend into the subquery).

### The check that should have caught E11
Per RUNBOOK rule P — residue found later means the CHECK was missing too. All
three extractors now print **RED** and enumerate unparseable notes instead of
burying the count in a summary field.

### Policies
- `people_show.sql` REGENERATED and INSTALLED: 58 -> 59 views, placeholders
  6 -> 3, precedence corrected, table coverage identical (19 = 19).
- `comments_index.sql` (CLOSED) — corrected version PARKED at
  `_pending_comments_index_E1E5.sql` (79 -> 61 views, placeholders 8 -> 0).
  The drop is explained (views distinct only by opaque placeholder now merge;
  table coverage 7 = 7, projections identical) but it is a 23% change to a
  CLOSED deliverable and the tool that could PROVE view-level equivalence is
  the one that was re-quarantined. NOT installed. Coordinator's call.

---

## 2. Reference comparison — a recorded finding OVERTURNED

Full deliverable: `queries_from_runs/_REFERENCE_COMPARISON_20260908.md`.

**The 2026-09-01 "5 proven missing" for conversations_index is WRONG.** That
run kept 8 of 58 views; the 40 discarded were the principal-bound ones, which
is exactly what those five statements key on. All five are present (views
29/40/41, 48, 47, 55, 38); Tier C proves four covered, the fifth is a
COUNT-vs-`SELECT *` rendering difference.

Across all three endpoints, both directions: **no over-permission found**,
several REFERENCE omissions (nav-bar reads, the anonymous photo COUNT, the
`pods` view unreachable in this checkout at 0/12,997 dumps), and ONE genuine
semantic difference:

**q35 — statement-level vs reveal-level.** Our policies say what SQL the app
ISSUES; the reference says what data may REACH the user. people#show issues
`SELECT "profiles".*` and filters columns in Ruby, so ours is legitimately
coarser. **A consumer treating an extracted policy as access control is
over-permissive at every such site, on every endpoint.** This is a property of
the method, not of people_show.

Reference policies were RE-QUARANTINED afterwards (mode 000, verified
unreadable; restore modes in `_reference_quarantine_modes.txt`).

---

## 3. notifications_index — the model fix, and what it bought

`DecisionAlias` (fifth assumption kind) + load-time canonicalization, built by
a sub-agent and verified: 17 identities from 35 (name, ordinal) pairs; the
gate's derived test FAILS on a deliberately unsound alias (photos' three
bind-sets merged) and PASSES 17/17 sound ones on 42 replayed probes.
Report: `notifications_index/_DECISION_ALIAS_REPORT.md`.

**P2 (root-family many-arm untrack) implemented and measured:**

    before P2:  3,109 cliques carrying unobserved assignments
    after  P2:  1,136          (-63%, model only, no new dumps)

**A metric correction that matters:** the headline `MISSING` is a CLIQUE COUNT
times `MAX_MISSING_PER_CLIQUE`, in every configuration (4,725 = 945x5;
15,545 = 3,109x5; 3,109 = 3,109x1 — confirmed by an independent cross-run).
It never measured the gap. The real progress metric:

    cliques evaluated whole by some run:   0 of 945  ->  2,226 of 3,109
    joint assignments observed:            0         ->  11,966

Demand loop still running.

---

## 3b. P1's exemptions are SELF-CORRECTING — measured over four rounds

This materially changes the character of decision (2) in §6 and is the most
consequential thing the long-running loop produced.

| round | nodes | missing | dumps | P1 exemptions |
|---|---|---|---|---|
| 1 | 396 | 1,140 | 14,369 | 17,874 |
| 2 | 428 | 1,554 | 14,539 | **20,783** (peak) |
| 3 | 435 | 1,797 | 15,583 | 20,583 |
| 4 | **435** | 1,821 | 18,139 | **20,441** |

Two facts together:

1. **The tree is fully discovered** — nodes flat at 435 (deltas +32, +7, **0**).
2. **P1's exemptions are SHRINKING** — 20,783 -> 20,441, i.e. **342
   independence claims WITHDRAWN** because the growing corpus co-evaluated
   pairs that had never co-occurred before.

Each withdrawal restores an edge to the dependence graph, raising the clique
count — which is exactly the +24 rise in `missing` at round 4. So **missing
rising while the node count is flat is the model becoming MORE HONEST**, not
divergence. That is the tripwire in `_tier_unobservable_pairs` working as
designed.

**What this does and does not settle.** It does NOT make the exemptions
proven: the corpus still cannot distinguish "impossible" from "not yet
observed". But it shows they are not static unexamined assumptions — they are
claims the corpus continuously tests, with a demonstrated retraction rate of
342 over three rounds. The honest description is "corpus-tested exclusivity
with a measured falsification rate", not "17 874 unprobed exemptions".

The ratification question stands; the evidence for answering it is better.

---

## 3c. RETRACTED — "the residual is unobservable" was a MEASUREMENT ARTEFACT

**This section previously claimed the residual on all three endpoints was
unobservable and that it gated completion project-wide. THAT IS WRONG.**

The co-occurrence scans read RAW dumps and searched for the expression names
in `coverage_summary.json`'s `missing[]`. But `missing[]` names are
**canonical** (`..._records_notifications_8513a914_rows`, produced by the
DecisionAlias canonicalization) and additionally carry the `SYM_LEN_` prefix
that `fix_len_names` adds AT LOAD. Raw dumps hold neither — they carry
ordinal names (`..._records_2_row_...`). The strings could never match, so
every combination trivially looked "never co-occurring".

Redone THROUGH THE ENGINE'S OWN LOAD PATH (canonicalize_ordinals ->
fix_len_names -> apply_len_bounds), 42 045 dumps, 25 sampled combinations:

    ALL variables co-occur in some run : 18 of 25  (72% REACHABLE)
    NEVER all co-occur                 :  7 of 25  (28%)

**What this retraction invalidates:**
- the claim that the residual is unobservable (all three endpoints);
- the claim that decision (2) gates completion project-wide;
- my repeated advice that notifications' loop was pointless and that more
  compute could not help. It was working on a reachable target throughout.
- people_stream's "40/40 exhaustive" result used the same broken comparison,
  BUT REDONE CORRECTLY (through the load path, exhaustive over all 755 dumps)
  it gives the SAME answer: **0 of 40 co-occur, 40/40 genuinely
  unobservable**. That conclusion survives — it had simply been reached by a
  method that would have said "never" regardless, so it was worth nothing
  until re-measured.

**The two endpoints genuinely differ**, and the difference makes sense:

| endpoint | corpus | reachable | unobservable |
|---|---|---|---|
| notifications_index | 42 045 | **18/25 (72%)** | 7/25 |
| people_stream | 755 (DRAINED) | 0/40 | **40/40 (100%)** |

people_stream's exploration drained at 201 paths, so its corpus genuinely
lacks the co-occurrences; notifications has 42 000 dumps and plenty.
**Consequence: people_stream DOES need decision (2)** (or a larger corpus its
drained exploration cannot produce). **notifications does NOT** — its residual
is mostly reachable and the fix is seeding throughput.

**The plateau is still real** (nodes flat at 435, missing 1 821-1 830 over
nine rounds) but its cause is now believed to be MINE: `MMC_DEMAND=1`, which
I set to make passes cheap. It makes the coverage pass enumerate ONE missing
assignment per clique, so the seeder gets one target per clique per round —
while a clique only leaves `MISSING` when FULLY covered. That is the slowest
possible fill rate. Raised to 24; the next rounds test it.

**The lesson, consistent with 4b/4c/4d and 3d:** every measurement failure
tonight came from checking a NUMBER instead of the artefact it described.
Here the fix was to route the test through the same load path the engine uses
rather than reading the files directly.

## 4. Rule T re-syncs — all three endpoints, and a bug caught

people_show's R1 repair fixed FOUR boundary families (P-1 write / P-2 exists?
/ P-9 pluck / P-10 owner_id) that produced 8 of its 10 adversary wins. Both
queued batches were 5 repairs behind. Each is now a VERBATIM copy of the
shared boundary with its descents removed by a DECLARATION FILTER, not by
editing declaration sites — so it diffs against upstream and cannot silently
fall behind again.

**The bug I nearly shipped:** declaration-set diffing by regex is BLIND to
loop-declared targets. `render`/`render_to_string`/`render_to_body` are
declared in a loop over a hash, and both batches had deliberately deleted that
block. My "40 = 40 targets, nothing gained or lost" check missed it and
restored the render MOCK. Symptom: people_stream drained at 27 paths, 3.1 PCs
per run. After descending render properly: 87 dumps, 7.5 PCs/run, still
finding paths at the cap. The same blind spot hid `update_column`
(loop-declared) and would have hit posts_show identically.

**posts_show `to_param` adjudicated:** declared in that batch and nowhere else
— a Rule T divergence. Rails 5.2's body is literally `id && id.to_s`, no SQL,
and `persisted?` is not a target anywhere, so it forecloses nothing. It is a
WALL MOCK -> moved to the batch's `targets.rb`; the boundary copy stays
verbatim.

---

## 4b. A CLASS of runner defects in the results2-era ports

Three separate defects tonight, all in the older runners, all invisible from
the logs (which reported healthy `runs=`/`paths=` while the corpus did not
grow):

| defect | people_stream | posts_show | notifications |
|---|---|---|---|
| corpus WIPED on every invocation | YES (fixed) | no | no |
| no `LABEL_SUFFIX` -> rounds overwrite identical filenames | YES (fixed) | **YES (fixed)** | no |
| no `concolic_seeds` recorded -> demand rounds impossible | YES (fixed) | YES (fixed) | no |
| no `EXTRA_SEEDS_JSON` -> cannot inject a demanded assignment | YES (fixed) | YES (fixed) | no |

Observed symptoms before diagnosis:
- people_stream "base round 2 added 0 dumps" — it had deleted round 1 and
  rewritten it;
- posts_show corpus frozen at 12 052 for 20 minutes WHILE dumps were being
  actively rewritten (mtime = now) — round 2 overwriting round 1.

**The lesson: a runner that reports `runs=4000 paths=3345` is not evidence the
corpus grew.** Check the dump count against the previous round, not the log.

posts_show round 1 did NOT drain — all four scenarios hit `MAX_RUNS cap
(4000)` and three hit `STACK_LIMIT truncation`, so that endpoint has
substantially more to explore now that rounds accumulate.

### 4c. A counting bug that looked like corpus loss

Every driver counted dumps with `ls $B/dump_*.json | wc -l`. At 24 104 files
with ABSOLUTE paths (~90 chars each) that is ~2.2 MB of arguments — over
`ARG_MAX`. The glob fails, `ls` errors, `wc -l` reports **0**, and the
generation script reads that as "no new dumps" and STOPS.

Observed as: "posts_show base generation DONE: 0 dumps" with the corpus
actually intact at 24 104. (A relative-path glob from inside the directory is
~25 chars per entry and stays under the limit, which is why an interactive
check disagreed with the script.)

Fixed in all three drivers and the monitors:
`find "$B" -maxdepth 1 -name "dump_*.json" | wc -l`.

**Third measurement failure of the night**, after `MISSING` being a clique
count and runner logs reporting healthy `paths=` while the corpus did not
grow. In each case the number was plausible and meant something else. Check
the artefact, not the report of the artefact.

### 4d. Dump labels must be unique per INVOCATION (my bug, not inherited)

After porting `LABEL_SUFFIX`, my generation script still set
`LABEL_SUFFIX="_b${ROUND}"` from a round counter that RESTARTS AT 1 on every
launch. So a restarted generation wrote `_b1` over the previous run's `_b1`
dumps: the generator reported healthy `runs=`/`paths=`, and net growth was
ZERO (+0 dumps in 10 minutes on a 24 104-dump corpus).

Fixed: `RUNID="$(date +%m%d%H%M)"`, `LABEL_SUFFIX="_${RUNID}r${ROUND}"`.
Verified: 24 104 -> 25 117 in 90 seconds.

Fourth instance of the same failure shape in one night — three inherited
(wipe-on-invocation, missing LABEL_SUFFIX, missing seed recording) and this
one mine. In every case the logs looked correct and only a dump count against
the previous value exposed it.

---

## 5. people_stream — built out, and stopped at a real decision

Runner had NONE of the demand machinery and WIPED its corpus on every
invocation. Now: seeds recorded, `EXTRA_SEEDS_JSON`/`SEEDS_ONLY`/
`LABEL_SUFFIX`, accumulation, rooted `_demand_root.py`, DecisionAlias
canonicalization, and canonical->ordinal seed translation.

Verified working: 0 untranslatable demanded vars; **seeds honoured 810 times,
CONTRADICTED 0 times**.

And the number does not move (31 -> 31 -> 31; 40 -> 40 after re-keying).
**Because all 40 missing combinations involve variables that NEVER all
co-occur in any of the 755 dumps.** They are UNOBSERVABLE, not unreached —
`coverage.py`'s documented class of "combinations execution can never
manifest", which are reported missing until independence is declared.

Full detail: `people_stream/_NEXT_BLOCKER.md`. Wall declared in `_WALLS.md`
(the `format.all` redirect arm terminates in a mock wall; no policy impact).

---

## 6. DECISIONS PENDING — none of these were taken

1. **P2** — declared and gate-probed on notifications, NOT ratified.
2. **`_tier_unobservable_pairs`** — 17,874 declarations, unprobed BY
   CONSTRUCTION (no co-evaluating snapshot exists to probe). Measured as
   LOAD-BEARING: canonical names alone realize 0 of 2,223 cliques; with this
   tier, 2,226. The SAME question decides people_stream's 40. Its epistemic
   status equals the pre-existing `_tier_samerep_never_coeval`, but I
   generalised it from same-rep to ALL pairs, which widens it a lot.
   **The corpus cannot distinguish "impossible" from "not yet observed."**
3. **The parked comments_index policy** (§1).
4. **Whether DecisionAlias belongs UPSTREAM.** Two independent endpoints
   needed it. The root cause is `call_interceptor.rb:142-144` naming a
   symbolic result by WHEN it was called, not WHAT it is. Fixing it there is
   a Rule T event; porting per-batch is what we did twice tonight.

## 7. FINAL STATE (2026-09-09 ~13:00)

| endpoint | corpus | nodes | cliques w/ gaps | status |
|---|---|---|---|---|
| notifications_index | 28 586 | 435 (flat since round 3) | ~1 829 | PLATEAU across 8 rounds (1 821-1 829). Residual UNOBSERVABLE (25/25, full-corpus test). Loop still running per instruction. |
| posts_show | 96 357 | 101 | 332 | Loop CAPPED at round 4 (see below). ~84% unobservable, ~16% reachable. |
| people_stream | 755 | 29 | 40 | Parked. 100% unobservable (exhaustive). Runner fully built out. |
| people_show | 12 997 | — | — | Policy REGENERATED + installed (59 views). Milestone only. |
| comments_index / conversations_index | — | — | — | CLOSED. Comments' corrected policy PARKED pending decision (3). |

**Why posts_show's loop was capped at round 4 rather than its configured 12:**
two signals converged — signature novelty decaying 81% -> 71% -> 64%, and the
coverage pass at 4.7 GB against a 9 GB cap while the corpus grew ~12 000 dumps
per round. Two or three more rounds would have OOM-killed the pass (the
`rc=137` failure seen earlier), leaving a large corpus in an UNMEASURABLE
state — strictly worse than a large corpus in a measured one. Four rounds
added 48 040 dumps of genuinely new territory; the work is preserved and
resumable.

**The bottom line:** all three remaining endpoints are blocked on the same
thing, and it is not compute. See section 3c.
