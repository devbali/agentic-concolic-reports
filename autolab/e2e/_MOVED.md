# Where round 1, `logs/`, `dryrun/`, `fixtrial*/` and `results/` went

**Nothing was lost.** On **2026-09-30** this directory's superseded report
layer was moved — intact and unmodified — to:

```
_trash/autolab_history_20260930/e2e/
```

(path relative to the project root, `/home/dev/project`).

| was here | is now at |
|---|---|
| `e2e/_round1/` | `_trash/autolab_history_20260930/e2e/_round1/` |
| `e2e/logs/` | `_trash/autolab_history_20260930/e2e/logs/` |
| `e2e/dryrun/` | `_trash/autolab_history_20260930/e2e/dryrun/` |
| `e2e/fixtrial/`, `e2e/fixtrial_v1_fix1only/` | `_trash/autolab_history_20260930/e2e/fixtrial/`, `…/fixtrial_v1_fix1only/` |
| `e2e/results/` | `_trash/autolab_history_20260930/e2e/results/` |

The move's own record — what was checked before each directory was moved, and
the list of things that deliberately STAYED — is
`_trash/autolab_history_20260930/_RETIRED.md`. It is intact: to get any of
this back, move it back.

Two things that `_RETIRED.md`'s table could be misread about:

* **`e2e/findings/` is still here**, and the copy under the trash tree is an
  OLDER version of the same two files (`AUTOLAB_GAPS.md`,
  `SRC_NEW_DEFECTS.md`) — they differ. **The live ones here are current**;
  the trash copies are history, not the originals.
* **`e2e/results_s6fix/` is not `e2e/results/`.** The retired `results/` is
  in the trash; `results_s6fix/` is later, separate work and was never
  moved.

**Also deliberately stayed** and still here: `e2e/runs/` (`corpus_root` in
four live queue configs), `e2e/fixes/` (161 of 161 scaffold `config.json`),
`e2e/tools/pipeline.py` (164 of 164 `stats.json`), `e2e/probes/`
(`entrypoints/lib/autolab_dse.rb`, which a live sweep loads).

---

**Why this file exists.** The `_RETIRED.md` above sits at the TRASH root, and
nothing at the SOURCE said where anything had gone. Two agents independently
read the resulting dangling paths as **data loss that had not happened**.
This pointer is here so that does not recur. Added 2026-10-03.
