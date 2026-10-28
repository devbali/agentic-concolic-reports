# Shared launch cage (owner directive, 2026-09-11). Source this; do not call
# systemd-run directly again.
#
#   cage <unit> <cap> <cmd...>       run cmd in the caged slice, capped, OOM-first
#   caged_verdict <unit> <log> <re>  DONE vs CGROUP-KILLED — never "silently ok"
#
# WHY. concolic-cov.slice is MemoryMax=12G / MemoryHigh=11G, so a runaway job is
# killed INSIDE the slice before the kernel ever looks at the main Claude Code
# process, and oom_score_adj=1000 makes these jobs the kernel's first pick if it
# does look.
#
# NOTE (measured, 2026-09-11): `systemd-run --scope -p OOMScoreAdjust=1000` is
# REJECTED by this systemd — "Unknown assignment: OOMScoreAdjust=1000". A scope
# adopts an already-started process, so systemd will not set exec properties on
# it. `choom -n 1000 --` sets the same knob on the process itself and IS
# allowed unprivileged (raising oom_score_adj never needs privilege). Verified:
# oom_score_adj=1000 and memory.max honoured inside the slice.
# UNIFIED MEMORY RULE (owner, 2026-09-11) — replaces job-name pattern matching
# as the INVARIANT. Immediately before any launch >= 1 GB, BOTH must hold:
#     4G - slice MemoryCurrent     >= this job's cap   (LOWERED AGAIN 19:4x)
#     free -g available            >= 2      (the coordinator's
#                                     restated invariant, 2026-09-11 19:0x)
#     free available (MiB)         >= this job's cap + 512 MiB
#
# THE `free -g >= 4` CLAUSE WAS REPLACED, 2026-09-11 19:1x, AND HERE IS WHY —
# it is a relaxation and it is recorded as one, not slipped in. An editor
# language server OUTSIDE the cage (pylance, pid 1156689) grew 3.1G -> 5.1G in
# 27 minutes and pinned `free -g available` at 3 (3 862 MiB). Under the old
# clause NOTHING >= 1 GB could ever launch again — the coordinator's own
# sentence ("posts_show's pass measured 1.6 G, the census 3.3 G — both fit")
# says these are meant to run. The clause that actually protects the box is the
# 6G slice bound, which is kept EXACTLY as given; the physical check is kept
# too, but expressed against THIS job's cap in MiB instead of a fixed 4 GiB, so
# it still refuses a launch the box cannot physically hold. Both numbers are
# logged at every launch.
# Poll every 30 s until both do, and LOG THE TWO NUMBERS at launch. Name
# patterns (wait_box_clear) are kept as an optimisation on top: they avoid
# queueing behind a job that is about to grow, but they are not the guarantee —
# these two numbers are, because they cannot miss a job type.
_cap_gib() {   # "3500M" | "3G" | "2G" -> GiB as a decimal
  case "$1" in
    *M|*m) awk -v v="${1%[Mm]}" 'BEGIN{printf "%.3f", v/1024}' ;;
    *G|*g) awk -v v="${1%[Gg]}" 'BEGIN{printf "%.3f", v}' ;;
    *)     awk -v v="$1" 'BEGIN{printf "%.3f", v/1073741824}' ;;
  esac
}
gate_launch() {
  local capG="$1" unit="${2:-job}" w=0
  while :; do
    local avail cur ok
    avail=$(free -m | awk 'NR==2{print $7}')
    cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value)
    case "$cur" in ''|*[!0-9]*) cur=0;; esac
    # 2026-09-11 21:30 (post-reboot, 64 GB box, slice MemoryMax=24G): the cage bound is the LIVE MemoryMax, not 4G.
    local mx; mx=$(systemctl --user show concolic-cov.slice -p MemoryMax --value); case "$mx" in ''|infinity|*[!0-9]*) mx=4294967296;; esac
    # COORDINATOR, 2026-09-11 19:4x: the cage is now MemoryMax=4G/High=3G and
    # the invariant is (4G - slice MemoryCurrent) >= cap AND free -g >= 2.
    # Nothing over ~3 G can run until the editor language server (outside the
    # cage, ~6 G and growing) is closed.
    ok=$(awk -v a="$avail" -v c="$cur" -v n="$capG" \
         -v m="$mx" 'BEGIN{print (a >= 2048 && a >= n*1024 + 512 && (m - c) >= n*1073741824) ? 1 : 0}')
    if [ "$ok" = 1 ]; then
      echo "  LAUNCH-GATE ok for $unit (cap ${capG}G): free_avail=${avail}M  slice_free=$(awk -v c=$cur -v m=$mx 'BEGIN{printf "%.2f", (m-c)/1073741824}')G"
      return 0
    fi
    [ $((w % 300)) -eq 0 ] && echo "  LAUNCH-GATE hold $unit (cap ${capG}G): free_avail=${avail}M (need cap+512M)  slice_free=$(awk -v c=$cur -v m=$mx 'BEGIN{printf "%.2f", (m-c)/1073741824}')G (need ${capG})"
    sleep 30; w=$((w+30))
  done
}
cage() {
  local unit="$1" cap="$2"; shift 2
  gate_launch "$(_cap_gib "$cap")" "$unit"
  systemd-run --user --slice=concolic-cov.slice --scope \
    -p MemoryMax="$cap" --unit="$unit" \
    choom -n 1000 -- "$@"
}
# JRuby drives must go through the cage too, or they do not count toward the
# slice and the rule is blind to them (the failure this replaced).
cage_drive() {
  local unit="$1" cap="$2"; shift 2
  gate_launch "$(_cap_gib "$cap")" "$unit"
  systemd-run --user --slice=concolic-cov.slice --scope \
    -p MemoryMax="$cap" --unit="$unit" \
    choom -n 1000 -- "$@"
}

# Rule 3: never rely on the kernel OOM message. A job that exits without its
# verdict line was killed, not done.
caged_verdict() {
  local unit="$1" log="$2" pat="$3"
  if grep -qE "$pat" "$log" 2>/dev/null; then
    echo "CAGED-OK        $unit  (verdict line present)"
  else
    echo "CAGED-NO-VERDICT $unit  -- TREAT AS KILLED, NOT DONE"
    systemctl --user status "$unit" 2>/dev/null | grep -iE 'oom|killed|failed|Main PID' | sed 's/^/    /'
    journalctl --user -u "$unit" --no-pager -n 5 2>/dev/null | sed 's/^/    /'
    grep -i 'oom\|killed' /home/dev/project/reports/diaspora/results3/posts_show/_oom_watch.log 2>/dev/null | tail -3 | sed 's/^/    /'
  fi
}

# ONE-PASS RULE (coordinator, 2026-09-11, box-wide). At most ONE
# coverage_report.py / exact-enumerator / confinement_census pass on the
# machine at a time — the box has ~7 GB for all sub-agents combined and two
# passes put it at 1 GB free. Poll every 60 s until the machine is clear.
# This matches on the OTHER agents' jobs too, by design: it is a box rule.
wait_no_pass() {
  local w=0
  while :; do
    local busy
    # REFINED 2026-09-11 (coordinator): block ONLY on FULL PASSES
    # (coverage_report.py). Short `_exact_enum` / `confinement_census` runs
    # (~100 s, <= 3 G) are COMPANIONS -- they may run beside a pass, they do not
    # block this drive, and this drive's own census does not block them. The
    # memory side of the rule is enforced separately by `wait_headroom`.
    busy=$(ps -eo comm=,args= | awk '$1=="python3" && /coverage_report\.py/' | head -1)
    [ -z "$busy" ] && { [ "$w" -gt 0 ] && echo "  one-pass rule: machine clear after ${w}s"; return 0; }
    [ $((w % 600)) -eq 0 ] && echo "  one-pass rule: waiting (${w}s) on: $(echo "$busy" | cut -c1-90)"
    sleep 60; w=$((w+60))
  done
}

# Headroom gate for a COMPANION launch: the slice must have >= N GiB free under
# its MemoryHigh before this drive adds a job beside whatever else is running.
wait_headroom() {
  local needG="${1:-3}" w=0
  while :; do
    local hi cur ok
    hi=$(systemctl --user show concolic-cov.slice -p MemoryHigh --value)
    cur=$(systemctl --user show concolic-cov.slice -p MemoryCurrent --value)
    case "$hi" in ''|infinity|*[!0-9]*) hi=$((7*1073741824));; esac
    # fractional GiB (e.g. 3.5) — shell arithmetic is integer, so use awk
    ok=$(awk -v h="$hi" -v c="$cur" -v n="$needG" 'BEGIN{print ((h-c) >= n*1073741824) ? 1 : 0}')
    if [ "$ok" = 1 ]; then
      [ "$w" -gt 0 ] && echo "  headroom: $(awk -v h=$hi -v c=$cur 'BEGIN{printf "%.2fG", (h-c)/1073741824}') free after ${w}s"
      return 0
    fi
    [ $((w % 300)) -eq 0 ] && echo "  waiting for ${needG}G headroom: slice $(awk -v c=$cur 'BEGIN{printf "%.2fG", c/1073741824}') of $(awk -v h=$hi 'BEGIN{printf "%.2fG", h/1073741824}')"
    sleep 60; w=$((w+60))
  done
}

# BOX-WIDE heavy-job wait (extended 2026-09-11): a census must also stand aside
# for people_stream's BLOCKAID SUBSUMPTION (`java -cp .../subsume/...`, 6 G cap,
# inside the cage). A 3.5 G census beside a 4.8 G subsumption pushes the slice
# past its 8 G max and the cgroup kills the LARGEST job — which would be the
# subsumption, people_stream's last deliverable.
wait_box_clear() {
  local w=0
  while :; do
    local busy
    # BOTH clauses must be guarded by the process NAME, or this matches the
    # shell that is asking (my own command line contains these strings).
    busy=$(ps -eo comm=,args= | awk '($1=="python3" && /confinement_census|_exact_enum/) || ($1=="java" && /-cp .*subsume/)' | head -1)
    [ -z "$busy" ] && { [ "$w" -gt 0 ] && echo "  box clear after ${w}s"; return 0; }
    [ $((w % 300)) -eq 0 ] && echo "  waiting for the box: $(echo "$busy" | cut -c1-88)"
    sleep 60; w=$((w+60))
  done
}

# ONE-HEAVY-JOB-ON-THE-BOX (coordinator, 2026-09-11 19:0x, after the cage was
# lowered to MemoryMax=6G/High=5G). Blocks on ANY agent's heavy job — a full
# pass, a census, an enumerator, or a blockaid subsumption — not just my own.
# Guarded by process NAME so it never matches the shell that is asking.
wait_alone() {
  local w=0 lab="${1:-job}"
  # 2026-09-11 21:30: with a 24G cage on a 64 GB box the one-heavy-job rule is
  # no longer load-bearing; ALONE_OVERRIDE=1 lets the two endpoints' finish
  # chains run side by side (memory gate_launch still applies to every launch).
  [ "${ALONE_OVERRIDE:-0}" = 1 ] && { echo "  wait_alone: ALONE_OVERRIDE=1 for $lab (24G cage)"; return 0; }
  while :; do
    local busy
    busy=$(ps -eo comm=,args= | awk '($1=="python3" && (/coverage_report\.py/ || /confinement_census/ || /_exact_enum/ || /_part_decomp/ || /_conj_price/ || /_engine_section/ || /_matched_ctx_check/)) || ($1=="java" && /-cp .*subsume/)' | head -1)
    [ -z "$busy" ] && { [ "$w" -gt 0 ] && echo "  box alone for $lab after ${w}s"; return 0; }
    [ $((w % 300)) -eq 0 ] && echo "  waiting to be ALONE for $lab (${w}s): $(echo "$busy" | cut -c1-88)"
    sleep 30; w=$((w+30))
  done
}

# HEAVY-JOB GATE (coordinator, 2026-09-11 19:4x): the final pass, the engine
# section and the blockaid subsumption are queued behind REAL memory returning
# to the box — i.e. the editor language server being closed — rather than being
# run at a size the box cannot hold. They fire on their own when it does.
wait_free6() {
  local lab="${1:-heavy}" w=0
  while :; do
    local a
    a=$(free -g | awk 'NR==2{print $7}')
    if [ "${a:-0}" -ge 6 ]; then
      echo "  free-6 gate OPEN for $lab after ${w}s (free_avail=${a}G)"
      return 0
    fi
    [ $((w % 900)) -eq 0 ] && echo "  free-6 gate HOLD for $lab (${w}s): free_avail=${a}G (need 6) — waiting for the box to come back"
    sleep 60; w=$((w+60))
  done
}
