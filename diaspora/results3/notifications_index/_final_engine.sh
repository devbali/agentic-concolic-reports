#!/bin/bash
# FINAL engine report: coverage checker + completion section (shim extract+test,
# note check, MANDATORY assumption gate, extra audits format_coverage +
# note_fidelity). Prints OVERALL_COMPLETE. The assumption gate replays probes
# via JRuby (flock-serialized) — no other JRuby must run concurrently.
set +e
unset JAVA_TOOL_OPTIONS
cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
LOG="$B/_final_engine.log"
echo "=== final engine start $(date -Is) ===" > "$LOG"
# RUNBOOK §4 (2026-08-27, revised): the HEAVY lock covers ONLY the memory-heavy
# coverage/Z3 pass — coverage_report.py takes it around that phase itself and
# releases it before the completion section, so the multi-hour assumption gate
# (JRuby-bound, small) does not starve the other batches. The gate's probes
# still take the SLOT lock per launch.
MAX_MISSING_PER_CLIQUE=4 PYTHONPATH=src python3 "$B/coverage_report.py" >> "$LOG" 2>&1
echo "=== final engine DONE $(date -Is) rc=$? ===" >> "$LOG"
