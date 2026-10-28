# P31 — STATUS AND THE EXACT RESUME COMMAND (2026-09-13, light phase)

**LAUNCHED 2026-09-13 19:55:07** (coordinator released the pause). The
confinement gate is relaunched as `posts-p26-gate-v2-20260913` (~1.1 probe/s,
CPU-bound, 12-13 GB) and **must never be stopped**; it is continuous, so it is
deliberately NOT a hold condition. What the round DOES hold on, polled every
2 minutes, is notifications' finite CLOSURE RECORD:

```
  notifications_index/_engine_section.py
  assumption_checker.py ...notifications_index   (NOT posts_show's own — that
                                                  IS the gate)
  _c7_audits                                     (the audit chain)
  coverage_report.py                             (ANY endpoint's pass)
  any notif-* systemd unit                       (its drives)
```

The cage's own memory gate is unchanged and still runs on every launch on top
of this (`_cage_hold_while_gate.sh` holds `concolic-cov.slice` at 24 G while a
gate unit is active; `gate_launch` needs free_avail >= cap+512M and
24 G - slice MemoryCurrent >= cap).

## THE ONE COMMAND

```bash
cd /home/dev/project/reports/diaspora/results3/posts_show
nohup bash _p31_round.sh > _p31_round.out 2>&1 &
```

It is idempotent and stage-skipping: a stage whose output is already on disk is
skipped, so a re-run after a kill costs only the unfinished stage. To force a
restart from stage *n*: `P31_FROM=n bash _p31_round.sh`.
Verdict lines: `P31-ROUND-DONE` / `P31-ROUND-FAILED <stage>`; watch with
`tail -f _p31_round.log`.

## PRE-LAUNCH CHECKS (the script does the first two itself; do them anyway)

```bash
pgrep -a python3 | grep -q "notifications_index/coverage_report[.]py" ; echo "notif pass: $?  (1 = clear)"
systemctl --user list-units 'notif-*' --no-legend | grep -c .   # 0 = no notif drive
free -g | sed -n 2p                                             # available >= 4
systemctl --user show posts.slice -p MemoryCurrent              # 24G - this >= 7G
```

## WHAT THE ROUND DOES, AND WHAT IT COSTS

| stage | what | cap | ~wall |
|---|---|---|---|
| S0 | hold while a notifications pass/drive is active | — | — |
| S1 | **round 8's OUTSTANDING pass** `P30B2` (§89.7's `NEXT`) | 7G | ~15 min |
| S2 | OR-refined census + §16f emission `P31A` on the new list | 7G | ~21 min |
| S3 | rebuild: bootstrap gaps → **fresh index** → gaps → **P31 construct** | 6G | ~10 min |
| S4 | **offline dry-check** — a violation ABORTS before the drive | <0.3G | ~1 s |
| S5 | drive `DRIVE_PAR=2 CONCOLIC_SLOTS=4` | — | ~7 min |
| S6 | explain per key — **the verdict of the round** | 4G | ~1 min |
| S7 | pass `P31A2`, §16e + §16f, W=3 | 7G | ~7 min |
| S8 | OR census `P31AB` — the residue for round 10 | 7G | ~21 min |

One heavy job at a time; the script never launches beside a notifications
pass or drive (`hold` is called before S2, S3, S5, S7 and S8 as well as at S0).

## THE TEST OF THE ROUND

Round 8 (`_p30_explain_P30B.json`): 187/569 walked, 84.8 % honoured,
**1 636 contradicted literals, 1 636 of them on the length gate**.
The base rule works **iff S6's contradicted column falls to ~0.** Nothing else
in the round decides whether the rule was right.

## WHAT CHANGED, AND THE EVIDENCE IT IS SOUND

`_p31_construct.py` — base choice is now a HARD FILTER (see its docstring):

* **HARD-1 emptiness pins.** Feasible for **569/569** gaps (`_p31_basecompat.py`,
  48 497 indexed bases; median 153 admissible bases, minimum 14).
* **HARD-3 enabling gates**, applied only where a base satisfying it exists —
  186/569 here; the whole shortfall on the other 383 is 1–2
  `as_api_response_<n>_row_guid` gates, every one of them SEEDABLE
  (`_p31_gapdiag.py`), so the base must REACH them, not already take them.
* **RANK-0 the gap's own round dump**, matched by node_constraint, used when it
  is at least as admissible as what the search found (round 8's dumps enter the
  index at S3, which is why the index is rebuilt).
* **determinism**: `api_members` returns a set and Python randomises string
  hashing per process, so the split layer gave 1 235 vs 1 207 split pins on
  identical inputs. Sorted; the seed batch is now a function of its inputs.
* **the exhausted split**, found by the dry-check and repaired: when two api
  reads bind two ordinals of the SAME canonical and both need it non-empty
  while the cube pins it EMPTY, the old split machinery flipped every ordinal
  and contradicted the cube's own literal by construction. One ordinal now
  always keeps the cube's state. 182 releases in 175 of 569 seeds.

Dry run on round 8's own demand (`_p31_construct_P31DRY.log`, 80 s, 206 MB):

```
  seeds whose base REALISES every cube emptiness pin :  569/569   round 8:  39/569
  seeds whose base WALKS every enabling gate         :  186/569   round 8: 176/569
  seeds admissible on BOTH                           :  186/569   round 8:  27/569
```

Reproduction control — every knob OFF (`P31_PIN_HARD=0 P31_GATE_HARD=0
P31_OWN_FIRST=0 P31_GROUP_GATES=0 P31_SPLIT_RELEASE=0`) reproduces round 8's
base choice EXACTLY: 244 groups, 70 distinct bases, the SAME base for 569/569
gaps, D1 bit on 125 groups / 3 959 352 bases rejected, 39 / 176 / 27.

`_p31_drycheck.py` (offline, no JRuby, re-derives every base's length state from
the base's OWN dump rather than from the index the filter read):

```
  P31-DRYCHECK-PASS  violations=0
  V1  569/569 bases realise every emptiness pin the seed assumes
  V1b 921 pins with every ordinal in the pinned state, 391 splittable,
      0 with no ordinal in it  (so the canonical-level filter is ordinal-sound)
  V2  0 manifests overstate the gates walked
  V4  0 seeds contradict the cube's own length pin on every ordinal (was 175)
```

## FILES

```
  _p31_basecompat.py  _p31_basecompat.json     the 569-gap base-compatibility census
  _p31_owndump.py     _p31_owndump.json        the gap's own round-8 dump, scored
  _p31_gapdiag.py     _p31_gapdiag.json        pins vs residual gates, per gap
  _p31_construct.py                            the constructor (HARD pin filter)
  _p31_drycheck.py    _p31_drycheck.json       the offline dry-check
  _p31_rebuild.sh  _p31_emit.sh  _p31_round.sh the round
  _p31_construct_P31DRY.log  _p15_manifest_P31DRY.json  _p15_seedsP31DRY_*.json
  _p31_pins_P31DRY.json                        the dry run's admissibility report
```

`src/`, `targets.rb`, the shared target boundary, `_p23_construct.py`,
`_p26_*`, `_p29_*`, `_p30_*` and everything under `notifications_index/` are
UNTOUCHED. `posts-p26-gate-20260913` was never stopped.
