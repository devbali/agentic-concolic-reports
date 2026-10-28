# posts_show — post-gate re-extraction + benchmark recipe, and what blocks it

Researched 2026-09-25 from the closed endpoints' own scripts and logs. Every
command below is quoted from a file on disk, not reconstructed.

**Nothing here runs until the gate returns a genuine `complete:true`.**

---

## 0. THE FOUR THINGS THAT NEED AN OWNER DECISION

### (a) The §B1 gate is mechanically met but SUBSTANTIVELY not

`reports/diaspora/docs/TODO.md` §B1 (owner instruction, 2026-09-15):

> **B1. Run `policy-extraction-bench` once ALL SIX endpoints have a policy.**
> Do NOT do any of this before the gate is met.
> *The gate:* all six diaspora endpoints have an extracted policy —
> `people_stream`, `comments_index`, `conversations_index`,
> `notifications_index`, `people_show`, `posts_show`.

and its own caution:

> *"an incomplete policy benchmarked as if complete is a meaningless number"*

All six `.sql` files exist, so by the literal criterion the gate is OPEN. But
**three of the six are not fit to benchmark as-is**:

| endpoint | .sql date | problem |
|---|---|---|
| posts_show | Sep 15 20:05, 119 views | extracted from the **B-4-invalid** corpus — this is what P47/P48 is regenerating |
| comments_index | Sep 23 15:22, **227 views** | **`subsume_ran:false`** — `_summary_comments_index.json` records *"subsumption check failed: TimeoutExpired … timed out after 3600 seconds"*, 0 views dropped. See (b). |
| people_show | Sep 22 23:10 | SET ASIDE, known Class-S gap (T2): no `users` statement though the endpoint reads users; `identity_symbolicity_audit` RED, so signed-in views carry literal ids instead of `_MY_UID` |

### (b) comments_index was silently re-extracted and is NOT what its REPORT.md says

This is the most serious incidental finding and it is **not a posts_show
problem** — raising it because it would poison any union number.

* `comments_index.sql` is dated **Sep 23 15:22** and holds **227 views**.
* Its closure is documented at **79 views** (2026-09-01) and `REPORT.md` still
  reads as if 79 is current.
* The Sep-23 file shipped with **`subsume_ran: false`** after a 3 600 s
  subsumption timeout — i.e. **no views were dropped**, which is exactly why
  227 > 79.
* **No log, no driver script and no closure document records who re-extracted
  it on Sep 23, or why.** It was not possible to determine this from disk.

A union built on this counts ~148 views that a completed subsumption pass would
have proven redundant. Subsumption is conservative (null = timeout = KEPT), so
this is not unsound — but it is not the closed artifact either.

### (c) My inherited numbers were stale — corrected

| claim carried in memory | actual |
|---|---|
| comments_index "79-view policy" | true on 2026-09-01; the shipped file is now **227** (see (b)) |
| comments_index "84 vs 94" | those are coverage-tree **NODES**, not views (`REPORT.md:56`) |
| people_stream "162-view policy, 51 null kept" | true 2026-09-11; now **96 views with ZERO undecided** — `people_stream/POLICY_HEADER.txt:44-47` says so; alias hashing changed the distinct-view count |

### (d) `POLICY_HEADER.txt` is a BLOCKING deliverable, not a formality

`results3/posts_show/POLICY_HEADER.txt` (35 927 B, Sep 15 21:48) still opens
**"THIS ENDPOINT IS NOT COMPLETE"**, cites `MISSING=706`, and describes html-arm
gaps that no longer exist. The extractor splices it onto the top of the `.sql`
on **every** run, and its own opening states the rule:

> "Under the M-17 resolution (comments C12), the declaration IS the safeguard:
> a policy file that simply stops at a wall is indistinguishable from one that
> covers everything, so every exclusion is stated HERE, not only in a report."

---

## 1. THE BASELINE TO BEAT — posts-show has been graded before

`policy-extraction-bench/results/agent-incomplete.{jsonl,graded.jsonl,blockaid.jsonl,NOTES.md}`,
committed `b344261` (2026-09-19, snapshotting the 2026-09-15 policies). Its
`diaspora/posts-show` row:

| metric | value |
|---|---|
| statements predicted / reference | 119 / 93 |
| disclosure precision / recall / f1 | **0.8345 / 0.6402 / 0.7246** |
| table precision / recall | 1.0 / 0.75 |
| missed tables | aspects, contacts, conversation_visibilities, roles, services, users |
| Blockaid written / loadable | 119 / **78** |
| Blockaid precision / coverage | 0.1818 (20 allow / 90 deny / 9 error) / 0.4086 (38/93) |

**Do NOT overwrite these files** — they are the committed historical record.
Use a new run label. A v2 result is only meaningful *against* this.

---

## 2. ORDERING

```
gate complete:true
  -> Phase 3 fold audits ON DUMPS
  -> skipped_pcs_audit BOTH ways (mandatory pre-flight, see §4)
  -> extraction DRY   (SKIP_SUBSUME=1 — proves the scan and the view count)
  -> extraction FULL  (solver)
  -> policy_loadability_audit (F7)
  -> POLICY_HEADER.txt rewrite
  -> candidate JSONL
  -> bench.grade
  -> [optional] blockaid_sweep
  -> rebuild union -> sweep union
```

RUNBOOK ops invariant: *"extraction later in a FRESH unit (page-cache cgroup
accounting)."*

---

## 3. RE-EXTRACTION

Output goes to `results3/queries_from_runs/`, **not** the endpoint dir.

posts_show already has a launcher, `_p35_extract_ship.sh`:

```bash
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
Q=/home/dev/project/reports/diaspora/results3/queries_from_runs
. "$B/_cage.sh"
cd /home/dev/project
export QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json
V=/home/dev/project/venvs/queries_from_runs/bin/python
cage p35ext2.scope 20G env QFR_APP_CONFIG="$QFR_APP_CONFIG" \
  EXTRACT_WORKERS=6 EXTRACT_CHUNK=500 SUBSUME_SOLVER_THREADS=6 \
  JAVA_TOOL_OPTIONS= PYTHONPATH=/home/dev/project/src \
  $V -u $Q/_p35_extract_posts_show_par.py > "$L" 2>&1
```

### ⚠ IT DOES NOT SET `DUMP_LIST` — it globs the live dump dir

`_p35_extract_posts_show_par.py:161` reads `DUMP_LIST`; absent, it globs. For
v2 this MUST be set, to `_snapshot_v2_20260925.txt`. Copy the notifications
guard rather than defaulting it (`_c30_extract.sh`):

```bash
LIST="${DUMP_LIST:?DUMP_LIST is REQUIRED — refusing to guess a corpus}"
```

**Do not extract from `_snapshot_pruned_P44FRESH2.txt`** — that is the
invalidated corpus.

### Env knobs (`_p35_extract_posts_show_par.py`)

| var | line | note |
|---|---|---|
| `QFR_APP_CONFIG` | — | REQUIRED, `reports/diaspora/queries_config/app.json` |
| `DUMP_LIST` | :161 | the v2 snapshot |
| `OUT_SQL` / `OUT_SUMMARY` | :98/:99 | default `posts_show.sql` / `_summary_posts_show.json` |
| `SKIP_SUBSUME=1` | :259 | the DRY run — scan only, no JVM |
| `QUERIES_OUT` | :228 | deduped query list + flags |
| `SUBSUME_CACHE` | — | a rerun skips the ~42 min JVM pass |
| `SUBSUME_SOLVER_THREADS` | — | default 4; use 6; **never above 6 without watching RSS** |
| `SUBSUME_TIMEOUT_MS` | — | default 3000 — **DO NOT CHANGE, it changes verdicts** |
| `BLOCKAID_NORMALISE=1` | :52 | leave UNSET |

Thread count never changes a verdict; `SUBSUME_TIMEOUT_MS` does. Subsumption is
conservative: null = timeout = KEPT, only proven pairs drop.

### Promote CONDITIONALLY (people_stream's `_x7_subsume_when_free.sh`)

Take a dated backup, then overwrite only on proof the solver ran:

```bash
if grep -q "subsume_ran=True" "$LOG"; then
  mv $Q/posts_show.sql.subsume        $Q/posts_show.sql
  mv $Q/_summary_posts_show.json.subsume $Q/_summary_posts_show.json
fi
```

This is precisely the discipline comments_index's Sep-23 file did not get.

### Missing arm

`posts_show_pcfold3_base.sql` / `_pcfold3_fix.sql` **do not exist** — posts_show
is the only endpoint without the pcfold3 arm, and `_pcfold3_fix.sql` is exactly
the arm the 2026-09-19 graded run used for the other four. Builder:

```bash
$Q/_pcfold3_parallel.py --endpoint posts_show --dumpdir <v2 dump dir> \
    --out-dir $Q [--shards N] [--cap 2]
```

---

## 4. MANDATORY PRE-FLIGHT — `skipped_pcs_audit` BOTH ways

RUNBOOK / comments C12 (2026-09-01): run it vanilla **and**
`--patched .../_experiment/variant_d`, and install the patch if they differ.
Measured on cycle-12 corpora: comments_index parsed 575 447 / **DROPPED 73 461**
→ RED, patch REQUIRED; conversations_index dropped 0 → pass.

posts_show records the same `(VAR == VAR(_))` StringVal shape (STI `posts.type`,
`users.language` locale arms), so **variant_d/assoc_fold is already hard-installed**
at `_p35_extract_posts_show_par.py:74-75`. **Keep it.** Extracting without it
silently drops recorded constraints and still looks green.

## 5. F7 loadability audit, after extraction

```bash
PYTHONPATH=src /home/dev/project/venvs/queries_from_runs/bin/python \
  /home/dev/project/src/queries_from_runs/audits/policy_loadability_audit.py \
  /home/dev/project/reports/diaspora/results3/posts_show \
  /home/dev/project/reports/diaspora/results3/queries_from_runs/posts_show.sql

python3 /home/dev/project/reports/diaspora/tools/policy_loadability.py \
  /home/dev/project/reports/diaspora/results3/queries_from_runs/posts_show.sql
```

Both go RED without `QFR_APP_CONFIG` exported.

---

## 6. BENCHMARK

`diaspora/posts-show` is a **task_id**, not a directory.
Reference: `policy-extraction-bench/data/answers/diaspora/posts-show.sql`
(93 statements, difficulty hard). **Never write to `data/answers/`.**

**Step A — candidate JSONL.** ⚠ *No committed script writes a single-endpoint
row.* `scripts/policy_to_jsonl.py` is app-level only; the per-endpoint rows used
for the graded runs are untracked and were built ad hoc. ~15 lines of Python;
the field contract is:

```
run, task_id ("diaspora/posts-show"), app ("diaspora"), answer_sql (whole .sql text),
source_file, source_path, source_sha256, source_mtime, is_model_run:false,
mode:"concolic", model:"concolic-engine", method:"program analysis: …",
run_label, header_stripped:true, n_statements, n_reference_statements, status_caveat
```

Strip the POLICY_HEADER block with the benchmark's own
`bench.sqlnorm.split_statements`, asserting the SELECT count is unchanged.

**Step B — grade** (seconds, no JVM, no sqlglot):

```bash
cd /home/dev/project/policy-extraction-bench
python3 -m bench.grade /abs/path/<run>.jsonl
make check     # selftest; the oracle must score 1.0
```

Headline metric is `disclosure_*` over `(table, column)` pairs with `t.*` expanded.

**Step C — Blockaid containment** (heavy). Env first:

```bash
export JAVA_HOME=/home/dev/opt/micromamba/root/envs/blockaid
export PATH=$JAVA_HOME/bin:$PATH
export BLOCKAID_HOME=/home/dev/.blockaid-bench/blockaid
export BLOCKAID_SOLVERS=/home/dev/.blockaid-bench/solvers
export BLOCKAID_DRIVER=/home/dev/.blockaid-bench/driver
export BLOCKAID_CP=/home/dev/.blockaid-bench/cp.txt
```

```bash
scripts/blockaid_check.sh diaspora <candidate.sql> <reference.sql>
python3 scripts/blockaid_sweep.py results/<run>.jsonl \
    --desugar --solve-timeout 120000 --jobs 6 --shards 8 --timeout 14400
```

*GOTCHA:* `scripts/blockaid/README.md` documents `blockaid_check.sh` as
`<reference> <candidate> <app>`; the script is actually
`APP="$1"; CAND="$2"; REF="$3"`. **The script is authoritative.**

Both directions are sound LOWER bounds (a DENY means "not proven compliant").
Control: the answer key scores 0.999/0.999 against itself at 120 s.

**CLOSED — do not attempt:** `python3 -m bench.containment`. 15 min of 100 % Z3
on the cheapest task with no result; its `--max-statements` default of 60 exists
to refuse policies of our size. Lowering `--timeout` was deliberately NOT done:
UNKNOWN statements are *excluded* rather than counted, so the score would look
clean while covering only the easy statements.

**Step D — union** (B1 step 2), `/home/dev/project/scripts/app-union-pipeline.sh`:

```bash
cd /home/dev/project/policy-extraction-bench
python3 scripts/build_union.py diaspora --jobs 32 --minimize-timeout 20000
python3 scripts/blockaid_sweep.py results/union/jim.jsonl \
    $(ls results/union/*.jsonl | grep -v -E '\.blockaid|/jim\.jsonl') \
    --checker diff --desugar --solve-timeout 120000 --jobs 6 --shards 8
python3 /home/dev/project/scripts/derive_containment.py results/union
```

Existing union: `results/union/concolic-engine.jsonl` (170 257 B, Sep 15 17:19);
last measured 542 distinct → 448 after Blockaid minimisation. Budget HOURS.

---

## 7. NON-NEGOTIABLES

* **`JAVA_TOOL_OPTIONS` must be UNSET** — `unset JAVA_TOOL_OPTIONS` at script
  top AND `JAVA_TOOL_OPTIONS=` in the env line. A leaked value breaks the JVM
  run; enforced at `tools/blockaid_coverage.py:41`,
  `tools/policy_loadability.py:52`,
  `src/queries_from_runs/audits/policy_loadability_audit.py:81`.
* Python: `/home/dev/project/venvs/queries_from_runs/bin/python`
  (sqlglot 30.16.0, z3-solver 5.0.0) with `PYTHONPATH=/home/dev/project/src`.
  Plain `python3` is fine for `bench.grade`.
* `timeout N systemd-run --user --scope …` does **not** bound the work.
  Stop by `systemctl --user stop <exact unit>`. **Never `pkill -f`.**
* Prefer `--no-block --unit=` with `StandardOutput=file:` over `--scope`: a
  `--scope` client is killed with the session that launched it (two hour-long
  jobs were lost this way on 2026-09-13).
* `ruby_examples/dse-apps/policies/` is QUARANTINED; `app.json`'s
  `cli.reference_dir` is null on purpose.

### Resource settings actually used

| job | cap | knobs |
|---|---|---|
| posts_show extraction | **20G** | workers 6, chunk 500, solver threads 6. Measured 5 308 s over 236 997 dumps; a first attempt died **rc=137 OOM at 4 922 s**, hence 20G |
| people_stream extraction | 6G solver / 2G `SKIP_SUBSUME` | |
| notifications extraction | 8G syntactic / 12G solver | chunk 200, `MemorySwapMax=0`, `choom -n 1000` |
| blockaid_sweep (union) | — | `--jobs 6 --shards 8 --solve-timeout 120000 --timeout 14400`; each PolicyCheck is its own JVM |

---

## 8. STALE posts_show ARTIFACTS TO REGENERATE

Nothing in `results3/posts_show/` is itself an extraction output — extraction
writes to `results3/queries_from_runs/`. The endpoint dir holds the launcher,
its logs, the header and the cage.

In `results3/queries_from_runs/` (all from the B-4 corpus):

```
posts_show.sql                     Sep 15 20:05  67,857 B  119 views  STALE
_summary_posts_show.json           Sep 15 13:14   6,328 B             STALE
posts_show_loadable.sql            Sep 15 20:20  68,242 B             stale
posts_show_pcfold.sql              Sep 16 01:48  70,454 B             stale
posts_show_pcfold2.sql             Sep 16 06:30  71,290 B             stale
posts_show_pcfold3_{base,fix}.sql  DO NOT EXIST — the missing arm
```

In `results3/posts_show/`:

```
POLICY_HEADER.txt            Sep 15 21:48  MUST BE REWRITTEN (see §0d)
_p35_extract_ship.sh         reusable, but ADD DUMP_LIST
_snapshot_pruned_P44FRESH2.txt  THE INVALIDATED LIST — do not extract from it
_snapshot_v2_20260925.txt       165,423 dumps — THE LIST TO USE
```

---

## 9. STATED UNKNOWNS (not guessed)

1. No committed script writes a single-endpoint bench candidate row — it must
   be written (~15 lines; contract in §6 Step A).
2. Who re-extracted comments_index on 2026-09-23 and why is **undetermined** —
   no log, no driver, no doc.
3. Whether `results/union/concolic-engine.jsonl` covers all six endpoints or
   the five that had policies on Sep 15 was **not verified** (its size matches
   `agent-incomplete.jsonl` exactly, suggesting six, but the file was not
   opened).
