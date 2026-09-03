# PAUSED — notifications_index (cycle 7), 2026-09-01 18:00

**Stopped by a hard account limit, not by a defect.** The batch agent was
terminated mid-task: *"You've hit your weekly limit · resets Sep 4, 8pm (UTC)."*
Nothing was running when it died and nothing is half-written; the last artifact
(`_c7_clique_profile.log`) closed cleanly with `rc=1` (expected — a coverage-ONLY
pass exits 1 while `missing > 0`). Written by the coordinator, since the agent
could not write its own handoff.

## State on disk

| | |
|---|---|
| corpus | **4 938 dumps**, regenerated from scratch on the REPAIRED C7 model |
| coverage (coverage-ONLY, `SKIP_COMPLETION=1`) | 151 nodes, **7 681 missing**, `TRUNCATED=True`, 1 200 runs, 70 133 PCs, peak RSS 375 MB, 4 640 s |
| `coverage_summary.json` | **is the coverage-only pass — NOT a result.** Its `blocking` says "completion gate did not run". Do not quote it. |
| dump_errors | `Template::Error` 77, `I18n::InvalidLocale` 2 — both application terminals |
| pre-repair corpus | archived to `_archive_c7pre_dumps/` (39 956 dumps). Do not mix. |

## What IS in this corpus (the C7 repairs, all verified before the stop)

1. **Layout un-pinned** — `layout(false)` withdrawn from `run_dse.rb` and all six
   manifests; the real `with_header_with_footer` / mobile layouts render, the
   full `before_action` chain runs via `run_callbacks(:process_action)`, and
   mobile reaches `:mobile` through the app's own `mobile_switch` filter.
   Seven previously-absent shapes are present (`aspects`, `services`,
   `tags ⋈ tag_followings`, `roles` ×2, `COUNT(*) contacts`, `SUM(…unread)`).
2. **Discovery wall relocated to `Person#fix_profile`** — `Discovery.new` and
   `#fetch_and_save` withdrawn. Verified: `reload` events **0** (was 1 906
   over-emitted), wall events present, the arm truncates on the nil profile
   instead of asserting a clean 200 the app cannot reach. Terminal substitution
   (`NoMethodError` for `DiscoveryError`) is declared in `POLICY_HEADER.txt`.
3. **Aggregate projections repaired locally** for `sum` and `size` (both were
   rendering a ROW projection from the shared calculations family).
4. **Singular-association loaded-target memo** — a second read of the same
   `has_one` in one request no longer re-issues.

## NEXT, in order, when the limit resets (Sep 4, 8pm UTC)

0. **STEP 1 IS DONE — CLIQUE PROFILE ANSWER (coordinator, 2026-09-03).**
   **MULTIPLY — decisively.** See the `_c7_clique_analysis.py` output and the
   model proposal at the bottom of this file. Do NOT re-run the profile; go
   straight to step 2.
1. Close the demand with paged rounds (the corpus is only 1 200 runs; it needs
   base rounds before demand rounds are meaningful), **but first read the model
   proposal below and deliver it to the coordinator for adjudication** — the
   demand rounds must be shaped by whatever the coordinator approves.
2. Full engine report to `complete: true`, 0 FAIL / 0 NOT-TESTABLE, 0 red shims.
3. `_c7_audits.sh` — it already encodes the closing set correctly, including
   `skipped_pcs` BOTH ways and ONE `--runs` with every file.
4. Coordinator sweep → adversary round → extraction (mandatory fold check first).

## Open items carried

- **INSTR-9** (ground truth must be one request per process) is APPLIED here:
  the 14-process manifests are built and the rebuilt ground truth is 38 shapes
  in the union. Do not go back to multi-request manifests.
- **Four boundary notes** reported not patched (Rule T3), recorded in
  `docs/TARGET_FUNCTIONS.md`: gon stub's stale justification, `sum` projection,
  `size` projection, `find_target` memo. To be fixed ONCE, deliberately, before
  people_show starts.
- **`reload` is now unreachable on this endpoint** — `fix_profile` was its only
  route. The exercise census will show it 0-invoked; that is correct, not a
  regression. Say so in the REPORT beside the census output.
- Two per-REQUEST candidates were explained before the stop (`size` row
  projection explained BOTH the `notifications … unread` over and the
  `COUNT(*)` under; `people.owner_id` was a real double-read, 86 of 4 954 dumps,
  same bind, 0 with two owners).

---

## STEP 1 ANSWER — clique profile: MULTIPLY (coordinator, 2026-09-03)

Ran `_c7_clique_analysis.py` over `coverage_summary.json` (the coverage-ONLY
pass, 1 200-run sample of the 4 938-dump corpus). This is a SAMPLE statistic;
the conclusion is structural, so the sample size does not change it.

### Evidence

- 7 680 of 7 681 missing entries are `combination` (1 is a `taken` quirk in a
  journey formatter).
- **ALL 7 680 share the same joint product space.** 18 distinct var-set
  signatures; the dominant one (6 060 entries, 79%) is exactly the 13 core
  length vars — `CollectionProxy_records_{1..8,11}`, `Relation_to_ary_1` +
  its `_row_actors_row`, `Relation_records_{1,2}`. The remaining 1 620 are the
  same 13 plus one extra var (`target_photos`, `followed_tags`, …).
- Comparison buckets across all entries: `> 1` (99 840), `== 0` (1 380),
  `!= 0` (300), `> 3` (120), `> 0` (60). The length vars range over the
  `{0, 1, 2-3, >3}` domains declared in `apply_len_bounds` (B-7: preloaded
  associations carry the extra `>= 4` arm).
- **6 060 entries in ONE clique at cap 60** ⇒ the per-clique cap is NOT the
  limiting factor here; the demand loop enumerated 6 060 distinct unobserved
  outcome assignments of the single 13-var clique before `TRUNCATED`.
  (3^13 ≈ 1.59M — the enumerated corner is tiny, but the SPACE is the joint
  product.)

### Why the six dimensions MULTIPLY (not ADD)

If the six content dimensions ADDED to the 125 cliques, the missing
assignments would be spread across many small per-dimension cliques (a
"services" clique over just `services_rows`, a "tags" clique over just
`tag_followings_rows`, …). Instead, 100% of the combination-missing entries
sit in the JOINT 13-variable space: every run's path records a length decision
for each dimension (the page layout renders all six on every request), so the
dependence graph sees them as fully pairwise-co-occurring and demands every
joint outcome — the PRODUCT of the dimensions' lengths, not their sum.

### Why the naive fix is already refuted (W-E)

`coverage_assumptions.py` §W-E (withdrawn 2026-08-29): **
`(len(X) > 1)` is independent of NOTHING.** The cardinality determines the
statement shape (`= $(key)` for one row, `IN ($(k1), $(k2), …)` for many), so
flipping it together with any decision that gates a read produces a bulk
statement absent from both singles. 9 of the gate's 12 FAILs were exactly
this class — length × DECISION (dispatch, `_target_is_photo`, `_text_nil`,
contact `_not_found`). Declaring the 13 length vars pairwise independent
would re-open those FAILs and violate Rule D. **Do not propose that.**

### MODEL PROPOSAL — cross-dimension length×length independence (new tier)

The W-E withdrawal covers length × read-gating-DECISION pairs. It does NOT
cover length × length pairs from DIFFERENT statement families. Per dimension,
the list length gates that dimension's OWN dedicated `SELECT` (aspects has its
own query, services its own, tags ⋈ tag_followings its own, …). The concern
Rule D/W-E names — one statement whose shape changes with cardinality — does
not arise between two statements that never share a row source.

Proposal: a NEW tier in `coverage_assumptions.py` that declares
`(len(X) > 1) ⊥ (len(Y) > 1)` ONLY for length vars whose statements are
proven DISJOINT families, subject to the engine's flip-both probe per pair
(D3, as every existing tier uses):

- Flip X's length while holding Y fixed: Y's statement family must be
  unchanged (no new shape, no new statement).
- Flip Y while holding X fixed: X's statement family must be unchanged.
- Only pairs passing BOTH flips are declared. Nested/co-source pairs stay
  DEPENDENT: `Relation_to_ary_1` × its `_row_actors_row` (the actors preload
  is INSIDE the to_ary list — same row source), `CollectionProxy_records_*`
  sharing one rep, and any length × the DECISION it gates (W-E still applies
  there).

Expected effect: the 13-var clique splits into per-dimension cliques (~13
single-var enumerate-able pieces), collapsing the 3^13 product to ~13 × k
combos — the 7 680 missing should fall to near zero WITHOUT new runs, purely
from the model. If any pair FAILS the flip-both probe (a genuinely shared
row source, e.g. a join), keep that pair observed and say so in the report.

**Refinement (coordinator, 2026-09-03): the 13 vars are per-run ORDINALS of
~6 statement families, not 13 distinct dimensions.** Row-column fingerprinting
over 150 dumps: RELR[1]=@notifications (recipient_id/unread/target_type),
RELR[2]=mentions_container people, REL[1]=the polymorphic target
(target_guid/text family), CP[2]/CP[3]/CP[5]/CP[8]=services, CP[1]=aspects.
The indices are call ordinals (targets.rb cycle-2 fact-cache note: "records_2 /
records_4 / records_6 — one FACT modelled as three"). So build the pair list by
STATEMENT FAMILY (aspects × services × tags ⋈ tag_followings × roles ×
contacts × notifications × actors × target), not by index — and confirm the
family grouping against targets.rb's own mints before declaring any pair.

**Adjudication required:** the coordinator must approve the tier before the
demand rounds use it (Rule T3: assumptions are model — the batch agent may
propose, not ship). Deliver the pair list with flip-both evidence.

### What the demand rounds should do meanwhile

Even before the model is adjudicated, paged base rounds are safe and needed:
the corpus is 1 200 runs and the missing enumeration truncated at
`TRUNCATED=True` — base rounds enlarge the observed outcome set, which shrinks
the unobserved corner regardless of the model decision. Run those first; bring
the pair list to the coordinator with them.

### Hardening-lint triage (coordinator, 2026-09-03) — see `_hardening_triage_20260903.md`

Lint on the C7 corpus: **2 flags.** H3 (`CollectionProxy#load_target` note)
is a FALSE POSITIVE — it fires only on the already-loaded no-statement path
(Rails issues no SQL); answer it by documenting the target as a declared
wall in the batch notes, no code change. H4 (`records_4_rows` one-polarity)
is REAL — seed a non-empty `records_4` in a demand round (map `records_4` to
its association first). H1/H2/H5 clean; H6 skipped (needs `--runs`, closing
pass only). Both feed step 2; nothing blocks the resume.
