# local_cvd6 — the closing round for `conversation_visibilities_destroy`, with a recording

Drive 6. The drive that gives §6.3's static half its one missing input, through
the real seam and inside the boxes.

**IT HAS NOT RUN. It cannot, and the reason is one line of `src_new/sweep/`
that is outside this drive's fence.** See "Why it has not run", below. Nothing
in this directory is a result; everything in it is the drive, ready.

## What drive 6 is, against drive 5 and drive 4

| | drive 4 | drive 5 | drive 6 |
|---|---|---|---|
| the two halves in boxes | yes | **no** (by hand, and it said so) | yes |
| a real-mode recording | no producer existed | produced, by hand | produced as a **stage** |
| recording reaches the static half | no slot for it | n/a — no box | `recording=` → `in/real_mode.json` |
| `--real` in `STATIC_ARGV` | omitted, correctly | n/a | **present** |
| `--app-config` | `domains.load` took no config | n/a | **present** |
| `statement_differential` | `check-not-implemented` | `check-not-implemented` | **built, and it runs** |

Drive 5's own README lists three things it could not wire and says "none of it
is this drive's to fix". All three are fixed now, and this drive is what uses
them.

## Stages

```bash
cd /home/dev/project/reports/autolab/local_cvd6
P=/home/dev/project/venvs/queries_from_runs/bin/python3
unset JAVA_TOOL_OPTIONS
$P drive.py --stage batch    --attempt 1   # the packet-producing agent
$P drive.py --stage pregate  --attempt 1   # §5.2's three mechanical steps
$P drive.py --stage check    --attempt 1   # the engine, on its own box
$P drive.py --stage policy   --attempt 1   # the IR, from the APPROVED corpus
$P drive.py --stage realmode --attempt 1   # THE RECORDING  <-- new on drive 6
$P drive.py --stage concrete --attempt 1   # §6.3's two halves
```

`realmode` comes **after** `policy` and before `concrete`, and both orderings
are load-bearing:

* after `policy`, because the plan takes its **target vocabulary** from this
  drive's own IR — the same IR the two C1 checks read their notes and views
  out of — so the two sides of the comparison cannot disagree about which
  target names exist;
* before `concrete`, because the recording is a `ro` **mount** on the static
  half's box and a mount needs a file.

`--stage concrete` **refuses** if `realmode` has not run, rather than falling
back to no recording. Falling back would reproduce drive 4's result (two unmet
obligations), which is already recorded in `local_cvd4/state/` and would prove
nothing new.

## Why it has not run

`sweep/binding.py::WorkerLayer._concrete` and `._static` pass
`recording=self.recording` to `plan_concrete` and `plan_static`. **Neither
function accepts that keyword**, and neither forwards it to the `recording`
field its plan dataclass does have. So the call raises before anything happens:

```
TypeError: plan_concrete() got an unexpected keyword argument 'recording'
```

This is not specific to drive 6 and not caused by anything here — it breaks
**every** §6.3 concrete round, with or without a recording, because the
keyword is passed unconditionally. `src_new`'s own suite catches it: ten
failures in `sweep/tests/test_binding.py`, every one of them that
`TypeError`.

Measured 2026-10-07:

```
plan_static   -> accepts `recording`: False      StaticPlan   has the field: True
plan_concrete -> accepts `recording`: False      ConcretePlan has the field: True
concrete_mounts -> accepts `recording`: True     REL_RECORDING = in/real_mode.json
```

The fix is four lines in `sweep/workers/concrete.py` — the keyword on each of
the two `plan_*` signatures, and `recording=None if recording is None else
Path(recording)` in each plan's constructor call, exactly as `real_plan` and
`fixtures` already do it. **`sweep/` is outside this work's fence, so it was
reported and not made.**

Everything downstream of that fix is verified correct here:

```
concrete_mounts(recording=out/concrete_run.json)
   -> Mount(target='in/real_mode.json', mode='ro')
STATIC_ARGV ... --real in/real_mode.json ...
   -> --real matches REL_RECORDING exactly: True
```

## The app config: this campaign has one, and it is worth passing

`reports/autolab/blockaid/config/app.json`. Two measured facts about it, both
of which the brief for this work asked to be re-checked rather than trusted:

1. **It carries no `note_aliases` key**, so the one thing
   `static_check.py --app-config` is named for in its own docstring costs
   nothing on this endpoint — the claim holds. The frame alias this endpoint
   *does* need (`FinderMethods#first` → `devise_user_first`) is applied one
   layer earlier, by the real-mode plan's own `frame_aliases` block, at
   capture time, so the recording arrives already attributed.
2. **It is still worth passing, for the schema.** On this endpoint's drive-4
   IR, `render_views` dropped **7** condition predicates with the config and
   **17** without, and emitted one view carrying a predicate it otherwise
   could not confirm was a column. `statement_differential` compares against
   that render, so the config changes what the differential's right-hand side
   *is* — not just how the document reads.

It is passed as an **absolute** path, which is a named gap: `--policy` is
relative because `concrete_mounts` mounts the policy IR, and
`concrete_mounts` has no slot for an app config. On the `host` backend a box
is a directory on this machine so an absolute path works, and it is exactly as
absolute as `VENV_PY` and `static_check.py` already are in the same argv. On a
backend with real filesystem isolation it would not work, and the fix is a
mount beside `REL_POLICY` — again `sweep/`, again not a campaign's to add.

## Ground truth is the coordinator's, and the agent may not supply it

`inputs/conversation_visibilities_destroy_config.json` declares both artefacts
the producer needs and may not invent — they were `null` on drives 1–4:

```
fixtures       = local_cvd6/fixtures/conversation_visibilities_destroy
real_mode_plan = local_cvd6/plan/real_mode_plan.json
```

Both are copies of drive 5's, which are `cvd-world-1` and `cvd-real-1`; the
plan is `cvd-real-2` here and differs only in its three paths. The three
scenarios are **deliberately not re-chosen**: drive 5 established that they
issue every statement the endpoint can issue, and a plan rewritten alongside a
corpus change would stop being the independent ground truth it exists to be.

The world is rebuilt from its document before **every** scenario, outside the
capture window — this endpoint deletes rows, so a second scenario against the
first one's leftovers would be a run against a world nobody declared.

## What the gate will say, and what it will not

`statement_differential` is built (`domains/ruby_rails_sql/checks.py`), so
`check-not-implemented/statement_differential` is gone from every result from
here on. In its place the domain runs a third real comparison, against the
**folded view set** rather than against the corpus notes.

Run out of band against drive 4's IR and drive 5's recording — **which is not
this endpoint's state** (every pre-2026-10-07 policy and review item on this
app was nullified, and that IR is one of them), only a demonstration that the
chain runs end to end:

```
[static_check] domain=ruby_rails_sql items=4 policy=yes real=yes app_config=yes
  statement-shape/matched-under-another-target/ActiveRecord::Base.destroy
  statement-shape/note-mismatch/ActiveRecord::Base.destroy
  statement-differential/not-in-views/DELETE/conversation_visibilities
  statement-differential/not-in-views/DELETE/conversations
exit 1
```

The two `not-in-views` items are the differential's own class and
`shape_check` cannot make either: the fold refuses both DELETE atoms
("terminates in DELETE, which is a write and not a select view"), so the
shipped view set names neither of this endpoint's deletions — while the note
for one of them is correct and satisfies `shape_check` completely. **The
policy understates what the endpoint writes.**

What the differential deliberately does **not** claim, because an unstated
limit reads as a pass: the count/multiset half (core, as T1b) and the
predicate level against a view. The second is the cross-principal case, and it
is caught one layer earlier by `shape_check`'s `pred <= r_pred` against the
unfolded, bind-preserving notes.

## Layout

```
drive.py                                  the six stages
inputs/<endpoint>_config.json             fixtures + real_mode_plan DECLARED
plan/real_mode_plan.json                  cvd-real-2: scenarios, principal, rig, frame aliases
fixtures/<endpoint>/world.json            cvd-world-1: the declared database world
out/concrete_run.json                     THE RECORDING (written by --stage realmode)
out/policy-1.json                         the IR, from the approved packet's corpus
state/*.json                              one record per stage
tools/{app_tree_digest,build_policy_ir}.py
agent_config/                             credentials symlink + the allow/deny posture
addendum_local.md, protocol.md            drive 4's, verbatim
```

`APP_TREE_PIN` is drive 4's value and still measures equal
(`916d393795a47b…`): `targets/core.rb` changed on 2026-10-07 and is correctly
outside the pin, which covers `app/ lib/ config/ db/schema.rb Gemfile
Gemfile.lock` and nothing else.
