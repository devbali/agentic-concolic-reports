# `policy_example.txt` — the policy IR from this corpus

**Date:** 2026-09-24 (supersedes the 2026-09-23 version, which was built from
a partial corpus — see "What changed" below)
**Corpus:** all five DSE dumps in this directory —
`dump_anon_json_dse0001.json` … `…0005.json`, regenerated clean with
`MAX_RUNS=6 TIME_BUDGET=600 scripts/diaspora-concolic ./run_dse.rb`
(6 runs, 5 distinct paths, 0 run errors).
**Runtime:** `src_new/runtimes/ruby_runtime`, with the 2026-09-24
`call_interceptor.rb` fixes in place (identity-based call/record pairing;
per-call scoping of the pending-note channel) on top of the
`kind: TARGET_FUNCTION` / `kind: SHIM` classification applied to every
`declare_target` in this directory's `concolic_targets.rb` / `targets.rb`.
Each dump carries 104 declarations: 63 `target_function`, 41 `shim`.
**Certificate:** none — no coverage/completion pass was run against this
corpus, so `outcome=UNDECIDED` and there is no `coverage_summary.json` here.

## What it is

The output of running `dumps_to_policy/README.md`'s "The one call" against
these dumps for real:

```
Run.from_dict → build_policy(entrypoint="comments_index")
              → normalize_detailed  (§6: merge, subsume, simplify)
              → print_policy
```

**All five dumps build. Zero `BuildError`s.** One policy over the whole
corpus: `atom_budget` 13 → 13 unmerged atoms → **11 after §6 normalization**,
6 signatures, `minimal=full` with the solver in use.

## What changed since 2026-09-23

The previous version of this file led with three blockers. Two of them were
the same runtime defect and are now **fixed in `src_new`**; the third is
unchanged.

1. **~~`BuildError` on 2 of 4 runs~~ — FIXED.** The diagnosis recorded here
   was right: `call_interceptor.rb` zipped a **pre-order** call list against a
   **post-order** symbolic-result list by position, which only coincides when
   no target call nests inside another target's mock. It nests constantly —
   `ActiveRecord::Relation#records`'s mock calls
   `ConcolicThroughLoadProbe.load_intermediate` — so the parent's result
   symbol was bound *after* the decisions that read it:

   ```
   BuildError: run 'anon_json_dse0005': a decision before
   ConcolicThroughLoadProbe.load_intermediate (idx 12) reads ['c4'],
   which no earlier call bound — §10.2 rule 1
   ```

   On the superseded 24-dump set in this directory that was **16 of 24 dumps**
   refused (the 2026-09-23 note's "2 of 4" was measured on a smaller set).
   Records now carry the identity of the call that published them
   (`TargetCall#call_id`), so the pairing is a fact the runtime recorded
   rather than one the assembler reconstructs. Positional zipping also
   silently shifted every later pair whenever a target RAISED; that is closed
   by the same change. Regression tests:
   `runtimes/ruby_runtime/tests/test_ruby_runtime.rb` ("dump assembly: a
   nested target call does not swap the pairing"),
   `runtimes/py_runtime/tests/test_interceptor.py`, and end-to-end in
   `src_new/tests/test_e2e_policy_extraction.py::NestedTargetCallEndToEnd`.

2. **A note landing on an unrelated call — FIXED** (this is
   `../aspect_memberships_create/REPORT.md`'s defect **D9**). In the
   superseded dumps, `dump_anon_json_dse0020.json` and `…0038.json` carried
   `note: "DiasporaFederation::Discovery#fetch_and_save (webfinger network
   wall; raises before any data access …)"` on an
   `ActiveRecord::FinderMethods#first` event — and not even from the same run.
   Cause: the wall mock publishes its note on
   `Thread.current[:concolic_pending_note]` and then raises on purpose, so
   `CallInterceptor.extract_note` — which is the only thing that clears the
   channel — was never reached, and the next target call consumed it.
   `run` did not clear the channel either, so it crossed run boundaries.
   Each target call now runs with an **empty** channel and restores its
   caller's on the way out, so a note can only ever be read by the call that
   wrote it.

3. **`print_policy` cannot print a certificate-free policy** — unchanged, and
   still worked around in the driver only. `build_policy`'s `certificate` is
   optional, but the printer falls back to a default `Certificate()` with
   `atoms=0` and then fails its own `check_atoms`. A blank
   `Certificate(app="results4/comments_index").with_atoms(n)` is attached; its
   default `outcome=UNDECIDED` says in the text itself that this describes
   what was seen and is not a certified policy.

4. **`ActionController::Metal#status=` is not a §10.2 qname** — unchanged.
   The printer's `_QNAME` admits Ruby's `?`/`!` suffixes but not `=`. Widened
   **at runtime in the driver script only**; nothing under `dumps_to_policy/`
   was modified. Both (3) and (4) remain open cosmetic gaps in the printer.

## What the policy says

```
policy comments_index
  cert   report=none  outcome=UNDECIDED  app=results4/comments_index
         atoms=11  minimal=full  inferred=175  declared=43  elided=0
  entry  comments_index($"Length(SYM_PARAM_post_id)": int,
                        $SYM_RESULT_…first_1_not_found: bool,
                        $SYM_RESULT_…first_1_type: str)

  sig ActionController::Head#head(status: str) -> int shim
  sig ActionController::Metal#status=(arg: int) -> opaque? shim
  sig ActionController::Rendering#_set_rendered_content_type(format: str) -> [opaque] shim
  sig ActiveRecord::FinderMethods#first() -> opaque? target_function
  sig ActiveRecord::Relation#records() -> int target_function
  sig ConcolicThroughLoadProbe.load_intermediate(sql: str) -> int target_function
```

Eleven atoms over two entrypoint arms (`len(post_id) < 16` → `posts.id`,
`>= 16` → `posts.guid`), the app's own gating chain off `find_public!`
(`c1.not_found != true`, `c1.public == true`, `c1.type != "Photo"`), and the
comment/author/profile read chain behind it.

**The producer→consumer edges the fix restored.** Atom 4 is the shape the old
corpus could not state at all:

```
c2 = ActiveRecord::Relation#records()
     // SELECT "comments".* … WHERE "comments"."commentable_id"
     //        = $$(SYM_RESULT_ActiveRecord__FinderMethods_first_1_id) …
assert c2.row_text_has_dlink != true
assert c2.row_text_has_mention != true
assert len(c2.rows) <= 1
access c3 = ConcolicThroughLoadProbe.load_intermediate(
     "SELECT \"people\".* … WHERE \"people\".\"id\"
        = $$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id)")
```

`c2` is bound, then read, then the nested probe it gates is the access. Under
the positional zip `c2` was bound three events too late and the dump was
rejected outright.

## How it differs structurally from the examples already in the repo

Two examples exist elsewhere, and neither was built from a real, kind-
classified corpus:

* `src_new/README.md`'s "Example" — a synthetic two-function Python demo
  (`find_post` / `find_author`), 2 atoms, both `target_function`.
* `src_new/dumps_to_policy/examples/comments_index.*.policy` — built from the
  **old `results2`** corpus, which predates declarations entirely, and which
  (being nesting-free) is exactly why the committed fixtures never exposed the
  pairing defect.

Against those, this one shows:

* **Real declared kinds on the `sig` lines** — `… -> opaque target_function`
  and `… -> opaque? shim` both appear, and `declared` is non-zero. The
  `results2` fixture prints `inferred=200 declared=0` and no kind suffix at
  all.
* **Shims that are real Rails plumbing**, not stand-ins:
  `ActionController::Metal#status=`,
  `ActionController::Rendering#_set_rendered_content_type` — on the path,
  never terminating an atom.
* **Real SQL notes on the accesses**, carried through verbatim as opaque
  `note` strings, including `$$(…)` binds against an earlier call's result.
* **Nested accesses**, which no previously buildable corpus in this tree
  contained.

## Findings still open

* **Provenance loss on the entry signature.** It reads
  `comments_index($"Length(SYM_PARAM_post_id)": int)` — the actual
  `post_id: str` parameter is gone. `SymbolicString#length` (`string.rb:219`)
  mints a symbol *named* `Length(<z3_expr>)` instead of emitting a structured
  `{"op":"length", …}` term. The legacy string-`expr` path re-parsed that name
  back into a `Length` term; the structured `expr_term` path does not, so on
  this point the new path is a regression. The same runtime *does* emit
  structured `length` for list lengths in these very dumps (24 of the 30 PCs
  here are structured, 6 are legacy strings).
* **The `people_from_string` / mention-lookup provenance question is still
  open.** No dump here contains that call: the mention path is gated on
  `<rep>_text_has_mention == true`, and that decision is `taken=false`
  wherever it is recorded. `dump_anon_json_dse0005.json` does reach the
  `mentions` *association* load, which is not the same call. Closing this
  needs a dump with that branch taken.
* **No completeness claim.** `worklist_exhausted: false` — the 6-run budget
  stops with seeds queued, and no `CoverageChecker` pass was run. This is a
  description of five real paths, not a policy for the endpoint.

## Reproducing it

The build driver lives in `reports/diaspora/tools/` (nothing under
`src_new/dumps_to_policy/` is modified — the printer workarounds are runtime
monkeypatches in the driver):

```
cd /home/dev/project/src_new
/home/dev/project/venvs/queries_from_runs/bin/python3 \
  ../reports/diaspora/tools/build_policy_example.py \
  comments_index ../reports/diaspora/results4/comments_index/policy_example.txt \
  ../reports/diaspora/results4/comments_index
```

## Files

* `policy_example.txt` — the full printed policy described above.
* `dump_examples/` — five representative dumps with a per-file README.
* `POLICY_EXAMPLE.md` — this file.
* `src_new/README.md`'s "Example" section carries a dated pointer here.
