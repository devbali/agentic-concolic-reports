#!/bin/bash
# C23 (2026-09-14) — run the remaining measurement passes STRICTLY IN SEQUENCE.
# Each is a full `_c23_pass.sh` invocation with its own tag, own checkpoint and
# own output files; the passes never overlap, so only one 8G job of this
# agent's is ever on the box. MEASUREMENT ONLY.
B=/home/dev/project/reports/diaspora/results3/notifications_index
cd "$B" || exit 2
say(){ echo "[$(date -Is)] CHAIN $*" | tee -a "$B/_c23.log"; }

# never start while one of THIS agent's passes is still running
while pgrep -a python3 2>/dev/null | grep -v shell-snapshots \
      | grep -q "notifications_index/_c23_coverage_report[.]py"; do
  say "WAIT: a _c23 pass is still running"; sleep 60
done

run(){ # run <TAG> <env assignments...>
  local tag="$1"; shift
  say "START $tag  ($*)"
  env "$@" bash "$B/_c23_pass.sh" "$tag"
  say "END $tag rc=$?"
}

# ORDER (2026-09-14): risk-first. The two rows the strategy question needs are
# OFF (already launched separately) and C1+exact -- the highest-precision
# variant that keeps some demand reduction -- so C1X runs before the rest. Each
# pass is ~1 h and the box is shared with the C22 round and the P26 gate; if the
# chain is cut short, the rows that exist are the ones that decide.
run C1X    CONF_KEEP_NOTES=1 CONF_KEYING=exact
run C1     CONF_KEEP_NOTES=1
run C1C2   CONF_KEEP_NOTES=1 CONF_SPAN_UNION=1
run C1C2X  CONF_KEEP_NOTES=1 CONF_SPAN_UNION=1 CONF_KEYING=exact
# CONTROL, last: today's settings on the SAME frozen C21R1 snapshot under the
# NEW engine (coverage.py changed 2026-09-13 21:26 for C2/C3; C21R1 ran on the
# old one). It is the only row that makes the four above a differential, and it
# is also the only way to read C21R1's ACTUAL licensed-pair count (the 656 come
# from the C20 declaration file, written before the 78 withdrawals landed).
run ON     CONF_KEEP_NOTES=0
say "CHAIN DONE"
