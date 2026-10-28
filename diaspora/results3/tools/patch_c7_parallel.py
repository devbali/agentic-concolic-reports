#!/usr/bin/env python3
"""Rewrite a batch's _c7_audits.sh so its audits run CONCURRENTLY.

The audits are independent read-only scans over one corpus and were run one
after another (3 h 10 m on notifications' 311k dumps, bounded below by
cardinality_consistency ~59 min).  This patch turns `run` from "execute now,
append to the log" into "enqueue", adds a bounded-width drain and an emitter
that writes each audit's section into $LOG in the ORIGINAL SCRIPT ORDER.

Preserved exactly:
  * each audit's own `##### name #####` section and its `EXIT=` line,
  * the order of those sections (so `grep -c '#####'` and a reader both work),
  * the AUDITS_CHECKPOINT=1 done-marker logic AND its key (untouched: the
    width is not an input to anything an audit reads),
  * the final `=== c7 audits DONE` verdict line and the trailing echo blocks
    of the people_stream / posts_show copies.

Every anchor is asserted UNIQUE before it is spliced.
"""
import hashlib
import re
import shutil
import sys
import time
from pathlib import Path

OLD_RUN = '''run() {
  local _n="$1"; shift
  echo "" >> "$LOG"; echo "##### $_n #####" >> "$LOG"
  if [ -n "${AUDITS_CHECKPOINT:-}" ] && [ -f "$CKDIR/$_n.ok" ]; then
    cat "$CKDIR/$_n.out" >> "$LOG" 2>/dev/null
    echo "EXIT=0 [checkpoint: replayed, not re-run]" >> "$LOG"
    return 0
  fi
  if [ -n "${AUDITS_CHECKPOINT:-}" ]; then
    rm -f "$CKDIR/$_n.ok"
    "$@" > "$CKDIR/$_n.out" 2>&1; local _rc=$?
    cat "$CKDIR/$_n.out" >> "$LOG"; echo "EXIT=$_rc" >> "$LOG"
    [ "$_rc" = "0" ] && touch "$CKDIR/$_n.ok"
    return $_rc
  fi
  "$@" >> "$LOG" 2>&1; echo "EXIT=$?" >> "$LOG"
}
'''

NEW_RUN = r'''# PARALLEL (2026-09-14). These audits are INDEPENDENT read-only scans over one
# corpus and were run one after another: 3 h 10 m on notifications' 311k dumps,
# against a lower bound of ~59 min (cardinality_consistency). They now run
# CONCURRENTLY at a bounded width.
#   `run` ENQUEUES; `_c7_drain` executes at width W; `_c7_emit` appends each
#   audit's section to $LOG in the ORIGINAL SCRIPT ORDER. Output is buffered
#   per audit and never interleaved -- interleaving would destroy both the
#   log's readability and the `grep -c '#####'` progress checks. The section
#   text, the EXIT= line and the checkpoint replay marker are byte-for-byte
#   what the sequential script produced.
#   WIDTH: AUDITS_PAR unset/auto -> min(nproc, memory budget); AUDITS_PAR=1 ->
#   exactly the old one-at-a-time behaviour (kept for differentials);
#   AUDITS_PAR=<n> -> that width. Several audits peak at 2-3 GB resident, so
#   MEMORY caps the width as well as cores: (MemAvailable - 4 GB headroom) / 3 GB.
#   The width is deliberately NOT an input to the checkpoint key -- it changes
#   nothing any audit reads, and folding it in would invalidate every marker on
#   a box with a different core count.
#   PROGRESS while running: the log is written at the end, so watch
#   `$B/_c7_audits.par/*.sec` (or, with the checkpoint on, `$CKDIR/*.ok`).
_c7_width() {
  local _w="${AUDITS_PAR:-auto}"
  if [ "$_w" != "auto" ]; then echo "$_w"; return 0; fi
  local _cpu _memkb _mw
  _cpu=$(nproc)
  _memkb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
  _mw=$(( (_memkb - 4*1024*1024) / (3*1024*1024) ))   # 3 GB/audit, 4 GB spare
  [ "$_mw" -lt 1 ] && _mw=1
  [ "$_cpu" -lt "$_mw" ] && _mw=$_cpu
  echo "$_mw"
}
PARDIR="$B/_c7_audits.par"
rm -rf "$PARDIR"; mkdir -p "$PARDIR"
_QN=0; declare -a _QNAME
run() {
  local _n="$1"; shift
  _QNAME[$_QN]="$_n"
  printf '%q ' "$@" > "$PARDIR/$_QN.cmd"      # %q round-trips through eval
  _QN=$((_QN+1))
}
# One audit, into its OWN buffer files. No two workers share a path: the
# checkpoint output file is $CKDIR/<name>.out and the names are distinct, so
# the done-marker logic is concurrency-safe as written.
_c7_one() {
  local _i="$1" _n="${_QNAME[$1]}" _rc _sec="$PARDIR/$1.sec"
  { echo ""; echo "##### $_n #####"; } > "$_sec"
  if [ -n "${AUDITS_CHECKPOINT:-}" ] && [ -f "$CKDIR/$_n.ok" ]; then
    cat "$CKDIR/$_n.out" >> "$_sec" 2>/dev/null
    echo "EXIT=0 [checkpoint: replayed, not re-run]" >> "$_sec"
    return 0
  fi
  if [ -n "${AUDITS_CHECKPOINT:-}" ]; then
    rm -f "$CKDIR/$_n.ok"
    eval "$(cat "$PARDIR/$_i.cmd")" > "$CKDIR/$_n.out" 2>&1; _rc=$?
    cat "$CKDIR/$_n.out" >> "$_sec"; echo "EXIT=$_rc" >> "$_sec"
    [ "$_rc" = "0" ] && touch "$CKDIR/$_n.ok"
    return $_rc
  fi
  eval "$(cat "$PARDIR/$_i.cmd")" > "$PARDIR/$_i.raw" 2>&1; _rc=$?
  cat "$PARDIR/$_i.raw" >> "$_sec"; echo "EXIT=$_rc" >> "$_sec"
  return $_rc
}
_c7_drain() {
  local _W _i _t0 _t1
  _W=$(_c7_width); [ "$_W" -lt 1 ] && _W=1
  [ "$_W" -gt "$_QN" ] && _W=$_QN
  _t0=$(date +%s)
  echo "[parallel] width=$_W over $_QN audits (nproc=$(nproc), MemAvailable=$(awk '/^MemAvailable:/{printf "%.1fG", $2/1048576}' /proc/meminfo), AUDITS_PAR=${AUDITS_PAR:-auto}); sections are emitted in SCRIPT ORDER" >> "$LOG"
  if [ "$_W" -le 1 ]; then
    for ((_i=0; _i<_QN; _i++)); do _c7_one "$_i"; done
  else
    for ((_i=0; _i<_QN; _i++)); do
      while [ "$(jobs -rp | wc -l)" -ge "$_W" ]; do wait -n 2>/dev/null || sleep 0.2; done
      _c7_one "$_i" &
    done
    wait
  fi
  _t1=$(date +%s)
  for ((_i=0; _i<_QN; _i++)); do cat "$PARDIR/$_i.sec" >> "$LOG"; done
  echo "" >> "$LOG"
  echo "[parallel] $_QN audits finished in $(( _t1 - _t0 ))s at width $_W" >> "$LOG"
}
'''

DRAIN_CALL = '_c7_drain   # run the queued audits and emit their sections in order\n'


def patch(path: Path) -> None:
    src = path.read_text()

    # -- anchor 1: the sequential `run` helper, asserted unique ------------
    n = src.count(OLD_RUN)
    assert n == 1, f"{path}: `run()` anchor matched {n} times, expected 1"
    out = src.replace(OLD_RUN, NEW_RUN)

    # -- anchor 2: after the LAST `run <name> ...` invocation (plus any
    #    backslash continuations), before the trailing echo blocks / DONE.
    lines = out.split("\n")
    idx = [i for i, l in enumerate(lines) if re.match(r"^run\s+\S", l)]
    assert idx, f"{path}: no `run <name>` invocations found"
    last = idx[-1]
    while lines[last].rstrip().endswith("\\"):
        last += 1
    # the splice point must not already carry a drain, and must precede DONE
    done = [i for i, l in enumerate(lines) if "c7 audits DONE" in l]
    assert len(done) == 1, f"{path}: DONE line matched {len(done)} times"
    assert last < done[0], f"{path}: last run at {last} is after DONE at {done[0]}"
    assert not any("_c7_drain" in l for l in lines[last + 1:]), \
        f"{path}: a drain call already exists"
    lines.insert(last + 1, DRAIN_CALL.rstrip("\n"))
    out = "\n".join(lines)

    # -- sanity: every enqueued audit still present, DONE still last ------
    assert out.count("run ") >= 15, f"{path}: lost run invocations"
    assert "=== c7 audits DONE" in out
    assert 'grep -n "EXIT=" "$LOG"' in out

    bak = path.with_name(path.name + f".seq_{time.strftime('%Y%m%d_%H%M%S')}")
    shutil.copy2(path, bak)
    path.write_text(out)
    path.chmod(0o755)
    print(f"patched {path}\n  backup {bak}\n  md5 {hashlib.md5(out.encode()).hexdigest()[:8]}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        patch(Path(p))
