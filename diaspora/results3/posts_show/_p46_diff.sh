#!/usr/bin/env bash
# _p46_diff.sh -- bounded per-fix differential harness (phase (a), 2026-09-25).
#
# Each prerequisite fix in the posts_show stack is landed and validated ON ITS
# OWN before the corpus re-drive is committed to. The pattern is the one that
# proved B-4 (_p45_b4_ctl vs _p45_b4_fix):
#
#   * build a PRIVATE directory holding copies of run_dse.rb / targets.rb /
#     concolic_targets.rb, so nothing in the live batch dir moves,
#   * drive a small, fixed set of runs across all four scenarios,
#   * run the three REAL checks (mock_note_check, note_fidelity,
#     empty_relation_emission) against THAT directory -- they glob / take a
#     dump-list, so a private dir is exactly-scoped,
#   * diff the candidate's path conditions against the control's. A note fix
#     MUST leave every PC identical; anything else is a behaviour change
#     masquerading as a note repair.
#
# usage:
#   _p46_diff.sh build   <dir>            # private copy of the live batch files
#   _p46_diff.sh drive   <dir> [runs]     # drive all 4 scenarios into <dir>
#   _p46_diff.sh checks  <dir>            # the three real checks, scoped to <dir>
#   _p46_diff.sh compare <ctl> <trt>      # PC / note differential
set -uo pipefail

B=/home/dev/project/reports/diaspora/results3/posts_show
PY=/home/dev/project/venvs/queries_from_runs/bin/python
RUNS="${RUNS:-25}"
BUDGET="${TIME_BUDGET:-900}"

cmd="${1:?usage: build|drive|checks|compare}"; shift

case "$cmd" in

build)
  d="${1:?dir}"
  mkdir -p "$d"
  cp "$B/run_dse.rb" "$B/targets.rb" "$B/concolic_targets.rb" "$d/"
  # the checks need these; copy (not symlink) so the dir is self-contained
  cp "$B/concrete_run.json" "$B/concrete_aliases.json" "$d/" 2>/dev/null || true
  echo "built $d from the live batch files"
  ;;

drive)
  d="${1:?dir}"; r="${2:-$RUNS}"
  rm -f "$d"/dump_*.json
  cd /home/dev/project
  CONCOLIC_SLOTS="${CONCOLIC_SLOTS:-5}" MAX_RUNS="$r" TIME_BUDGET="$BUDGET" \
  JAVA_TOOL_OPTIONS= \
    reports/diaspora/tools/slot scripts/diaspora-concolic "$d/run_dse.rb" \
    > "$d/drive.log" 2>&1
  echo "drive exit=$? dumps=$(ls "$d"/dump_*.json 2>/dev/null | wc -l)"
  grep -E "runs=|drained=|\[stop\]" "$d/drive.log" | tail -8
  ;;

checks)
  d="${1:?dir}"
  ls "$d"/dump_*.json > "$d/_dumps.txt" 2>/dev/null
  echo "== scoped to $(wc -l < "$d/_dumps.txt") dumps in $d =="
  cd /home/dev/project
  echo "--- note_check ---"
  PYTHONPATH=/home/dev/project/src DUMP_LIST="$d/_dumps.txt" $PY \
    /home/dev/project/src/end_to_end_completion_checker/mock/mock_note_check.py \
    "$d/concrete_run.json" "$d" --aliases "$d/concrete_aliases.json" \
    --dump-list "$d/_dumps.txt" > "$d/_chk_note_check.txt" 2>&1
  echo "exit=$?"; grep -E "^RESULT|NOTE-MISMATCH|OUTSIDE any target" "$d/_chk_note_check.txt" | head -20
  echo "--- note_fidelity ---"
  PYTHONPATH=/home/dev/project/src $PY \
    /home/dev/project/reports/diaspora/tools/note_fidelity_audit.py \
    "$d" "$d/concrete_run.json" --aliases "$d/concrete_aliases.json" \
    > "$d/_chk_note_fidelity.txt" 2>&1
  echo "exit=$?"; grep -E "^RESULT|^-- " "$d/_chk_note_fidelity.txt" | head -20
  echo "--- empty_relation_emission ---"
  PYTHONPATH=/home/dev/project/src python3 \
    /home/dev/project/src/queries_from_runs/audits/empty_relation_emission_audit.py \
    "$d" --dump-list "$d/_dumps.txt" > "$d/_chk_empty_rel.txt" 2>&1
  echo "exit=$?"; grep -E "^RESULT|^-- " "$d/_chk_empty_rel.txt" | head -20
  ;;

compare)
  ctl="${1:?ctl}"; trt="${2:?trt}"
  python3 - "$ctl" "$trt" <<'PY'
import json, sys, glob, os, collections
ctl, trt = sys.argv[1], sys.argv[2]
def load(d):
    out={}
    for p in glob.glob(os.path.join(d,'dump_*.json')):
        out[os.path.basename(p)]=json.load(open(p))
    return out
C,T=load(ctl),load(trt)
print(f'dumps: control {len(C)}  treatment {len(T)}')
only_c=sorted(set(C)-set(T)); only_t=sorted(set(T)-set(C))
if only_c: print('  ONLY IN CONTROL  :', len(only_c), only_c[:5])
if only_t: print('  ONLY IN TREATMENT:', len(only_t), only_t[:5])
pcs=lambda d:[(e.get('expr'),e.get('taken')) for e in d.get('events') or [] if e.get('type')=='path_condition']
notes=lambda d:[(e.get('target'),str(e.get('note') or '')) for e in d.get('events') or [] if e.get('type')=='symbolic_call']
pc_same=pc_diff=0; note_changed=collections.Counter(); err_diff=[]
for k in sorted(set(C)&set(T)):
    a,b=C[k],T[k]
    if pcs(a)==pcs(b): pc_same+=1
    else: pc_diff+=1
    if a.get('error')!=b.get('error'): err_diff.append((k,a.get('error'),b.get('error')))
    na,nb=notes(a),notes(b)
    if len(na)==len(nb):
        for (t1,n1),(t2,n2) in zip(na,nb):
            if n1!=n2: note_changed[(t1,n1[:80],n2[:80])]+=1
    else:
        note_changed[('<EVENT COUNT DIFFERS>',f'{len(na)}',f'{len(nb)}')]+=1
print(f'shared dumps: {pc_same} with IDENTICAL path conditions, {pc_diff} DIFFERING')
if err_diff: print('  dump error changed in', len(err_diff), 'dumps:', err_diff[:4])
print(f'note changes: {len(note_changed)} distinct')
for (t,a,b),n in note_changed.most_common(12):
    print(f'  x{n:<5} {t}')
    print(f'      CTL: {a}')
    print(f'      TRT: {b}')
PY
  ;;

*) echo "unknown: $cmd" >&2; exit 2 ;;
esac
