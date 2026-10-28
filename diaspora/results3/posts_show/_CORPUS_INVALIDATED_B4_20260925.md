# posts_show corpus is INVALID for note-bearing evidence (B-4), 2026-09-25

**Do not run the assumption gate or the completion checker against this
corpus again until it has been re-driven.** `concolic_targets.rb` was
repaired today; the 206,593 dumps in `_snapshot_pruned_P44FRESH2.txt` were
not, and the two now disagree about what a target-call SHAPE is.

## What was wrong

`concolic_targets.rb` in THIS directory was the last copy in the tree still
carrying boundary gap **B-4 / bug-2b** (`docs/BOUNDARY_NOTE_GAPS_20260915.md`
:245-252). Two halves were missing:

* `render_relation_sql` used `Arel::Visitors::ToSql` instead of
  `ConcolicSymbolicToSql` — the class was absent from this file entirely.
* `collect_binds` did `out << node.value` for `Arel::Nodes::Casted`; arel-9
  exposes `#val`, not `#value`.

Every STI relation builds a `Casted` (`type IN ('Reshare')` via
`type_condition` -> `Attribute#in` -> `build_quoted`), so every Reshare query
raised `NoMethodError` inside note rendering, and `sql_for`'s rescue stored
the **exception text** as the note:

    Reshare query (render_relation_sql failed: NoMethodErrorundefined
    method `value' for #<Arel::Nod), args=arg=nil,
    args={:author_id=><SymInt SYM_PERSON_PO_id = 1>}

## Measured blast radius on the frozen corpus

* **96.6 %** of dumps (2898 / 3000 sampled, seed 7) carry at least one
  degraded note.
* 3 distinct degraded note strings stand in for 3 distinct real statements
  (`concrete_run.json`): `posts.root_guid = ?`, `... LIMIT ?`, and
  `... AND posts.author_id = ? LIMIT ?`. The mapping is not 1:1 — the
  degraded string is keyed on the Ruby args hash, not the SQL.
* `concolic_engine/assumptions.py::call_shape` wildcards `$$()` binds and
  `'...'` literals. It does **not** wildcard `<SymInt NAME = 1>`, so the
  degraded shape carries a CONCRETE BIND VALUE. Shapes are therefore both
  conflated (different SQL -> same string) and value-sensitive (same SQL ->
  different strings across base/flip arms). `call_shape` is the currency of
  BOTH the engine's per-decision footprint (`coverage.py::infer_footprints`)
  and the gate's access trace
  (`assumption_checker.py::access_trace`).
* In `coverage_summary.json` (run REAL10, 2026-09-24): **451 of the 460**
  ConfinementAssumption FAILs name this degraded shape as the deciding shape
  (379 as the `(viii)` interaction shape, 72 in the `(i)`/`(ii)`
  outside-footprint lists). Only 9 do not.
* `note_check` / `note_fidelity` RED includes the two Reshare shapes with
  "NO corpus note anywhere" — same cause.

## Proof the repair works

Isolated differential under `_p45_b4_fix/` (private copies of `run_dse.rb`,
`targets.rb`, `concolic_targets.rb`; `VARIANTS=auth_html MAX_RUNS=2`).
With the back-port applied the same call now records:

    ActiveRecord::FinderMethods.find_by ::
    SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('Reshare')
      AND "posts"."root_guid" = $$(SYM_RESULT_ActiveRecord__Relation_evilq_act_vis_1_guid)

i.e. exactly the statement `mock_note_check` reported as having no corpus
note. Control copy under `_p45_b4_ctl/`.

## Exposure is posts_show-only

`results3/people_stream/concolic_targets.rb` is also UNFIXED, but its
endpoint drives no STI relation: 0 / 600 sampled people_stream dumps carry a
degraded note (comments_index 0/600, conversations_index 0/600). No
previously-closed endpoint's verdict is affected.

## What was changed here

`concolic_targets.rb` only; original kept as
`concolic_targets.rb.bak_pre_b4_20260925`. The change is a back-port of code
that already exists in `reports/diaspora/concolic_targets.rb` and in all five
other endpoint copies — it moves this batch ONTO the shared boundary, it does
not move the boundary.

## Still outstanding (NOT fixed here)

See the session report. In short: B-5 (`Calculations#ids` projection — the
canonical fix renames the list variable, which crosses the name boundary and
must not be applied blind), B-2 (`user.person` stubbed by a singleton method
in `run_dse.rb:104-109`, so `people.owner_id` is never minted), the
`update_all` note rendering as a SELECT (no fix exists anywhere), `pluck`
suppressed by the `_descend` deny-list (`concolic_targets.rb:475-482`), and
the empty-list representative escape at `targets.rb:828`.
