#!/usr/bin/env bash
# Capture each leg's exploration_summary.json before the next leg clobbers it.
#
# THE PROBLEM. run_dse.rb:562 writes its summary to
# `File.join(HERE, "exploration_summary.json")` — HERE is the runner's own
# directory, and all legs of a drive share it. The last leg to finish wins.
#
# WHY IT MATTERS. That file is the ONLY place the frontier accounting lives:
# `frontier_entries_dropped`, `worklist_exhausted`, `stack_remaining`,
# `stop_reason`. run_dse.rb writes `frontier_entries_dropped` to the JSON only
# (:533) and NEVER to stdout, so a lost file is a permanently lost number —
# step 0 of the post-drive sequence cannot be reconstructed from the logs.
#
# ---------------------------------------------------------------------------
# RACE FIX, 2026-09-26 — this script LOST DATA on the v3 drive. Read this
# before "simplifying" it back.
#
# The previous version parsed the scenario OUT OF $SRC and THEN copied $SRC.
# Two separate reads of a file that four legs rewrite. If a leg rewrote it
# between those reads, one leg's CONTENT was filed under another leg's NAME.
#
# That is not hypothetical. On the v3 drive all four legs finished within 23 s
# (08:08:04–08:08:27, because P48 ran them flat four-wide) and
# `exploration_summary_auth_json.json` came out BYTE-IDENTICAL to
# `exploration_summary_anon_json.json` (md5 86557db5). Both AUTH legs' frontier
# accounting was lost, and worse, one file actively misreported which scenario
# it described — a silent wrong answer, not a visible gap.
#
# THE FIX: COPY FIRST, then read the scenario FROM THE COPY, then rename. The
# filename then always describes the bytes it holds. A snapshot that loses the
# race is just a duplicate of an already-captured scenario and is discarded.
# The poll is also 0.2 s rather than 1 s, which narrows the window but is NOT
# the fix — do not rely on it.
# ---------------------------------------------------------------------------
set -uo pipefail
B=/home/dev/project/reports/diaspora/results3/posts_show
V="$B/v3"
SRC="$V/exploration_summary.json"
OUT="$B/_p48_leg_summaries"
LOG="$B/_p48_catch_summaries.log"
UNIT="${P48_UNIT:-p48-gen-v3-posts-show.scope}"
mkdir -p "$OUT"
: > "$LOG"

scenario_of() {
  python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
ss = d.get("scenarios") or d.get("scenario_summaries") or []
print((ss[0].get("scenario") or "unknown") if isinstance(ss, list) and ss else "unknown")
' "$1" 2>/dev/null
}

capture() {
  [ -f "$SRC" ] || return 0
  local tmp scen dst
  tmp=$(mktemp "$OUT/.snap.XXXXXX") || return 0
  # COPY FIRST — everything after this reads the COPY, never $SRC again.
  cp "$SRC" "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  scen=$(scenario_of "$tmp") || { rm -f "$tmp"; return 0; }
  if [ -z "$scen" ] || [ "$scen" = unknown ]; then rm -f "$tmp"; return 0; fi
  dst="$OUT/exploration_summary_${scen}.json"
  if [ -f "$dst" ]; then rm -f "$tmp"; return 0; fi
  mv "$tmp" "$dst"
  echo "[$(date -Is)] captured scenario=$scen -> $(basename "$dst")" >> "$LOG"
}

cleanup() {
  capture
  rm -f "$OUT"/.snap.* 2>/dev/null
  echo "[$(date -Is)] watcher exiting; captured: $(ls "$OUT" 2>/dev/null | tr '\n' ' ')" >> "$LOG"
  # State the gap rather than let a missing file pass as "nothing to report".
  for s in auth_html anon_html auth_json anon_json; do
    [ -f "$OUT/exploration_summary_${s}.json" ] || \
      echo "[$(date -Is)] *** NO SUMMARY CAPTURED FOR $s — its frontier accounting is UNRECOVERABLE" >> "$LOG"
  done
}
trap cleanup EXIT

while systemctl --user is-active --quiet "$UNIT"; do
  capture
  sleep 0.2
done
capture
echo "[$(date -Is)] unit $UNIT inactive; captured: $(ls "$OUT" 2>/dev/null | tr '\n' ' ')" >> "$LOG"
