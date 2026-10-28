# Where run 1, `results/` and `logs/` went

**Nothing was lost.** On **2026-09-30** this directory's superseded report
layer was moved — intact and unmodified — to:

```
_trash/autolab_history_20260930/shakedown/
```

(path relative to the project root, `/home/dev/project`).

| was here | is now at |
|---|---|
| `shakedown/_run1_20260925/` | `_trash/autolab_history_20260930/shakedown/_run1_20260925/` |
| `shakedown/results/` | `_trash/autolab_history_20260930/shakedown/results/` |
| `shakedown/logs/` | `_trash/autolab_history_20260930/shakedown/logs/` |

The move's own record — what was checked before each directory was moved, and
the list of things that deliberately STAYED — is
`_trash/autolab_history_20260930/_RETIRED.md`. It is intact: to get any of
this back, move it back.

**`shakedown/runs/` deliberately stayed** and is still here: it is pinned by
`targets/registry.json`, `tools/reconcile_with_app.py` and
`tools/build_inventory.py`.

---

**Why this file exists.** The `_RETIRED.md` above sits at the TRASH root, and
nothing at the SOURCE said where anything had gone. Two agents independently
read the resulting dangling paths — `REPORT.md`'s "Run 1 is preserved intact
at `_run1_20260925/`" among them — as **data loss that had not happened**.
This pointer is here so that does not recur. Added 2026-10-03.
