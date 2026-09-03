#!/bin/bash
# C7 discovery evidence, ONE PROCESS EACH (a JVM abort names its own probe).
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
B=/home/dev/project/reports/diaspora/results3/notifications_index
S=/home/dev/project/reports/diaspora/tools/slot
P=/home/dev/project/src/ruby_runtime/completion_checker/concrete_run_probe.rb
LOG="$B/_c7_disc_probes.log"; echo "=== disc probes start $(date -Is) ===" > "$LOG"

# 1. PARSEABLE host: does the success arm abort the JVM HERE? (expect nonzero)
mv -f "$B/concrete_run.json" "$B/_c7_saved_cr3.json" 2>/dev/null
$S /home/dev/project/scripts/diaspora-concolic $P "$B/_c7_disc_parseable_probe.rb" \
  > "$B/_c7_disc_parseable.log" 2>&1
echo "[parseable] exit=$?" >> "$LOG"
mv -f "$B/concrete_run.json" "$B/_c7_disc_parseable_run.json" 2>/dev/null

# 2. GAP EVIDENCE: the app's OWN :save_person_after_webfinger callback, no network.
$S /home/dev/project/scripts/diaspora-concolic "$B/_c7_disc_gap_probe.rb" \
  > "$B/_c7_disc_gap.log" 2>&1
echo "[gap] exit=$?" >> "$LOG"
mv -f "$B/_c7_saved_cr3.json" "$B/concrete_run.json" 2>/dev/null
echo "=== disc probes DONE $(date -Is) ===" >> "$LOG"
