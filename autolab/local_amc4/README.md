# local_amc4 — `aspect_memberships_create`, drive 11

**Status: NOT YET RUN.** Everything above the horizontal rule was written
before the drive started. The record of what happened goes underneath.

## Why this drive exists

Drives 8, 9 and 10 all certified `VERDICT=NOT CLOSEABLE`. Since drive 9 the
ENGINE half has come back complete, so every one of those was the **domain**
half — and it failed for a reason about the gate rather than about the
application:

| | |
|---|---|
| `static_check.py` | exited 1 on **any** review item |
| `sweep/binding.py::_static_gate` | reads that exit code and *"NOTHING HERE READS A REVIEW ITEM"* |
| `coordinator/driver.py` | the static conjunction *"is not a function of which individual claims a reviewer accepted"* |

So one item of any kind blocked the endpoint permanently and no acceptance
could clear it. Two of this domain's item classes are **undetermined by
construction** — `statement-shape/matched-under-another-target`, whose own text
says the expected cause is frame nesting and the shape IS recorded, and
`principal-restriction/unrestricted`, where a fold that lost a predicate and a
read that really is unrestricted produce the identical view. An item whose text
invites acceptance met a gate where acceptance is irrelevant. That is why no
autolab endpoint had ever closed.

## What changed, and where

Entirely in the domain layer, nothing outside it. `ReviewItem.blocking`
separates a determined failure from a claim the check cannot settle with the
inputs it has; `static_check.py` exits on the blocking items alone. An advisory
item is still written to `review_items.json`, still reaches the coordinator as
a claim to answer, and still prints under its own `ADVISORY` line. Determined
failures and missing inputs still block — *skipped is not passed* — and the
default is blocking, so a check added later gates unless its author says why
not.

Ground truth is held fixed as on every drive of this endpoint: world
`amc-world-2`, plan `amc-real-2`, byte-identical and keeping their ids. No
gate, audit, timeout or limit in the config has moved across the four drives.

## What it expects, in advance

1. **The domain half passes and the endpoint CLOSES.** Measured on drive 10's
   own artefacts before this campaign existed: the same six items, each
   advisory, zero blocking, exit 1 → **0**. If the chain still certifies NOT
   CLOSEABLE then the loosening did not reach the gate, and that is the finding.
2. **The six claims are still present.** Six rows in `review_items.json`, each
   `blocking: false`, reported by the concrete stage. **A close with the claims
   dropped is the failure mode to watch for** — it would mean they were hidden
   rather than declassified, and it would look identical in the certificate.
3. **The engine half is unchanged**: `complete: true`, `missing_branches: 0`,
   `assumptions_used: 6`, all six gate rows still "8 base(s) probed, 8
   realising". Nothing here touches `concolic/`, so a difference is a surprise
   to investigate, not a result.

## What a close here does *not* mean

Four `principal-restriction` claims stay outstanding, each with two causes this
drive does not prejudge: the fold lost the predicate, or the application's read
really is unrestricted. **If the second is true, this endpoint closes over a
real cross-principal read.** That is the declared trade of making an
undetermined claim advisory, and it is why the claims are carried rather than
discarded. Answering those four is the next piece of work, and it is a
`render.py` question before it is an application question.

## Running it

```bash
cd /home/dev/project/reports/autolab/local_amc4
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
unset JAVA_TOOL_OPTIONS
$PY drive.py --stage batch --attempt 1     # the agentic stage
bash run_rest.sh                            # pregate -> check -> policy -> realmode -> concrete
```

`src_new` is run-only here, committed and clean at `ed73ca6`; the domain edit
rotated the engine digest, so `ENGINE_PIN` in `drive.py` is this drive's own
measurement.

---

## What happened

*(added after the chain completes)*
