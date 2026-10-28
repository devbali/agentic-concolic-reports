# NOTES — conversation_visibilities_destroy, drive 2, attempt 1
config_digest 88d02aafc0c5993a04f6b55745ec31fc971d9736466570dedbb5d3d41bbdf1c6
runner /home/dev/project/reports/autolab/entrypoints/scaffold/conversation_visibilities_destroy/run_dse.rb
launcher .../scaffold/conversation_visibilities_destroy/launch.sh
targets /home/dev/project/reports/autolab/targets/registry.json ; shims shared_shims.rb
scenarios MAX_RUNS 24 TIME_BUDGET 300
No in/response.json, no in/denials.json => attempt 1: baseline corpus only (addendum 2 §10).
app_tree_digest 916d393795a47b99d2128464ba268defb51524555bc26c659560575051501954
src_new HEAD ee49d91794b451aa4774d41417a4f528796a863d ; app HEAD 0760b6a22e113b74567330ff69ccc55a1d07022c
ENV GOTCHAS on this host: (1) systemd-run --user needs XDG_RUNTIME_DIR=/run/user/1000 or it fails "Failed to connect to bus".
(2) shim_extractor.rb crashes "invalid byte sequence in US-ASCII" when LANG is unset; LANG=C.UTF-8 fixes it -> 22 keys.
   This affects the config's extract_cmd if the check box runs with no locale. Not mine to fix; noted.
shim_tests.rb in batch/ is byte-identical to first drive's batch-2 packet file.

## Attempt 1 results (2026-10-02)
Explorer: default invocation (MAX_RUNS=24 TIME_BUDGET=300), 18 runs, 7 distinct paths, worklist empty, exit 0,
terminals {I18n::InvalidLocale: 3}. Dumps dse0001-0005,0007,0008 copied to batch/ top level and packet dumps/.
Coverage layer (CoverageChecker + coverage_kwargs_of(config)) over batch/: complete True, tree_complete True,
missing 0, truncated False, total_runs 7.
Decision co-occurrence in baseline corpus (identity = structured expr), A=count==1 B=lang=='pl' C=lang=='xx' D=not_found==true:
  0001 A=T B=F C=F D=F | 0002 A=T B=T D=F | 0003 B=F C=T | 0004 B=F C=F D=T | 0005 A=F B=F C=F D=F | 0007 B=T D=T | 0008 A=F B=T D=F
  (A×D: TF,FF present; A×B: TT,TF,FF,FT present; A×C: TF,FF; B×D: TF,FT,FF.) Per §10 no co-occurrence runs pre-constructed.
assumptions.json = [] (worklist exhausted, tree complete: no licence needed). validate_declared -> ok.
Shims: extractor 22 keys (needs LANG=C.UTF-8); shim_tests.rb (first drive's, byte-identical) -> PASS 10, PROTOCOL 12, 0 red.
Manifest: DEVIATES from addendum 2 §6 on workdir/DUMP_OUT. diaspora-concolic cd's into the app dir, and autolab_dse.rb:1108
  uses DUMP_OUT verbatim, so relative 'in/packet/dumps' would write probe dumps into the app tree where replay._dump_dirs
  never looks. Using workdir=/tmp, DUMP_OUT=/tmp. VERIFIED: replay.run_probe with this manifest from a mock box root
  (/tmp/cvd2b1_check, packet at in/packet) found its probe dump and cleaned it up; app dir untouched.
  Escalated as ctl/ask/manifest-dumpout.json; no answer received before submission.
Standalone assumption_checker with declared [] -> 0 tested (inferred pairs are merged in by the pipeline, not standalone).
note_check NOT CONFIGURED: expected (fixtures/real_mode_plan null); no concrete_run.json produced.
