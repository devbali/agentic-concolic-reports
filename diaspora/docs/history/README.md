# results3 — discipline-clean mock surface (no mock may cover SQL potential)

Third generation. results2 fixed *symbolic arguments* and *coverage
semantics*; results3 fixes the **mock surface** so the recorded SQL is the
whole SQL. Governing law: main `../README.md` §THE DISCIPLINE. The two
concrete upgrades over results2:

- **(a) Note fidelity** — every mock that stands in for a query renders the
  real SQL (with `$$()` binds) into its `note`: finder/relation mocks
  (already did), association loads (`SingularAssociation#find_target`,
  collection loads — table/FK from the reflection), class-level dynamic
  finders, and any other query-result-returning mock.
- **(b) No mock over SQL potential** — nothing whose real body issues SQL
  or calls another target may be mocked. The historical shared-layer
  no-ops (render / `render_to_string`, `ActsAsApi as_api_response`,
  presenter subtree mocks like `decorated_stream_posts`,
  `attach_user_likes`, `mark_user_notifications`, …) are REMOVED and their
  subtrees EXECUTE; the walls that made those no-ops attractive get closed
  at genuine SQL-free leaves instead (identity shims, boundary decisions
  with `true`/`nil`, `ConcolicDate`, `IterableSymbolicList` representative
  iteration, `to_param`/`to_i` leaf shims). Per-row queries firing once via
  the representative element is correct query-shape capture. Bare-truthiness
  branches in newly-executing code are non-fatal but untracked — reported,
  not fabricated.

## Layout — one self-contained dir per entrypoint (results2 conventions)

```
results3/<entrypoint>/
├── concolic_targets.rb   ← rebuilt from results2's copy: SQL-boundary family
│                            kept (with (a) upgrades); every violation of the
│                            discipline removed or descended. Document each
│                            removal/descent in the file header.
├── targets.rb            ← batch-local leaf shims for the descent walls
├── run_dse.rb            ← ported from results2 (param registration in-body,
│                            prefix-directed DSE, StringVal unwrap, probes)
├── coverage_report.py    ← cap-4 era, assumptions loader, SYM_LEN rename
├── coverage_assumptions.py, dump_*.json, exploration_summary.json,
├── coverage_summary.json ← combination-coverage bar unchanged: complete=true
│                            earned (truncated=false, solver_lost=0,
│                            unevaluable=[]) or an honest stop
└── (REPORT content returned as text; coordinator saves REPORT.md)
```

Completion bar, exploration method, operational limits (concolic-slot, one
JRuby, `free -h` ≥1.2Gi, kill only own PIDs, synchronous execution), and
the audit standard for assumptions are all identical to
`../results2/README.md` + `../results2/COMPLETION_BRIEF.md`.

## Success metric

`queries_from_runs` extraction + blockaid diff vs
`ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint/`: the
reference-rejected-by-ours residual should collapse to the genuinely
semantic differences (aggregate rewrites, disclosure-vs-execution), not
missing query families. results2's baseline for comparison:
notifications 1 vs 71 reference queries, people_stream 5 vs 168.

## Order

notifications_index first (simplest universe, biggest relative gap), then
by remaining gap: people_stream, comments_index, people_show,
conversations_index, posts_show. `../results2/MOCK_AUDIT.md` (when landed)
is the violation ledger to work from; where it doesn't exist yet, audit
the mocks your endpoint actually exercises by reading their real bodies.

## Worked example

`notifications_index/` is the reference implementation of this generation:
its `concolic_targets.rb` header ledger, `targets.rb` leaf shims
(ConcreteSymbolicString for mock string returns — bare String gets
re-wrapped by to_symbolic; polymorphic `find_target` via receiver.klass —
reflection.klass raises on polymorphic; to_param shim; federation
network-I/O wall), the render plumbing its runner needed
(ctrl.response= / action_name= / explicit default_render), and its
REPORT.md. Extraction gate result: 17 distinct queries vs results2's 1.
