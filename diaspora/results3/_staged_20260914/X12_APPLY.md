# X12 — multi-base derived tests: **MERGED** 2026-09-14 (was staged; approved by the coordinator)

LANDED. `src/end_to_end_completion_checker/assumption/assumption_checker.py`
md5 `c16805d221ed29ba069eb5af44174221` -> `5ae1b13ce1af73532e863c75e4a5b896`;
`src/test_multibase_gate.py` added (md5 `802c9d1148d8e7b181d49cb0595f470e`).
DISCIPLINE §17 carries the record and the measurements.

The probe banks keyed on the engine digest (posts_show `_p26_achk_probes.ckpt.jsonl`,
the notifications equivalents) are now stale and will be rebuilt on the next gate
run. The coordinator's ruling: that is not a real cost — the 08:40 verdicts are on
disk in `_p26_gate_results.json`, the bank was already stale from the 04:52/06:57
index edits and the name-boundary merge, and any re-gate should use the multi-base
test anyway.

## To revert

    cp reports/diaspora/results3/_bak_src_20260914/assumption_checker.py.pre_x12_20260914 \
       src/end_to_end_completion_checker/assumption/assumption_checker.py
    rm -f src/test_multibase_gate.py

## Verified before staging

* suite 391 -> 415 green (24 new tests, 0 regressions)
* end to end through the REAL `assumption_checker.py --declared` on
  people_stream's 30 declared assumptions:
  `ACHK_BASES=1` -> **0 verdict differences from the shipped gate**, one base
  probed per assumption; `ACHK_BASES=8` -> also 0 differences, with the
  evidence grade recorded (19 at 8 realising bases, 6 at 1).
  Cost: stage 1 = 51 distinct probes, stage 2 = 313 (6.1x on an
  independence-only gate, which has no base-independent probes to amortize).
* corpora unchanged: probe dumps are drained (`keep=False`).

`ACHK_BASES=1` is the old behaviour exactly, so the patch can land inert and be
turned on per gate run.
