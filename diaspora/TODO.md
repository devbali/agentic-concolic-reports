# TODO — diaspora

## Mock/boundary fixes needed for SQL notes (queries_from_runs unloadable residue)

Full detail, exact file:line, and status (already fixed vs. still open) for
each: `results3/queries_from_runs/_MOCK_NOTE_FIXES_20260916.md`.

Quick index (see that doc for evidence and exact fixes):

1. **B-1** — class-level finder (`*rest` + keyword syntax) drops its WHERE.
   Already fixed in `src/ruby_runtime/call_interceptor.rb` AND in the mock's
   `extract_finder_where`. Blocks on: **corpus regeneration only**
   (people_show, 4 statements).
2. **B-3** — `ActsAsApi::Collection#as_api_response` note carry-through.
   Already fixed (2026-09-15) in `concolic_targets.rb`. Blocks on:
   **corpus regeneration only** (people_stream 2, posts_show 4 statements).
3. **B-4** — `Arel::Nodes::Casted#value` crash on Reshare relations
   (posts_show `collect_binds`, line ~247). **Not fixed** — one-line patch
   given in the doc (`node.val` vs `node.value`). Frozen for the live
   posts_show campaign (`concolic_targets.rb` pinned at `627bac2c1199…`);
   apply once that campaign can move off the pin, then regenerate.
   ~21 statements.
4. **B-5** — `ids` naming / `find_by_{3,6,9}_author_id` (posts_show, 4
   statements). Not independently traced this pass; likely closes with B-4 +
   regeneration — re-check first before spending more time.
5. **X1** — `SYM_PERSON_via_user` fixed mint name (people_stream, 19
   statements). **Not fixed**, Rule T (shared boundary, needs a corpus-wide
   naming ruling — see `_X1_PERSON_ID_FIX_20260910.md`). Fix shape: the mint
   needs to encode which `User` row `#person` was called on, not one fixed
   name for every row.
6. **Type mismatch** `posts.guid = posts0.id` (posts_show, 9 statements).
   **Not fixed**, Rule T. Not traced to an exact mint site this pass — next
   step is to find where a self-joined `posts` copy's `id` and the base
   copy's `guid` share a naming source in `concolic_targets.rb`.
7. `_SYM_POSTS_GUID` (people_show, 1 statement) — **not a defect** (a
   deliberate free symbolic leaf, no query behind it). Fix, if wanted, is
   extraction-side (treat it like a request param), not a mock change.
8. Loader `NullPointerException` (people_show, 1 statement) — **fixed** in
   `src/queries_from_runs/transform.py` this pass (`_drop_projection_of` now
   has a regression test); not a mock issue.

## Steps to get to 100% loadability

Per the classification above, of the 62 currently-unloadable statements
across people_show/people_stream/posts_show:

1. **Already-fixed-at-the-boundary, just needs re-driving** (B-1 + B-3 ≈ 10
   statements): regenerate people_show and people_stream against the current
   runtime/mocks. No code change needed. Do this first — it's free.
2. **B-4 fix + regenerate posts_show** (~21 statements, the largest single
   bucket): apply the one-line `collect_binds` patch in
   `_MOCK_NOTE_FIXES_20260916.md` §3 once the live posts_show campaign is
   willing to move off its pinned `concolic_targets.rb` commit, then
   regenerate. Re-check whether B-5's 4 statements (§4 above) clear at the
   same time before separately investigating them.
3. **X1 rename ruling** (19 statements, people_stream): needs a
   coordinated, corpus-wide decision (this is the same class of change as
   the X1 §7.1 rename that was previously refused) — not a unilateral code
   change. Bring to whoever owns `principal.binds` / Rule T decisions.
4. **`guid = id` naming fix ruling** (9 statements, posts_show): same Rule T
   shape as #3; needs its exact mint site traced first (not done yet — see
   `_MOCK_NOTE_FIXES_20260916.md` §6 for where to start looking).
5. `_SYM_POSTS_GUID` (1 statement) and the loader NPE (1 statement, already
   fixed): the two non-boundary residuals; see §7/§8 above.

**None of steps 2-4 are extraction bugs** — `queries_from_runs` is correctly
reporting "no producing SELECT recorded" / "these columns' types disagree"
from what the corpus actually contains. 100% loadability is not reachable by
further extraction-code changes on the CURRENT corpora; it needs
regeneration (steps 1-2) and two boundary-naming rulings (steps 3-4).

## Pruning-rule precision fix

See `results3/queries_from_runs/_PRUNE_DIAGNOSIS_20260916.md` — new
`--reliable-pruning-witnesses` flag (off by default) in
`src/queries_from_runs/{pcs,transform,dump}.py`, with a ground-truth
differential on both notifications_index and conversations_index. Not yet
run against the full corpora / not yet made the shipped default — that's the
natural next step once box capacity frees up from the posts_show campaign.
