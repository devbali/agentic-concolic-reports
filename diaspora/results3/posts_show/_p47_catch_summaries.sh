#!/usr/bin/env bash
# Capture each leg's exploration_summary.json before the next leg clobbers it.
#
# THE PROBLEM. run_dse.rb:562 writes its summary to
# `File.join(HERE, "exploration_summary.json")` — HERE is the runner's own
# directory. All four P47 legs share `v2/`, so they all write the SAME path and
# the last one to finish wins. Worse, the three original legs started together
# (04:20:24) with an identical `TIME_BUDGET=36000`, so they will hit their
# budget within seconds of each other — a slow poll would miss two of them.
#
# WHY IT MATTERS. That file is the ONLY place the frontier accounting lives:
# `frontier_entries_dropped`, `worklist_exhausted`, `stack_remaining`,
# `stop_reason`. With all four legs pinned at `STACK_LIMIT` for hours (see the
# handoff §4b), those numbers are the difference between "the legs drained" and
# "the legs ran out of time with N novel candidates discarded". Step 0 of the
# post-drive sequence cannot be done without them.
#
# THE CATCH. inotifywait is not installed on this box, so this polls fast (1 s)
# and keys each capture by the SCENARIO NAME INSIDE the file, not by arrival
# order. A file whose scenario has already been captured is ignored, so a
# duplicate write is harmless; a genuinely new scenario is copied immediately.
# It also re-checks on exit, so the final writes are not lost if the legs and
# the watcher end together.
set -uo pipefail
B=/home/dev/project/reports/diaspora/results3/posts_show
V="$B/v2"
SRC="$V/exploration_summary.json"
OUT="$B/_p47_leg_summaries"
LOG="$B/_p47_catch_summaries.log"
mkdir -p "$OUT"
: > "$LOG"

capture() {
  [ -f "$SRC" ] || return 0
  # the scenario name is inside; a partial write just fails to parse and retries
  local scen
  scen=$(python3 - "$SRC" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
ss = d.get('scenarios') or d.get('scenario_summaries') or []
if isinstance(ss, list) and ss:
    print(ss[0].get('scenario') or 'unknown')
else:
    print('unknown')
PY
) || return 0
  [ -n "$scen" ] || return 0
  local dst="$OUT/exploration_summary_${scen}.json"
  if [ ! -f "$dst" ]; then
    cp "$SRC" "$dst"
    echo "[$(date -Is)] captured scenario=$scen -> $(basename "$dst")" >> "$LOG"
  fi
}

trap 'capture; echo "[$(date -Is)] watcher exiting; captured: $(ls "$OUT" | tr "\n" " ")" >> "$LOG"' EXIT

# All THREE scopes, not two. The authenticated legs were relaunched into
# p47-auth-relaunch.scope at 10:24 with their own 10 h budget, so they outlive
# the anon legs by ~6 h; watching only the original two scopes would have
# stopped this catcher at ~14:20 and lost exactly the two summaries whose legs
# ran longest.
while systemctl --user is-active --quiet p47-gen-v2-posts-show.scope \
   || systemctl --user is-active --quiet p47-leg-anon-html.scope \
   || systemctl --user is-active --quiet p47-auth-relaunch.scope; do
  capture
  sleep 1
done
capture
echo "[$(date -Is)] both scopes inactive; captured: $(ls "$OUT" | tr '\n' ' ')" >> "$LOG"
