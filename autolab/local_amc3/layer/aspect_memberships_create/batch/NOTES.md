# drive 10 working notes
config digest 7995d56e4ccddc57b130d2b2d52e67921f25793252db3c42eee6a6499f8ec925 (in/config.json -> local_amc3/inputs/aspect_memberships_create_config.json)
runner /home/dev/project/reports/autolab/entrypoints/scaffold/aspect_memberships_create/run_dse.rb ; launch.sh beside it
targets registry.json ; shims shared_shims.rb ; MAX_RUNS 1500 TIME_BUDGET 3000
batch -> local_amc3/layer/aspect_memberships_create/batch (empty at start). No denials/response: first attempt.
run1 launched -> batch/explore1, log batch/logs/run1.log, sentinel batch/logs/run1.done
drive9 packet: local_amc2/boxes/aspect_memberships_create-batch-1-dfb2bc19/out/packet (6 UntrackedPath records, manifest workdir /tmp/amc2_achk_dumps)
run2 launched: 14 seeds from missing_decl.json (identical set to drive 9 seeds_r2), SEEDS_ONLY, _cov2 -> explore2
run1: 1500/403/false/{}/112 InvalidLocale,151 ATM/unflip 0, 51.0s; installed lines present; 0 SELECT blocks.*; cov none 88 trunc; d9 decl -> 14 missing; sib2 identical to drive9 (169/169 devise differ; 264/264/54 differ 0)
run2 attempt A passed JSON content in EXTRA_SEEDS_JSON (driver wants a FILE PATH, autolab_dse.rb:1118) -> ran 1 default seed; discarded, never copied to batch top. Re-run with path.
local gate launched: cwd /tmp/amc3_chkbox (in/packet/dumps = copy of 417), workdir /tmp/amc3_achk_dumps, log batch/logs/gate.log
gate attempt1 killed at stage2 after 18min (runner default MAX_RUNS=6 -> singles). Manifest env now MAX_RUNS=1500 TIME_BUDGET=3000; gate re-launched.
