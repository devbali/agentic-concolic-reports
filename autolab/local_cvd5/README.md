# local_cvd5 — real-mode capture for `conversation_visibilities_destroy`

Drive 5. The one thing drives 1–4 could not do: **`shape_check` actually
compared.** Drive 4's domain gate reported
`statement-shape/no-real-mode-recording` — "compared nothing: no recording was
supplied (`real` is None)" — because no producer existed anywhere in the tree.
There is one now, and this directory is the first endpoint it ran on.

## Result

```
[static_check] domain=ruby_rails_sql items=2 policy=yes real=yes
  statement-shape/matched-under-another-target/ActiveRecord::Base.destroy
  check-not-implemented/statement_differential          (unbuilt, unchanged)
```

`real=yes`. One substantive finding, and it is a **real defect, not the benign
cause the item's own text expects**. See "What it found", below.

## Run it

```bash
unset JAVA_TOOL_OPTIONS
systemd-run --user --scope -p MemoryMax=12G --quiet python3 drive_real_mode.py all
```

~70 s, almost all Rails boot. `capture` and `compare` are separable stages.
Reproducible: two runs produced byte-identical `review_items.json`
(`b1b73277fea5…`).

## The three things that were missing, and where each now lives

| | What | Where |
|---|---|---|
| **the driver** | `RuntimeAdapter.drive_real_mode(cfg, plan, *, out)` | `src_new/concolic/runtime/adapter.py` (protocol), `ruby.py` (impl), `real_mode.py` (the launch) |
| **the Rails probe** | `sql.active_record` capture joined to the target-frame thread-local | `src_new/domains/ruby_rails_sql/real_mode/real_mode_probe.rb` |
| **the fixture world** | a declared database world | `fixtures/conversation_visibilities_destroy/world.json` |
| **the real-mode plan** | which scenarios to drive | `plan/real_mode_plan.json` |

The generic/Rails split: the adapter and `real_mode.py` know only that a
configured command takes a `{plan}` and writes an `{out}` — the same contract
`extract_cmd` / `test_cmd` already have with their two Ruby probes. Everything
that knows what a SQL statement *is* lives in the domain, beside the check that
consumes it. `concolic/` may not import `domains/`, and
`concolic/runtime/tests/test_adapter.py::test_real_mode_py_holds_no_rails_or_sql_knowledge`
asserts the core half stayed clean by scanning the source.

## Fixtures and the plan are CONFIG, and the agent under test may not supply them

Both are JSON documents the coordinator owns. An agent that writes its own
ground truth has been handed the answer key — which is why the batch brief
(`local_cvd/addendum_local.md` §8) forbids a batch agent from producing a
`concrete_run.json` at all. Being data rather than a Ruby manifest is what
makes that boundary enforceable; the prior manual harness
(`reports/diaspora/tools/concrete_checker/`, read for its mechanism, written to
never) had each adversary round hand-write its own lambdas, which its own
README names as the gap.

**How a reader knows which world a recording came from.** Every scenario record
carries a `world` block: `world_id`, the world document's SHA-256, the schema
file's path and SHA-256, the transform applied, tables created, rows seeded.
The recording also stamps `plan_sha256` and the policy IR it took its target
vocabulary from. Nothing about a recording's provenance has to be reconstructed.

The world is **rebuilt from the document before every scenario**, outside the
capture window — this endpoint deletes rows, so a second scenario run against
the first one's leftovers would be a run against a world nobody declared.

## What it found

Four of the five target frames are **clean**: every statement the real run
issued under `devise_user_first`, `find_target`, `FinderMethods.first` and
`Calculations.count` matched a note that target recorded, shape for shape. So
is `ActiveRecord::Base#destroy`'s own `DELETE FROM conversation_visibilities`.

`ActiveRecord::Base#destroy` issues **three more real statements that it
records no note for**:

```
SELECT "conversations".*            FROM "conversations"            WHERE id = ?            LIMIT ?
SELECT "conversation_visibilities".* FROM "conversation_visibilities" WHERE conversation_id = ?
DELETE FROM "conversations" WHERE "conversations"."id" = ?
```

They are `ConversationVisibility#check_orphan_conversation` — the model's
`after_destroy` callback, which loads the conversation, counts its remaining
participants and destroys it when none are left, cascading to its dependent
rows. **The mock for `ActiveRecord::Base#destroy` skips the real body**
(`reports/autolab/targets/core.rb`: "Every declare_target below SKIPS the real
body"), so the callback never runs concolically and mints exactly one note: the
`DELETE` of the row itself.

The item's identity is `matched-under-another-target`, and its text says the
expected cause is frame nesting, "in which case the shape IS recorded and
nothing is wrong". **That explanation does not hold here**, and accepting the
item on those grounds would be wrong:

* the `conversations` SELECT matches a note recorded under `find_target`, but
  that note is the controller's `@vis.conversation` association load, not the
  callback's `Conversation.find_by_id`;
* the `conversation_visibilities` SELECT matches a note under
  `FinderMethods.first` — the controller's own lookup, not the dependent-destroy
  load;
* **`DELETE FROM "conversations"` has no note anywhere in the corpus.** It
  matched only because `_shape_of` is `(tables, projection, predicates)` and
  carries no statement KIND, so a `DELETE` is satisfied by a `SELECT` note over
  the same table with the same predicate column. This is the residue of INSTR-7
  (the 2026-08-30 finding that two judges compared SELECTs only):
  `_is_data_access` was widened to admit DML, but the shape predicate was not.

**Consequence for the policy.** This endpoint can delete a row from
`conversations`, and nothing in the corpus or the rendered view set says so. The
policy understates what the endpoint writes. That is the `Person#name` class —
a target mock emitting less evidence than the body it stands in for — reached
through a callback rather than through a junk note.

Not fixed here: the `destroy` mock is in the shared target library
(`reports/autolab/targets/`), which is fenced to another agent, and Rule T makes
a target-boundary change restart every endpoint. `core.rb` was last modified
2026-09-26 11:22, i.e. not yet touched by the concurrent work on this same mock.

## What is still not wired

Named in `drive_real_mode.py`'s header, and none of it is this drive's to fix:

1. `sweep/workers/concrete.py::concrete_mounts` mounts `in/real_mode_plan.json`
   (the plan) and has **no slot for the recording**.
2. `local_cvd4/drive.py`'s `STATIC_ARGV` omits `--real` — correctly, while there
   was nothing to point it at.
3. `domains.load(name)` takes no arguments, so the static half's `Domain` has
   `app_config=None` and `shape_check`'s `note_aliases` is always empty. Costs
   nothing on this endpoint; would matter where a mock records under another
   target's name.

So this drive ran the two halves in the order the gate will run them, against
the real artefacts, through the real seam — it did not run them inside boxes.

## Layout

```
drive_real_mode.py                        capture (via the adapter) + compare (static_check.py)
fixtures/<endpoint>/world.json            the declared database world
plan/real_mode_plan.json                  scenarios, principal, rig helpers, frame aliases
out/concrete_run.json                     THE RECORDING
out/gate/review_items.json                what shape_check said
```

`policy-1.json` is **not** rebuilt here: it is drive 4's, built from the
approved packet's corpus. Re-deriving it would mean comparing against a corpus
side nobody approved.
