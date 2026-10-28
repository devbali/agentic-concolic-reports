# NOTES — conversation_visibilities_destroy, drive 3 attempt 1
- config digest: f87df0c3c85f7457eb8a0c3731f53929534419a973896d5a821a5d798dd20fe7
- runner: /home/dev/project/reports/autolab/entrypoints/scaffold/conversation_visibilities_destroy/run_dse.rb (launch.sh beside it)
- targets: /home/dev/project/reports/autolab/targets/registry.json ; shims: .../targets/shared_shims.rb
- scenarios: MAX_RUNS 24 / TIME_BUDGET 300
- no in/response.json, no in/denials.json -> attempt 1 (baseline)
- completion.batch_dir = local_cvd3/layer/conversation_visibilities_destroy/batch (NOT box batch/; empty at start)

## What was driven (attempt 1, baseline — no response.json / denials.json present)
- Default invocation of launch.sh (MAX_RUNS=24, TIME_BUDGET=300, DUMP_OUT=batch/dumps): 18 runs, 7 distinct paths,
  worklist empty: true, run errors {}, terminals {"I18n::InvalidLocale"=>3}. Same shape as drive 2.
- Dumps kept: dump_auth_html_dse000{1,2,3,4,5,7,8}.json, copied to batch/ top level, to out/packet/dumps/, and to
  completion.batch_dir (local_cvd3/layer/conversation_visibilities_destroy/batch). The config's audits scan that
  directory, and it is not this box's batch/.
- assumptions.json = []. The worklist is exhausted and the tree is complete, so no licence not to explore is needed. Validator: ok.
- shim_tests.rb: copied byte-identical from drive 2. Re-verified here against the extractor's 22 keys:
  10 PASS + 12 PROTOCOL, 0 red.
- assumption_manifest.json: drive 2's corrected manifest, unchanged (batch_dir in/packet/dumps, runner launch.sh
  absolute, workdir /tmp, DUMP_OUT /tmp).
- app_tree_digest 916d3937...1954 (matches drive 2 / pin; app untouched). runtime_revision d73105b.

## Local dry run of the designed check (what blocks the endpoint now)
Ran `python -m concolic.check <config copy> in/packet --profile --base --out` in /tmp/cvd3_dry. The config copy
changed only completion.batch_dir -> /tmp/cvd3_dry/batch, so no gate scratch landed in the shared layer dir. The packet
copy's config_digest was set to match that config copy. Result: exit 1, INCOMPLETE.
- coverage: coverage_complete true, missing_branches 0, tree_complete true, truncated false, assumptions_used 0.
- audits: 6/6 green. shims: 10 PASS + 12 PROTOCOL.
- Q1 (what is in the gate's claim list): NOTHING. Declared [] + coverage-inferred [] = empty. Drive 2's four confinement
  rows (A-D) do not appear, as expected after d73105b.
- BLOCKING lines:
  1. note_check: NOT CONFIGURED (known structural wall, addendum 3 §8).
  2. assumption gate: NOT CONFIGURED (assumption_cfg is mandatory; ...)  <-- ENGINE DEFECT, not a missing artefact.
     The packet supplies assumption_manifest, and concolic/check.py:988-989 maps it to cfg["assumption_cfg"]. But
     concolic/checks/assumptions.py:225 `if not declared: return None` returns None for an EMPTY claim list, and
     concolic/checks/run.py:160 reads `ac is None` as NOT CONFIGURED and blocks. So an endpoint with nothing to
     verify gets reported as unconfigured.
- Q2 (is complete:true reachable?): NOT at this engine revision. note_check: NOT CONFIGURED is NOT the only remaining
  blocking line. The second one is the mislabelled assumption-gate line above. If the engine treated an empty claim
  list as vacuously passed, note_check: NOT CONFIGURED would be the only remaining blocking line.
- I did NOT declare a dummy assumption to make the gate run. That would be manufacturing a claim to move a row.
- Escalated: ctl/ask/empty-claims-reported-not-configured.json (class sweep-wide). No answer arrived before submission.
  Without one, I submitted the honest baseline packet unchanged.
