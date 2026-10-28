# local_amc3 — `aspect_memberships_create`, drive 10

**Status: RAN 2026-10-14, all six stages. VERDICT: NOT CLOSEABLE** — the
engine half complete, the domain half blocked. Everything above the horizontal
rule was written before the drive started and has not been edited since.

## What this drive is

Drive 9 (`local_amc2`) got this endpoint's ENGINE half to complete — the lab's
first `complete: true`, with `blocking: []`, `missing_branches: 0` and
`assumptions_used: 6`. It did **not** close the endpoint: its certificate reads
`VERDICT=NOT CLOSEABLE`, the domain half blocked on two
`statement-shape/matched-under-another-target` items. Four
engine changes have landed since, three of which can move a verdict on exactly
the kind of assumption drive 9's engine half rested on. A result stands against the engine
that produced it, so this drive re-asks drive 9's question of the engine as it
is now.

Ground truth is held fixed on purpose: same world (`amc-world-2`), same plan
(`amc-real-2`), byte-identical and keeping their ids, and not one gate, audit,
timeout or limit changed in the config. The only mechanism difference in
`drive.py` is that `ENGINE_PIN` is declared and passed, because the comparison
it feeds did not exist when drive 9 ran. Anything that differs in the outcome
is therefore attributable to the engine.

## The four changes

| | change | bearing on this endpoint |
|---|---|---|
| assumption gate | a probe that never reaches the expression answers `NOT-TESTABLE` / `NOT-REALISED` rather than PASS, and no longer credits itself as one of the three witnesses the floor wants | **direct.** All six of drive 9's PASSes are `UntrackedPathAssumption`s on the non-principal `users.language` compares |
| assumption gate | `AliasAssumption` in `mode: "loop"` keys members on a variant family (`<VERB> OVER <sorted relation set>`); a set spanning more than one family FAILS instead of merging | none expected — no alias is declared here |
| domain layer | `principal_restriction_check`, static on both sides, so it reaches a comparison with or without a recording | **direct.** Expected to block |
| pre-gate | engine provenance is a measured content digest compared three ways; a tree that moves under the drive is refused | guards the drive rather than judging it |

## What it expects, written down in advance

1. **The domain half is expected to BLOCK, and that is the correct answer.**
   Against drive 9's own shipped policy, `principal_restriction_check` produces
   **four items over three of the 19 views** — the starkest being
   `SELECT people.* FROM people` with no `WHERE` at all — and `static_check.py`
   exits 1 with **six**, once the two pre-existing
   `statement-shape/matched-under-another-target` items are counted. The
   endpoint was already blocked by those two. The four new ones are the first
   this domain has produced at the predicate level, and each has two possible
   causes this drive does not prejudge: the fold lost the predicate, or the
   application's read really is unrestricted.
2. **The assumption gate may withdraw some of drive 9's six PASSes.** Whether a
   flipped probe on a `users.language` compare *arrives* at that compare is a
   question drive 9 never had to answer, because a non-arrival passed. If some
   do not arrive, those rows read NOT-TESTABLE, the coverage demand loses them,
   and `missing_branches` can rise off zero.
3. **So `complete: true` is not this drive's objective or its success
   criterion.** A drive that reports fewer assumptions and a non-empty blocking
   list has measured something true about an engine that no longer credits what
   it used to, and reporting that is the result. The failure mode to guard
   against is the opposite one: an unchanged `complete: true` obtained because
   the engine silently kept crediting a non-arrival.

## Running it

```bash
cd /home/dev/project/reports/autolab/local_amc3
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
unset JAVA_TOOL_OPTIONS
# stage 1, the agentic one, in the background; then the deterministic chain
$PY drive.py --stage batch --attempt 1
bash run_rest.sh
```

`src_new` is run-only here and is committed and clean at `962acb0` at this
drive's start; its digest is pinned in `drive.py` as `ENGINE_PIN`. If an edit
lands in that tree while the drive runs, the pre-gate refuses the attempt with
`moved_in_flight` — which is the point of the pin, and is what drive 9 could
only report after the fact.

---

## What happened

All six stages ran. `batch` 1580s, `check` 132s, `policy` 9s, `realmode` 37s,
`concrete` 339s. Four distinct boxes, asserted.

    [certificate] ENGINE=COMPLETE(0 blocking) DOMAIN=BLOCKED(1 blocking)
                  claims=13 VERDICT=NOT CLOSEABLE

### The engine half closed again, and this time it is known not to be vacuous

    coverage_complete  True        missing_branches  0
    assumptions_used   6           truncated         False
    corpus             417 runs    blocking          []

**Prediction 2 was wrong, and the reason is the useful part.** The six
declarations are the same `users.language` / `person.owner.language` family
drive 9's engine half rested on, and all six PASSED — but the gate detail says why they are
entitled to:

    [8 base(s) probed, 8 realising; 4 witness(es)/1 scenario(s),
     floor 3 of 4 available; PASS=8] access trace identical on both sides

**8 probed, 8 realising**, on every row, byte-identical to drive 9's rows. Every
probe ARRIVED at the expression. So drive 9's close never rested on a
non-arriving probe, and the new rule confirms it rather than overturning it.
The vacuous-PASS defect is real — it was measured on synthetic trees, where the
old code answers PASS on a non-arrival with a non-empty delta — but this
endpoint does not reach it. The open question "was drive 9's `complete: true`
bought with a vacuous pass?" now has a measured answer: **no.**

### The domain half blocked, exactly as predicted

`static_check.py` exited 1 with **six** items: the two pre-existing
`statement-shape/matched-under-another-target` rows, and **four**
`principal-restriction/unrestricted` rows over **three** distinct views —

    principal-restriction/unrestricted/people/041f9adc
    principal-restriction/unrestricted/users/041f9adc
    principal-restriction/unrestricted/people/41b606e7
    principal-restriction/unrestricted/people/6ea95655

the view `041f9adc` leaving two declared tables unrestricted and so counting
twice. Four items over three views is what the check measured against drive 9's
shipped policy before this drive existed, reproduced here through the real seam.
Each row has two possible causes and this drive does not prejudge them: the fold
lost the predicate, or the application's read really is unrestricted.

The static half also reports what it did NOT compare: **16 write statements**,
excluded because this domain is reads-only. The item count is over reads, so a
write the mocks mis-record is unmeasured here rather than absent.

### Provenance held, and step 4 ran for the first time

    [pregate] step 3: app tree digest 916d3937… matches the pin
    [pregate] step 4: engine digest 4ff15f8f… matches the pin and the tree
              this gate is running in; HEAD 962acb0…

`src_new` was clean at `962acb0` before the drive and clean at `962acb0` after,
and the three ground-truth files (`world.json`, `real_mode_plan.json`,
`<endpoint>_config.json`) were SHA-256 pinned before the batch agent started and
verified byte-identical afterwards. Drive 9 could only report a mid-drive engine
edit after the fact; this drive would have been refused.

### Real-mode capture is reproducible

10 scenarios, 99 statements, 6 scenarios recording an error — the same six, the
same errors and the same statement total as drive 9. Three are
`Redis::CannotConnectError` (no Redis on this host), one `I18n::InvalidLocale`
for the deliberate `xx` arm, one `RecordNotFound` for the deliberate missing
person, one `AssociationTypeMismatch` on `aspect-not-mine`. Pre-existing and
deterministic, not introduced here.

### Open, found by this drive

* **`EngineComparison.detail()` omits a separator.** `{where or ' '}` supplies
  one only when `where` is EMPTY; carrying a revision it has no trailing
  separator, so step 4 prints
  `…HEAD 962acb01a739276ea37ba53453dd09a0225e7376the drive ran the pinned
  engine throughout`. Cosmetic, in the success path only. Not fixed here:
  `src_new` is run-only on this campaign, and editing it would rotate the very
  digest this drive is pinned to.
* **Ground truth is inside the agent's writable root.** `settings.json` grants
  `Write(local_amc3/**)`, which covers `fixtures/` and `plan/`; only prose
  forbids the batch agent authoring the answer key. It did not touch them (the
  pin above proves it), but the next drive should deny those two paths
  explicitly rather than rely on the addendum.
* **13 claims** are this round's review items and are the closing agent's
  output, not verdicts: six `note-fidelity/*` (three `not-same-read`, two
  `overstated-write`, one `same-read/LIMIT-DIFF`), one
  `proposal/real-mode-plan/*` asking for dispatch arms that reach past
  `defer_dispatch`, and the six static items above.
