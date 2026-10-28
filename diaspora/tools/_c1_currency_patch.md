# C1 — the trace-currency fix for the three lean loaders (2026-09-13)

`docs/CONFINEMENT_PRECISION_20260913.md` §2. `notifications_index`,
`comments_index` and `conversations_index`
`coverage_report.py::fix_len_names` pops `note` and `args` off every event (a
2026-08-27 memory optimisation, written 15 days before §16c). The engine reads
`note`/`args` in exactly ONE place —
`coverage.py:2130  sh = call_shape(ev.target_name, ev.note, ev.args)` — so the
pops silently degenerate `call_shape` to the bare TARGET NAME, and the
footprint is not measured in the currency the assumption gate's `access_trace`
is tested in. `posts_show`'s loader keeps them and is unaffected.

## The change

In `fix_len_names`, delete the two pops. `traceback` may stay dropped: nothing
in `call_shape` reads it.

```diff
     for ev in dump.get("events") or ():
         e = ev.get("expr")
         if e and "len(" in e:
             ev["expr"] = _LEN_RE.sub(r"SYM_LEN_\1", e)
-        ev.pop("note", None)
-        ev.pop("args", None)
+        # C1 (2026-09-13): `note` and `args` are the OTHER TWO THIRDS of
+        # `concolic_engine.assumptions.call_shape`. Dropping them made the
+        # engine's §16c footprint currency the bare target name while the
+        # assumption gate's `access_trace` stayed on the full shape, and the
+        # two disagreed by 5.7x on notifications and 1.7x here. Measured cost
+        # of keeping them (this batch, 26 528 dumps, `share_run_objects`
+        # flyweight already in place): peak RSS 1 413 -> 1 451 MB, +2.7 %.
         ev.pop("traceback", None)
```

`sv.pop("note", None)` on `symbolic_vars` stays: `call_shape` never reads it.

## Measured, on the endpoints' own loaders

`tools/_c1_currency_cost.py --batch <dir> --snapshot <list> --mode
{today,keep,digest}` imports the endpoint's own `coverage_report` and runs its
own `canonicalize_ordinals` / `fix_len_names` / `apply_len_bounds` /
`share_run_objects` chain, so the numbers are the loader's, not a model of it.

| endpoint | dumps | mode | peak RSS | distinct `call_shape`s |
|---|---|---|---|---|
| comments_index | 26 528 | today | 1 413 MB | 13 |
| comments_index | 26 528 | **keep** | **1 451 MB (+2.7 %)** | **22** (= the gate's) |
| comments_index | 26 528 | digest | 1 431 MB (+1.3 %) | 22 (same SET) |

`keep` is affordable, so the digest is not needed. It is measured anyway
because the brief asked for a fallback, and it does reproduce the shape set
exactly — see the caveat below before using it.

## Why full retention, not a hash

A hash of the note is NOT a currency fix, whatever count it reproduces.
`CoverageResult.confinement_to_dict()` hands the footprints to the assumption
gate as `shape_str(...)` STRINGS, and the gate compares them against the
strings its own `access_trace` builds. A digest changes those strings and
breaks the handshake. The only cheap form that survives it is the one
`_c1_currency_cost.py --mode digest` measures: replace the note by its
`call_shape` NORMAL FORM (binds `$$(...)` -> `?`, string literals -> `'?'`,
which is idempotent under `call_shape`) and every arg value by a shared
sentinel of the same type. Even that has a caveat: the engine's
`AssumptionSet.apply_aliases` renames names INSIDE notes, and pre-wildcarding
removes the bind text an alias would have rewritten. On the three loaders this
is inert (they canonicalize ordinals at LOAD, before `fix_len_names`), but on
a batch that declares an `AliasAssumption` instead it is not. Full retention
has no such caveat.

## Status

* `comments_index` — applied (see `_RESTORED_20260913.md` §4).
* `conversations_index` — **applied 2026-09-26**, NOT on 2026-09-13.

  > **Correction, 2026-09-26.** This line previously read
  > "`conversations_index` — applied", with no date. **That was wrong**, and
  > it contradicted this document's own source: `docs/
  > CONFINEMENT_PRECISION_20260913.md` §8.1 says the patch
  > "**Landed in `comments_index` only** ... `conversations_index` is a closed
  > endpoint outside this work's scope and re-running it was not in budget."
  > §8.1 is the accurate one. Both pops were still live in
  > `results3/conversations_index/coverage_report.py` when the
  > 2026-09-19 -> 2026-09-26 full assumption gate ran, so that gate measured
  > §16c footprints on **22** shapes where its own `access_trace` measures
  > **48** — and it FAILed 71 of 113 confined pairs, 55 of them on clauses
  > (i)/(ii), which are a set difference of shape strings and therefore cannot
  > pass when one side carries SQL notes and the other does not. The 727
  > declared footprint entries of that run carry an empty note; under the fix
  > the same corpus yields 1012 entries of which 865 are noted, and the two
  > shape-identity sets are **disjoint**. The broken currency also
  > OVER-licensed: 113 pairs declared where the fixed measurement declares 94,
  > a strict subset.
  >
  > Cost of the fix measured on that batch's 18 633 dumps: peak RSS
  > 522 -> 610 MB (+17 %), load time unchanged.
  >
  > Anyone auditing a `conversations_index` result dated before 2026-09-26
  > should treat its confinement layer as measured in the wrong currency. Full
  > write-up, including why the endpoint's coverage verdict does not depend on
  > the §16c licence at all:
  > `results3/conversations_index/_C1_CURRENCY_FINDING_20260926.md`.

* `notifications_index` — **NOT applied**: `coverage_report.py` is the script
  the C21 pass is executing right now (pid 1617583), and a running script is
  never edited. The diff above is the whole change; whoever owns C21 should
  land it between passes. Until then the endpoint's §16c footprints are
  measured on 21 shapes where the gate measures 91, which is the first of the
  three reasons its gate refutes them at 76 %.

For a census that must not wait for that, `tools/confinement_census.py` now
takes `CONF_KEEP_NOTES=1`, which wraps the batch's own `fix_len_names` for the
duration of the census instead of editing it.
