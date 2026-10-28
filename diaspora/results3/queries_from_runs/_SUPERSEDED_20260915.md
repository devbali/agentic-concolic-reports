# The extraction layer is superseded by one script (2026-09-15)

`reports/diaspora/tools/extract_policy.py` — 168 lines — replaces all of:

| file | lines | why it existed |
|---|---:|---|
| `_experiment/variant_d/assoc_fold.py` | 254 | registers producers from `symbolic_vars` notes and unwraps `StringVal('x')` in path conditions, by MONKEYPATCHING `_Build._bind_value` and `pcs.parse_pc` at import time |
| `_blockaid_fold.py` | 363 | E1–E11 post-pass so the emitted SQL is loadable, by monkeypatching four more entry points |
| `_extract_comments_index_streaming.py` | 253 | |
| `_extract_conversations_index_streaming.py` | 264 | |
| `_extract_people_show_streaming.py` | 258 | |
| `_extract_notifications_index_streaming.py` | 290 | |
| `_extract_people_stream_streaming.py` | 398 | |
| `_extract_posts_show_streaming.py` | 357 | |
| `_c30_extract_par.py`, `_p35_extract_posts_show_{seq,par}.py` | 1 142 | |
| **total** | **3 579** | |

The six drivers are ~80 % identical to each other (measured: 83, 94 and 228
differing lines against the conversations one). Every one of them begins by
putting `_experiment/variant_d` on `sys.path` and calling
`assoc_fold.install()`.

## Why they existed, and why they no longer need to

All of it traces to one rule: **`src/` was not to be edited**, so every fold
repair was built as an in-process monkeypatch in a batch directory, and every
endpoint got its own copy of the driver that installs them. The folds are
generic — nothing in them is about diaspora — so they belonged in `src/`
from the start, and they are there now:

| was | is now |
|---|---|
| `assoc_fold`'s producer registration | `transform.RunTransformer.bind_producers` — a `symbolic_vars` note IS a producing query, so the bind is a join (README rule 3) |
| `assoc_fold`'s `StringVal` unwrapper | `pcs._SOLVER_STR_RE`, applied in `parse_pc` |
| `_blockaid_fold` E2 (principal `person_id`) | subsumed: the general recursion reaches `users.id = _MY_UID` through the recorded chain, with no rule about the word `person` |
| `_blockaid_fold` E5 (parenthesised OR) | already upstream in `_Build.assemble_where` |
| `_blockaid_fold` E8 (aggregates, LEFT joins) + E11 (count subquery) | `transform.RunTransformer._emission_conventions` (README rule 7) |
| six copies of the driver | `tools/extract_policy.py <endpoint>`; the only per-endpoint input is the corpus directory and `results3/<endpoint>/POLICY_HEADER.txt` |

`_blockaid_fold` E9 is deliberately NOT carried over. It BROADENED any bind
that was still unresolved — dropped its predicate — which hid the very defect
this work was about. An unresolved bind is now a declared finding
(`docs/BOUNDARY_NOTE_GAPS_20260915.md`) and a RED in
`audits/policy_loadability_audit.py`, not a silent widening.

## Nothing here has been deleted

`posts_show` has a LIVE campaign that owns `_p35_extract_posts_show_par.py`,
and the closed endpoints' files are their own historical record. These files
stay exactly as they are; this note records that new work should not use them.
`<endpoint>_loadable.sql` was produced with `extract_policy.py`; the canonical
`<endpoint>.sql` files were not touched.

---

## Postscript (2026-09-15, later the same day): the last driver is gone too

`tools/extract_policy.py` — the 168-line script this note was written about —
is **retired** (`tools/extract_policy.py.bak_pre_pcprune_20260915` keeps it).
Its pipeline is now IN the package, as four named stages of
`queries_from_runs.dump`:

```
extract_statements  ->  prune_conditions  ->  drop_subsumed  ->  render_policy
```

and its CLI is the package's own:

```bash
PYTHONPATH=src python3 -m queries_from_runs --results results3 \
    --out results3/queries_from_runs --endpoint <endpoint> [--no-subsume] \
    [--sample N --sample-seed S] [--suffix S]
```

Everything that made `extract_policy.py` a separate script is now either a
flag (`--sample`, `--sample-seed`, `--suffix`) or a file the package already
looks for beside the dumps (`POLICY_HEADER.txt`). Verified by differential:
the module CLI reproduces `comments_index --sample 300 --sample-seed 20260915`
statement-for-statement.

The nine files in the table above are still on disk, still untouched, and
still their endpoints' historical record. Removing them is a decision for the
owner, not for the agent that stopped needing them.
