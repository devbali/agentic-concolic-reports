# TODO — deferred work

Items deliberately NOT being worked. Each says why it is deferred and what it
would cost to pick up. **Owner ruling 2026-09-15: do not reopen closed
endpoints.** Anything here touching a closed endpoint stays closed until the
owner says otherwise.

Live work is not tracked here — see the per-endpoint campaign docs under
`results3/<endpoint>/`.

---

## ARMED — a standing owner instruction waiting on a gate

### B1. Run `policy-extraction-bench` once ALL SIX endpoints have a policy
**Owner instruction, 2026-09-15.** Do NOT do any of this before the gate is met.

*The gate:* all six diaspora endpoints have an extracted policy —
`people_stream`, `comments_index`, `conversations_index`, `notifications_index`,
`people_show`, `posts_show`.

*Status of the gate as of 2026-09-15 08:30:*

| endpoint | policy `.sql` | note |
|---|---|---|
| people_stream | YES | closed |
| comments_index | YES | closed |
| conversations_index | YES | closed; POLICY_HEADER missing (T1, deferred) |
| notifications_index | YES | **CLOSED + SHIPPED 2026-09-15** — 99 views, md5 `45b288b1`, POLICY_HEADER 475 lines |
| people_show | YES | SET ASIDE, policy has a known Class-S gap (T2) |
| posts_show | **NO** | open campaign — **this is the only hard blocker** |

So the gate reduces to **posts_show shipping a policy**. The other five files
exist. As of 2026-09-15 ~10:20 posts_show is the ONLY endpoint without one. T1 and T2 are deferred by owner ruling and do NOT block this — but see
the caution below before trusting the resulting numbers.

*The action, once the gate is met:*
1. Add every endpoint's policy to `/home/dev/project/policy-extraction-bench/results`.
2. Create the **union directory** with the **union policy** across all six.
3. Run the benchmark over it.

*Cautions to raise with the owner AT bench time, not before:*
- **people_show's policy is known-incomplete** (T2): no `users` statement
  despite the endpoint reading users, and `identity_symbolicity_audit` RED so
  signed-in views carry literal ids instead of `_MY_UID`. It will pass any
  "does a policy exist" check and still poison a comparison.
- **posts_show may ship INCOMPLETE** — its residue is characterised, not
  closed. If so the bench entry must say so; an incomplete policy benchmarked
  as if complete is a meaningless number.
- conversations_index's verdict predates §16c and the foreclosure rungs (T1).

### B2. Standing operational instruction (2026-09-15, ~5-6 h window)
Monitor continuously, keep every stage parallelised, keep pushing the two live
campaigns forward. Parallelism levers that were found stale and must not be
allowed to go stale again: the blockaid-JVM "one at a time" rule (a 32 GB-era
memory constraint, obsolete on the 70 GB box), the single-threaded extraction
transform loop (sharded 2026-09-15), and the staged step-6 coverage
parallelisation (`results3/tools/land_coverage_parallel.sh`).

---

## Closed endpoints — DO NOT REOPEN (owner, 2026-09-15)

### T1. conversations_index has no POLICY_HEADER
Every other closed endpoint carries one; this one closed before the convention
existed. It has a shipped policy (`results3/queries_from_runs/conversations_index.sql`)
but no `results3/conversations_index/POLICY_HEADER.txt`.

*Cost:* low — a read-only task. Derive the numbers from that endpoint's own
artefacts (verdict line, view count, declared assumptions and gate verdicts,
untracked entries, audit reds, §15 scope ruling) and write the header in the
form of `people_stream/POLICY_HEADER.txt`. No runs, no re-extraction.

*Note when written:* its verdict predates §16c confinement and the later
foreclosure rungs, and its foreclosure inference was never witness-tested.

### T2. people_show is SET ASIDE with a Class-S defect
Has a policy (58 views) and a header, but was never closed by the three-check
standard — the completion gate never ran (`coverage_summary.json` carries no
`completion` key). Two carried findings, both in its policy header:
the fold drops 26 062 `Contains`/`IndexOf` PCs on `people.diaspora_handle`
(costs WHERE precision, not statements), and `identity_symbolicity_audit` is
**RED** — every `auth_*` scenario drives a CONCRETE principal, so signed-in
views extract with literal ids instead of `_MY_UID`.

Separately recorded: ~10 767 noted events with degenerate placeholder notes,
and no `users` statement in the policy despite the endpoint reading users.
**That second item was never assessed** — whether it follows from the
placeholder notes or is a distinct defect is unknown.

*Cost to reopen (from README):* re-run the signed-in scenarios with a symbolic
principal (F6), then the completion gate.

**Benchmark caution:** people_show HAS a policy file, so a naive "does every
endpoint have a policy" check passes. Its policy is missing at least one
statement the endpoint issues. Entering it into a comparison benchmark without
assessing that would produce a number that looks fine and means nothing.

### T3. Foreclosure inference was never witness-tested on the closed endpoints
A witness test exists as of 2026-09-15
(`src/end_to_end_completion_checker/assumption/foreclosure_gate.py`) and has
been run on **posts_show only**, where it refuted 491 of 493 probed §16f
classes. people_stream (`FORECLOSURES=332`/`135`) and comments_index both ship
verdicts that apply §16b foreclosure untested; notifications ships with §16b
(5 345) + §16e (89) + §16f (26) untested and discloses that in its header.

**COUNTER-EVIDENCE, recorded 2026-09-15 after notifications closed — read this
before assuming the closed endpoints are at risk.** notifications_index DID
gate-test its own foreclosure classes, through the §17/X12 gate at K=8, with
classes taken from its own summary:

```
§16e  89 PASS /  0 FAIL
§16f  20 PASS /  6 NOT-TESTABLE / 0 FAIL
§16g   4 PASS / 22 NOT-TESTABLE / 0 FAIL
-> ZERO refutations; 113 of 141 confirmed, 28 un-evidenced
```

Against posts_show's 484 FAIL / 0 PASS that is a sharp contrast, and it is
evidence the collapse is a property of **posts_show's heavily pruned 48,943-profile
snapshot**, not of foreclosure inference as such. Caveat: the §17/X12 gate is
NOT the same instrument as `foreclosure_gate.py`'s witness test — it does not
attempt to CONSTRUCT a run realising `C ∧ d`. So this is real evidence, not
proof, and the two results are not strictly comparable.

*Owner ruling 2026-09-15: scoped to posts_show only. Do not re-examine the
closed endpoints.* The posts_show campaign agent recommended pointing
`foreclosure_gate.py` (which is general — it takes a `(C,d)` export and a
manifest, nothing endpoint-specific) at ONE closed endpoint to settle whether
this is endpoint-specific or framework-wide. **That remains the cheapest
decisive experiment if the question is ever reopened**, and notifications is
the natural target since its classes are already exported and its zero-refutation
§17 result gives a prediction to test against. The posts_show refutation is itself still under
verification (is the member predicate testing "d evaluated" or "d holds"?), so
the rate may not transfer even if someone later wants to look.

---

## Engine / process work, not blocking any endpoint

### T4. `src/` docstrings for the independence-vs-confinement SCOPE difference
Ruled and documented in `DISCIPLINE.md` §16c and
`ASSUMPTION_KIND_UNIFICATION_20260915.md` §0. The two `src/` docstrings were
deferred because `coverage.py` was being edited by a live campaign and
`assumptions.py` is in `_phase_keys` (a byte change forces a ~15 min checkpoint
rebuild; neither touches the probe bank). Exact wording required for each is in
that note's §0.3.

### T5. The standing disqualifier extended to DECLARED pairs, report-only
The counterexample scan that produces `confinement_disqualified` runs at load
on every pass and needs no footprint, so it applies to declared independence
claims as-is. It is the one benefit identified in the unification review that
is both real and currently absent — **no audit for declared pairs exists
anywhere in `src/`**. Report-only: emit a `CoverageResult` field naming
declared pairs the corpus contradicts, change no demand.
*Falsifier:* `missing` and `complete` byte-identical on all five corpora, with
the new field non-empty on at least one.

### T6. X11 remains open on the declared path
The independence flip probe FAILs only on a novel shape and cannot see AND-cell
dependence. The filed symmetric fix was **rejected as unsound** on 2026-09-15
(it manufactures false refutations on the OR pattern ruled benign 2026-09-11);
the sound instrument is the orientation-invariant per-shape 2×2. A read-only
measurement exists (`reports/diaspora/tools/declared_pair_2x2.py`, ~90 s/endpoint,
`KEEP_NOTES=1` mandatory) and found 1 602 interactions across three closed
endpoints. Recorded in `DISCIPLINE.md` §16c-X11.
*Owner ruling 2026-09-15: dropped for now.*

### T7. §16f W=5 adoption is SUSPENDED
Width was measured as a clean win (residue 3 868 → 2 927 at W=5, budget never
binding, knee at W=5) and booked as §109. Suspended the same day: wider W fits
LONGER conjunctions to the SAME corpus, which is overfitting, so a lower
residue at wider W may be more false pruning rather than progress. The decisive
test needs no new runs — partition the 856 gate results by |C| ≤ 3 vs |C| ∈
{4,5} and compare refutation rates. Do not widen W anywhere until that lands.

### T8. Master template `reports/diaspora/concolic_targets.rb` is unfixed for B-8
The batch copies carry the repair; the master template does not. Forward risk
for any NEW batch created from it. B-8 in the shared boundary is settled
(§33.C) — this is only about the template.

### T9. Suffix-seeding regression — **CLOSED 2026-09-15, verified**
Verified in the live file: `results3/notifications_index/concolic_targets.rb:218-231`
has **no `length_var?` guard** and carries the 2026-09-14 comment recording the
regression. The skip survives only in `_diff_sfxlen_20260914/pre/`. Nothing is
owed to the other seven batches — `grep -c seed_suffixes` is 0 in every other
copy, master included. No action. Original text below for the record.

### T9-orig. Suffix-seeding regression at `concolic_targets.rb:~224`
A skip added during the name-boundary work suppresses suffix seeding for length
variables, justified by a claim that is false here (`_demand_suffixes.json` has
6 of 15 scenarios keyed `"_rows)"`). **Inert** for drives using
`SEEDS_ONLY=1 EXTRA_SEEDS_JSON=…` without `SEED_SUFFIXES` — which is what the
current campaigns do — but live for any `_gen_dsfx.sh`-family scenario. Needs a
ground-truth differential before repair.

### T10. `concolic_targets.rb.b8_next` must be reduced to its splice
Built from the Aug-29 base, so landing it wholesale would REVERT the
name-boundary shim across all 8 shared copies. The real repair is one line plus
a comment at L797/798. Splice only, or annotate the file so nobody lands it.

## T-DIV — the "shared" target boundary has silently diverged (2026-09-15)

**Not a task. A latent correctness risk that an owner must decide about.**

Rule T (DISCIPLINE §8) rests on a premise: the target declarations are SHARED
app-wide, so a defect in one voids every endpoint. Measured today, the premise
does not hold — the live copies of `concolic_targets.rb` are up to 519 lines
apart and no two share a hash:

| copy | lines | md5 (12) | vs canonical |
|---|---:|---|---:|
| canonical              |  1527 | `ad2cd94da7f8` |    +0 |
| comments_index         |  1683 | `8a943288e440` |  +156 |
| conversations_index    |  1671 | `79fb69d98f87` |  +144 |
| notifications_index    |  2046 | `40ff12764cae` |  +519 |
| people_show            |  1902 | `71a1164fb0a3` |  +375 |
| people_stream          |  1805 | `b03f1d8b0f74` |  +278 |
| posts_show             |  1679 | `627bac2c1199` |  +152 |

The six `targets.rb` copies differ likewise (614 / 881 / 1371 / 2156 / 2168 /
2206 lines). There are ~55 further copies under `results/`, `results2/`,
`_bak_*`, `_diff_*`, `_experiment/`, `_x7diff/`, `_swprobe/`, `_x7probe/` and
`_gatedir/`; those are FROZEN historical records and must stay untouched —
several of this project's findings are auditable only because they preserve
the boundary as it was.

### This is NOT theoretical — it already caused a measured defect

B-4 (`BOUNDARY_NOTE_GAPS_20260915.md`) is the proof. `collect_binds` crashed on
`Arel::Nodes::Casted` because arel-9.0.0 exposes `#val`, not `#value`, so every
STI relation (`type IN ('Reshare')`) raised `NoMethodError` and the exception
text was stored AS THE NOTE — 1 574 occurrences per 150 posts_show dumps, the
largest single gap in the corpus.

**That bug was already fixed on 2026-08-19 ("bug-2b").** The fix reached the
five endpoint copies and never reached the CANONICAL copy or posts_show's. So
the defect survived for a month in exactly the two copies that had drifted,
and appeared to be a posts_show-specific mystery. It was a divergence
artefact. Nothing detected it; it took a placeholder audit on a shipped policy
to surface it, and only then by its downstream symptom.

Read that again as a general risk: **a repair applied to the boundary is silently
partial**, and the endpoints that miss it look like they have their own unique
defect.

### Why it matters

Every claim of the form "this repair at the boundary protects all endpoints"
is only as true as the copies being the same. They are not. A repair applied
to one endpoint's copy does not reach the others, and nothing currently
detects that. The boundary-note instrumentation done on 2026-09-15
(`BOUNDARY_NOTE_GAPS_20260915.md`) had to be applied copy by copy and verified
by **changed-region** hash, because whole-file equality was impossible — that
is the first time the divergence was measured rather than assumed.

### What is NOT proposed here

Reconciling the copies. That is a large owner decision with consequences for
every corpus on disk, and it is explicitly out of scope for the task that
found this. Recorded so the next person to rely on Rule T's premise checks it
first.

### Cheap partial mitigation, if wanted

A pre-flight lint that hashes the copies and fails when a live endpoint's
boundary differs from canonical in any region other than a declared
per-endpoint block. It would not fix the divergence but would stop it growing
silently.

Three architectural follow-ons raised 2026-09-20 (unifying the completion-test
stack, an IR splitting query extraction, an agentic completion-driving loop)
are `src/`-level, not diaspora-specific — recorded in `src/TODO.txt` instead
of here.
