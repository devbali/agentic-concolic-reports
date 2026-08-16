# posts batch — concolic re-run (prefix-directed DSE + batch-local targets)

Batch 1: `posts` / `reshares` / `status_messages`, driven through Rails' own
`ActionController::TestCase` rig against the real app.

Re-run **2026-08-15** with `run_dse.rb` + the batch-local overlay `targets.rb`,
superseding the 2026-08-14 round. `posts_show` additionally has the verified
reference runner `posts_show/run_proper.rb`. Coverage checked **per entrypoint**
over that entrypoint's own runs only.

- This batch's runners and overlay touch neither `src/`, the shared
  `concolic_targets.rb`, nor the app source. (One **authorised** `src/` fix was
  made separately on 2026-08-16 — the coverage-checker defect this batch
  exposed; see "The engine defect this exposed" below.)
- **28,248 dumps / 54,630 executions / 1941.6 s of exploration** (excluding
  JRuby+Rails boot and slot-queue waiting), plus 33 dumps in the separate
  anonymous tree
- **755,932 path conditions** — roughly 99 % of the whole experiment's recorded
  PCs come from this one batch

> **Provenance and status.** This batch's agent was **killed at 01:12 on
> 2026-08-15**, one message after `"reshares_create: 40000 runs, 26102 paths,
> 0 errors, capped (not drained). Now the coverage check on 26k dumps"`, when
> the coordinator session's pinned provider went away. The runs are complete and
> on disk; `reshares_create`'s coverage check never ran.
>
> **Update 2026-08-15 (later): it has now been run**, via assumption-based
> pruning rather than by loading 26,102 dumps — see "`reshares_create` — checked,
> by pruning" below. `coverage_summary.json` now exists for every entrypoint in
> the batch. Everything else below is a fresh re-measurement of the dumps
> (`reports/diaspora/batch_stats.py posts`).

## Results — BEFORE (2026-08-14) vs AFTER (this round)

| entrypoint | dumps | PCs | nodes | missing | complete | genuine | **both sides seen** | clean dumps | runs | drained |
|---|---|---|---|---|---|---|---|---|---|---|
| **`reshares_create`** | 1540 → **26102** | 20751 → **730685** | 1743 → **912** † | **0** † | **true** † | genuine | **24 / 24** | 1 → **26102 / 26102** | 5768 → **40000** | yes → **NO (cap)** |
| `posts_show` | 2113 | 25155 | 2112 | 0 | true | genuine | 24 / 24 | 1728 / 2113 | 14541 | yes |
| `posts_mentionable` | 7 | 21 | 6 | 0 | true | genuine | 6 / 6 | 7 / 7 | 22 | yes |
| `posts_destroy` | 7 | 21 | 6 | 0 | true | genuine | 4 / 4 | 3 / 7 | 19 | yes |
| `reshares_index` | 7 | 21 | 6 | 0 | true | genuine | 6 / 6 | 6 / 7 | 22 | yes |
| `status_messages_create` | 4 → **5** | 15 → **22** | 8 → **10** | 0 | true | genuine | 3 / 4 | **5 / 5** | 12 | yes |
| `posts_oembed` | 4 | 9 | 3 | 0 | true | genuine | 3 / 3 | 4 / 4 | 10 | yes |
| `status_messages_new` | 3 | 5 | 2 | 0 | true | genuine | 2 / 2 | 3 / 3 | 6 | yes |
| `status_messages_bookmarklet` | 1 | **0** | 0 | 0 | true* | **VACUOUS** | — | 1 / 1 | 1 | yes |
| **total** | 3686 → **28249** | 45998 → **755939** | — | **0** | 9/9 checked | **8 genuine, 1 vacuous** | **72 / 73** | **27859 / 28249** | **54633** | **8 / 9** |

(Totals cover the nine entrypoints; the 33 dumps of the anonymous tree are
counted separately below, as they were in the previous round's "3719".)

`*` complete only because the tree is empty.

`†` `reshares_create` is not checked over all 26,102 dumps — that is neither
possible in this machine's memory nor the right thing to check. Its row reports
the **assumption-pruned** check: **55 runs**, 912 nodes, 288 findings, all
untracked, **0 blocking**, in 25 s. Read it with its assumption set (serialised
into `coverage_summary.json`) — it is completeness over the action's *tracked*
decisions, not a claim that the exploration drained. Full account in
"`reshares_create` — checked, by pruning".

Between the two rounds only `reshares_create` changed; `status_messages_create`
changed again on 2026-08-16 when its `gsub` wall was closed. Every other
entrypoint reproduces its previous numbers exactly. `posts_show` again reproduces the
reference runner exactly: 14,541 executions → 2,113 distinct paths → 2,112 nodes
→ 0 missing.

### `complete=true` is the weakest number in that table

Per `COMPLETENESS_AUDIT.md`. **72 of 73 branch expressions are two-sided**,
measured from the dumps independently of the solver. The single one-sided
expression is `status_messages_create`'s
`(SYM_RESULT_Anonymous_diaspora_initialize_1_guid != StringVal(''))` at
`journey/formatter.rb:41` — a route-generation guard recorded only under the
`guid == ''` prefix, i.e. **UNSAT by construction**, the same shape as
`people_stream` in the audit. It is not a gap.

### Anonymous scenario (`anonymous_scenario/`, 33 dumps)

Kept in a **separate tree**, deliberately not merged into the entrypoint dirs —
see Finding 1. Unchanged this round.

| | dumps | PCs | nodes | missing | complete | both sides | clean | drained |
|---|---|---|---|---|---|---|---|---|
| `posts_show` | 26 | 179 | 25 | 0 | true | 9 / 9 | 8 / 26 | yes |
| `reshares_index` | 4 | 9 | 3 | 0 | true | 3 / 3 | 2 / 4 | yes |
| `posts_oembed` | 3 | 5 | 2 | 0 | true | 2 / 2 | 3 / 3 | yes |

## `reshares_create` — the headline result

**What changed.** The previous round had **1,539 of 1,540 dumps crashing** at
`NotImplementedError: SymbolicList#each`, in
`PostInteractionPresenter#as_api` (`post_interaction_presenter.rb:29`,
`collection.includes(author: :profile).map { … }`) via
`PostPresenter#with_interactions`. Exploration still reached 1,743 nodes because
the wall sat *after* the branch points — but everything downstream of the
presenter chain was unreachable.

With the overlay it runs to completion: **26,102 dumps, 730,685 PCs, 0 errors**,
and PCs per path roughly doubled (13.5 → 28). The gain is mostly **genuine
scalar branches (23 of 28 PCs), not length PCs** — the presenter chain now
actually executes. `social_actions.rb:56`'s `update!` executes in 303 dumps
where `SymbolicInt#next` previously raised.

**The exploration itself is still capped — that has not changed.** The worklist
did not drain:

```
runs_executed: 40000            stop_reason: "MAX_RUNS cap (40000) + STACK_LIMIT truncation"
distinct_paths: 26102           worklist_exhausted: false
stack_remaining: 200000         frontier_entries_dropped: 336652
elapsed_seconds: 1756.5         run_errors: {}
```

The frontier hit `STACK_LIMIT` (200,000) and 336,652 entries were dropped. Both
the cap and the truncation are **counted and reported** rather than silently
absorbed. By the audit's recommended criterion the **unpruned** search fails at
step 1 — it did not reach a fixpoint, and the pruned check below does not change
that. What that check establishes is narrower and stated exactly there: the
action's decision surface is **6 decisions**, and all six are covered both ways
under every prefix the assumption set still demands, using 55 of the 26,102
explored paths.

## `reshares_create` — checked, by pruning

Loading all 26,102 dumps is not the way to check this entrypoint, and it never
was. `CoverageChecker` holds every parsed `Run` plus the whole tree in memory —
398 MB of JSON took the earlier attempt to 1.6 GB RSS before it was killed. But
the size is an artifact of *what was explored*, not of the action's complexity.

**`ResharesController#create` has exactly one decision:**

```ruby
def create
  reshare = reshare_service.create(params[:root_guid])
rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid
  render plain: ..., status: 422          # <- the only branch of the action
else
  render json: PostPresenter.new(reshare, current_user).with_interactions
end
```

Everything after `else` is response serialisation.
`PostPresenter#non_directly_retrieved_attributes` and
`PostInteractionPresenter#as_json` are **hash literals** whose entries each read
a different association of the same already-fetched `@post` — `text`, `nsfw`,
`author`, `root`, `photos`, `mentioned_people`, `likes`, `reshares`, `comments`,
`participations`, … Strict-per-node demands the **Cartesian product** of those
sibling field-builders, and that is where 26,102 paths come from.

Measured over all 26,102 dumps by splitting each dump at its own first presenter
frame: **there are only 19 distinct action-zone path signatures.** Every one of
the other 26,083 dumps differs from one of those 19 *only in response
serialisation*.

`prune_reshares.py` declares each presenter-only branch expression
`UntrackedPathAssumption(expr=...)` and checks one run per distinct
**tracked-decision subsequence**:

| | before | after |
|---|---|---|
| dumps fed to the checker | 26,102 (OOM at 1.6 GB) | **49** |
| wall clock | killed | **7.5 s** |
| tracked action decisions | — | **6** |
| untracked presenter decisions | — | **18** |
| findings | — | 253 (**248 untracked, 5 blocking**) |

Assumptions are keyed by **expression, not source location**, because these path
conditions are recorded at the mock boundary *by design* — one shared
`finder_mock` serves every finder in the program, so all twelve finder decisions
here record at `concolic_targets.rb:331`. The expression names the decision; the
line names the mechanism.

### Why untracking the presenter is sound here

1. **Structural.** Those decisions are downstream of the action's only branch,
   in sibling entries of a hash literal, each reading a different association of
   the same `@post`. None can change whether the action returns 201 or 422 —
   that is settled before the presenter is constructed.
2. **Empirical.** All 24 branch expressions in this entrypoint are observed
   **both ways** across the 26,102-path corpus. Untracking excuses no unexplored
   branch; it removes only the demand for their cross-product.

`IndependenceAssumption` is the more natural tool for (1) and, since the
2026-08-16 engine change, is finally *expressible* here — keyed by `expr_a`/
`expr_b` it can relate two decisions that share a source line, which
`are_independent` used to reject outright. It is not used yet: independence is
the most dangerous assumption in the system, and untracking was sufficient.

### Closing the residual — and why the first attempt did not

Pruning on the tracked-decision subsequence is necessary but not sufficient. The
checker is **prefix-sensitive**: it demands a tracked decision under each
distinct prefix, and those prefixes run through *untracked* presenter decisions
too. Two dumps with the same tracked subsequence but different presenter
prefixes collapse to one representative, and the checker then asks for a prefix
whose representative was dropped. First attempt: 49 runs, **5 blocking**.

The five were **not** an unexplored gap — each was realised by **132 to 2,931 of
the 26,102 dumps.** So the run set is closed by iteration rather than guessed:
check, and for each blocking finding add a dump that actually realises it
(its prefix, then the missing side).

| round | runs | nodes | findings | blocking |
|---|---|---|---|---|
| 1 | 49 | 782 | 253 | 5 |
| 2 | 54 | 890 | 281 | 1 |
| 3 | **55** | **912** | **288** | **0** |

Every added run is a real explored path already in the corpus — nothing
fabricated, and no extra assumption introduced to absorb it. A finding no dump
realised would be a genuine gap in the capped exploration and would be reported
as such; that did not arise.

**Why `find_by_1` was the one that resisted.** It is tracked because it is
evaluated in the action zone in 7,845 dumps — and in the presenter zone in
18,256 others. Both are true: the interceptor names results with a **per-run
call ordinal**, so `find_by_1` is the action's `participate?` lookup in runs
where the action reaches one, and the presenter's first lookup where the action
short-circuits. The name is ambiguous across runs, so it is treated as tracked
everywhere — the conservative choice, and the reason the closure loop is needed.

**An earlier `complete=true` here was withdrawn and is now re-earned on a sound
basis.** The withdrawn version rewrote each PC's `PathSource` to a synthetic
action/presenter zone, which untracked the presenter *occurrences* of
`find_by_1` — excusing a tracked decision rather than covering it. It is now
covered.

### The engine defect this exposed — now FIXED

When this check was first run it reported `coverage_complete: false` even though
nothing about the action was uncovered. Of its 156 findings, the **126 from the
per-node pass honoured the assumptions (0 blocking)**, while the **30 from the
strict-per-node continuation pass** (`coverage.py:532-582`) all blocked — **and
all 30 were expressions explicitly declared untracked.** That pass appended its
`MissingCoverage` records without ever consulting `_is_untracked` /
`_is_side_untracked` and without setting `untracked=`, so its findings blocked
`complete` no matter what any assumption said.

That defeated the assumption system on any entrypoint producing continuation
findings — and is why `LOOP_ASSUMPTION_PROPOSAL.md` could truthfully say all 13
batches reached their completeness "under strict per-node with **zero**
assumptions": the assumption path had never been exercised.

**Fixed 2026-08-16 in `src/concolic_engine/coverage.py`** (authorised — `src/` is
otherwise raise-to-Bali). The continuation pass now consults the continuation
node's own source and reports exactly as the per-node pass does: a fully
untracked source is reported with `untracked=True` and does not block; the
untracked side of a `OneSideUntrackedPathAssumption` is skipped after Z3 has
run. Regression test:
`src/test_assumptions.py::test_continuation_pass_honours_untracked`, verified to
fail before the change and pass after.

That fix is verified and holds. It is **not**, however, what makes this
entrypoint complete — see the next section: with assumptions keyed by expression
rather than by a synthetic per-zone source, 5 findings still block, and that is
the honest result.

The fix cannot change any batch that declares no assumptions — `_is_untracked`
returns `False` for every source when the `AssumptionSet` is empty — and that
was verified rather than assumed: **all 113 zero-assumption entrypoints were
re-checked against their stored summaries and 0 differed.**

### What is still true about the exploration itself

The DSE run remains **capped, not drained** (`worklist_exhausted: false`,
`MAX_RUNS` 40,000 plus 336,652 dropped frontier entries), so criterion 1 of the
audit's completeness test is still unmet for the *unpruned* search, and the
pruning does not change that.

What the pruning does establish, stated exactly: the action's own decision
surface is **6 decisions**, its distinct tracked-decision subsequences number
**49**, and **all 24 branch expressions in the entrypoint — tracked and
untracked alike — are two-sided in the corpus.** What is *not* established is
both-sides coverage of `find_by_1_not_found` at every prefix, for the reason
given above. That is the whole of the residual.

Read `coverage_summary.json` here **with its assumption set** — serialised into
the file, each entry carrying the expression it names — never on its own.

## What is in `targets.rb`

The batch hit two walls, and **neither is fixable by mocking the enclosing app
method**:

- `as_api`'s body fires `Relation#records`, a declared target — mocking it would
  hide the symbolic query chain.
- `people_allowed_to_be_mentioned`'s body **is** the branch (`if public?`) — so
  mocking it is the exact regression the wall-fixing discipline forbids.

Both are fixed at the **mock boundary** instead, which is where
`src/ruby_runtime` says they belong. `list.rb`'s own header states the design:

> "Iteration (each/map/reject/select/find) STAYS unimplemented — iteration is
> handled by caller-wrapping at the mocked boundary, never executed against the
> list."

So `SymbolicList#each` raising is **not** a `src/` bug to patch; the missing
piece is the caller-side wrapper the design calls for, and a wrapper is exactly
what a batch-local target file is allowed to provide.

| # | target | shape | bought |
|---|---|---|---|
| 1 | `IterableSymbolicList < SymbolicList` | yields the representative once when `concrete_length != 0`, zero times when 0, recording the canonical `(len(X) != 0)` PC on entry with `taken = non-empty` | iterate-vs-skip becomes a genuinely flippable branch instead of a crash |
| 2 | the same mock re-declared on **`ActiveRecord::Associations::CollectionProxy`** | `CollectionProxy` has its **own** `records` (`collection_proxy.rb:1003`) which shadows `Relation#records` | this is why 259 dumps still died on `SymbolicList#each` in the first overlay attempt |
| 3 | `SuccIntValue < SymbolicInt` with `#next`/`#succ` | wired in by wrapping `ConcolicTargets.symbolic_instance` — the failing `count` is an integer **column**, not `Calculations#count` | `social_actions.rb:56`'s `update!` now executes |
| 4 | `Calculations#pluck` / `#ids` | replaces the shared `UNSUPPORTED` raise | `status_messages_create` past its `pluck` wall |
| 5 | `Mentionable.people_from_string`, `ActsAsApi::Collection#as_api_response` | they returned plain Arrays/symlists that got re-wrapped **without a representative** | the presenter chain completes |

The expression `IterableSymbolicList` records is **identical** to the one
`#empty?`/`#any?` already emit, so it path-signature-matches, and `len(X)` is
already a seedable key (the collection mock builds the length via
`seed_for("len(NAME)", …)`, `concolic_targets.rb:452`). `run_dse.rb`'s
`flip_seed` already understands `(len(NAME) != 0)`.

**Honest limits, restated because iteration makes them observable:** one
representative row is modelled, not N — a list seeded `len=3` still yields once,
and distinct-row branching is not modelled. A non-empty list with **no**
representative still raises loudly rather than silently yielding nothing; an
unmodelable iteration must stay a visible wall, not become a silent empty loop.

### `include Enumerable` was tried first and REJECTED

`Enumerable` sits between the subclass and `SymbolicList` in the ancestor chain,
so it also shadows the **tracked** API (`first`/`count`/`include?`/`any?`/
`none?`). The `streams` batch measured what that costs: all 8 of its entrypoints
went genuine → VACUOUS, 72 PCs → 0, **while `complete` stayed `true` for all 8**.
This overlay delegates explicitly instead. Any batch reusing an iterable-list
snippet on a list whose `any?`/`count`/`first` carries the branch will hit this;
the shadow set is exactly `{any?, count, first, include?, none?}` and `empty?`
is **not** in it.

## Finding 1 — `CoverageChecker` merges unrelated trees, order-dependently

**`src/concolic_engine/coverage.py`, `_insert_run`.** It reuses
`current.taken` / `current.not_taken` **without checking that the existing
child's `constraint` equals `next_pc.expr`**. Runs whose PC *sequences* diverge
in expression — not merely in polarity — are silently absorbed into whichever
tree shape was inserted first.

Measured on `posts_show`, and independently reproduced by the coordinator:

| insertion order | runs | nodes | complete |
|---|---|---|---|
| auth only | 2113 | 2112 | true |
| anon only | 26 | 25 | true |
| anon first (this is what filename sort gives) | 2139 | **25** | true |
| auth first | 2139 | **2112** | true |

The union is neither 25 nor 2112 (separate trees sum to 2137), and **both merge
orders report `complete=true`**. Because `dump_anon*` sorts before `dump_dse*`,
simply dropping both scenarios into one directory would report `complete=true`
over a tree that had silently swallowed 2113 runs.

**Consequence:** `tree_nodes` is only trustworthy for a homogeneous run set. A
cross-batch audit of all 104 entrypoints found 2 affected — `photos/photos_index`
(16 true nodes vs 9 reported, and a false `complete=true`) and
`oidc_federation_nodeinfo/webfinger` (9 vs 5, already reporting
`complete=false`). Every other entrypoint matched an order-free reconstruction
exactly. Raise to Bali. Not patched. This is why the anonymous runs live in
`anonymous_scenario/` rather than alongside the authenticated ones.

## Finding 2 — `status_messages_bookmarklet` is vacuous

1 dump, 0 path conditions. **Not covered**, regardless of `complete=true`. It is
genuinely branch-free rather than crash-before-PC: the action body
(`@aspects = current_user.aspects; gon.preloads[…] = {…}`) contains no
conditional, and `ActionController::Rendering#render` is a declared target, so
the view — where any branching would live — never executes.

## Finding 3 — the anonymous half was structurally unreachable

`PostService#find!` branches on a bare `if user`. That is a request property,
not a symbolic value: the runtime cannot record it and DSE cannot flip it. The
inherited harness always supplied a `current_user`, so the entire anonymous half
(`find_public!` → `post.public?` → `Diaspora::NonPublic`) could never be reached
in the previous round. Adding a `current_user = nil` scenario reaches it: the
`_public` PCs appear and 9 real `Diaspora::NonPublic` outcomes are recorded.
Run with `EPS=posts_show_anon,posts_oembed_anon,reshares_index_anon`.

## Every `error` in every dump

**27,857 of 28,248 dumps are clean** (was 1,756 of 3,686). 390 of the remaining
391 are **real app outcomes**; exactly one framework wall is left.

| error | dumps | where | classification |
|---|---|---|---|
| `ActiveRecord::RecordNotFound` | 385 (`posts_show`), 1 (`posts_destroy`), 1 (`reshares_index`) | the 404 raise at `post_service.rb:60`. In `posts_show` it is reached *from inside the presenter*: `PostPresenter#with_initial_interactions` → `ReshareService#find_for_post` → `PostService#find!` | real app outcome |
| `Diaspora::NotMine` | 3 (`posts_destroy`) | the 403 path at `post_service.rb:32` (`post.author == user.person` false) | real app outcome |
| ~~`NotImplementedError: SymbolicString#gsub`~~ | 1 → **0** | `string.rb:355` ← `mentionable.rb:62 filter_people` | **CLOSED 2026-08-16** — see below |
| — | — | (anonymous tree: `Diaspora::NonPublic` ×9 + `RecordNotFound` ×9 in `posts_show`, ×1 + ×1 in `reshares_index`) | real app outcomes |

Walls present in the previous round and now **gone**:

| gone wall | count before | how |
|---|---|---|
| `NotImplementedError: SymbolicList#each` | 1539 (`reshares_create`) | overlay §1 + §2 (the `CollectionProxy#records` shadow was the non-obvious half) |
| `NotImplementedError: Calculations#pluck` | 1 (`status_messages_create`) | overlay §4 |

### The last wall, closed 2026-08-16

`Diaspora::Mentionable.filter_people` does `msg_text.to_s.gsub(REGEX) {…}`.
**`filter_people` cannot be mocked** — its body calls `people_from_string`,
itself a declared target (§5), so mocking it would hide that symbolic query
chain, which is the README's invariant. `filter_mentions` is worse: its body
*is* the branch (`return if people_allowed_to_be_mentioned == :all`).

So the VALUE is fixed instead, with a batch-local `SubstitutableSymbolicString`
under the same exactness discipline as `search_links_reports_profiles` §3:
`REGEX` is the mention syntax, and when the witness contains no mention,
`gsub(REGEX)` **provably returns an equal string** — so it returns `self`,
preserving `sym_name`, note and the whole constraint history. When the witness
does match, it raises, exactly as it does today. **Strictly no worse than the
status quo: it can only turn a crash into a faithful no-op.**

Wired in by extending the existing `symbolic_instance` wrapper (`upgrade_text!`
alongside `upgrade_ints!`), mutating the same `attrs` Hash the column readers
close over — **no new singleton reader**, because re-installing one shadows app
readers that take an argument (the photos batch measured that at 46 broken
dumps). Deliberately narrowed to the `text` column, the only string this batch
substitutes over.

Result: **4 → 5 dumps, 15 → 22 PCs, 8 → 10 nodes, 3/4 → 5/5 clean, 0 errors.**

**The earlier `pluck` fix had moved the wall exactly one frame deeper, as the
round before predicted** ("Caveat: `Mentionable.filter_people` would then iterate the list —
likely the next wall"). It is now `SymbolicString#gsub` inside
`filter_people`. Reported, not mocked: `filter_people`'s body is the substitution
itself, so a mock there would replace app logic rather than a boundary.

## Other branches the runtime cannot record

- `post = post.absolute_root if post.is_a? Reshare` in `ReshareService#create` —
  the mock allocates the *real* class, so `is_a?` is a concrete class check and
  the branch is invisible to the engine.
- `render` is a declared target, so views and presenters never execute.
  `posts#mentionable`'s
  `Person.allowed_to_be_mentioned_in_a_comment_to(...).limit(15)` relation is
  built but never materialized; `posts#oembed`'s `OEmbedPresenter` is
  constructed but not rendered.
- `posts#oembed`'s blanket `rescue; head :not_found` swallows every downstream
  exception, so its tree is only the finder chain — 3 nodes is the real ceiling
  for this harness, not an artifact.

## Harness decisions (not app modeling)

- `format: :json` for `posts#mentionable` and `status_messages#create`. Their
  `respond_to` blocks have no HTML branch, so under the default `:html` format
  `mentionable` returned 406 via `format.any { head :not_acceptable }` before
  touching a symbolic value — **that alone is why it reported 0 PCs two rounds
  ago**; it now yields 7 paths / 6 nodes.
- Flip helper extended to `(VAR != LITERAL)` and Z3-rendered literals
  (`StringVal('')`), which removed the last unflippable PC. `unflippable_pcs` is
  empty for every entrypoint in this batch, including the capped one.

## `src/` gaps to raise to Bali (worked around batch-locally, NOT patched)

1. ~~**The strict-per-node continuation pass ignores every assumption.**~~
   **FIXED 2026-08-16** (authorised change to `src/concolic_engine/coverage.py`).
   `coverage.py:532-582` appended its `MissingCoverage` records without
   consulting `_is_untracked` / `_is_side_untracked` and without setting
   `untracked=`, so those findings blocked `complete` whatever the assumption
   set said. Measured on `reshares_create` before the fix: 126/126 per-node
   findings honoured the assumptions, while **30/30 continuation findings
   blocked — and all 30 were expressions explicitly declared untracked.** The
   pass now consults the continuation node's own source and reports exactly as
   the per-node pass does. Regression test
   `test_assumptions.py::test_continuation_pass_honours_untracked`; all 94
   engine tests pass and all 113 zero-assumption entrypoints re-check
   identically.
2. ~~**Assumptions cannot address decisions that share a source line.**~~
   **FIXED 2026-08-16** — assumptions can now be keyed by branch **expression**
   (`UntrackedPathAssumption(expr=...)`, `IndependenceAssumption(expr_a=...,
   expr_b=...)`), which is what names a decision when the source is a shared
   mock boundary.

   The earlier diagnosis here — "`caller_frame` returns the mock, not the app
   call site; add `concolic_targets.rb` to `SKIP_FILES`" — **was wrong and is
   withdrawn.** Recording a path condition inside a mock is *intended design*,
   not misattribution: a target standing in for an external boundary decides
   found/not-found with an explicit symbolic compare and returns a concrete
   value, because the app's own `rescue RecordNotFound` / bare `if row` is not
   interceptable. `caller_frame` reporting the mock is therefore correct — that
   is genuinely where the PC is created. Measured: **63.7% of this experiment's
   path conditions are recorded in mocks, 34.7% in framework internals, 1.7% at
   a line of app source**, and 129 of 146 distinct branch expressions (88%) sit
   at a source shared with at least one other expression.

   `SKIP_FILES` would also have made it *worse*, measured: walking up to the app
   frame maps `find_by_1/3/5/7` all to `post.rb:143 like_for` and
   `find_by_2/4/6/8` to `post.rb:138 reshare_for` — 4 distinct decisions per
   key, twice. Expression keys give one key per decision instead. See
   "Identifying a path condition" in `src/concolic_engine/assumptions.py` and
   the boundary-decided section of `src/TODO.txt`.
3. **`CoverageChecker` cannot be run on a 26k-dump entrypoint** — it holds every
   parsed `Run` and the full tree in memory (398 MB of dumps → >1.6 GB RSS). A
   streaming or incremental tree build is needed, or large entrypoints are
   permanently uncheckable without pruning.
4. **`coverage.py::_insert_run` merges unrelated trees order-dependently**
   (Finding 1) and reports `complete=true` both ways.
5. `SymbolicList#each`/`#map` raise even when a `representative:` is present,
   although `#first`/`#last`/`#[0]` honour it — and `CollectionProxy` shadows
   `Relation#records`, so any fix must cover both.
6. `SymbolicInt` has no `#next`/`#succ`; `SymbolicString` has no `#gsub`.
7. `Calculations#pluck` was declared `UNSUPPORTED` (`concolic_targets.rb:469`).
8. **`CallInterceptor#run` leaks.** It appends every `TargetCall` (with its full
   PC snapshot) to `@all_calls` and never trims — it only slices
   `@all_calls[old_count..]`. Over 14.5k executions this dominates the heap; the
   first `posts_show` re-run reached ~1.8 GB RSS and was OOM-killed. `run_dse.rb`
   clears it per run (behaviour-preserving — `old_count` recomputes from the
   empty array).
9. Engine: `len(X)` constraints unparseable; `coverage.py` treats them as UNSAT
   while leaving `solver_lost` at 0.

## Runner-local (deliberately not in the overlay)

- `@all_calls` cleared per run (gap 6 above).
- Frontier stored as `(parent_id, one-flip)` against a parent table; dedup sets
  keyed by 16-char digests rather than retained JSON/expression strings — without
  this, `reshares_create`'s 40k executions do not fit in memory at all.

## Incident (2026-08-14, previous round)

The agent of that round ran `pkill -f "run_dse.rb"` intending to stop only its
own runner. Every batch names its runner `run_dse.rb`, so it very likely killed
in-flight runs for `comments`, `conversations`, and `users_sessions`. Reported to
the coordinator at the time; those batches were told to re-run rather than trust
dumps written in that window. All later kills were scoped to explicit PIDs.

## Files

```
results/posts/
├── targets.rb                     BATCH-LOCAL overlay (PostsTargets.install!)
├── run_dse.rb                     prefix-directed DSE runner (all 9 entrypoints)
├── run_concolic.rb                previous runner, kept as harness reference
├── run_phase4.rb / run_phase5.rb  previous seed passes, superseded
├── elapsed_seconds.txt            per-entrypoint exploration wall time
├── <entrypoint>/
│   ├── dump_*.json                one per distinct path
│   ├── exploration_summary.json   runs / paths / drained / unflippable / errors
│   └── coverage_summary.json      engine result for THIS entrypoint only
│                                  (absent for reshares_create — see above)
├── posts_show/run_proper.rb       verified reference runner (memory-hungry variant)
└── anonymous_scenario/            current_user = nil runs, kept separate per Finding 1
```

Reproduce:

```
scripts/diaspora-concolic /home/dev/project/reports/diaspora/results/posts/run_dse.rb
PYTHONPATH=src python3 reports/diaspora/batch_stats.py posts
```

`MAX_RUNS` (default 1500; this round used 40000 for `reshares_create`),
`TIME_BUDGET`, `STACK_LIMIT` (200000), `EPS`.
