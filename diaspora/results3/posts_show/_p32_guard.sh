#!/bin/bash
# =============================================================================
# P31 GUARDS (sourced) — the coordinator's three rules, 2026-09-13 21:2x, after
# the owner raised the cage to MemoryMax=32G / MemoryHigh=30G (flat; the
# 19G<->24G hold watchers are retired). Memory no longer forces this endpoint
# to queue behind notifications' passes, so the blanket
# "no coverage_report.py anywhere" hold is DROPPED and replaced by:
#
#   (1) at most ONE heavy stage of MINE at a time — structural: _p31_round.sh
#       is sequential and every heavy step is a `cage`d scope it waits on.
#   (2) the memory invariant against the LIVE cap. Already exact in
#       `_cage.sh:gate_launch`, which reads `MemoryMax` from the slice at every
#       launch (not a constant) and requires
#           free avail >= cap + 512 MiB   AND   (MemoryMax - MemoryCurrent) >= cap
#       and launches through `systemd-run --slice=concolic-cov.slice`.
#       For a 7 G stage `free avail >= 7680 MiB` is STRICTER than the
#       coordinator's `free -g >= 4`, so the invariant is satisfied a fortiori.
#       `gate_check` below only RECORDS it so the log shows the numbers.
#   (3) A CPU GUARD ON THE GATE, which is the long pole and must not be
#       starved. Sampled immediately before a stage launches and again 10
#       minutes in. Below ~0.7 probes/s the CURRENT stage finishes and the NEXT
#       one holds until notifications' pass clears.
#
# TWO RATES ARE REPORTED, and the threshold is applied to the second:
#   cum    the coordinator's formula, batches x 40 / elapsed-since-gate-start.
#          Comparable to their ~1.1/s, but DAMPED: the gate spent its first
#          ~30 min building a 232 523-dump corpus index during which it emitted
#          zero probes, so `cum` understates the live rate and moves far too
#          slowly to detect starvation that starts now.
#   win    the same quantity over a SAMPLING WINDOW (delta batches x 40 / delta t).
#          This is the instantaneous rate and it is what the 0.7 threshold
#          tests. Both are printed at every sample so the trade is visible.
# =============================================================================
GATE_LOG="${GATE_LOG:-/home/dev/project/reports/diaspora/results3/posts_show/_p26_gate_v3.log}"
GATE_UNIT="${GATE_UNIT:-posts-p26-gate-v3-20260914.service}"
GATE_MIN_RATE="${GATE_MIN_RATE:-0.7}"
GUARD_DIR="${GUARD_DIR:-/home/dev/project/reports/diaspora/results3/posts_show}"
STARVED_FLAG="$GUARD_DIR/_p31_gate_starved.flag"

gate_batches(){ grep -c "probe batch" "$GATE_LOG" 2>/dev/null || echo 0; }

# ---------------------------------------------------------------------------
# P32, 2026-09-14 — COUNT PROBES, NOT BATCHES.
# The old sampler multiplied batches by a HARD-CODED 40. v2 logged 40 roots per
# batch so that happened to be right; v3 (posts-p26-gate-v3-20260914) sets
# ACHK_PROBE_BATCH=200, so the same formula under-read the live gate by 5x and
# reported 0.9/s while the gate was actually doing 4.0 probes/s. The batch size
# is IN the log line -- "[probe batch 5: 200 roots in scenario ...]" -- so read
# it instead of assuming it. Works for v2 and v3 and for any future batch size.
gate_probes(){
  awk 'match($0, /probe batch [0-9]+: ([0-9]+) roots/, m){n+=m[1]} END{print n+0}' \
      "$GATE_LOG" 2>/dev/null || echo 0
}

gate_start_epoch(){
  local ts; ts=$(head -1 "$GATE_LOG" 2>/dev/null | sed -n 's/^\[\([^]]*\)\].*/\1/p')
  [ -n "$ts" ] && date -d "$ts" +%s 2>/dev/null || echo 0
}

# cumulative rate, the coordinator's formula
gate_cum_rate(){
  local b s n; b=$(gate_batches); s=$(gate_start_epoch); n=$(date +%s)
  [ "$s" = 0 ] && { echo "0.000"; return; }
  awk -v b="$b" -v e="$((n-s))" 'BEGIN{printf "%.3f", (e>0)? b*40/e : 0}'
}

# windowed rate over $1 seconds, in PROBES/s, read from the log's own root counts
gate_win_rate(){
  local secs="${1:-$GATE_WIN_SECS}" a b t0 t1
  a=$(gate_probes); t0=$(date +%s)
  sleep "$secs"
  b=$(gate_probes); t1=$(date +%s)
  awk -v a="$a" -v b="$b" -v t="$((t1-t0))" 'BEGIN{printf "%.3f", (t>0)? (b-a)/t : 0}'
}

# A CLEAN BASELINE, measured with nothing of ours running. The threshold is a
# FRACTION of this, never an absolute -- see the block above GATE_WIN_SECS.
gate_baseline(){
  local f="$GUARD_DIR/_p32_gate_baseline.txt"
  if [ -s "$f" ]; then cat "$f"; else echo "${GATE_BASELINE:-0}"; fi
}
gate_measure_baseline(){
  local r; r=$(gate_win_rate "${1:-900}")
  echo "$r" > "$GUARD_DIR/_p32_gate_baseline.txt"
  echo "$r"
}

# the memory invariant, RECORDED (gate_launch enforces it)
mem_line(){
  local cap="${1:-7}" avail cur mx
  avail=$(free -m | awk 'NR==2{print $7}')
  cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value 2>/dev/null)
  mx=$(systemctl --user show concolic-cov.slice -p MemoryMax --value 2>/dev/null)
  case "$cur" in ''|*[!0-9]*) cur=0;; esac
  case "$mx"  in ''|infinity|*[!0-9]*) mx=0;; esac
  awk -v a="$avail" -v c="$cur" -v m="$mx" -v n="$cap" 'BEGIN{
    printf "MEM free_avail=%dM (need %dM)  cap=%dG  MemoryMax=%.1fG  MemoryCurrent=%.1fG  slice_free=%.2fG (need %d)  -> %s",
      a, n*1024+512, n, m/1073741824, c/1073741824, (m-c)/1073741824, n,
      (a >= n*1024+512 && (m-c) >= n*1073741824) ? "OK" : "WOULD HOLD"}'
}

gate_alive(){ systemctl --user is-active "$GATE_UNIT" >/dev/null 2>&1; }

# --- notifications' pass, path-qualified and shell-snapshot-filtered ---
notif_pass_busy(){
  pgrep -af "python3.*notifications_index/coverage_report\.py" 2>/dev/null \
    | grep -v 'shell-snapshots' | head -1
}

# =============================================================================
# COORDINATOR REFINEMENTS, 2026-09-13 21:4x — accepted and wired here rather
# than in `_p31_round.sh`, so a future refinement never needs an edit to a
# script that may be running.
#
#  * THE THRESHOLD IS ON THE WINDOW RATE (confirmed), the cumulative figure is
#    kept alongside for the record.
#  * THE WINDOW IS ~300 s, NOT 120 s. A batch is 40 probes, so at ~1 probe/s a
#    120 s window holds only ~3 batches and ONE slow batch reads as starvation.
#    At 300 s it is ~7-8 batches and the quantisation noise is halved.
#  * TWO CONSECUTIVE SUB-0.7 WINDOWS are required before standing down, so a
#    single stall does not idle the round for nothing. The second window is
#    taken immediately after the first, and BOTH are logged with their batch
#    deltas so the reading can be checked rather than believed.
# =============================================================================
# 900 s, not 300 (coordinator, 2026-09-14): at 40 roots a batch, a 300 s window
# holds ~7 batches and quantises hard; 900 s triples the resolution.
GATE_WIN_SECS="${GATE_WIN_SECS:-900}"
# stand down only below this FRACTION of the measured clean baseline
GATE_STARVE_FRAC="${GATE_STARVE_FRAC:-0.60}"

# window rate, reported as "rate|dbatches|dt" so the raw counts are visible
gate_win_detail(){
  local secs="${1:-$GATE_WIN_SECS}" a b t0 t1
  a=$(gate_probes); t0=$(date +%s)
  sleep "$secs"
  b=$(gate_probes); t1=$(date +%s)
  awk -v a="$a" -v b="$b" -v t="$((t1-t0))" \
      'BEGIN{printf "%.3f|%d|%d", (t>0)? (b-a)/t : 0, b-a, t}'
}

# BELOW = below GATE_STARVE_FRAC of the MEASURED baseline, not below an
# absolute. (Coordinator, 2026-09-14: the absolute 0.7/s was unmeasurable --
# a 40-root batch quantises a 300 s window to 0.533/0.666/0.800, so 0.7 is not
# a value the instrument can return, and notifications lost 22 min standing
# down on a false low. If no baseline has been measured, NEVER stand down:
# an unmeasured threshold is not evidence.)
_below(){
  local d="$1" base; base=$(gate_baseline)
  awk -v d="$d" -v b="$base" -v f="$GATE_STARVE_FRAC" \
      'BEGIN{ if (b+0 <= 0) exit 1; exit !(d+0 < f+0 * b+0) }'
}

# $1 stage label, $2 cap GiB. Logs cum + memory now; arms a pre window and a
# T+10min during window (with the two-consecutive-windows rule).
stage_begin(){
  local lab="$1" cap="${2:-7}"
  gate_alive || say "  *** GATE UNIT NOT ACTIVE — rates reported anyway ***"
  say "  GATE before $lab: cum=$(gate_cum_rate)/s over $(gate_batches) batches"
  say "  $(mem_line "$cap")"
  rm -f "$GUARD_DIR/_p31_rate_${lab}.txt"
  ( d=$(gate_win_detail); r=${d%%|*}; rest=${d#*|}
    say "  GATE before $lab: win=${r}/s (${rest%|*} batches / ${rest#*|}s) <- threshold is on this"
    echo "$r" > "$GUARD_DIR/_p31_rate_${lab}_pre.txt" ) &
  ( sleep 600
    d1=$(gate_win_detail); r1=${d1%%|*}; s1=${d1#*|}
    say "  GATE during $lab (T+10min): win=${r1}/s (${s1%|*} batches / ${s1#*|}s)  cum=$(gate_cum_rate)/s"
    if _below "$r1"; then
      say "  GATE during $lab: window 1 BELOW ${GATE_MIN_RATE}/s — taking a SECOND window before standing down"
      d2=$(gate_win_detail); r2=${d2%%|*}; s2=${d2#*|}
      say "  GATE during $lab: window 2 = ${r2}/s (${s2%|*} batches / ${s2#*|}s)"
      if _below "$r2"; then
        : > "$STARVED_FLAG"
        echo "$r1 $r2" > "$GUARD_DIR/_p31_rate_${lab}.txt"
        say "  *** TWO CONSECUTIVE WINDOWS BELOW ${GATE_MIN_RATE}/s DURING $lab —"
        say "      this stage finishes, the NEXT stage stands down until the gate recovers (P32) ***"
      else
        echo "$r1 $r2 recovered" > "$GUARD_DIR/_p31_rate_${lab}.txt"
        say "  GATE during $lab: RECOVERED on window 2 — no stand-down (this is the"
        say "      single-stall case the two-window rule exists to absorb)"
      fi
    else
      echo "$r1 ok" > "$GUARD_DIR/_p31_rate_${lab}.txt"
    fi ) &
}

stage_end(){
  local lab="$1" pre dur
  pre=$(cat "$GUARD_DIR/_p31_rate_${lab}_pre.txt" 2>/dev/null)
  dur=$(cat "$GUARD_DIR/_p31_rate_${lab}.txt" 2>/dev/null)
  say "  GATE verdict $lab: before=${pre:-<stage too short>}/s during=${dur:-<stage too short>} " \
      "$([ -f "$STARVED_FLAG" ] && echo '-> STARVED, next stage holds' || echo '-> ok')"
}
