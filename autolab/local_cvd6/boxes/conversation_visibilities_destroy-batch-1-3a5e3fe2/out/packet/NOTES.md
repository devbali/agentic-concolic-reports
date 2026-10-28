# NOTES — conversation_visibilities_destroy, drive 6, attempt 1
- config digest: 5ca3f53c8671235d6979fa04941abc0410c9e580171c226b3b9aaf0db682818e
- runner: /home/dev/project/reports/autolab/entrypoints/scaffold/conversation_visibilities_destroy/run_dse.rb (launch.sh beside it)
- targets: /home/dev/project/reports/autolab/targets/registry.json ; shims: .../targets/shared_shims.rb
- scenarios auth_html MAX_RUNS 24 TIME_BUDGET 300
- runtime_revision ee9f17bcddbc38285a0a2c2099831369b27b9f29
- batch/ == completion.batch_dir (layer/.../batch); dumps must be top-level here
- no in/response.json, no in/denials.json -> attempt 1

## What was driven (attempt 1)
- Explorer: launch.sh, MAX_RUNS=90 TIME_BUDGET=900, DUMP_OUT=batch/explore. 62 runs, 15 distinct paths,
  worklist empty: true, run errors {}, terminals {I18n::InvalidLocale: 7}. PRODUCED this drive, not inherited.
- This does NOT match the addendum's measured baseline (18 runs / 7 paths). New decisions vs drive 3's corpus:
  count_2_count == 0, find_by_1_not_found, len(find_by_sql_1_rows) != 0 -- ConversationVisibility#check_orphan_conversation
  (after_destroy) is now reached. targets/core.rb mtime is 2026-10-07 06:29, presumably the cause.
- All 15 dumps copied to top level of batch/ and to packet dumps/.
- Audits run locally over batch/: statement_note_lint, noteless_call_audit, empty_relation_emission_audit,
  identity_symbolicity_audit PASS; cardinality_consistency_audit PASS (VACUOUS);
  exception_note_audit RED: 12 notes over 4 dumps (dse0006, 0011, 0024, 0039) record
  "NotImplementedError: SymbolicList#to_ary is not supported (contents out of scope)" raised from
  Conversation#destroy's before_destroy (dependent: :destroy). The fix belongs in the ruby runtime SymbolicList or in
  targets/core.rb -- both outside my write boundary. Escalated as ctl/ask/exception-note-red.json (class shared);
  no answer arrived before submission. I did NOT drop those dumps and did NOT edit shared code.
- assumptions.json = [] (worklist exhausted; nothing pruned). Validator: ok.
- assumption_manifest.json = drive 2/3's corrected manifest (batch_dir in/packet/dumps, workdir /tmp, DUMP_OUT /tmp).
- shim_tests.rb = drive 1/2/3's file byte-identical; re-run here against 22 extracted shims: 10 PASS + 12 PROTOCOL, 0 red.
- app_tree_digest 916d3937... (matches pin used by drive 3); nothing in the app was changed.
- Expectation for the check: engine conjunction likely NOT complete, because of exception_note_audit RED.
