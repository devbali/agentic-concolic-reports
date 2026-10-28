# `_staged_fixes/` — the D1-D8 write-note repairs, staged

**Nothing in here is live.** A shakedown was driving 161 endpoints against
`../core.rb` while these fixes were built, so every change was made and
verified against a copy. `apply.sh` is the only thing that touches the live
files, and it refuses to run while a concolic runner or sweep is in flight.

```
_staged_fixes/
├── README.md               you are here
├── apply.sh                staged -> live, atomic, reversible, idempotent
├── BASELINE_MD5            the live md5s this staging branched from
├── core.rb                 <- ../core.rb + the fixes
├── shared_shims.rb         UNCHANGED (kept so the tree mirrors the real layout)
├── endpoints/
│   ├── aspect_memberships_create.rb   <- ../endpoints/… + delegation to the core
│   └── comments_index.rb              UNCHANGED
├── _dml_section.rb.fragment        the inserted core section, kept separately for review
├── KNOWN_GAPS.md           what is STILL lost after these fixes, measured
└── _verification/
    ├── differential.rb     the executed real-vs-mock statement-SET differential
    ├── compare.py          the set comparison + the normalisation rule
    └── out/                every measured run: baseline_* (before), fixed_* (after)
```

## What `apply.sh` writes

| destination | source |
|---|---|
| `reports/autolab/targets/core.rb` | `core.rb` |
| `reports/autolab/targets/endpoints/aspect_memberships_create.rb` | `endpoints/aspect_memberships_create.rb` |
| `reports/diaspora/results4/aspect_memberships_create/concolic_targets.rb` | `core.rb` |
| `reports/diaspora/results4/comments_index/concolic_targets.rb` | `core.rb` |
| `reports/diaspora/results4/aspect_memberships_create/targets.rb` | `endpoints/aspect_memberships_create.rb` |
| `reports/autolab/targets/registry.json` | md5 fields only |

Those five files were byte-identical in pairs before (`registry.json` records
it) and stay byte-identical after — `apply.sh` verifies that as its last step.

It does **not** touch `reports/diaspora/results3/` (explicit instruction),
`src/`, `src_new/`, `shared_shims.rb`, `endpoints/comments_index.rb`, or git.

```bash
./apply.sh --dry-run        # preflight only
./apply.sh                  # apply; prints the revert command
./apply.sh --revert <dir>   # put the previous contents back
```

`apply.sh` was exercised end to end — dry run, apply, idempotent re-apply,
revert to the exact original md5s — against a sandbox copy of the tree
(`APPLY_ROOT`), and its "a run is in flight" guard was confirmed to refuse on
the live tree.

## The check

`_verification/differential.rb` runs each AR operation TWICE in one process:
first against real ActiveRecord on a private copy of `db/concolic.sqlite3`
with every statement captured from `sql.active_record`, then against the mock
stack with every note captured from `SymbolicFunc.get_call_records` — the same
records the dump writer turns into `symbolic_call` events, so what is compared
is what the extraction reads. `compare.py` diffs the two as SETS in both
directions: **LOST** (real, carried by no note) and **FABRICATED** (noted,
never issued). The normalisation rule, and exactly what it does and does not
collapse, is documented at the top of `compare.py`.

Run it:

```bash
cd /home/dev/project/ruby_examples/dse-apps/apps/diaspora
TARGETS_DIR=…/targets/_staged_fixes OUT=…/out/x.json \
  …/shakedown/tools/diaspora-concolic-mod …/_verification/differential.rb
python3 …/_verification/compare.py …/out/x.json -v
```
