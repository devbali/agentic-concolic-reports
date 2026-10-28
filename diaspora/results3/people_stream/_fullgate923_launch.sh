#!/usr/bin/env bash
# people_stream FULL GATE, 2026-09-23 — the re-close after the 2026-09-19
# fullgate came back RED on two blockers:
#
#   1. `shim User.person: FAIL-COVERAGE` — the X7/B-2 repair (2026-09-11)
#      replaced targets.rb §8's one-line note with a RENDERED statement
#      guarded by `rescue Exception => nil`, and shim_tests.rb never drove
#      that arm. Fixed in shim_tests.rb (the arm is driven with a real
#      NotImplementedError wall in the batch's OWN renderer, restored in
#      `ensure`), not waived — shim_test_runner.rb rejects waivers outright.
#
#   2. four `ConfinementAssumption` FAILs. Confinement pairs are INFERRED by
#      the engine, never declared here, and the engine's protocol is that a
#      gate-refuted pair is fed back via `CoverageChecker(withdrawn_pairs=)`
#      so the next pass never licenses it. That feedback leg was never wired
#      in this batch's driver, so the FAIL could not clear. Now wired
#      (coverage_report.py + confinement_withdrawn.json). MEASURED: with all
#      four withdrawn the coverage verdict is UNCHANGED —
#      NODES=39 MISSING=0 TREE_COMPLETE=True DEMAND_SETS=21 — so nothing
#      here rests on the refuted pairs (_probe_withdrawn_20260923.json).
#
# CONCURRENCY. Two other endpoints hold JRuby slots (conversations_index
# gate at CONCOLIC_SLOTS=3, posts_show at 6). tools/slot's locks are GLOBAL
# by index, so N=6 here joins the existing pool without raising the ceiling.
# PROBE BANK: the 2026-09-19 checkpoints are left UNTOUCHED — today's src
# commit 8ceccfb changed assumption_checker.py, so their `engine` header key
# no longer matches and reusing the path would only rotate 292 MB aside.
set -u
B=/home/dev/project/reports/diaspora/results3/people_stream

# The gate OVERWRITES the batch's evidence files in place. Snapshot the
# 2026-09-19 fullgate's evidence first — it is what the diagnosis above is
# argued from and must stay readable after this pass.
for f in coverage_summary.json _shim_results.json _assumption_results.json \
         _assumptions_declared.json _assumption_driver_failure.log \
         exploration_summary.json _c1/_gate_engine.log; do
  [ -e "$B/$f" ] && cp -a "$B/$f" "$B/$f.pre_withdrawn_20260923"
done

exec env PYTHONPATH=/home/dev/project/src \
  CONCOLIC_SLOTS=6 CONCOLIC_PROBE_WORKERS=2 \
  JAVA_TOOL_OPTIONS= JRUBY_OPTS=--debug \
  ACHK_PROBE_BATCH=4 \
  ACHK_CONF_PROFILES=500 \
  ACHK_CHECKPOINT="$B/_fullgate923_probes.ckpt.jsonl" \
  ACHK_INDEX_CHECKPOINT="$B/_fullgate923_index.ckpt.jsonl" \
  python3 -u "$B/coverage_report.py"
