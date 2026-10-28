# Mock/boundary changes needed to fix SQL notes — 2026-09-16

Written while diagnosing the 62 unloadable statements in the shipped
`*_pcfold2.sql` policies (see `_ARMS_DIFFERENTIAL_20260916.md` and
`_LOADABILITY_PCFOLD2_20260916.log`). This is a HANDOFF document for whoever
owns each endpoint's mocks / the shared runtime — **nothing here was edited
by this pass**: `src/` changes are limited to the pruning-rule fix (see
`_PRUNE_DIAGNOSIS_20260916.md`), and every file named below is either Rule-T
territory (`concolic_targets.rb`) or `results3/posts_show/` (a live campaign's
frozen copy) — both off limits to this pass.

Every one of the 62 unloadable statements is an unresolved `_SYM_RESULT_…`
placeholder or a type-mismatched join. None is an extraction bug: extraction
correctly reports "no producing SELECT for this bind" or "these two columns'
schema types disagree" from what the corpus actually recorded. The fix, where
one exists, is upstream of extraction — in the mock that renders a
`symbolic_call` event's `note:`, or in a symbol's name at its mint site.

## Summary table

| class | statements affected | mock status | what closes it |
|---|---|---|---|
| B-1: `*rest`-signature finder called with keyword syntax | people_show 4 (`find_by_1/2/3/4`) | **already fixed**, both layers | corpus regeneration only |
| B-3: `ActsAsApi::Collection#as_api_response` note carry-through | people_stream 2, posts_show 4 | **already fixed** (2026-09-15) | corpus regeneration only |
| B-4: `Arel::Nodes::Casted#value` crash (Reshare relations) | posts_show ~21 | **not fixed** — exact line identified below | one-line mock fix, **frozen for the live campaign**; then regeneration |
| B-5 / naming: `ids` result var, `find_by_{3,6,9}_author_id` | posts_show 4 | not traced this pass | needs the boundary owner (same family as B-4's corpus; likely clears with B-4 + regeneration) |
| X1: `SYM_PERSON_via_user` fixed mint name | people_stream 19 | **not fixed**, Rule T | rename at the mint site (below); needs a corpus-wide ruling (same class as the refused X1 §7.1 rename) |
| type-mismatch: `posts.guid = posts0.id` | posts_show 9 | **not fixed**, Rule T | a symbol-naming collision at the boundary; not traced to an exact call site this pass |
| `_SYM_POSTS_GUID` | people_show 1 | **not a defect** | extraction-side: treat as a param-like leaf (see below) |
| checker NPE (`Integer.intValue()` on null) | people_show 1 | n/a — loader bug, not ours | already isolated as a `checker-NPE` class; not an extraction or mock defect |

## 1. B-1 — class-level finder called with `*rest` + keyword syntax (FIXED, needs regeneration)

**Symptom**: `SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1` (and
`_2`/`_3`/`_4` on people_show) carries the note:

```
Like query (class-level finder; WHERE unavailable -- interceptor drops
kwargs for *rest-signature finder methods called with keyword syntax, see
call_interceptor.rb param binding), args=args=nil LIMIT 1
```

`args=nil` means `class_finder_sql`'s `extract_finder_where` (people_show's
`concolic_targets.rb:220-248`) found no usable Hash to build a `WHERE` from.

**Root cause, already fixed**: `Model.find_by(col: val)` dispatches to a
method declared `def find_by(*rest)`; the interceptor's wrapper must declare
`**kwargs` (to forward keywords to targets that *do* take them), so Ruby
routes the caller's keyword hash into `kwargs` instead of `rest`, and the
param-binding loop — which only reads `kwargs[<named param>]` — never sees
it. `src/ruby_runtime/call_interceptor.rb:131-158` (dated 2026-09-15, "gap
B-1") already restores the hash into the `*rest` parameter's slot, additively
(only fills a slot that's otherwise nil).

**The mock is already correct for this fix**: `extract_finder_where`
(`concolic_targets.rb:237-248`) already looks for a nested non-empty Hash in
`args` and builds the condition from it — once the interceptor populates the
`rest` slot, this code renders a real `SELECT ... WHERE "col" = $$(SYM)`
without any further mock change.

**Why the shipped corpus still shows the bug**: every people_show dump on
disk was captured *before* the interceptor fix landed. Re-driving people_show
is out of scope here (not requested, and the box is running posts_show's
live campaign) — regenerating people_show's corpus against the current
`call_interceptor.rb` should make these 4 statements resolve to real joins
with **no further code change**. Confirm by diffing extraction output on a
small fresh sample before committing to a full re-drive.

## 2. B-3 — `ActsAsApi::Collection#as_api_response` (FIXED, needs regeneration)

**Symptom**: `SYM_RESULT_ActsAsApi__Collection_as_api_response_{1,2}_row_id`
(people_stream) and `_{1,2,3,4}_row_id` (posts_show) are unresolved — the
serializer's mock minted a representative row with a prose note
(`"ActsAsApi::Collection#as_api_response"`), not a SELECT, so nothing can
join back to it.

**Already fixed**: `people_stream/concolic_targets.rb:1410-1456` ("Boundary
gap B-3 ... repaired 2026-09-15") now carries the SOURCE relation's own
rendered SQL (or the row's own `#concolic_note`) through into the
representative row's note, additively — anything that isn't a SELECT still
falls back byte-identically to the old prose, so no existing note shape can
regress.

**Why it still shows up**: same as B-1 — the shipped corpus predates the fix.
Regeneration only.

## 3. B-4 — `Arel::Nodes::Casted#value` crash on Reshare relations (NOT FIXED)

**Symptom** (posts_show, ~21 of its 35 unloadable statements —
`records_2_row_{root_guid,id,author_id}` and downstream `find_by_{3,6,9}`):
every `Reshare` relation's note is captured-exception TEXT instead of SQL —
8,503,439 occurrences corpus-wide (see `_COMPLETION_20260910.md` §115,
already measured; not re-derived here).

**Exact site, confirmed this pass**: `posts_show/concolic_targets.rb:242-260`,
`collect_binds`:

```ruby
if defined?(Arel::Nodes::Casted) && node.is_a?(Arel::Nodes::Casted)
  out << node.value          # <-- raises under this Arel version
  return
end
```

This raises inside `render_relation_sql` (line ~226-236), which propagates up
into `sql_for`'s `rescue Exception => e` (line 163) — the OUTER guard that
exists precisely so a note-rendering crash can't wall the mock — and THAT
rescue's fallback string becomes the note:
`"#{klass} query (render_relation_sql failed: #{e.class}#{e.message[0,40]}), args=..."`.
(§115 found the note is closer to bare exception prose than this fallback
format in the corpus; either this call site or a second, similarly-shaped one
for the same class needs re-confirming against a live trace, but the
mechanism — `Arel::Nodes::Casted` has no `#value` reader in this Arel version
— is the one to fix either way.)

**Fix** (one line, additive, matches this file's own "wall-fixing
discipline" pattern used elsewhere for version-shape differences):

```ruby
if defined?(Arel::Nodes::Casted) && node.is_a?(Arel::Nodes::Casted)
  out << (node.respond_to?(:val) ? node.val : node.value)
  return
end
```

(`Arel::Nodes::Casted` carries its bound value under `val` in the Arel
version this app pins; `value` is kept as a fallback for any Arel version
where that reader does exist, so the change is additive.)

**Why this pass does not apply it**: `results3/posts_show/concolic_targets.rb`
is a live campaign's file, explicitly held at a pinned commit
(`627bac2c1199…` per the 2026-09-15 handoff) so its coverage numbers stay
comparable across the campaign. This is a one-line, low-risk, well-evidenced
fix — apply it, then regenerate, once the live campaign is willing to move
off that pin.

## 4. B-5 / `ids` naming, `find_by_{3,6,9}_author_id` (posts_show, not traced)

Grouped with B-4 in the coordinator's classification as part of the same
"already fixed at source, corpus predates it" family. This pass did not
independently trace `SYM_RESULT_ActiveRecord__Calculations_ids_1_ids` or the
`find_by_{3,6,9}_author_id` binds to a specific mock line — they may already
be closed by the B-4 fix above (the `find_by` calls in question look up rows
by an id read off a Reshare association) plus regeneration. Re-check after
B-4 is applied and the corpus regenerated before spending more time here.

## 5. X1 — `SYM_PERSON_via_user` fixed mint name (people_stream, not fixed, Rule T)

**Symptom**: 19 of people_stream's 21 unloadable statements carry
`_SYM_PERSON_via_user_id` as an unresolved placeholder.

**Root cause** (fully diagnosed in
`_X1_PERSON_ID_FIX_20260910.md` — not re-derived here): a module
`UserSymPersonAssociation`, `prepend`-ed onto the `User` class, mints
`symbolic_instance(Person, "SYM_PERSON_via_user", …)` for `user.person` — ONE
FIXED NAME regardless of which concrete `User` row `#person` was called on.
Extraction cannot recover which producing query (`User.find_by_username(...)`
in this case — the VIEWED person, not the principal) that name stands for,
because the dump carries no link from the mint back to it.

**Fix shape**: the mint needs to carry the calling User row's own identity
into the name (e.g. include that row's own symbolic id or a per-call
discriminator in the `SYM_PERSON_via_user...` name, mirroring how every other
producer name already encodes its call site) so extraction's existing
longest-name-first producer lookup (`pcs._suffix_candidates`,
`_Build._bind_value`) can resolve it exactly like any other `SYM_RESULT_*`
producer — no extraction-side change would be needed once the name itself is
disambiguated.

**Why this pass does not do it**: this is Rule T (a shared-boundary mint
name is part of the contract `principal.binds.non_principal_identity_name`
depends on; changing it without coordinating `app.json` and every consumer
of the old name is exactly the class of change `_EXTRACTION_OPEN_ISSUES.md`'s
X1 write-up says is "DECLARED OPEN, not shipped as access control" pending
that coordination.

## 6. `posts.guid = posts0.id` — type-mismatched join (posts_show, not fixed, Rule T)

**Symptom**: 9 posts_show statements compare a `guid` (string) column against
an `id` (int) column of a self-joined `posts` copy — rejected by the loader's
solver-type probe (`Sorts CS!STRING and CS!INT are incompatible`).

Per the coordinator's classification (not independently re-traced to an
exact mint site this pass, given time spent on B-4/X1 above): this is a
**symbol-naming defect**, not a note-rendering one — a value that stands for
one column's contents ends up compared, via a shared symbol name, against a
different column. Memory also names this "the unfixed prefix-relative
var-naming bug." Fixing it means renaming a symbol at the boundary, and that
name very likely appears inside OTHER statements' already-recorded notes too
— the same non-additive-safe shape as the X1 rename above, i.e. blocked on a
corpus-wide ruling rather than on unwritten code. **Action for the next pass
with capacity**: grep `results3/posts_show/concolic_targets.rb` for wherever
a `posts` self-join's second copy's `id` and the base copy's `guid` are
minted from the same source variable or a shared naming helper, and confirm
whether the fix is a one-line disambiguation or genuinely needs the
`author_id`/`root_guid` chain renamed corpus-wide.

## 7. `_SYM_POSTS_GUID` (people_show, not a defect)

Traced this pass to `people_show/concolic_targets.rb:1814`
(`Diaspora::MessageRenderer` mock): a guid parsed out of post/bio text via
`DIASPORA_URL_REGEX`, deliberately minted as a free symbolic string
(`symstr("SYM_POSTS_GUID", ...)`) with the comment "pass the guid as a SymStr
so the finder mock renders a `$$` bind." There is no producing query behind
it by design — it is an app-level input, structurally identical to a request
parameter. **No mock change is needed.** The fix, if any, belongs on the
extraction side: teach `queries_from_runs` to treat a symbolic var whose
`note` is plain prose (not a SELECT) and whose name does not match any
`SYM_RESULT_*` producer as a widened, param-like leaf — the same treatment
`is_param_bind` already gives `principal.binds.request_param` — rather than
an honest-but-permanent placeholder. Out of scope for this pass (it is one
statement, and changing the placeholder-vs-widen boundary needs its own
differential); flagged here for whoever picks up extraction-side gaps next.

## 8. Loader `NullPointerException` (people_show #22, not a mock defect)

Traced and **fixed** in `src/queries_from_runs/transform.py` this pass — see
`_PRUNE_DIAGNOSIS_20260916.md` §"the loadability NPE fix." Not a mock issue:
the emitted SQL itself referenced a table (`share_visibilities`) it no longer
joined, because the outer-join-split rewrite dropped that table from one arm
without dropping the aggregate-as-rows rewrite's SELECT-list column for it.
`_drop_projection_of` now prunes the arm's own projection to match; a
regression test (`test_outer_join_split_drops_its_own_column_from_the_projection`)
pins it. Confirmed absent from a fresh people_show extraction (see the main
report for the before/after loadability numbers).
