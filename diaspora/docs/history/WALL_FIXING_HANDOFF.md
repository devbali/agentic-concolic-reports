# WALL-FIXING — OPERATIONAL HANDOFF (temporary)

> **Temporary working doc** for a compacted session to systematically apply the
> wall-fixing discipline to EVERY diaspora batch's entrypoints, batch by batch,
> until they stop crashing. NOT a permanent spec — the permanent discipline lives
> in `reports/diaspora/README.md` → **"Wall-fixing discipline"** section. Read
> that first; this doc is just the operational runbook for this go-around.

---

## 1. What this is

The concolic runs crash when a "wall" is hit — an unsupported symbolic op
(`SymbolicInt#to_i`, `SymbolicList#each/map`, `SymbolicString#gsub/strip/scan/…`)
or an app/plumbing `NoMethodError` on a nil (`@attributes`, `@_response`, `gon`,
`post_location`, …) — before the entrypoint reaches completion. We close each
wall by mocking the **smallest SQL-free unit** that encloses it, preserving the
real finder SQL on the enclosing path.

**Goal:** every entrypoint in every batch runs to completion (`error=none`),
recording its real path conditions; the only remaining "crashes" should be the
**intended seeded `RecordNotFound` not-found branches** (those are correct
coverage exploration, not bugs).

**Already done (latest):** the `posts` batch is fully wall-fixed. It went from
**21 crashed → 2 crashed (both intended RecordNotFound)**, 25 runs → 23 ok,
`complete=False` with **35 tree nodes / 4 missing branches** (the checker now
finds real gaps instead of crashing before any PC). posts_show records 9–11 PCs
(was 1–2).

---

## 2. THE DISCIPLINE (summary — full detail in README)

On every wall traceback:

1. **Find the raise frame**, trace outward to the **smallest enclosing method
   whose real body contains NO SQL and calls NO other declared target function**.
   That is the only legal mock unit.
   - If the body queries (`.where/.find/…`) or calls another `declare_target`ed
     function → do NOT mock it. Move outward, or extract the SQL-free leaf and
     wrap only that (the Gate-1b function-boundary-split pattern).
2. **Mock it symbolically** via `declare_target(receiver, method, returns: …)`
   in `reports/diaspora/concolic_targets.rb` (register in `install!`; give it an
   `X{letter}.` comment header matching the pattern).
3. **Preserve the real query path.** The enclosing finder (`find!` → EvilQuery,
   `aspects_from_ids`, `target.subscribers`, persistence mocks) must still run
   for REAL; you replace only a SQL-free leaf.
4. **Return-value rule (critical):** the mock must not re-enter the interceptor
   or break the dump JSON.
   - `nil` → passes through unchanged (use when result is discarded).
   - concrete `String`/`Integer`/`Array` → re-wrapped into Symbolic by
     `to_symbolic` — beware: **`[]` → SymbolicList** (which has no
     `as_api_response`). If the caller needs a real Array/collection behavior,
     mock one level up or return a non-native stub.
   - non-native stub objects (`dev_stub`/`gon_stub` pattern) pass through
     unchanged.
   - **JSON-safety:** a returned object must be JSON-serializable (a
     `RelatedEntity` whose `to_json` takes 0 args breaks `JSON.pretty_generate`).
5. Re-run the batch, re-apply on the next wall, repeat until `error=none`
   everywhere except intended RecordNotFound.

### Gotchas learned on `posts` (recheck per batch)
- **Eager-load required.** A target's class must be FULLY loaded before
  `install!` runs, or `define_method` lands on a discarded autoloaded class and
  the mock silently never fires. Add the file to the `eager_files` list in
  `install!` (the loop now covers `app/controllers app/models app/presenters
  app/services lib`). Fully-loaded check: `Klass.instance_method(:m).source_location`
  should show `call_interceptor.rb:107`, NOT the app file.
- **Private methods.** `Klass.instance_methods.include?` only lists public ones.
  Use `instance_methods.include?(m) || private_instance_methods.include?(m)` for
  private presenter/helper methods.
- **Class methods (`def self.x`).** Target `Klass.singleton_class` (see the
  `Mentionable.singleton_class` precedent).
- **Column/method name clash.** If a class has both a DB column AND a real
  method with the same name (e.g. `Profile#image_url`), the `symbolic_instance`
  per-instance column reader shadows the class method with arity 0. Fix with a
  per-instance override inside `symbolic_instance`, not `declare_target`.
- **Reshare-only methods on base Post** (e.g. `post_location`): give safe
  per-instance defaults in `symbolic_instance` for the base model so presenter
  code that calls them unconditionally doesn't NoMethodError.
- **nil-`@attributes` family:** give symbolic instances working
  `attributes`/`write_attribute`/`_write_attribute`/`[]=`/`inspect` overrides
  (already in `symbolic_instance`).
- **gon uses `method_missing`** for `gon.foo = …` — the stub must swallow
  arbitrary setters (`gon_stub.method_missing`).

---

## 3. STATUS — where each batch stands

Table shows the PRE-WALL-FIX state (dumps from before this pass). Apply the
discipline to move each toward `error=none`-everywhere.

| batch | runs | ok | crash | complete | nodes | miss | action |
|---|---|---|---|---|---|---|---|
| **posts** | 25 | **23** | **2** | False | **35** | **4** | ✅ DONE (2 crashes = intended RecordNotFound; 4 real missing to seed) |
| comments | 9 | 5 | 4 | True | 3 | 0 | apply discipline |
| contacts_aspects_blocks | 22 | 20 | 2 | False | 12 | 2 | ✅ DONE (2 crashes = intended RecordNotFound) |
| conversations | 14 | 1 | 13 | True | 2 | 0 | apply discipline |
| likes | 9 | 2 | 7 | False | 5 | 1 | apply discipline |
| notifications_tags | 12 | 3 | 9 | True | 2 | 0 | apply discipline |
| oidc_federation_nodeinfo | 7 | 2 | 5 | True | 0 | 0 | apply discipline |
| people | 19 | 9 | 10 | False | 5 | 3 | apply discipline (high crash) |
| photos | 16 | 1 | 15 | False | 10 | 5 | apply discipline (high crash) |
| search_links_reports_profiles | 11 | 3 | 8 | False | 2 | 2 | apply discipline |
| services_admin | 12 | 5 | 7 | False | 2 | 2 | apply discipline |
| streams | 18 | 7 | 11 | True | 7 | 0 | apply discipline |
| users_sessions | 28 | 4 | 24 | False | 2 | 1 | **high crash count — start here or contacts** |

**Suggested order (highest crash density first):** `contacts_aspects_blocks`,
`users_sessions`, `photos`, `people`, then the rest in any order. `posts` is the
reference worked example — diff `concolic_targets.rb` §X to see every pattern.

---

## 4. PER-BATCH RUNBOOK (repeat for each batch)

For one batch `B`:

1. **Capture baseline.** `python3 reports/diaspora/verify_gate1b.py B` → note
   ok/crash counts.
2. **Run the batch fresh.** Remove stale dumps in
   `results/B/` (they're append-never-overwrite), then:
   ```
   scripts/diaspora-concolic reports/diaspora/results/B/run_concolic.rb
   ```
   (Each batch's `run_concolic.rb` drives real controller actions; some are
   per-entrypoint and need `<entrypoint> [round]` args — check the header. The
   `comments` batch is per-entrypoint.)
3. **Read every `error`** in `results/B/*/dump_*.json`. For each, get the
   full traceback, apply §2 discipline, add the mock to `concolic_targets.rb`
   §X (eager-load the file, handle private/singleton/column-clash cases),
   re-run, repeat until `error=none` everywhere except intended RecordNotFound.
4. **Verify done.** `verify_gate1b.py B` → expect `ok` ≈ all runs, crash only
   `RecordNotFound` (intended seeds). Check `tree_nodes`/`missing` — those are
   real coverage gaps to seed next (the coverage loop), not walls.
5. **Check `$$(SYMNAME)` traceability** survived in the fresh dumps:
   `grep -rl '\$\$(' results/B --include='*.json'` should find files (symbolic
   bind rendered as `$$(NAME)`), and each `$$(NAME)` must resolve to a var in
   `symbolic_vars` whose `note` names the producing query.
6. Update this table's row for `B` with the new ok/crash numbers.

### How to run one batch (from project root)
```
scripts/diaspora-concolic reports/diaspora/results/<B>/run_concolic.rb
```
Runs from the app dir (`ruby_examples/dse-apps/apps/diaspora`) with
`RAILS_ENV=concolic`. Add `>& /tmp/batch_<B>.log` to capture.

### How to isolate a single crashing entrypoint fast
Reuse the `posts`-style script or the per-batch `run_concolic.rb` entrypoint
arg; grab the traceback directly from the dump JSON:
```
python3 -c "import json;d=json.load(open('results/B/ep/dump_x.json'));print(d['error']['message']);[print(' ',l) for l in d['error']['traceback'].split(chr(10)) if ':in ' in l]"
```

---

## 5. Verification (after all batches)

- Runtime regression (should stay green — the only runtime change in this pass
  is the `note` on target calls, Ruby + Python parity):
  ```
  cd src && ruby test_ruby_runtime.rb && python3 -m pytest py_runtime/test_list_rep.py test_symbolic.py test_query_ops.py test_interceptor.py -q
  ```
- Framework smoke (expect 3 PCs):
  ```
  scripts/diaspora-concolic scripts/test_framework_targets.rb
  ```

---

## 6. Git / files touched

- `reports/diaspora/concolic_targets.rb` — ALL wall mocks live here (§X +
  everything). Freely edit (untracked reports zone).
- `reports/diaspora/README.md` — has the permanent **Wall-fixing discipline**
  section; keep it in sync with what you learn. Also untracked.
- `src/ruby_runtime/call_interceptor.rb` + `symbolic_func.rb` — `note` on the
  target call (committed). Do NOT change runtime unless a genuine new wall
  needs it — mirror Python (`src/py_runtime/symbolic_func.py` +
  `call_interceptor.py`) if you do.
- `reports/` is NOT a git repo (only `src/.git` and `ruby_examples/dse-apps/.git`).

**THIS DOC:** delete it once the session is done / folded into `STATUS.md`.
