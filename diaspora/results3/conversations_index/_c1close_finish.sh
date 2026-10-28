#!/usr/bin/env bash
# conversations_index — post-extraction half of the 2026-09-26 closure pass.
#
# Runs after _pcfold3_parallel.py has written <endpoint>_c1close_{base,fix}.sql
# into the scratchpad. Steps follow reports/diaspora/results3/_redrive_20260919/
# _finish_rc1.sh (STEP 6-8) plus the F7 loadability audit that
# _P48_EXTRACTION_RECIPE.md §5 requires between extraction and grading.
#
# Promotes NOTHING to canonical: results3/queries_from_runs/conversations_index.sql
# is deliberately left as it stands (coordinator ruling 2026-09-26, consistent
# with _BENCHMARK_RUNS_20260919.md §2).
set -uo pipefail

R3=/home/dev/project/reports/diaspora/results3
B=$R3/conversations_index
QFR=$R3/queries_from_runs
RD=$R3/_redrive_20260919
BENCH=/home/dev/project/policy-extraction-bench
PY=/home/dev/project/venvs/queries_from_runs/bin/python3
SP=/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad/c1close_extract
LOG=$B/_c1close_finish.log

export QFR_APP_CONFIG=/home/dev/project/reports/diaspora/queries_config/app.json
unset JAVA_TOOL_OPTIONS

say() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }
: > "$LOG"

say "STEP 1: collect extraction output"
for arm in base fix; do
  src="$SP/conversations_index_c1close_${arm}.sql"
  if [ ! -f "$src" ]; then say "  MISSING $src"; exit 2; fi
  cp -p "$src" "$B/_c1close_${arm}.sql"
  say "  $arm -> $B/_c1close_${arm}.sql ($(wc -c < "$B/_c1close_${arm}.sql") bytes, $(grep -c ';$' "$B/_c1close_${arm}.sql") stmts)"
done
cp -p "$SP/_summary_conversations_index_c1close.json" "$B/_c1close_summary.json" 2>/dev/null && say "  summary copied"

say "STEP 2: ensure POLICY_HEADER.txt is on the fix arm (idempotent)"
# NOTE: _pcfold3_parallel.py:168 already calls dump_mod._header_for(dirname(dumpdir),
# endpoint). With --dumpdir results3/conversations_index that resolves to
# results3/conversations_index/POLICY_HEADER.txt, so the header is spliced BY THE
# EXTRACTOR. (RC-1 got no header only because its dumpdir was
# _redrive_20260919/conversations_index, where no POLICY_HEADER.txt exists — which
# is why conversations_index_rc1mod_fix.sql carries the provenance block alone.)
# This step therefore only splices when the header is genuinely absent.
if grep -q "CANONICAL HEADER" "$B/_c1close_fix.sql"; then
  say "  header already present (spliced by the extractor) — nothing to do"
  cp -p "$B/_c1close_fix.sql" "$B/_c1close_fix.headed.sql"
else
  say "  header absent — splicing"
# Same splice _x7_subsume_when_free.sh does for people_stream: strip the
# extractor's own leading comment block, then header + blank line + body.
# The extractor's provenance block is re-appended under the header so the
# dump/query counts are not lost.
python3 - <<'PY' 2>&1 | tee -a "$LOG"
B="/home/dev/project/reports/diaspora/results3/conversations_index"
hdr = open(f"{B}/POLICY_HEADER.txt").read().rstrip("\n")
p = f"{B}/_c1close_fix.sql"
lines = open(p).read().split("\n")
i = 0
prov = []
while i < len(lines) and (lines[i].startswith("--") or not lines[i].strip()):
    if lines[i].startswith("--"):
        prov.append(lines[i])
    i += 1
body = "\n".join(lines[i:])
out = f"{B}/_c1close_fix.headed.sql"
with open(out, "w") as fh:
    fh.write(hdr + "\n--\n-- ---------------------------------------------------------------------------\n"
             "-- EXTRACTION PROVENANCE (emitted by _pcfold3_parallel.py)\n"
             "-- ---------------------------------------------------------------------------\n"
             + "\n".join(prov).rstrip("\n") + "\n\n" + body)
print(f"  wrote {out}")
PY
fi

say "STEP 3: F7 loadability (both audits)"
PYTHONPATH=/home/dev/project/src $PY \
    /home/dev/project/src/queries_from_runs/audits/policy_loadability_audit.py \
    "$B" "$B/_c1close_fix.sql" --sample 2000 2>&1 | tail -12 | tee -a "$LOG"
python3 /home/dev/project/reports/diaspora/tools/policy_loadability.py \
    "$B/_c1close_fix.sql" 2>&1 | tail -8 | tee -a "$LOG"

say "STEP 4: build candidate jsonl (main-corpus arm) from the RC-1 baseline"
python3 "$RD/_build_and_grade.py" \
  "$RD/ours_rc1_all.jsonl" \
  "$B/_c1close_bench.jsonl" \
  "diaspora/conversations-index=$B/_c1close_fix.sql" 2>&1 | tee -a "$LOG"

say "STEP 5: grade"
cd "$BENCH" || exit 1
$PY -m bench.grade "$B/_c1close_bench.jsonl" 2>&1 | tee -a "$LOG"

say "C1CLOSE_FINISH_COMPLETE"
