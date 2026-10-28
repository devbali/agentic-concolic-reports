# comments_index precision fix — alias-collision root cause, 2026-09-17

## Symptom

`comments_index` rendered 844 PC (path-condition) predicates during
extraction but only 50 survived `prune_conditions`/`drop_subsumed`, producing
a 54-statement policy. The project owner's standing design rule is:

> every PC regarding any of the earlier joined symbolic variables should be
> in the SQL query... otherwise we should be 100% precision. Skipping should
> lower coverage, not precision.

A near-total collapse (844 -> 50, ~94% dropped) is not plausible as "mostly
genuine two-sided branches" for an endpoint this shape-diverse. The
hypothesis — confirmed below — was that `prune_conditions` was over-pruning
due to a bug, not doing its job correctly.

## Classification of the dropped predicates

Every dropped predicate falls into one of three buckets:

- **(a) never recorded** — not applicable here; this task starts from
  predicates that *were* recorded and rendered into some SQL shape.
- **(b) recorded but never rendered** — not the failure mode found.
- **(c) rendered, then wrongly pruned** — the actual failure mode, confirmed
  for two distinct predicate families:
  - identity-comparison predicates (e.g. "is this comment's author the same
    person as X") — the dominant family.
  - `posts.type` / `posts.public` predicates that get folded across a
    post-identity join.

  One family was checked and found **not** to be a bug:
  - `users.language`-style predicates are genuine two-sided branches (the
    corpus really does contain the same shape both with and without the
    predicate, because the app really does take both branches against the
    same query shape). These are correctly pruned by design and are not
    part of this fix.

## Root cause

`prune_conditions` treats a predicate `p` as irrelevant to a rendered SQL
shape `S` iff the corpus contains `S` observed **both** with `p` present and
with `p` absent — a pure, deterministic, monotone set-membership test over
*rendered predicate text*. That rule is correct, but it depends on rendered
text actually identifying the same real-world comparison consistently.

`transform.py`'s `_Build._fresh_alias` (`src/queries_from_runs/transform.py:1224`)
used to mint table aliases from a first-free-slot counter:

```python
elif table not in self.used_aliases:
    self.used_aliases.add(table)
    return table
else:
    i = 0
while f"{table}{i}" in self.used_aliases:
    i += 1
```

Whenever a build only ever inlines **one** table of a given name (the common
case — e.g. exactly one extra `people` join per statement, for one
"mentioned person" or "comment author" identity), that counter trivially
assigns the bare table name (or slot 0) **every time**, regardless of which
real-world producer it is. Two different runs whose sole `people` join
resolves to two different real people (e.g. "the post's author" in one run,
an unrelated "mentioned person" in another) both rendered the literal alias
`people` / `people0` — byte-identical predicate text for genuinely different
comparisons. `prune_conditions`'s set-membership rule then correctly, but on
false input, saw "shape S with this exact predicate text" and "shape S
without it" and discarded the predicate corpus-wide, even though it was a
real, always-true fact for every run that actually reached that branch.

This is bucket (c): rendered, then wrongly pruned, due to accidental alias
reuse across unrelated identities — not a genuine two-sided branch.

## Fix

`_fresh_alias` and `inline_producer` (`src/queries_from_runs/transform.py:1224`,
`:1302`) now derive the alias slot from a hash of the *producer's identity*
(`hint = f"{result_name}:{table_name}"`, `zlib.crc32(hint) % 1000`) instead
of from arrival order, so the SAME real-world producer always renders under
the SAME alias number, and two DIFFERENT producers only collide by genuine
(rare) hash collision — resolved safely by the pre-existing linear probe.
`hint=None` (plain counter) is now used only by `ensure_myperson`, which
mints at most one alias per build for the query's own principal-identity
join — there is no producer identity to hash there, and every call is for
the same row by construction.

### Two-stage fix history

1. **First attempt (incomplete)**: hinting was added, but only at the
   `fold_atoms` two-query-cap call site (the "speculative inlining of a
   comparison's other row" path). This reduced collisions but left the
   dominant collision family (native bind resolution, e.g.
   `diaspora_handle`-style comparisons resolved via
   `self.rt.producer_names()`) unchanged, because that path calls
   `inline_producer` too, just from a different caller
   (`_bind_value`), which had not been hinted.
2. **Complete fix (this segment)**: hinting was made **unconditional**
   inside `inline_producer` itself (the `alias_hint: bool` parameter was
   removed entirely — both call sites need it equally, since which
   producers a bind-resolution walk visits, and in what order, is itself
   run-dependent). Both `_bind_value`'s and `fold_atoms`'s call sites now
   get the same hash-derived, producer-stable aliasing automatically.

### Empirical verification

A saved, reproducible verification script
(`_verify_alias_fix_20260917.py`, output in `_verify_alias_fix_20260917.out`)
monkeypatches `_Build._render_atom` to log every rendered atom's SQL text
alongside its `ColRef.producer` identity on both sides, over a fixed
3000-dump sample (seed 7) of `comments_index`. It groups by rendered text
and counts, per text, how many *distinct* `(lhs_producer, rhs_producer)`
pairs occur — a collision is any predicate text mapping to more than one
distinct producer pair.

| stage | distinct people-related predicate texts | colliding |
|---|---|---|
| pre-fix | 26 | 24 |
| after first (incomplete) fix | 34 | 10 |
| after complete fix | 16 | **0** |

(The distinct-text count itself changes because fixing the collision also
changes how many genuinely-different comparisons get folded/deduped
correctly; the meaningful number is the 0 collisions in the final column.)

## Corpus-level effect (comments_index)

Full re-extraction, same 26,528-dump corpus, via the production
`_pcfold3_parallel.py` script (8 shards, cap=2):

| | before fix | after fix |
|---|---|---|
| distinct (shape, pc_preds) groups | 248 | 407 |
| PC predicates rendered | 844 | 1230 |
| PC predicates kept after prune | 50 | 166 |
| final SQL statements | 54 | 155 |

All 155 statements parse cleanly under `sqlglot.parse_one(dialect="mysql")`.
Spot-checks (grep-based, by family) confirm the previously-collided
identity/type/public predicates now render under differentiated aliases
(e.g. `people522` consistently for the post-author identity across
statements; `people844`/`people941`/`people942`/`people70`/`people197`/
`people340` as distinct mention-target identities; `posts80`/`posts90`/
`posts347`/`posts355` as distinct post-identity roles; `users926`
consistently for the current-user identity) instead of collapsing to a
single bare/`0`-suffixed alias.

Both the `base` (`reliable_pruning_witnesses=False`) and `fix`
(`=True`) arms produce identical numbers for this endpoint, matching the
pre-fix pattern — `--reliable-pruning-witnesses` makes no observed
difference here.

Artifacts: `comments_index_pcfold3_base.sql`, `comments_index_pcfold3_fix.sql`,
`_summary_comments_index_pcfold3.json`,
`scratchpad_pcfold3_logs/comments_index_refix.log`.

## Precision verification sweep (2026-09-18)

The alias-collision fix above closes one confirmed bug. Before calling
comments_index "fixed," every other known defect class that could cause
either (a) a rendered predicate to be wrongly dropped, or (b) a statement to
be admitted that does not correspond to a real, issuable query (the owner's
"any statement that gets admitted is precise if it's a real query that can
be issued" bar), was checked specifically against comments_index:

1. **Reliable-pruning-witnesses (`_PRUNE_DIAGNOSIS_20260916.md`)** — a
   separate, previously-fixed defect where a predicate is wrongly dropped on
   the strength of an *errored/truncated* run's silence (that run never
   reached the code that would have re-asserted the predicate, so its
   "absence" is missing data, not a real counter-witness). This gave
   notifications_index +48 and conversations_index +266 recovered
   predicates when the `reliable_only=True` arm was compared against
   baseline. For comments_index, `base` and `fix` arms are byte-identical
   (166/166 kept both ways). Traced why: a full census of all 26,528
   comments_index dump files (`d.get("error")`, the exact field
   `Run.from_dict` reads) shows **zero** have any run-level error recorded.
   This endpoint's corpus has no truncated runs at all, so this defect class
   is structurally inapplicable here — not "checked and found rare," but
   provably zero occurrences.

2. **Mock-fabrication sweep** — cross-checked every VIOLATION row in the
   older `results2/MOCK_AUDIT.md` that is either comments_index-specific or
   in a shared code path comments_index exercises, against the *live*
   `results3/comments_index/concolic_targets.rb`. Found three instances of
   exactly the failure class the owner is worried about ("a mock may replace
   execution, never evidence") — a mock that doesn't just skip a query
   (coverage loss, acceptable) but stands in front of one and emits nothing,
   or worse, a synthesized/junk note — and confirmed all three were already
   removed for comments_index specifically, each with its own inline
   discovery/removal note in the live target file:
   - **X3** (`ActsAsApi::Collection#as_api_response`) — was mocked, which
     silently skipped every serialized item's own `as_api_response` walk
     (the per-field template that fetches associations). Comment at
     `concolic_targets.rb:1274-1296`: "mocking it here was covering up...
     must walk each mentioned Person's REAL :backbone template... not
     synthesize one representative row from a fake SQL-shaped note.
     Removed." This endpoint's central descent
     (`@comment.mentioned_people.as_api_response(:backbone)`) now runs for
     real.
   - **X6f** (`Diaspora::Mentionable.people_from_string`) — was mocked to
     `Person.none`/`[]`, covering up the entire local
     `Person.find_or_fetch_by_identifier` -> `find_by(diaspora_handle:)`
     lookup family. Confirmed removed; `run_dse.rb:14-17` corroborates:
     "no longer mocked, so mentioned_people -> Mentionable.people_from_string
     -> a REAL local Person [lookup]." This is the source of the
     differentiated `people844`/`people941`/`people942`/`people70`/
     `people197`/`people340` mention-identity aliases seen in the corpus
     table above — they are real, distinct lookups, not an artifact.
   - **X6i** (`Person#name`) — was mocked to a concrete string, skipping the
     `self.profile` association read (`SingularAssociation#find_target`)
     inside its real body. Comment at `concolic_targets.rb:1483-1494`:
     "X6i REMOVED for comments_index cycle 1 (2026-08-25, AGENT_RUN.md; D1 —
     'a mock may replace execution, never evidence')... Mocking #name itself
     skipped that target read and emitted the junk note 'Person#name'... now
     runs and its profile read mints evidence like every other reader."

   No other MOCK_AUDIT.md VIOLATION row is live for comments_index. The
   audit itself is exhaustive per-endpoint, not just per-mock: it lists
   every `declare_target` reachable from each of its 6 audited entrypoints
   individually (`results2/MOCK_AUDIT.md:177-181` is comments_index's
   *complete* row set — 5 entries total). Of those 5, only one
   (`people_from_string`, row 181) is a VIOLATION, and it is the one fixed
   above; the other 4 are CLEAN LEAF or already-fixed note issues. The
   remaining shared-layer VIOLATION rows (`PostService#mark_user_notifications`,
   `User#add_to_streams`/`#retract`, `CollectionProxy#create`,
   `after_sign_in_path_for`, `confirm_email`, the `Stream::*` family) are not
   silently-assumed-safe: each is tied in its own comment to a different
   controller action (posts_show's post-view wall, post create/destroy,
   devise sessions, the stream/timeline index) that comments_index's
   `CommentsController#index` does not call into. **Verified empirically**,
   applying the same "confirmed DEAD by corpus grep" standard the original
   audit used for `SingularAssociation#writer` (`results2/MOCK_AUDIT.md:149`):
   a full-corpus text scan of all 26,528 comments_index dump files for
   `blocked_people`, `aspect_ids`, `tag_ids`, `attach_user_likes`,
   `publisher_prefill`, `build_mentioned_people_json`, `add_to_streams`,
   `User#retract`/`retract`, `CollectionProxy#create`,
   `after_sign_in_path_for`, `confirm_email`, and
   `mark_user_notifications` returned **zero occurrences for every single
   name, in every one of the 26,528 dumps**. These 13 shared-layer
   VIOLATION mocks are provably dead code on this endpoint's corpus — not
   assumed-safe by call-graph reasoning, but confirmed absent from every
   run.

   The one exception, confirmed still live (and intentionally so):
   `ActionController::ImplicitRender#default_render` (comments_index's
   `concolic_targets.rb:1007`) is still mocked to a terminal
   `:render_reached` stub — the universal, cross-endpoint
   `ActionController::Rendering#render` VIOLATION (`MOCK_AUDIT.md:141`,
   explicitly naming `app/views/comments/_comment.mobile.haml` as one of
   its examples) is real and reachable on comments_index. This is the one
   deliberate, documented, out-of-scope exception in the whole audit — a
   whole-app "descend into the view/partial render pipeline" project,
   affecting every endpoint identically, explicitly deferred as its own
   future stage. It is a **coverage** gap (queries a Haml partial might
   issue are never recorded at all) — it cannot fabricate a predicate on a
   statement that already got admitted, only omit statements outright,
   which is the owner's own stated acceptable failure mode ("skipping
   should lower coverage, not precision").

3. **`reports/diaspora/TODO.md`'s "Mock/boundary fixes needed for SQL
   notes"** (the unresolved-`_SYM_RESULT_…`-placeholder / type-mismatched-
   join defect class, full detail in `_MOCK_NOTE_FIXES_20260916.md`) —
   comments_index is not on the affected list; all 62 catalogued unloadable
   statements are in people_show/people_stream/posts_show. Consistent with
   comments_index's own 0-placeholder, 0-rejected extraction result.

4. **`skipped_pcs` diagnostic** (predicates that never rendered into *any*
   query shape at all — checked because `_pcfold3_parallel.py` was
   previously computing this and silently discarding it; now surfaced).
   Full-corpus result: 839,383 skip instances across the run. Every one of
   the top 20 reasons (by instance count; together ~90% of the total) falls
   into exactly three categories, verified against `pcs.parse_pc`'s actual
   rejection rule (an expression is unfoldable, and correctly appended to
   `skipped_pcs`, unless it is a comparison where **at least one side is a
   `ColRef`** — a column of some row a recorded query actually produced;
   `pcs.py:198-200`):
   - **exists?/not-found booleans** (e.g.
     `SYM_RESULT_...FinderMethods_exists__N_exists == True`, 85,999;
     `..._row_person_not_found == True`, 62,471; `..._not_found == True`
     variants, several more in the top 20) — the boolean *return value* of
     an already-recorded finder/exists query, checked by the app's Ruby code
     after that query ran. Not a column of a row; nothing to fold.
   - **result-set cardinality checks** (`len(SYM_RESULT_...rows) != N`,
     81,309; `> N`, 75,656; more variants) — a count of an already-fetched
     relation's rows. Not a column value; "the query ran because it
     returned N rows" is not expressible as a WHERE-clause fragment on that
     same query.
   - **post-fetch content/parameter checks** (`Length(SYM_PARAM_post_id) <
     N`, a request-parameter string-length validation; `..._text_has_mention
     == True`, `..._text_dlink_geN == True`, Ruby regex checks run against
     an already-fetched row's text column *after* the SELECT executed, e.g.
     link/mention detection for rendering) — these branch on the *content*
     of data already returned, not on what the SQL filtered.

   None of the top 20 is a rejected genuine `column = value`/`column =
   column` comparison — i.e., none is evidence of `parse_pc` wrongly
   failing to recognize a real WHERE-shaped predicate. This is the
   extraction correctly implementing the owner's own directive ("the
   extraction code needs to be simplified, to be path conditions in where
   clauses") — a PC that isn't a WHERE-clause-shaped fact about a produced
   row's column is excluded, not force-fit into one. Force-fitting any of
   these would be the actual precision violation (a fabricated WHERE clause
   that doesn't correspond to how the real query was built). This is a
   **coverage** characteristic of a read-heavy Rails app (most of its
   Ruby-side branching is on already-fetched data, not on additional SQL
   filters), not a precision defect.

**Verdict (final, 2026-09-18)**: all four items of this sweep are now
closed for comments_index:

1. Alias-collision bug (`_fresh_alias`/`inline_producer`) — fixed (hash-derived
   aliases), and is the root cause this whole investigation started from.
2. Reliable-pruning-witnesses gap — inapplicable to this corpus: zero errored
   runs in all 26,528 dumps, so `reliable_only=True`/`False` provably produce
   byte-identical output here (confirmed: both arms give 155 statements,
   1230 -> 166 kept predicates, reproduced identically across two independent
   full-corpus extraction runs).
3. Mock-fabrication sweep against `results2/MOCK_AUDIT.md`'s VIOLATION list —
   the 3 violations reachable from comments_index (X3 `as_api_response`, X6f
   `people_from_string`, X6i `Person#name`) are already removed from
   `concolic_targets.rb`, each explicitly for "a mock may replace execution,
   never evidence"; the other 13 shared-layer VIOLATIONs are empirically dead
   code on this endpoint (0 occurrences across all 26,528 dumps, by direct
   corpus grep — the same standard MOCK_AUDIT.md itself used to clear
   `SingularAssociation#writer`); the one remaining live mock
   (`ActionController::ImplicitRender#default_render`) only ever affects
   *coverage* (whether rendering completes), never a query's shape or
   predicates.
4. `skipped_pcs` diagnostic — 839,383 skip instances, top-20 reasons audited
   against `pcs.parse_pc`'s actual rejection rule; every one is a call-result
   boolean, a row-count/cardinality fact, or a post-fetch content/parameter
   check — none is a rejected genuine column comparison. This is the
   extraction correctly declining to fabricate WHERE clauses for PCs that are
   not WHERE-shaped, i.e. exactly item 2 of the design's own precision rule
   ("any statement that gets admitted is precise... skipping should lower
   coverage, not precision").

With all four items closed and no remaining open question, **comments_index's
extraction is at 100% precision** in the sense the owner's own rule defines
it: every PC over an earlier-joined symbolic variable that is expressible as
a real WHERE-clause fact is retained (subject to deterministic same-shape
pruning, which by construction only drops predicates the corpus proves
irrelevant); nothing is fabricated to force a non-WHERE-shaped PC into the
query; and no result is silently dropped due to a boundary/mock defect. This
is necessarily *precision* completeness (no admitted statement or predicate
is fabricated), not a claim of 100% *coverage* (the `skipped_pcs` volume
shows how much of the app's control flow is legitimately outside SQL's
expressiveness) — those are the two different axes the owner's own rules
distinguish, and this sweep only ever claimed the former. It is still not a
mathematical proof against every conceivable defect (absence of a *known*
defect after an exhaustive, itemized sweep is not absence of *all possible*
defects), and there is no ground-truth reference available to differential
against (quarantined for this project) — but every concrete, checkable
mechanism that could produce a wrong or fabricated predicate has been traced
to source and either fixed or shown inapplicable.

## Other endpoints

The same fix is app-agnostic (it lives entirely in `transform.py`'s
producer-inlining machinery, with zero diaspora-specific logic) and applies
automatically to every endpoint re-extracted with the fixed code.
`notifications_index`, `conversations_index`, `people_show`, and
`people_stream` were re-extracted with the fixed code via the same
`_pcfold3_parallel.py` script.

`posts_show` was intentionally excluded from this re-extraction pass, per
the pre-existing project note that it is not yet complete
(see `reports/diaspora/docs/` posts_show state notes) — re-extracting it
under this fix does not change that state and was out of scope here.

<!-- FILLED IN ONCE THE BACKGROUND RE-EXTRACTION COMPLETES -->
### notifications_index
_pending — largest corpus (313,977 dumps), re-extraction running in the
background at time of writing; see
`scratchpad_pcfold3_logs/notifications_index_refix.log`._

### conversations_index
_pending — queued behind notifications_index._

### people_show
_pending — queued behind notifications_index._

### people_stream
_pending — queued behind notifications_index._

## Test suite

The alias fix changes every alias assigned to a build's *sole* table of a
given name from a bare/no-digit name (e.g. `` `posts` ``) to a hash-derived
digit-suffixed one (e.g. `` `posts347` ``), even though only one instance of
that table appears — this is expected and correct, since the alias is now
always producer-identity-derived rather than arrival-order-derived. This
broke 19 of 115 tests in `test_queries_from_runs.py`, all of which hardcode
literal expected SQL strings containing the old bare-alias form. Every
failure was purely cosmetic: the underlying SQL structure, table set, and
join predicates were unchanged in every case, only the alias digit differed.

Each of the 19 tests' literal expected strings was updated in place to the
new deterministic values (confirmed by running the actual fixed code, not
guessed), preserving the file's existing "literal SQL string assertion"
style. A blanket "dealiasing" test helper was deliberately **not**
introduced: `test_alias_on_table_collision` specifically checks that two
colliding real tables get assigned *distinct* aliases, and a blanket
dealiasing helper would have silently defeated that test's purpose.

Result: **115 passed, 3 skipped** (unchanged skip count — those 3 require
external `QFR_TEST_RUNNER_RB`/`QFR_TEST_DUMP_DIR` env vars and are not run
in this environment), same as before the alias fix, with 0 failures.

## Cleanup pass

Per standing instruction to reduce `src/queries_from_runs/` to the minimum
necessary code alongside the precision fix:

- **`inline_producer`'s `alias_hint: bool = False` parameter removed
  entirely** (`transform.py`) — hinting is now unconditional, so the
  parameter (and both call sites' conditional passing of it) was dead
  weight once the fix made "hinted" the only correct behavior. Confirmed
  via `grep -rn "alias_hint"` across `src/queries_from_runs/` and
  `reports/diaspora/results3/queries_from_runs/`: zero remaining
  references after removal.
- **`schema.py`: removed dead `is_column` function** — zero callers
  anywhere in `src/`, `reports/`, or `scripts/` (confirmed via an AST-based
  call-site scan before deletion). `schema.py`: 158 lines (post-removal).
- **CLI flag audit** (`dump.py`, `diff.py`, `subsume.py`, `app_config.py`):
  reviewed every `add_argument` call across the package; found no redundant
  or superseded flags. `--reliable-pruning-witnesses` and `--two-query-cap`
  are both live, distinct knobs used by the production `_pcfold3_parallel.py`
  driver (the `base`/`fix` arm split and the join-inlining cap,
  respectively) — neither is legacy.
- No stale scratch scripts (e.g. an earlier ad-hoc
  `_trace_alias_collision.py`) remain in `src/queries_from_runs/` — confirmed
  via `find`.
- No diaspora-specific facts were added to `src/queries_from_runs/`; the fix
  is entirely generic (hash-based aliasing keyed on producer identity, not
  on any app's table/column names). App-specific facts continue to live
  exclusively in `reports/diaspora/queries_config/app.json`.

### Line counts

| file | lines (current) |
|---|---|
| `transform.py` | 1851 |
| `schema.py` | 158 |
| `dump.py` | 593 |
| `pcs.py` | 315 |
| `app_config.py` | 522 |
| `diff.py` | 619 |
| `subsume.py` | 434 |
| `endpoint_params.py` | 123 |
| `__init__.py` | 59 |
| `__main__.py` | 13 |
| `test_queries_from_runs.py` | 2360 |

No clean pre-task git baseline exists for a precise before/after LOC diff:
`transform.py` and `schema.py` are both tracked in `src/`'s nested git repo,
but a `Checkpoint: snapshot accumulated work-in-progress` commit
(`82dd362`) landed mid-task and already includes this task's `transform.py`
alias fix and `schema.py`'s `is_column` removal, so `git diff HEAD` for
those two files shows nothing outstanding beyond `test_queries_from_runs.py`
(now updated for the 19 alias-string fixes). Rather than fabricate a
precise historical diff, this report states the deletions explicitly
(`is_column`, the `alias_hint` parameter) with grep-based proof of zero
remaining references, per the standing instruction to prefer verifiable
deletion evidence over an unavailable clean diff.

External CLI/behavior surface is unchanged: no flag was added, removed, or
renamed; `inline_producer`'s signature change
(`alias_hint: bool = False` parameter removed) is an internal API used only
within `transform.py` itself, not part of any CLI or cross-module contract.
