# `dump_examples/` — comments_index

Copies of the generated dumps in `..`, kept under their original names, one
per distinct explored path. Regenerated 2026-09-25 with the §5.0 type declarations and §4.1.1c's note
envelope in place (see `../../../../src_new/DESIGN_IR.md` §5.0.1); originally
generated 2026-09-24 by
`MAX_RUNS=6 TIME_BUDGET=600 scripts/diaspora-concolic ../run_dse.rb`, with
`src_new/runtimes/ruby_runtime/call_interceptor.rb`'s identity-based
call/record pairing and per-call note scoping in place. All five build
cleanly through `dumps_to_policy.build.build_policy`.

| file | path / shape it illustrates |
|---|---|
| `dump_anon_json_dse0001.json` | **Short post_id.** `len(post_id) < 16` → the finder reads `posts.id = $$(SYM_PARAM_post_id)`; post found, not a `Photo`, `public == false` → the visibility branch ends the run. The minimal shape: one access, three decisions on its result. |
| `dump_anon_json_dse0002.json` | **Long post_id (guid branch).** The same call site with the branch flipped: `len(post_id) >= 16` makes `PostService#find_public!` read `posts.guid = $$(SYM_PARAM_post_id)` instead. Same decisions, a different statement — the entrypoint parameter reaching SQL as a genuine bind on both arms. |
| `dump_anon_json_dse0003.json` | **Not found → 404.** `first_1_not_found == true`, so the finder's `symbolic_call` carries its SELECT even though the mock returned nil (change 6's pending-note channel), and the run ends in `ActionController::Head#head`. |
| `dump_anon_json_dse0004.json` | **A target that RAISES.** The STI branch: `first_1_type == "Photo"` makes the finder raise `ActiveRecord::SubclassNotFound` (`concolic_terminal`). The dump carries the `call` event with **no** `symbolic_call` after it — the shape that used to shift every later pair by one, and whose pending note used to land on an unrelated later call (defect D9). |
| `dump_anon_json_dse0005.json` | **The nested-call path — only correct since Bug 1 was fixed.** `ActiveRecord::Relation#records`'s mock calls `ConcolicThroughLoadProbe.load_intermediate` internally, so the parent starts first and finishes last. 12 calls, 12 results, every `call` now immediately followed by *its own* `symbolic_call`; `records_1` is bound before the decisions that read its row attributes. Under the old positional zip this dump was refused: `BuildError … a decision before ConcolicThroughLoadProbe.load_intermediate reads ['c4'], which no earlier call bound — §10.2 rule 1`. |
