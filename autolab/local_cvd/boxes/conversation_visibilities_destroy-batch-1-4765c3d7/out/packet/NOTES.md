# NOTES — conversation_visibilities_destroy
- config digest: 2af5325b02ad492043f69e9b44b61229461c8278572adf0467872bc132aeb5bb
- runner: /home/dev/project/reports/autolab/entrypoints/scaffold/conversation_visibilities_destroy/run_dse.rb
- launcher: .../scaffold/conversation_visibilities_destroy/launch.sh
- targets: /home/dev/project/reports/autolab/targets/registry.json ; shims: .../targets/shared_shims.rb
- scenarios auth_html MAX_RUNS 24 TIME_BUDGET 300

## What was driven (2026-10-02)
- Baseline: MAX_RUNS=90 TIME_BUDGET=900. 18 runs, 7 distinct paths, worklist empty, terminals {I18n::InvalidLocale: 3}. That matches the measured baseline.
- Co-occurrence batch: EXTRA_SEEDS_JSON=<file> (NB: the driver reads a FILE PATH, autolab_dse.rb:1118, not inline JSON; inline JSON is silently ignored), SEEDS_ONLY=1, LABEL_SUFFIX=_cooc. Five seed dicts (cooc_seeds.json), giving 5 runs and 5 paths.

## The 4 inferred ConfinementAssumption pairs: what each dump RECORDS
Path_condition exprs per dump (corpus_index):
- pair 1, count==1 & lang=='pl': recorded by baseline dse0001, 0005, 0008 and cooc0001 (cooc0001 seeds set both dimensions).
- pair 2, count==1 & lang=='xx': recorded by baseline dse0001 (seeds {}) and dse0005. Seeding lang='xx' ends at I18n::InvalidLocale before the count decision, so cooc0002 does not record count. The only bases are the unseeded or count-seeded runs.
- pair 3, count==1 & not_found==True: recorded by baseline dse0001, 0005, 0008 and cooc0001.
- pair 4, lang=='pl' & not_found==True: recorded by baseline 0001, 0002, 0004, 0005, 0007, 0008 and cooc0001, cooc0003, cooc0004, cooc0005.
So co-occurrence was never missing: the preflight batch's own dump 0001 already records all four exprs.

## Why the gate still says "no run records both": a reader defect (escalated)
concolic/corpus/index.py:_index_row:75 indexes canon(ev['expr']). The dumps now carry STRUCTURED IR, so that is str(dict) = "{'op': '==', ...}". concolic/gate/replay.py:pick_bases_with looks up the infix text "(SYM_... == 1)". The two never match. Measured: pick_bases_with returns [] for pair 1 on both this batch and preflight/batch. No exploration can move these rows, and the fix belongs in src_new, where I am denied writes. Escalated as ctl/ask/confinement-index-ir-mismatch.json (no answer at submit time). The rows are left UNSETTLED. Nothing was dropped or re-declared.

## Manifest paths (escalated, ctl/ask/manifest-relative-batchdir.json)
I followed the brief: batch_dir and DUMP_OUT are in/packet/dumps. The concern: the assumption_cmd runs with cwd = completion.workdir (/home/dev/project), and run_probe writes seed files into batch_dir, which is read-only on the check box.

## assumptions.json = []
Worklist exhausted and tree complete, so there is no licence to claim. Validator: ok.

## Shims
22 keys from shim_extractor.rb. NOTE: it needs LANG=C.UTF-8; under a US-ASCII locale it crashes with "invalid byte sequence" (shim_extractor.rb:35).
shim_tests.rb is carried over from the posts_destroy packet (local_cc), whose boundary files (core.rb + shared_shims.rb) and key set are the same. I re-ran it HERE with shim_test_runner.rb: 10 PASS and 12 PROTOCOL, 0 NO-TEST, 0 FAIL (batch/shim_results.json).
