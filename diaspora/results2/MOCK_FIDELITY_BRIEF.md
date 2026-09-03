# MOCK_FIDELITY campaign — every mock a clean leaf, every note real SQL

Read `README.md` §THE DISCIPLINE first. This campaign enforces it across
the whole results2 mock surface, in two phases. Ground rules are unchanged:
`src/`, the diaspora app source are read-only; each endpoint's private
`concolic_targets.rb` and `targets.rb` are write-freely; concolic-slot for
every run; one JRuby at a time; check `free -h` (wait below 1.2Gi); no
monitor-and-stop — synchronous execution; return reports as text.

## Phase A — note fidelity (the query ran; the note lied)

Upgrade every mock that stands in for a query to render the real SQL with
`$$()` binds into its `note`, exactly as the finder/relation mocks already
do (`sql_for` is the reference implementation):

1. `ActiveRecord::Associations::SingularAssociation#find_target`
   (belongs_to / has_one): derive table + FK from
   `association.reflection`; note =
   `SELECT "<target_table>".* FROM "<target_table>" WHERE "<target_table>"."<pk>" = $$(<owner fk sym or concrete>)`.
   The returned symbolic instance is unchanged.
2. Collection association loads (`CollectionProxy` reads): the scoped
   `SELECT <table>.* WHERE <fk> = $$(owner id)` note.
3. Class-level dynamic finders (`find_by_username` and friends, the
   `"X query (class-level finder)"` fallback in `sql_for`): render the real
   WHERE from the matcher's attribute + argument.
4. Audit for any other mock returning query results with a non-SQL note
   (e.g. `Post.blocked_people`, `find_by_sql` paths) and fix the note.

Acceptance per endpoint: regenerated dumps contain zero SELECT-shaped
mocks with junk notes where the underlying operation is a query; spot-quote
the new notes.

## Phase B — the leaf audit (no mock may cover a target)

For EVERY `declare_target`/prepend in the shared per-dir
`concolic_targets.rb` copy and each batch `targets.rb`:

1. Read the mocked function's REAL body (app/gem source). Classify:
   - **CLEAN LEAF**: no SQL, no other target calls → keep (note-fidelity
     rules from Phase A still apply if it stands in for a query).
   - **VIOLATION**: body reaches SQL or another target (render /
     render_to_string, `as_api_response`, `decorated_stream_posts`,
     `attach_user_likes`, `mark_user_notifications`,
     `publisher_prefill`, `build_mentioned_people_json`, … — audit ALL,
     don't assume this list is exhaustive).
2. For each violation, DESCEND: remove/narrow the mock so the real body
   executes, then close the resulting walls at genuine leaves using the
   established toolbox (SymbolicString identity shims, boundary-decision
   symbools with `true`/`nil` returns, `ConcolicDate`,
   `IterableSymbolicList` representative iteration, `to_param`/`to_i`
   leaf shims for URL/pagination helpers). Splitting (extract the SQL-free
   leaf, mock only that) is the move when a unit mixes plumbing with
   targets. Expect the HTML render pipeline and the ActsAsApi serializer
   to be the deep descents; per-row queries firing once via the
   representative element is correct for query-shape capture.
3. Bare-truthiness branches encountered in newly-executing code are
   non-fatal but untracked — record them in the report (documented
   soundness note), do not fabricate PCs for them.
4. Where a violation's body is GENUINELY unreachable for an endpoint
   (verified against dumps), removing the mock is still preferred over
   keeping a dead violation; document either way.

## After the descent (per endpoint)

Regenerate the corpus → the PC universe will GROW (view/serializer
branches). Re-run the completion loop per COMPLETION_BRIEF.md (tiered,
code-cited assumptions; cap-4 checker; targeted residual runs; honest stop
if blocked). Update `coverage_assumptions.py` — new exprs need arguments;
old ones must be re-verified. Then the coordinator re-extracts
`queries_from_runs` and re-diffs against the reference; the diff residual
is the campaign's success metric.

## Order

Phase A first (cheap, independent), then Phase B audit (produces the
violation ledger), then per-endpoint descents biggest-reference-gap first:
notifications_index (71-query reference), people_stream (168), comments_index,
people_show, conversations_index, posts_show.
