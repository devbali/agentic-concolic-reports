#!/bin/bash
# C7 closing checks — every judge, current tools, populations printed.
# Run AFTER the regenerated corpus exists. No outer flock anywhere: the only
# heavy phase (coverage) self-locks, and these are bounded scans.
set +e; unset JAVA_TOOL_OPTIONS; cd /home/dev/project
# E12 (2026-09-11): src/queries_from_runs is app-agnostic and REQUIRES an
# app config; bind_resolution_audit and identity_symbolicity_audit read the
# schema and the principal columns from it and go RED without one.
export QFR_APP_CONFIG="${QFR_APP_CONFIG:-/home/dev/project/reports/diaspora/queries_config/app.json}"
B=/home/dev/project/reports/diaspora/results3/notifications_index
A=/home/dev/project/src/queries_from_runs/audits
T=/home/dev/project/reports/diaspora/tools
V=/home/dev/project/venvs/queries_from_runs/bin/python
LOG="$B/_c7_audits.log"; echo "=== c7 audits $(date -Is) ===" > "$LOG"
echo "corpus POPULATION: $(find $B -maxdepth 1 -name 'dump_*.json' | wc -l) dumps" >> "$LOG"   # find, not ls: past ARG_MAX ls returns 0
# CHECKPOINT (owner rule, 2026-09-12): this suite is 65+ min on posts_show and
# was still unfinished after 54 min on notifications, and it recomputed every
# audit from zero on a rerun (the log is truncated at the top of this script).
# With AUDITS_CHECKPOINT=1 each audit's OUTPUT is written to its own file under
# $B/_c7_audits.done/ as it finishes; a rerun REPLAYS an audit that finished
# with EXIT=0 into the log instead of re-running it, so the log is still
# complete. Unset (the default) = exactly the old behaviour, every audit run.
# The markers are keyed on the corpus (dump count + newest dump mtime), on this
# script's own hash, on the AUDIT SCRIPTS' SOURCE and on QFR_APP_CONFIG, and the
# whole directory is discarded when the key changes -- a stale audit result is
# never replayed. The old known limit ("the key does not see a CHANGE to an
# audit TOOL under src/ or tools/; bump this script when one of those changes")
# is CLOSED as of 2026-09-13: a fixed tool now invalidates the markers by
# itself. The `[checkpoint] key inputs:` line in the log names every component
# that went into the key, so the record shows what was digested.
CKDIR="$B/_c7_audits.done"
if [ -n "${AUDITS_CHECKPOINT:-}" ]; then
  mkdir -p "$CKDIR"
  _pop=$(find "$B" -maxdepth 1 -name 'dump_*.json' | wc -l)
  _new=$(find "$B" -maxdepth 1 -name 'dump_*.json' -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
  _self=$(md5sum "$0" | cut -d' ' -f1)
  # 2026-09-13: the AUDIT SCRIPTS' SOURCE is part of the key. Every *.py under
  # $A (src/queries_from_runs/audits) and $T (reports/diaspora/tools), plus this
  # batch's OWN audit scripts, is hashed in a stable (sorted) order; a file that
  # is not there contributes nothing and is not an error. So is the app config
  # the src/queries_from_runs audits read ($QFR_APP_CONFIG) -- without it
  # bind_resolution and identity_symbolicity go RED, so its content is an input.
  _tools=$( { find "$A" "$T" -maxdepth 1 -name '*.py' -print0 2>/dev/null;
              find "$B" -maxdepth 1 \( -name '_c7_*.py' -o -name '_lint_streaming.py' \
                       -o -name 'format_coverage_audit.py' \) -print0 2>/dev/null; } \
            | sort -z | xargs -0 -r md5sum 2>/dev/null | md5sum | cut -d' ' -f1)
  _ntools=$( { find "$A" "$T" -maxdepth 1 -name '*.py' -print 2>/dev/null;
               find "$B" -maxdepth 1 \( -name '_c7_*.py' -o -name '_lint_streaming.py' \
                        -o -name 'format_coverage_audit.py' \) -print 2>/dev/null; } | wc -l)
  _appcfg=$(md5sum "$QFR_APP_CONFIG" 2>/dev/null | cut -d' ' -f1)
  _key=$(printf '%s|%s|%s|%s|%s' "$_pop" "$_new" "$_self" "$_tools" "$_appcfg" \
         | md5sum | cut -d' ' -f1)
  echo "[checkpoint] key inputs: dumps=$_pop newest_dump_mtime=$_new self(${0##*/})=${_self:0:8}" \
       "audit_tools=${_tools:0:8} ($_ntools *.py under $A, $T and this batch)" \
       "qfr_app_config=${_appcfg:0:8} ($QFR_APP_CONFIG) -> key ${_key:0:12}" >> "$LOG"
  if [ -f "$CKDIR/_key" ] && [ "$(cat "$CKDIR/_key")" != "$_key" ]; then
    echo "[checkpoint] audit inputs changed; discarding $CKDIR" >> "$LOG"
    rm -rf "$CKDIR"; mkdir -p "$CKDIR"
  fi
  echo "$_key" > "$CKDIR/_key"
  echo "[checkpoint] ON: $(find "$CKDIR" -name '*.ok' | wc -l) audit(s) already finished" >> "$LOG"
fi
# PARALLEL (2026-09-14). These audits are INDEPENDENT read-only scans over one
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

run identity_symbolicity    env PYTHONPATH=/home/dev/project/src python3 $A/identity_symbolicity_audit.py "$B"
run statement_note_lint     env PYTHONPATH=/home/dev/project/src python3 $A/statement_note_lint.py "$B"
run bind_resolution         env PYTHONPATH=/home/dev/project/src $V $A/bind_resolution_audit.py "$B"
# MANDATORY BOTH WAYS before any extraction (RUNBOOK 2026-09-01): vanilla and
# patched. If they differ the extractor MUST install variant_d's assoc_fold.
run skipped_pcs_VANILLA     env PYTHONPATH=/home/dev/project/src $V $A/skipped_pcs_audit.py "$B"
run skipped_pcs_PATCHED     env PYTHONPATH=/home/dev/project/src $V $A/skipped_pcs_audit.py "$B" --patched /home/dev/project/reports/diaspora/results3/_experiment/variant_d
run pc_visibility           env PYTHONPATH=/home/dev/project/src python3 $A/pc_visibility_audit.py "$B" --gate type,unread,persisted,guid,first_name,last_name,person_id,diaspora_handle,rows,language
run empty_relation          env PYTHONPATH=/home/dev/project/src python3 $A/empty_relation_emission_audit.py "$B"
run noteless_call           env PYTHONPATH=/home/dev/project/src python3 $A/noteless_call_audit.py "$B"
run cardinality_consistency env PYTHONPATH=/home/dev/project/src python3 $A/cardinality_consistency_audit.py "$B"
run rig_crash_census        python3 $T/rig_crash_census.py "$B"
run boundary_declaration    env PYTHONPATH=/home/dev/project/src python3 $T/boundary_declaration_audit.py "$B" /home/dev/project/reports/diaspora/results3/comments_index /home/dev/project/reports/diaspora/results3/conversations_index
run format_coverage         python3 "$B/format_coverage_audit.py" "$B"
run note_fidelity           env PYTHONPATH=/home/dev/project/src $V $T/note_fidelity_audit.py "$B" "$B/concrete_run.json" --aliases "$B/concrete_aliases.json"
# H6 needs ONE --runs followed by EVERY run file, or it is skipped.
run hardening_lint          env PYTHONPATH=/home/dev/project/src python3 $T/hardening_lint.py "$B" --sample 400 \
      --runs "$B/concrete_run.json" $(ls "$B"/_c7_cr_*.json 2>/dev/null) $(ls "$B"/adversary/runs/A0*.json 2>/dev/null)
run count_matrix            python3 "$B/_c7_count_matrix.py" "$B" --runs "$B/concrete_run.json"
run variant_tuple_check     python3 "$B/_c7_variant_tuple_check.py"
_c7_drain   # run the queued audits and emit their sections in order
echo "" >> "$LOG"; echo "=== c7 audits DONE $(date -Is) ===" >> "$LOG"
grep -n "EXIT=" "$LOG"
