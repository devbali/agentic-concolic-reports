# §93. THE CONFINEMENT GATE'S THROUGHPUT — CONCURRENCY IS ALREADY PAST ITS
# KNEE; THE LEVER IS THE JVM BOOT, AND `ACHK_PROBE_BATCH` 40 -> 200 MEASURED
# **2.5x** (1.067 -> 2.667 probes/s), 2026-09-14

*(This file is `_p33_gate_*`'s. It does not touch `_COMPLETION_20260910.md`,
which P32 owns; §93 is claimed here because the gate it re-launches is §90's.)*

The brief was: can `posts-p26-gate-v2-20260913` be made materially faster by
raising `CONCOLIC_PROBE_WORKERS` (2 when the cage was 4 GB; the cage is now
32 G), and if so restart it. **Measured answer: no — concurrency is already
past its knee.** But the same rig found the thing that IS the wall: a probe
launch is dominated by JVM+Rails boot, and at `ACHK_PROBE_BATCH=40` the boot
is 1.32 s of every 1.88 s probe. Batch 200 was launched as
`posts-p26-gate-v3-20260914` and is measured at **2.667 probes/s**.

---

## §93.1 THE RIG — THE SAME MACHINERY, NONE OF THE GATE'S FILES

`run_probe` is `<runner> ` with `SEEDS_ONLY=1`, `EXTRA_SEEDS_JSON=<40 roots>`,
`LABEL_SUFFIX=<token>`. The rig replays exactly that, with 40 REAL gate probe
roots lifted from a live `_achk*_batch*.json`, against a private copy of
`run_dse.rb` + `concolic_targets.rb` + `targets.rb` in a scratch directory —
`HERE` is the runner's own directory, so **not one dump landed in
`posts_show/`**.

Two deliberate choices:

- **It does NOT go through `reports/diaspora/tools/slot`.** That wrapper's
  locks are machine-wide (`/tmp/concolic-slot-N.lock`) and the running gate
  held them, so a rig that took them would have measured lock queueing and
  would have starved production. Bypassing it means the rig's N runners are
  strictly ADDITIVE to the gate's 2.
- Therefore the honest reading of each row is **total JRuby concurrency =
  rig workers + the gate's 2**, and the quantity that answers the brief is
  **rig probes/s + the gate's probes/s over the same window**. After a
  restart the gate alone at N workers is that same total concurrency N.

Everything ran in `--slice=concolic-cov.slice` under its own `MemoryMax`,
with a per-setting preflight (`free -g` >= 4 and slice headroom to
`MemoryHigh` >= 1.4 GB x workers).

## §93.2 THE CONCURRENCY TABLE (a "probe" = one root; every launch was
## 40 roots x 4 scenarios, i.e. exactly what the gate pays for one probe)

| setting | total JRuby conc. | rig probes/s | wall | mean launch wall | peak JRuby RSS (box / rig) | load1 mean/max | **gate probes/s during** | **TOTAL probes/s** |
|---|---|---|---|---|---|---|---|---|
| baseline: gate alone, w=2, batch 40 | 2 | – | 300 s | ~75 s | – | 9.4 / 9.8 | **1.067** | **1.067** |
| rig w=1 | 3 | 0.343 | 233 s | 116.5 s | 2.75 / 0.85 G | 12.6 / 13.5 | 0.687 (−36 %) | 1.030 |
| rig w=2 | 4 | 0.587 | 273 s | 135.8 s | 3.70 / 1.89 G | 13.9 / 15.2 | 0.587 (−45 %) | 1.174 (+10.0 %) |
| rig w=4 | 6 | 0.828 | 387 s | 191.9 s | 5.85 / 4.06 G | 19.3 / 22.6 | 0.414 (−61 %) | 1.242 (+16.4 %) |
| rig w=6 | 8 | NOT RUN | | | | | | |

`w=6` was refused by the rig's own preflight — slice headroom to `MemoryHigh`
was 8.0 G against a 8.4 G requirement — and the trend made it pointless:
**tripling the box's JRuby concurrency buys +16 % total throughput.** The box
is 4 cores at `0.0 id` with the other rounds running; each JRuby sits at
100-110 % CPU, so more of them only re-slice the same four cores. Peak slice
memory during `w=4` was 29.9 G against a 30 G `MemoryHigh` — the 32 G cage
does NOT make 6 workers affordable while the gate's own python holds 13-17 G.

**Cost to production while testing (03:34-03:57):** the gate ran at 0.41-0.69
probes/s instead of 1.067 — worse than the 15 % the brief allowed. That is
why phase B below was cut to ONE rig worker and `w=6`/`w=8` were dropped
rather than measured. Estimated production loss for the whole exercise:
~12 minutes of gate work.

## §93.3 THE LEVER THE SWEEP FOUND — A LAUNCH IS MOSTLY BOOT

All three rows at **one** rig worker, so they share a load and are a clean
differential:

| # | per launch | launch wall | s/probe | vs B1 |
|---|---|---|---|---|
| B1 | 40 roots x 4 scenarios (what the gate does) | 116.5 s | 2.91 | – |
| B2 | 40 roots x 1 scenario (`VARIANTS=auth_html`) | 94.5 s | 2.36 | 1.23x |
| B3 | 120 roots x 1 scenario | 120.4 s | 1.00 | 2.90x |

B2/B3 are two points on one line: **boot = 81.6 s, 0.324 s per root** (one
scenario) at that concurrency; B1 gives 0.873 s per root for four. Scale both
by the single factor that reproduces the gate's own measured 1.067 probes/s
at its own concurrency (x0.644): **boot 52.6 s, 0.562 s/root (4 scenarios),
0.209 s/root (1)**. The model then predicts the gate exactly:

```
   52.6/40 + 0.562 = 1.877 s/probe  ->  2 workers  ->  1.066 probes/s
   measured baseline                                   1.067 probes/s
```

so `boot/B + r` is the right shape, and **B is the free variable nobody had
turned**. Predictions at the gate's own 2 workers:

```
   batch  40  (v2)              1.877 s/probe    1.07 probes/s
   batch 200                    0.825            2.42        (2.27x)
   batch 400                    0.694            2.88
   batch 200 + one scenario     0.472            4.24
```

Two things that could have eaten the gain, both measured and both negligible:
`_load_dump_uncached` is **5 ms/dump** (152 kB mean), i.e. 0.8 s of python per
160-dump launch and 3.8 s per 800-dump one; and `run_probe`'s 900 s timeout is
never approached (a batch-200 launch is ~95 s of runner at the gate's
concurrency).

**`VARIANTS` was measured (1.23x) and deliberately NOT taken.** The manifest
has no `env_by_scenario`, so every probe launch runs all four scenarios and
throws three of them away (`exploration_summary.json`: auth_html 14.6 s,
anon_html 1.1, auth_json 12.1, anon_json 2.7). Restricting it is worth another
~1.7x on top of batch 200 — but it changes what a probe launch EXECUTES, and
its soundness ("the dump for scenario S is identical whether or not the other
three ran before it") is a dump-level differential nobody has run. It also
moves the manifest, hence the `cfg` digest, hence the 2.8 GB probe
checkpoint's header. Left as a costed follow-up, not taken on a hunch.

## §93.4 RESTART ARITHMETIC — AND WHY THE REBUILD WAS 17 MIN, NOT 60

At the stop the gate had **60 063** probe records and **51 3xx** probes left;
at 1.067 probes/s that is **13.4 h**.

The brief assumed the corpus digest had moved and budgeted ~30 min of
re-indexing. It had moved — but not because the corpus changed. The index
checkpoint's 232 523 keys diff against the directory as:

```
   in the checkpoint, gone from disk : 104     ALL of them dump_*_achkP30K_*
   on disk, not in the checkpoint    :   0
```

v2 indexed **104 stale P30K probe leftovers as corpus** at 18:32; they were
deleted afterwards, leaving the 232 419 real dumps. Not one genuine dump was
added or removed. Since index rows are keyed per dump BASENAME and a dump is
write-once, every row stays valid and the 104 rows for deleted files are
simply never asked for — so the index header's `corpus` field was repointed in
place, §90.4's technique, a same-length 32-hex swap:

```
   697da27b253bff8d60cd0b81a4e358c4 -> 934bb9a9dbc9bd1402af50ca36b0be54
```

(the other four header keys — `engine`, `batch`, `canonicalize`, `declared` —
were each recomputed and already matched). The **derive** checkpoint was NOT
repointed: `grep _achk` finds **9** records whose representatives NAME the
deleted dumps, so its records are genuinely stale. It rotated and re-derived
in 964 s against the clean corpus — which is the more correct answer anyway,
and cost 44 probes out of 111 285.

```
   stop -> first probe        17 min   (04:03:52 -> 04:21)
     corpus index               ~1 min (232 523 rows replayed; repointed)
     derive                    16 min  (rotated, 1363/1363)
     probe checkpoint           in the same window (2.8 GB, 60 063 records)
   had the index NOT been repointed:  +47 min
```

```
   remaining after the re-derive   51 556 probes
     at 1.067 probes/s (v2)         13.4 h
     at 2.42 probes/s (projected)    5.9 h
   saving                            7.5 h   against a 17 min rebuild
   ---
   for comparison, the concurrency options this round rejected:
     workers 2->4  (+10.0 %)        13.4 h -> 12.2 h   saves 1.2 h
     workers 2->6  (+16.4 %)        13.4 h -> 11.5 h   saves 1.9 h
   — the same order as one rebuild, and 2->6 does not fit in the cage.
```

## §93.5 WHAT WAS DONE

1. 300 s production baseline with nothing of mine running: **1.067 probes/s**.
2. Rig sweep (§93.2, §93.3). Nothing in `src/` was touched; no declaration,
   no extraction, no git.
3. `systemctl --user stop posts-p26-gate-v2-20260913`. The SIGTERM flush is in
   `_p26_gate_v2.log:892`:
   `[checkpoint] signal 15: flushed 60063 completed unit(s)` — and
   `wc -l _p26_achk_probes.ckpt.jsonl` = **60 064** = 1 header + 60 063. Match.
   The log's last batch was 820; 27 309 (v1) + 820x40 = 60 029 against 60 063
   written, the difference being duplicate `(scenario, seeds)` keys inside a
   chunk and the two launches in flight.
4. 104 stale `dump_*_achkP30K_*` and 13 orphaned `_achk*_batch*.json` seed
   files moved out of the batch dir to
   `results3/_p33_gate_stray_achkP30K_20260914/` (outside every endpoint dir,
   so no `dump_*` glob can see them). Corpus verified at 232 419 /
   `934bb9a9…` before the header was patched.
5. `_p26_gate_v3.sh` = `_p26_gate_v2.sh` with `ACHK_PROBE_BATCH` 40 -> 200, a
   v3 log, and the reasoning in its banner. **v2's script was not edited.**
   `CONCOLIC_SLOTS=2` and `CONCOLIC_PROBE_WORKERS=2` are unchanged — §93.2 is
   why. `ACHK_PROBE_BATCH` is not part of any checkpoint key (`ProbeCache`'s
   header is `engine`/`cfg`/`keep`/`phase`), so the probe checkpoint carried
   over with no repointing at all.
6. Launched, memory-preflighted (`free -g` 43; slice headroom 20.6 G):
   ```
   systemd-run --user --unit=posts-p26-gate-v3-20260914 \
       --slice=concolic-cov.slice -p MemoryMax=20G -p MemorySwapMax=0 --collect \
       /usr/bin/choom -n 1000 -- env CONCOLIC_SLOTS=2 CONCOLIC_PROBE_WORKERS=2 \
       ACHK_PROBE_BATCH=200 bash .../_p26_gate_v3.sh
   ```
   raised to `MemoryMax=24G` in place once probing showed 16.5-17.8 G (batch
   200 holds 800 dumps per launch instead of 160; slice stayed <= 30 G High).

## §93.6 VERIFIED WITHIN 15 MINUTES OF THE RELAUNCH

```
  [checkpoint] resuming ..._p26_achk_probes.ckpt.jsonl: 60063 completed unit(s) will be skipped
  [checkpoint] resuming ..._p26_achk_index.ckpt.jsonl: 232523 completed unit(s) will be skipped
  [checkpoint] DISCARDING stale ..._p26_achk_derive.ckpt.jsonl (input keys changed: corpus)
  [111241 distinct probes needed for 1363 assumptions]
  [probe checkpoint: 59685/111241 already recorded, skipped]
  [probe batch 1..11: 200 roots ... -> 200 dumps, 0 replayed singly, 200 matched]
```

- (a) **resumed, not restarted**: 60 063 records read back; 59 685 of them
  still wanted and skipped without a launch (378 belong to probes the
  re-derived set no longer asks for).
- (b) **`0 replayed singly` on 11 of 11 batches**, 200/200 matched — §90's fix
  still holds at 5x the batch size.
- (c) **rate 04:23:21-04:33:21, ten minutes: 1600 probes / 600 s =
  2.667 probes/s**, against 1.067 before. **2.5x**, and ahead of the model's
  2.42 — the box's background also lightened between the two windows
  (`p33-criteria` and `c20audits2` ended, a `p30passP31A2` pass started; load1
  9.4 -> 6.2-8.8), so read 2.42 as the load-matched figure and 2.667 as what
  the gate is actually getting. Peak unit memory 17.8 G of 24 G.

At 2.667 probes/s the ~49 700 probes left at 04:33 are **~5.2 h**, against
13.4 h on the v2 setting.

## §93.7 WHAT THE NEXT AGENT SHOULD KNOW

- **Do not raise `CONCOLIC_PROBE_WORKERS` on this box.** The table in §93.2 is
  the evidence; the ceiling is 4 cores, not the 32 G cage.
- **`ACHK_PROBE_BATCH` is checkpoint-free.** It can be re-tuned by stop +
  relaunch at the cost of the reload alone (~2 min now that index and derive
  checkpoints are both valid for this corpus) — batch 400 is worth a further
  ~1.19x if anyone wants it.
- **`VARIANTS` / `env_by_scenario` is the last big lever** (~1.7x on top of
  batch 200, taking the gate to ~4.2 probes/s). It needs (i) a dump-level
  differential showing a scenario's probe dump is identical run alone and run
  fourth, and (ii) a `cfg`-digest repoint of the probe checkpoint header, the
  §90.4 move. Both are cheap; neither was done here.
- The gate's `_run_chunk` loses a whole batch's work if a launch dies, so
  batch 200 raises that grain from 40 to 200 probes. It has not happened in
  11 batches.
