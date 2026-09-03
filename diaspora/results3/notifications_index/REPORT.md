# results3/notifications_index — CONTROL-VARIANT ADDENDUM (gen3, 2026-08-20)

(The sections below this addendum describe the gen2 corpus and are kept as
history; gen2's corpus is archived. The CURRENT corpus is gen3 — all 8 STI
type profiles driven, Person#name/as_api_response mocks removed per rule
(b), 7,837 dumps, 0 run errors — and this endpoint then served as the
CONTROL in the rule-regime experiment; see ../MOCK_RULE_EXPERIMENT.md
(final verdict), ../_experiment/ROUNDS.md, and ../MOCK_TEST_RECIPE.md.)

Control (gen3) numbers: extraction 28 final queries (52 distinct, 24
subsumed) from all 7,837 dumps; 13/28 usable as diff views (the assoc_*
placeholder gap, closed in round 2 by the fold — see the recipe's P1);
reference diff 15/71 covered, 16 provably rejected (all attributed: 6
before_action/layout scope, 1 notification_actors granularity, 8
mentions/profile-chain — the latter closed in round 2), 40 solver-unknown.
The control's cap-4 coverage loop did not complete on this corpus (the
46-expr universe's solver cost; see the recipe's P5 for the standing
pairwise-first rule). The WINNING rule-set's numbers on this same corpus
family: 30/71 covered, 6 rejected, 30/30 usable views
(../_experiment/variant_d/RESULT.md).

---

# results3/notifications_index — gen2 (discipline-clean mocks, symbolic persistence) — 2026-08-19

Gen2 = the post-BUGFIXES_20260819 rebuild: gen1's corpus (archived in
`../../trash/results3_gen1_20260819/`) was invalidated by the `1=0`
association-scope poisoning (bug 1) and the kwargs/note-rendering losses
(bug 2a/2b). This endpoint was rebuilt first, alone, on Bali's directive,
and carries the debugged tooling the other five endpoints will inherit.

## Verdict

`coverage_complete: false` — an **honest stop at full pairwise
combination coverage**, a strictly stronger bar than any prior batch:

- **Corpus:** 4,547 dumps (4,000-run deterministic exploration + seeded
  append rounds), **0 run errors, 0 unparseable**, 169,773 PCs,
  19-expr universe, `solver_lost: 0`, `unevaluable: []`.
- **Every expression explored on both sides** except two provably
  one-sided ones (the Journey-formatter `guid != ''` pair — see
  assumptions tier 2: recorded 1,595/1,997 times, taken=True never,
  value-forced at their only recording site).
- **Pairwise (2-way) combination coverage: 588/588 observable pairs
  covered.** The other 25 of the 613 raw pairs are each PROVABLY
  unobservable: same-variable value impossibilities (`TYPE==0 ∧ TYPE==1`,
  `guid=='' ∧ guid!=''`, `count<4 ∧ count==0`) or declared
  existence-foreclosures (finder-mock arms, count chains, the
  unpersisted-row count foreclosure) — all verified 0-violation over the
  full corpus.
- **What remains open** (why `complete` is false): the checker demands
  full k-way outcome assignments over the residual clique (~19 conjuncts
  per demand). That cross-product space is combinatorially large; its
  enumeration is itself solver-truncated (`truncated: true` from
  5s-timeout unknowns on the big mixed int/string conjunctions), so
  each check pass surfaces ~96 fresh demands regardless of how many the
  previous round closed. Three seeded rounds (96 + 96 + 26 targeted
  replays, all verified to have executed) closed every demand they were
  shown; the enumerator kept sampling new k-way combos from behind its
  own timeout horizon. Forcing `complete` by grinding was rejected;
  the pairwise bar plus the documented assumption structure is the
  honest description of what this corpus establishes.

## Assumptions (15, `coverage_assumptions.py` — every one carries a
code-site argument AND a 0-violation empirical proof over the corpus)

- **Gen1 finder-mock tier (kept, re-verified 0/3,892, extended):**
  `first_1_not_found==True` forecloses the found-arm attribute exprs —
  now including the gen2 `_persisted` decision, minted by the same
  found-arm `symbolic_instance` call.
- **Existence-foreclosure matrix (gen2, complete):** computed
  exhaustively over all ordered expr pairs × guard sides. Six families:
  count_3==0 → no count_4 (the two `actors.size` reads,
  `notifications_helper.rb:55` then `:9`, order fixed by `:77`);
  count_4==0 → no count_4==1 (i18n pluralization short-circuit); the two
  `guid ==''`/`!=''` same-var chains; unpersisted list row → no actors
  counts at all (flipped `_persisted` → Rails `null_scope?` → the size
  shim's concrete arm — the count mock never fires).
- **One-sided Journey exprs (gen2):** `first_1_guid != ''` and
  `records_1_row_guid != ''` declared `OneSideUntracked(not_taken)` —
  gen1's famous open residual, now with the mechanism: they record only
  inside actionpack `journey/formatter.rb:41`'s guid-empty region, where
  the value forces False. Only the constructively impossible side is
  released.

## Mock-surface changes this generation (`concolic_targets.rb` marked
blocks + `targets.rb` §gen2; full rationale in `../BUGFIXES_20260819.md`)

1. **Persisted-decision** (Bali directive "explore both paths"):
   `persisted?`/`new_record?` on every representative is a seeded,
   PC-recorded decision `<base>_persisted` (SYM_DECISION idiom, both
   readers through ONE expr polarity; default seed persisted). The
   unpersisted side's `1=0` scopes are explored and labeled by their own
   PC — 472 dumps, all on taken `_persisted == False` branches, zero
   unlabeled (the gen1 poisoning is gone).
2. **Kwargs-to-positional prepend** (bug 2a): finder conditions reach
   the mocks; zero "WHERE unavailable" notes remain.
3. **Note rendering** (bug 2b): arel-9 `Casted` no longer crashes
   `collect_binds`; `ConcolicSymbolicToSql` renders inline symbolic
   values as `$$(name)`; zero render-failure fallbacks remain.
4. **`CollectionAssociation#size` prepend:** `0 + count ≡ count` dodges
   the by-design coerce wall while COUNT SQL still flows through the
   declared mock — this is what let the symbolic actors count reach
   `number_of_actors < 4` (a branch gen1 could never record).
5. **`ConcolicIntValue` display-leaf `+`/`-`:** the ≥4-actors branch
   spends the count in `t(count: n - 3)` display text; concretize only
   Integer-operand arithmetic there (comparisons still record).

## Coverage-loop tooling debugged here (inherited by the next endpoints)

- `EXTRA_SEEDS_JSON` targeted-seed input + `LABEL_SUFFIX` collision-free
  append rounds (`run_dse.rb`).
- **`SEEDS_ONLY=1` pure-replay mode — the decisive fix:** the worklist
  is LIFO, so a seeded root's flip-children preempted every remaining
  root; in a 96-root round under MAX_RUNS=250, roots past ~#5 never ran
  (found by proving no dump ever carried the count_2=0 seed dicts).
  With replay mode the same 96 dicts execute in 2.3s.
- Loop budget rule: MAX_RUNS must exceed the seed count.
- `MAX_MISSING_PER_CLIQUE` is a WINDOW, not a total — equal missing
  counts across rounds with changing constraint hashes mean progress,
  not a stall. The checker's per-clique enumeration also stops at its
  first solver-unknown, so even uncapped counts are a lower bound.
- **Standing rule (Bali, 2026-08-19): never enumerate wide.** Run the
  checker at its default cap-4 only (~2 min); the 16/500-cap passes this
  endpoint paid for (up to 18 min each) bought counts that were still
  timeout-truncated lower bounds. The completeness evidence is the
  PAIRWISE MATRIX instead — pure Python counting over the dumps, no Z3,
  seconds — plus the foreclosure proofs for the unobservable pairs.

## Extraction gate (`../queries_from_runs/notifications_index.sql`)

7 final queries (19 distinct raw shapes — the seeded rounds surfaced 4
beyond the first extraction — 12 subsumed via blockaid; `subsume_ran:
true`, no flags), from all 4,547 dumps: the paginated notifications
list, unread-count, the
actors join (gen1's `1=0`-poisoned query, now clean:
`WHERE notification_actors.notification_id = notifications.id AND
notifications.recipient_id = _MY_UID`), actor profiles through the same
chain, polymorphic target fetch, target-author person fetch, and the
gen2-new mentions family (`mentions_container` + people join) opened by
the persisted-side `mentioned_people` branch. Three `_assoc_*`
placeholders remain, honestly flagged (association-sourced binds whose
producers are association loads).

**Reference diff (blockaid coverage, 120s/query solver timeout) vs the
policy set's 71 notifications queries: 7 covered, 22 provably rejected,
42 solver-undecidable.** (Ours vs reference: 2 covered, 1 rejected, 4
undecidable, 3 placeholder queries excluded as views.) The 22 rejected
collapse onto the DOCUMENTED scope residues, not missing families:
photos/people target fetches from the 6 undriven STI notification types
(only Liked/Reshared are driven, both Post-targeted), the profiles reads
behind the still-mocked `Person#name` (audited carried-over violation),
and the deliberately-skipped `started_sharing` ContactPresenter/ActsAsApi
descent. Baselines for comparison: results2 covered 1/71; gen1's corpus
had 42 provably rejected at 15s. The 42 undecidable are large multi-join
determinacy problems that time out even at 120s — a blockaid capacity
limit, not a corpus statement.

## Honest caveats

- The `assoc_target_*` exprs ride the polymorphic `find_target` mock's
  naming; their ordinals are per-run within-context (the conversations
  lesson) — no assumption keys on them beyond the observed-set tiers.
- Two id-identity compares (`first_1_id == SYM_PERSON_NI_id`,
  `records_1_row_id == SYM_PERSON_NI_id`) are DSE-unflippable but were
  covered on both sides via checker-model seeds.
- `truncated: true` is a solver-capacity statement, not a coverage gap
  claim: `solver_lost: 0`, `unevaluable: []`, and every demand the
  enumerator ever surfaced was either executed (seeded rounds) or proven
  unobservable (assumptions).
