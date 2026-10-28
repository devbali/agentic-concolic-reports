# §94. THE CONFINEMENT GATE'S SPEED — MEASUREMENT AND A POST-REBOOT PLAN
### written 2026-09-14 19:20 UTC, while `posts-p32-regate2-20260914` was stopped for the core upgrade

**Status: a PLAN, not an action.** Nothing was launched, nothing was
restarted, no setting was changed, `src/` was not touched. The gate was
stopped by the coordinator at 19:14:25 with a clean SIGTERM flush
(`[checkpoint] signal 15: flushed 75226 completed unit(s)`;
`wc -l _p32_regate_probes.ckpt.jsonl` = 75 227 = 1 header + 75 226 — match).
This file is what the next launch should be sized with.

---

## §94.1 STATE AT THE STOP

```
unit        posts-p32-regate2-20260914   18:19:40 -> 19:14:25   (54m 45s)
settings    CONCOLIC_SLOTS=2  CONCOLIC_PROBE_WORKERS=2  ACHK_PROBE_BATCH=200
            ACHK_BASES=8  cage MemoryMax=24G  checker md5 5ae1b13c
declared    243 classes, ALL of type ConfinementAssumption
stage 1     102 178 distinct probes needed for 243 assumptions
  carried in from the bank at launch      65 610
  completed this run (48 batches x 200)    9 600
  bank now holds                          75 226 records
  REMAINING STAGE 1                       26 968
batches     48/48 reported `0 replayed singly, 200 matched` — the batch path
            is healthy at B=200, no single-replay degeneration
```

The bank resumes. Verified in source, not assumed: the `ProbeCache` header
(`assumption_checker.py:1202-1208`) is keyed on
`engine` / `phase` / `cfg` / `canonicalize` / `keep` only, and the per-probe
key is `(scenario, json.dumps(seeds, sort_keys=True))` digested
(`ProbeCache._ck_key`, `:1214`). `PROBE_BATCH` is a class attribute read from
the environment at import (`:1168`) and appears in **no** key. **Changing
`ACHK_PROBE_BATCH` therefore costs nothing.** Changing the manifest does —
see §94.5.

---

## §94.2 THE MEASURED RATE — **3.5 probes/s**, not §93's predicted 2.42

Measured from the log's own ROOT counts (batch lines carry the root count
explicitly; the checkpoint record count is the same quantity and was used as
the cross-check), never from batch counts.

| window | span | roots | rate |
|---|---|---|---|
| clean sampler, 60 s ticks | 19:09:17 → 19:13:17, 240 s | 800 | 3.333 /s |
| whole probing phase | 18:28:43 → 19:14:25, 2 742 s | 9 600 | **3.500 /s** |

The long row is a ≥ 900 s window and it *includes* the bank-recall prologue
(65 610 records pulled from a 3.2 GB checkpoint before the first launch), so
it is a **lower bound** on steady state. The short row is consistent with it
inside its own quantisation (roots land 200 at a time, so a 240 s window
carries ±0.83 /s of granularity error). **Take 3.5 probes/s.**

I did not get the full 900 s of *clean* sampling the brief asked for — the
job was stopped for the reboot at minute 5 of that window. The 2 742 s
phase average covers the requirement and is the number quoted below.

> **§93's projection was 45 % low.** It predicted 2.42 /s at B=200 and the
> gate did 3.50. The model's *shape* (`boot/B + r`) is fine; its constant is
> not, because §93's ×0.644 calibration was taken while its own rig was
> loading the box. **Refit the constant after the reboot before trusting any
> projection in §94.4** — the shape survives a core change, the constant
> certainly does not.

Refit at the observed point (2 workers, 4 cores, B=200, 0.571 s/probe/worker),
scaling §93.3's unscaled one-worker lines by f = 0.4458:

```
  boot_eff = 36.4 s      r_eff = 0.389 s/root (4 scenarios)
                         r_eff = 0.144 s/root (1 scenario)
```

### Stage-1 projection at the settings it was stopped with

```
  26 968 remaining / 3.50 /s  =  7 705 s  =  2.14 h
```

---

## §94.3 STAGE 2 — **IT IS ~5 % OF STAGE 1, NOT A MULTIPLIER.** ≤ 5 103 probes.

This is the number nobody had sized, and the answer inverts the premise.
The fear was that 243 non-FAIL classes escalating to `ACHK_BASES=8` multiplies
102 178 by 8. **It does not**, and the reason is structural.

`run_declared` (`:3040-3085`) runs stage 1 at `_BASE_BUDGET=1` and stage 2 at
`_BASE_BUDGET=8` over everything stage 1 did not FAIL. All 243 are
`ConfinementAssumption`, so the test is `_test_confinement` (`:2029`):

```python
    bases = pick_bases_with(batch, [ea, eb])        # up to _BASE_BUDGET bases
    for sp, sd in bases:
        o = _confinement_composition(cfg, a, cache, {}, ea, eb, ...)   # <-- per base
        if cache.planning: continue
    ...
    # planning pass: enqueue the active probes' replays too   (:2146-2153)
    for who, e_, fp_, en_ in (("A", ...), ("B", ...)):
        _exhaustive_flip(...)          # <-- ONCE, OUTSIDE the base loop
        _constructed_route(...)        # <-- ONCE, OUTSIDE the base loop
```

* `_confinement_composition` makes **exactly 3** `cache.run` calls — the
  flip-A / flip-B / flip-both composition replays (`:2173`). That is the only
  base-dependent cost.
* `_exhaustive_flip` (`:1776`) and `_constructed_route` (`:1959`) are the
  expensive ones — one replay per profile representative
  (`ACHK_CONF_PROFILES` unset = ALL) and one per footprint shape with another
  producer. **Neither mentions `pick_bases_with`, `pick_snapshot_with` or
  `_BASE_BUDGET`** (checked by grep over both function bodies). They are
  functions of the decision and the corpus, exactly as the X12 comment at
  `:2091-2095` says. Stage 2 re-plans them and the ProbeCache serves every
  one from the bank.

So:

```
  stage 1 probes  =  3 x 1 x 243        +  actives   =  729    + 101 449 = 102 178
  stage 2 probes  =  3 x <=8 x 243      +  actives   =  <=5 832 + 101 449
  NEW in stage 2  =  3 x 7 x 243                     =  <= 5 103
```

and less than that in practice — pairs with fewer than 8 candidate bases in
the corpus get fewer, and identical seed dicts dedupe in the cache.

The derive log corroborates the split: the probe count went 3 021 → 92 537
between assumption 80 and 94 of 243, i.e. a handful of wide-footprint pairs
own ~90 % of the probes. Those are active probes. They are base-independent.
**They are already bought.**

### Stage-2 cost at the stopped settings

```
  <= 5 103 probes / 3.50 /s              = <= 1 458 s  = <= 24 min
  + stage-2 derive pass (re-plans 243)   ~   500 s     (stage 1's took 513 s)
  + stage-2 verdict pass                 ~  15 min     (CPU + dump loads, no launches)
  ------------------------------------------------------------------
  STAGE 2 TOTAL                          ~  45-50 min
```

**Size the new core count against stage 1, not stage 2.** Stage 2 is a
rounding error, and it is the one part of the job that more cores barely
touch (its derive and verdict passes are single-threaded python).

One thing stage 2 *does* change, and it matters for §94.5:
`pick_bases_with` is deliberately **scenario-diverse** after the first base
(`:1547-1555`). Every probe so far has been `auth_html`; **stage 2 will probe
`anon_html`, `auth_json` and `anon_json` too.** Any `env_by_scenario` map must
cover all four, and the differential must cover more than `auth_html`.

### Total remaining work, at the settings it was stopped with

```
  stage 1   26 968 probes                   2.14 h
  stage 1   verdict pass                  ~ 0.25 h
  stage 2   <=5 103 probes + 2 passes      ~0.80 h
  restart   rebuild (index ~1 min, derive 9-16 min, bank recall)  ~0.40 h
  ------------------------------------------------------------------
  TOTAL                                    ~3.6 h   at 4 cores / 2 workers
```

---

## §94.4 LEVER 1 — `ACHK_PROBE_BATCH` ABOVE 200. Worth ~+32 %. Ceiling +47 %.

Per-probe wall per worker is `boot_eff/B + r_eff` = `36.4/B + 0.389`.
Aggregate = `workers / that`. At 2 workers on 4 cores:

| B | s/probe/worker | probes/s | vs B=200 | share of the lever's total gain |
|---|---|---|---|---|
| 200 (as stopped) | 0.571 | **3.50** | – | – |
| 400 | 0.480 | 4.17 | +19 % | 41 % |
| 500 | 0.462 | 4.33 | +24 % | 51 % |
| **800** | **0.434** | **4.61** | **+32 %** | **68 %** |
| 1000 | 0.425 | 4.71 | +35 % | 74 % |
| 2000 | 0.407 | 4.91 | +40 % | 86 % |
| ∞ (boot free) | 0.389 | 5.14 | **+47 %** | 100 % |

**The whole lever is worth +47 % and B=800 already banks two-thirds of it.**
Everything past 800 is buying single-digit percentages against rising risk.

### Where the ceiling actually is — four candidates, only one binds

1. **`run_probe`'s 900 s `subprocess.run(timeout=900)`** (`:899`) — **this is
   the hard ceiling and it is in `src/`, frozen, do not edit it.** Launch wall
   ≈ `B x s/probe/worker`: B=200 → 114 s, B=1000 → 425 s, B=1500 → 632 s,
   B=2000 → **814 s, i.e. 86 s of margin on a 900 s kill.** A timeout is not a
   graceful degradation — the roots in flight are lost and re-run.
   **Hard cap B ≤ 1000** (425 s, 2.1× margin). On a faster box the per-root
   term shrinks and the cap rises, but re-derive it from the refitted model,
   do not assume.
2. **Memory.** A launch holds `4 x B` dumps (four scenarios) at ~152 kB mean.
   B=200 → 800 dumps ≈ 122 MB; B=1000 → 4 000 dumps ≈ 610 MB, per worker, in
   the JRuby *and* transiently in the checker's python. The checker's own RSS
   was 17.5 GB at 74 k bank records and grows ~58 kB/record (13.1 GB at derive
   done → 17.5 GB after recalling 65 610 + running 8 800), so it reaches
   **~19-20 GB by the end of stage 1** on its own. At B=1000 the transient
   launch load adds ~1.2 GB across 2 workers. The 24 G cage holds; a 24 G cage
   at B=1000 **and** more workers does not. See §94.6.
3. **Dump matching.** `_run_chunk` (`:1295-1302`) is `O(B²)` — for each of B
   roots it scans `found` (also ~B, since it is filtered to the one scenario)
   calling `seeds_as_written`. That function is a plain dict lookup
   (`:519-529`), so the constant is ~µs: 40 k comparisons at B=200, 1 M at
   B=1000, 4 M at B=2000 — seconds, not minutes. **Not the ceiling.** Also
   `_load_dump_uncached` is 5 ms/dump (§93.3), so 4 000 dumps = 20 s of python
   per B=1000 launch. Real but small against a 425 s launch.
4. **Checkpoint granularity.** A kill loses up to `B x workers` roots. At
   B=800 x 2 that is 1 600 roots ≈ 7 min. Acceptable; at B=2000 x 6 it is
   12 000 roots ≈ 40 min, which is not.

**Recommendation: `ACHK_PROBE_BATCH=800`**, and re-derive the cap from the
refitted model on the new box before going past it. Do not go to 2000.

---

## §94.5 LEVER 2 — `VARIANTS` / `env_by_scenario`. ~1.7×. **Now the one worth taking.**

The manifest (`assumption_manifest.json`) has no `env_by_scenario`, so
`run_probe` (`:884-890`) hands every launch the same env and **the runner runs
all four scenarios and the checker discards three.**
`exploration_summary.json`: auth_html 14.6 s, anon_html 1.1, auth_json 12.1,
anon_json 2.7. §93.3 measured the saving directly (B2 vs B1, one rig worker,
clean differential): 1.23× at B=40, and the per-root term drops
0.389 → 0.144 s, which is where the real money is as B rises.

| setting | s/probe/worker | probes/s @2w | vs 3.50 |
|---|---|---|---|
| B=200, 4 scenarios (as stopped) | 0.571 | 3.50 | – |
| B=800, 4 scenarios | 0.434 | 4.61 | 1.32× |
| B=200, 1 scenario | 0.326 | 6.13 | 1.75× |
| **B=800, 1 scenario** | **0.190** | **10.5** | **3.0×** |

It is now much more attractive than it was this morning, for the reason the
coordinator gave: **a restart is happening anyway**, so the 25-min rebuild is
already sunk and only the differential has to be paid for. (For the record,
the arithmetic *before* the reboot said "let it run": remaining probing was
~2.4 h, the batch lever alone saved ~37 min against a 25-min restart — under
the 2× bar — and only `VARIANTS`+B=800 cleared it, at the cost of a
differential that would itself have stolen ~36 % of the gate's throughput
while it ran and risked a 10 h bank on a header repoint. That trade has now
flipped, because the restart is free and the box is idle.)

### (a) What the dump-level differential must prove

Claim under test: **the dump the runner writes for scenario S is identical
whether or not the other three scenarios ran in the same launch.**

Rig: §93.1's, verbatim — a private copy of `run_dse.rb` + `concolic_targets.rb`
+ `targets.rb` in a scratch dir, `HERE` pointing at itself, **not**
through `reports/diaspora/tools/slot`. Not one dump may land in
`posts_show/`.

Inputs: real gate roots, not synthetic ones. Lift ≥ 2 x 200 roots from the
bank's own wanted set (or from a live `_achk*_batch*.json`).

Procedure, per scenario S in {auth_html, anon_html, auth_json, anon_json}:
run the same root set twice — once with today's env (all four scenarios),
once with `VARIANTS=S` — and compare the S dumps.

Three things must hold, and **the second is the one that can actually fail**:

1. **Per-dump equality.** Keyed on `seeds_as_written`, every field the checker
   consumes is identical: `concolic_seeds` / the raw-seeds key,
   `concolic_scenario`, the full `events` list (`path_condition` exprs and
   sides, `symbolic_call` `result_name`/`note`), and hence the derived
   `probe_record` and `access_trace`/`shape_str` set. Volatile fields
   excluded by an explicit allowlist only: wall timestamps, `LABEL_SUFFIX`,
   run ids, dump filename ordinal.
2. **Dump-SET cardinality and membership.** *This is the real risk and a
   per-dump diff will not catch it.* `_run_chunk`'s own comment (`:1305-1307`)
   says it: **"the runner writes a dump only for a NEW path signature"**. If
   path-signature novelty is tracked across the whole launch rather than per
   scenario, then dropping anon_html changes which signatures are new when
   auth_html runs, and the auth_html dump set changes — silently, and in the
   direction that looks like success (fewer roots "matched", more "replayed
   singly"). The differential must assert `200/200 matched, 0 replayed
   singly` **and** an identical set of dump basenames-modulo-suffix under both
   conditions. If it does not hold, the lever is dead — stop, do not take it.
3. **Cross-scenario independence in both directions.** Run at least
   `auth_html` (all probes so far) and one JSON scenario (`auth_json`, the
   other expensive one), because §94.3 says stage 2 will probe all four.

### (b) The `cfg`-digest repoint

Adding `env_by_scenario` to the manifest changes `_ckpt.digest(cfg)`, which is
the `cfg` key in the bank header. Untouched, the 3.2 GB / 75 226-record bank
is discarded — **~10 h to rebuild.** Repoint it, §90.4's technique:

```
  header line 1 today:  "cfg": "6efddfcc73612fd1f143b7c34e5abc3e"
  new value is another 32-hex string -> SAME-LENGTH in-place swap on line 1.
  No rewrite of the 3.2 GB file.
  Recompute and VERIFY the other four keys are unchanged first:
    engine       = _ckpt.source_hash(assumption_checker)   (src is frozen: must match)
    canonicalize = _canon_key()                            (gate_canon unchanged: must match)
    keep         = "False"
    phase        = "assumption_checker:ProbeCache"
  Compute the new cfg digest with the SAME code path the checker uses
  (_ckpt.digest on the loaded manifest dict), never by hand.
```

Soundness, and why the order matters: the bank's records are keyed on
`(scenario, seeds)` and hold the probe record derived from that scenario's
dump. **If and only if** the differential proves that dump is identical under
1 vs 4 scenarios, every existing record is exactly what a new-manifest probe
would produce, and reuse is sound. Repointing *without* the differential is
precisely the silent-stale-reuse hole the 2026-09-14 SOUNDNESS comment at
`:1178-1201` was written to close. **Differential first, repoint second, and
if the differential fails, neither.**

Also repoint nothing else: the **index** checkpoint is keyed per dump
basename and is unaffected; the **derive** checkpoint rotates on the corpus
key anyway (it did at 18:19:40 and will again, ~9-16 min).

### (c) What the manifest edit is

`assumption_manifest.json` lives in the batch dir — **report territory, not
`src/`.** No frozen file moves. All four scenarios must be named:

```json
  "env_by_scenario": {
    "auth_html": {"VARIANTS": "auth_html"},
    "anon_html": {"VARIANTS": "anon_html"},
    "auth_json": {"VARIANTS": "auth_json"},
    "anon_json": {"VARIANTS": "anon_json"}
  }
```

(confirm the runner's own spelling of the variable and of each scenario name
against `run_dse.rb` before writing it — §93.3 used `VARIANTS=auth_html`.)

---

## §94.6 `CONCOLIC_PROBE_WORKERS` AFTER THE REBOOT — the old verdict has expired

**§93.2's "concurrency is past its knee" was true of a 4-core box at 0 % idle
and of nothing else.** Its evidence — tripling total JRuby concurrency for
+16 % total, with the gate's own rate falling 36-61 % as the rig stole CPU —
is a statement about four cores, not about the workload. With more cores it
does not carry, and re-running the §93.1 rig is the first thing to do on the
new box.

What the workload is: each probe launch is one JRuby process measured at
**100-110 % CPU** while up, ~1.0 GB RSS at B=40 (§93.2: 4.06 GB total across
4 rig workers). It is boot (classload/JIT — CPU) plus per-root DB work (mixed
CPU and I/O waits). So it is *near* CPU-bound but not purely: a worker yields
during DB and GC, which is why workers may modestly exceed cores before the
box re-slices. Meanwhile the checker's own python is a **serial** consumer —
dump loading at 5 ms/dump plus the `O(B²)` match — and it needs roughly a
third of a core per worker at B=800.

Two caps; take the smaller.

```
  W_cpu  = floor(C - R)          R ~ 1.5 cores reserved
                                 (checker python 0.3-0.5 + one other round ~1.0)
  W_mem  = floor((cage_GB - python_peak_GB) / mem_per_worker_GB)
                                 python_peak ~20 GB at the end of stage 1
                                 mem_per_worker ~1.0 GB at B=200, ~1.3 GB at B=800
```

`W_cpu` is calibrated so that it reproduces the one point we measured: at
C=4 it gives 2, which is exactly where §93 found the knee.

| cores C | W_cpu | W_mem @ B=800, 32 G cage | **recommend** | note |
|---|---|---|---|---|
| 4 | 2 | 9 | **2** | the measured point |
| 8 | 6 | 9 | **6** | CPU still binds |
| 12 | 10 | 9 | **9** | crossover — memory starts to bind |
| 16 | 14 | 9 | **9** | **the 32 G cage binds, not the cores** |
| 32 | 30 | 9 | **9** | cage must rise to use the cores |

**The headline for whoever sizes the box: past ~12 cores the 32 G cage is the
constraint, not the core count**, because the checker's own python holds
~20 GB of probe records by the end of stage 1 and each worker wants another
1.0-1.3 GB. Buying cores past 12 without raising the cage buys nothing. If the
cage goes to 48 G, `W_mem` rises to ~21 and cores bind again.

Procedure on the new box, in this order:

1. `nproc`, `free -g`, and the slice's live `MemoryMax` / `MemoryCurrent`.
2. **Re-run §93.1's rig** at 1 worker, B=200 and B=800, one scenario and four,
   and refit `boot_eff` / `r_eff`. Do not reuse §94.2's constants — §94.2 is
   itself the proof that the constant does not survive a load change.
3. Take the `VARIANTS` differential (§94.5a) in the same rig session — the box
   is idle, which is the cheapest it will ever be, and the gate is already
   down so there is no production throughput to steal.
4. Launch with `ACHK_PROBE_BATCH=800`, `ACHK_BASES=8` (**never 1 — at 1 it
   reproduces the old single-base gate and the run is pointless**), the same
   `_p32_regate_NT.json` declared list and the same bank path, and
   `CONCOLIC_PROBE_WORKERS` from the table.
5. Copy the script, never edit the running one; launch under
   `systemd-run --user --no-block --unit=<new name> --slice=concolic-cov.slice
   -p MemoryMax=<cap> -p StandardOutput=file:<path>`; preflight `free -g` ≥ 4
   and (live slice MemoryMax − MemoryCurrent) ≥ cap.
6. **Verify within 15 minutes**: the log's `[probe checkpoint: N/102178
   already recorded, skipped]` shows N = 75 226-ish (the bank resumed; if it
   shows ~0, the `cfg` repoint is wrong — **stop and revert**), the first
   batches report `0 replayed singly`, and the new rate beats 3.50 /s. Any of
   those failing → revert to `ACHK_PROBE_BATCH=200` and no `env_by_scenario`.

### Expected total at a few post-reboot configurations

Remaining: 26 968 (stage 1) + ≤5 103 (stage 2) = **≤32 071 probes**, plus
~0.8 h of single-threaded derive/verdict passes that no lever touches and
~0.4 h of restart rebuild. (Scale the probes/s column by the refitted
constant — these use the 4-core fit and are therefore a *floor*.)

| config | probes/s | probe wall | + fixed | total |
|---|---|---|---|---|
| 4 cores, w=2, B=200, 4 scen (as stopped) | 3.50 | 2.55 h | 1.2 h | 3.7 h |
| 4 cores, w=2, B=800, 4 scen | 4.61 | 1.93 h | 1.2 h | 3.1 h |
| 8 cores, w=6, B=800, 4 scen | ~13.8 | 0.65 h | 1.2 h | 1.9 h |
| 8 cores, w=6, B=800, **1 scen** | ~31.6 | 0.28 h | 1.2 h | **1.5 h** |
| 16 cores, w=9, B=800, 1 scen | ~47.4 | 0.19 h | 1.2 h | 1.4 h |

Note what that last column says: **once the box has 8 cores, the fixed
single-threaded passes (~1.2 h) dominate everything.** Past 8 cores / 6
workers there is almost nothing left to win on the probing side, and the next
optimisation target would have to be the derive and verdict passes — which is
`src/` work and therefore out of scope.

---

## §94.7 WHAT WAS AND WAS NOT DONE

* **Done:** measured the rate from root counts over a 2 742 s window (§94.2);
  sized stage 2 from the source (§94.3) and found it is ≤ 5 103 probes, ~5 %
  of stage 1, not the several-fold multiplier it was feared to be; verified in
  source that `ACHK_PROBE_BATCH` is in no checkpoint key and the bank resumes
  across a batch-size change; established the batch-size ceiling and which of
  the four candidate limits actually binds (the 900 s `run_probe` timeout);
  costed the `VARIANTS` lever and written the differential and repoint it
  needs.
* **Not done, deliberately:** nothing was launched, restarted, or
  reconfigured; no rig was run; `src/` was not touched; the manifest was not
  edited; the bank header was not repointed; `notif-c29-pass-C29OFF1` was not
  disturbed. The gate was already stopped by the coordinator for the reboot
  before any of this could have been acted on, and the instruction was to
  stand down.
* **Open risk to carry across the reboot:** the gate is **stopped and not
  restarted**. That is deliberate and coordinator-directed, but it must not be
  forgotten — the bank at 75 226 records and the 102 178-probe stage-1 target
  are the state to resume from.
