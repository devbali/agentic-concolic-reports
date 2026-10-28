# local_tags1 — `tags_index`, driven to the end of the chain

The first drive of an `autolab` endpoint other than `posts_destroy` and
`conversation_visibilities_destroy`, and the first time the six-stage chain ran
with **both** of drive 6's new inputs actually mounted.

**It ran. It did not close, and it cannot.** The engine says `complete: true`
with `blocking: []`; the DOMAIN gate then reports two findings and blocks. Both
halves of that sentence are the result, and the second is the interesting one.

## Result

```
batch     submitted=True  detail=ok   elapsed=645s  cost=$1.03 (measured)  denials=0
pregate   passed=True     decision=D-0001   app_tree_digest matches the pin
check     outcome=COMPLETE  complete=True   blocking=[]
          coverage: coverage_complete true  tree_complete true
                    missing_branches 0  total_runs 2  truncated false  solver_lost 0
          audits: 6/6 green     shims: 22 extracted, 10 PASS / 12 PROTOCOL
          assumptions: 0 declared, vacuously satisfied
policy    runs=2  atoms=0  notes=0        <-- an EMPTY policy IR
realmode  6 scenarios, 4 statements captured in 29s
concrete  elapsed=185s  detail=agent:ok; static:ok   findings=4
          static half EXIT 1   boxes this round: agent + static (4 distinct overall)

[certificate] endpoint=tags_index attempt=1
              ENGINE=COMPLETE(0 blocking)  DOMAIN=BLOCKED(1 blocking)
              claims=4   VERDICT=NOT CLOSEABLE
```

`domain_blocking`, verbatim and entire — **one** line:

```
static half: EXIT 1 — §6.3's static half is a script with an exit code and this
one did not exit 0, so the domain's static checks did not pass. The claims are
this round's review items
```

The four claims, with who raised each:

| identity | raised by | catchable |
|---|---|---|
| `note-fidelity/not-same-read/MISSING/ActiveRecord::Relation#records/tags-autocomplete` | agent | true |
| `real-mode/frame-vocabulary/circular-from-policy` | agent | **false** |
| `statement-shape/outside-any-target-frame` | static | true |
| `statement-differential/no-views-rendered` | static | true |

So **"completion" is not reached**: the brief's test is the engine's
`complete: true` AND an empty `domain_blocking`, and the second conjunct fails.
Nothing was suppressed, waived or widened to get here.

### The engine is complete and the policy is still wrong

`TagsController#index` has exactly **one** branch and the concolic runtime
records exactly one path condition for it:

    (Length(SYM_PARAM_q) > 1)        app/controllers/tags_controller.rb:18

Both sides are in the corpus, the flip worklist is exhausted, and the coverage
layer is satisfied. But the **true** side — the entire endpoint: the tag query,
the limit arithmetic, the JSON render — terminates on the very next line:

    tags_controller.rb:19   params[:q].gsub!("#", "")
    -> NotImplementedError: SymbolicString#gsub! is not supported in the
       concolic runtime            (src_new/runtimes/ruby_runtime/string.rb:391)

`gsub!` is in `SymbolicString::UNSUPPORTED`, in the group commented
"Mutation / concat / format", under a header reading "This list is the complete
set of String methods that are NOT PC-tracked and MUST fail loudly." It is a
DECLARED NON-GOAL reached by application code on the only path that matters —
the same CLASS of wall as `conversation_visibilities_destroy`'s
`SymbolicList#to_ary`, and this endpoint has **five** of them stacked:

| line | expression | refused by |
|---|---|---|
| controller:19 | `params[:q].gsub!("#","")` | `SymbolicString#gsub!` — mutation |
| controller:20 | `params[:limit].to_i` | `SymbolicString#to_i` — numeric coercion |
| controller:21 | `params[:limit] - 1` | `SymbolicInt` arithmetic (CLAUDE.md) |
| model:12 | `name.downcase` in `Tag.autocomplete` | `SymbolicString#downcase` — transformation |
| controller:70 | `"#" + tag.name`, `@tags <<`, `@tags.uniq!` | `SymbolicString#+` — concat; list mutation |

So the corpus covers every branch and records **no data access at all**:
`statement_note_lint` reports "2 dumps, **0 clean notes**", and the only two
target calls are `ActionController::Rendering#_set_rendered_content_type` and
`ActionController::Head#head`, both declared shims and neither an access.
`--stage policy` therefore built an IR with `atoms=0 notes=0`: **the shipped
policy says this endpoint touches nothing.**

### What the real endpoint actually does, and what the gate said

`--stage realmode` drove the six declared scenarios against the declared world
and captured the statement the policy omits:

    SELECT "tags".* FROM "tags" WHERE (name LIKE ?) ORDER BY name ASC LIMIT ?

Four scenarios issue it (prefixes `alice%`, `al%`, `zzz%`); the two `else`-arm
scenarios issue nothing, which is also a fact worth recording. The
`q-hash-stripped-and-downcased` scenario passes `q="#ALICE"` and comes back as
`LIKE 'alice%'` — **both** `gsub!` and `downcase` ran for real, which is exactly
the pair the concolic runtime refuses.

The static half (`domains/static_check.py`, with `--policy`, `--real` and
`--app-config` all pointing at mounts) then reported two items:

```
statement-shape/outside-any-target-frame
  3 distinct statement(s) were issued under NO declared target function.
statement-differential/no-views-rendered
  the fold ran and emitted ZERO views, while the application really issued
  DML touching 1 relation(s): SELECT tags. … the fold excluded no atom and
  dropped no view, so the absence is not an exclusion this render reported.
```

The second item's last clause matters: it rules out the benign reading. The
views are not missing because the fold declined to emit them; they are missing
because the corpus never saw the access.

**This is the designed outcome, and it is the point of the drive.** Coverage
completeness and a true account of an endpoint are different claims, and this
endpoint is the clean separating example: the generic engine's conjunction is
satisfiable on a corpus that knows nothing about what the endpoint reads, and
only the domain gate — holding a real-mode recording against a real database —
can say so.

## Ground truth is the coordinator's, and it is this drive's own

`inputs/tags_index_config.json` declares both artefacts the producer needs and
may not invent (they are `null` in the scaffold config, which is this drive's
input):

```
fixtures       = local_tags1/fixtures/tags_index   (world_id tags-world-1)
real_mode_plan = local_tags1/plan/real_mode_plan.json (plan_id tags-real-1)
```

Neither is inherited. The world is five `tags` rows whose LIKE-prefix sets
nest, so the `LIMIT` bind does visible work (`limit=3` → `LIMIT 2` against a
4-row match) rather than being larger than the result. The plan has six
scenarios covering both sides of the only branch, both limit arms, a
zero-match arm and the two ways the `else` arm is reached. It carries **no
`principal` block** and **no `frame_aliases`**, each with its reason recorded
in the document: this endpoint is `signed_in: false`, its one table has no
principal column, and its corpus contains no finder frame to re-attribute.

Every scenario record in the recording stamps its provenance, and all of it was
recomputed and matched:

```
world_id tags-world-1   world_sha256 5eb9f285f2c0ba…  (recomputed: equal)
schema db/schema.rb     schema_sha256 cd1c837829458…  transform sql-dialect-strip
plan_id tags-real-1     plan_sha256  7e768b97e5c622…  (recomputed: equal)
tables_created 52       rows_seeded 5
```

## Drive 6's two blocked wires are no longer blocked

`local_cvd6/README.md` says that drive "HAS NOT RUN" because
`plan_concrete`/`plan_static` did not accept `recording=`. Measured here on
2026-10-07: both accept `recording` **and** `app_config`, and this drive's
concrete box has all three mounts on disk —

```
in/real_mode.json   -> local_tags1/out/concrete_run.json      (REL_RECORDING)
in/app_config.json  -> reports/autolab/blockaid/config/app.json (REL_APP_CONFIG)
in/policy.json      -> local_tags1/out/policy-1.json
```

so `--app-config` names the MOUNT and not an absolute host path, which is the
shape cvd6's own docstring argued for and could not reach. `_UNBUILT` is empty,
so `statement_differential` ran as a third real comparison rather than as
`check-not-implemented`.

## Two escalations were filed, and neither is this drive's to decide

The closing agent filed both into `boxes/tags_index-concrete-1-8a753443/ctl/ask/`
rather than working around either:

* **`tags-wall-runtime-nongoal`** (class `sweep-wide`) — the wall. It lists the
  three options (lift the runtime non-goals; relax `must_stay_symbolic` for
  this endpoint; accept that `tags_index` cannot close), declines to choose,
  and proposes no workaround.
* **`probe-target-vocabulary-circular`** (class `shared`) — **a real defect in
  shared tooling, found by this drive.**
  `real_mode_probe.rb::resolve_targets` takes the frame vocabulary ONLY from
  the policy IR's target-function signatures. This endpoint's IR has none, so
  `recording.targets.declared = []`, the recording came back
  `4 statement(s), 0 frame(s)`, and every captured statement has `under: null`.
  Generalised: **a target the corpus never reached can never frame a real
  statement**, so `shape_check` reports `outside-any-target-frame` instead of
  `note-missing/<target>` and the absence the check exists to catch is
  mis-attributed. It is not `tags`-specific — it affects any endpoint whose
  corpus misses a target outright. Changing the vocabulary source is a change
  to shared tooling and was correctly not applied here.

## The reported cross-principal gap did NOT manifest here

The known gap — a `SELECT … WHERE <fk> = ?` that omits the principal column
rendering as `*** UNRESTRICTED ***` with no check naming it — needs a RENDERED
VIEW, and this endpoint rendered **zero**. Its failure mode is strictly more
severe and is the one the differential named: not an over-broad view, but no
view at all. Separately, the statement's own table could not have triggered the
gap substantively: `tags` is `(id, name, taggings_count)` and
`blockaid/config/app.json`'s `principal.principal_columns` has no `tags` entry,
so a `tags` read has no principal column to omit and an unrestricted rendering
of it would have been truthful.

## Layout

```
drive.py                            the six stages, retargeted from local_cvd6
inputs/tags_index_config.json       fixtures + real_mode_plan DECLARED
fixtures/tags_index/world.json      tags-world-1: the declared database world
plan/real_mode_plan.json            tags-real-1: six scenarios, no principal
out/policy-1.json                   the IR — atoms=0, and that is the finding
out/concrete_run.json               THE RECORDING (written by --stage realmode)
state/*.json                        one record per stage
logs/*.log                          one log per stage
addendum_local.md                   THIS endpoint's operator addendum
tools/{app_tree_digest,build_policy_ir}.py
```

`APP_TREE_PIN` is unchanged and still measures equal
(`916d393795a47b…`), measured before and after: no application file was
touched by this drive.
