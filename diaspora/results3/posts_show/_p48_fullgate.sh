#!/usr/bin/env bash
# P48 FULL GATE over the v2 corpus — coverage + assumption gate + audits.
#
#   usage: _p48_fullgate.sh <snapshot.txt> [tag]
#
# Successor to `_real8_launch.sh`. Everything _real8_launch.sh did is kept; the
# differences are all forced by the v2 regeneration and by who else is on the
# box, and each is stated here because every one of them is silent if wrong.
#
# ---------------------------------------------------------------------------
# 1. FRESH CHECKPOINTS, NOT THE OLD ONES.
#
# `_real4_probes.ckpt.jsonl`, `_real4_index.ckpt.jsonl` and
# `_real7_coverage.ckpt.jsonl` are keyed to the OLD, B-4-corrupted corpus. A
# checkpoint is a cache of answers about dumps that no longer describe the same
# shapes. They are KEPT (never deleted) and never reused.
#
# 2. THE WITHDRAWAL FILE MUST BE NAMED EXPLICITLY.
#
# `coverage_report.py:366` defaults `WITHDRAWN_PAIRS_FILE` to
# `_confinement_withdrawn.json` — the 564 pairs measured against the B-4 corpus.
# Not passing this variable is not "no withdrawals", it is "the stale ones".
# We point at `_confinement_withdrawn_v3.json` — the file the v3 coverage-only
# pass used — which the fix-#2 feedback loop (`_extend_withdrawn_file`) refills
# from THIS corpus's own gate verdicts.
#
# CORRECTED 2026-09-26 22:41, caught 30 s into the first launch. This script was
# written while v2 was the live corpus and hardcoded
# `_confinement_withdrawn_v2.json`. The B-6 re-drive made v3 a THIRD note
# generation, and a withdrawal is a gate refutation against a PARTICULAR
# corpus's call-shapes. The v2 file happened to be EMPTY (`[]`), so nothing
# unsound would have been read IN — but `_extend_withdrawn_file` WRITES BACK,
# so a 12 h gate would have filed v3's refutations under a v2 name. That is
# provenance corruption of exactly the kind this campaign keeps paying for, and
# it is invisible afterwards. The corpus name now derives from the SNAPSHOT so
# it cannot drift from the corpus again.
#
# 3. PRIOR FOOTPRINTS: still disabled unless a v2 baseline has been promoted.
#
# `_prior_footprints.json` was measured on the B-4 corpus (conflated,
# value-sensitive `call_shape`s). The corpus tripwire
# (`coverage.py:2760-2768`) would withdraw pairs on that basis — the old pass
# reported WITHDRAWN_TRIPWIRE=745. Conservative, never unsound, but a large
# pessimism from a corrupted baseline. Set PRIOR_FOOTPRINTS=1 on a LATER pass,
# after deliberately promoting a v2 footprints file.
#
# 4. THE JRUBY SLOT NAMESPACE — this is the one that hurts other people.
#
# The assumption gate spawns JRuby through `assumption_manifest.json`'s
# `runner`, which is `reports/diaspora/tools/slot ...` — the SHARED namespace
# (/tmp/concolic-slot-N.lock). `tools/slot` searches slots 1..$CONCOLIC_SLOTS
# and HAS NO NOTION OF RESERVATION: N is a SEARCH RANGE. _real8_launch.sh set
# CONCOLIC_SLOTS=6, so it searched 1..6 — and conversations_index's full gate
# runs CONCOLIC_SLOTS=3 and can only ever use slots 1-3. A P48 pass at 6 would
# take all three of them as they fell free and hold each for its command's
# whole life. That is the 2026-09-25 04:20 incident, and it is why
# `_p47_slot.sh` exists.
#
# So this script uses a PRIVATE manifest (`_p48_assumption_manifest.json`)
# whose runner is `_p47_slot.sh`, and sizes itself with $P47_SLOTS. Two jobs can
# share one namespace only if they AGREE on the pool size; separate namespaces
# mean each caps itself and the launcher sizes the total.
#
#   CHECK BEFORE LAUNCH: if conversations_index's gate has finished, this is
#   still correct — a private namespace is never wrong, only sometimes
#   unnecessary. Do not "simplify" it back to tools/slot.
#
# 5. MEMORY.
#
# 48G cap. Measured on this endpoint: 32G was OOM-killed, peak 36.9G — on the
# OLD 206k-dump snapshot. v2 is 165k dumps, so expect less, but the cap stays
# where the measurement put it. The cap is not a reservation; watch the box.
set -euo pipefail
SNAP="${1:?usage: _p48_fullgate.sh <snapshot.txt> [tag]}"
TAG="${2:-P48GATE}"
B=/home/dev/project/reports/diaspora/results3/posts_show
cd /home/dev/project

[ -s "$SNAP" ] || { echo "snapshot $SNAP is empty or missing" >&2; exit 2; }

# Derive the corpus tag from the snapshot filename (_snapshot_v3_*.txt -> v3)
# rather than hardcoding it, so this can never again name a different corpus
# than the one being gated.
CORPUS_TAG=$(basename "$SNAP" | sed -n 's/^_snapshot_\(v[0-9]*\)_.*/\1/p')
[ -n "$CORPUS_TAG" ] || { echo "REFUSING: cannot derive corpus tag from $(basename "$SNAP")" >&2; exit 2; }
WD="$B/_confinement_withdrawn_${CORPUS_TAG}.json"
[ -f "$WD" ] || echo '[]' > "$WD"

MAN="$B/_p48_assumption_manifest.json"
[ -f "$MAN" ] || { echo "missing $MAN (private-slot manifest)" >&2; exit 2; }

# coverage_report.py:605 hardcodes `completion_config.json` — there is NO env
# override — so the private-slot manifest only takes effect if that file's
# `assumption_cfg` names it. Refuse rather than run the shared-slot runner by
# accident: the failure mode is invisible (the gate just works, while quietly
# holding the protected endpoint's slots).
CC="$B/completion_config.json"
python3 - "$CC" "$MAN" <<'PY' || exit 2
import json, sys
cc, man = sys.argv[1], sys.argv[2]
d = json.load(open(cc))
if d.get("assumption_cfg") != man:
    sys.exit("REFUSING: completion_config.json:assumption_cfg is\n"
             "    %s\nbut this launcher requires\n    %s\n"
             "Point it at the private-slot manifest (keep a .bak) before launching."
             % (d.get("assumption_cfg"), man))
print("assumption_cfg OK -> %s" % man)
PY

# SUMMARY_OUT must NOT be set here. coverage_report.py:607 treats it (like
# NO_PINS) as a COUNTERFACTUAL/scratch pass and forces `complete: False`
# without running the completion gate at all. The full pass writes
# coverage_summary.json in place, which is exactly what a shipped verdict is.
if [ -n "${SUMMARY_OUT:-}" ]; then
  echo "REFUSING: SUMMARY_OUT is set; that forces a counterfactual pass with complete=False" >&2
  exit 2
fi

# PRIOR_FOOTPRINTS=1 opts IN to the tripwire (see note 3). Default is OFF, and
# it is expressed as an explicit array element rather than a `${x:+}` expansion
# so that an unexpected value cannot turn into a stray `env` argument.
PF=(NO_PRIOR_FOOTPRINTS=1)
if [ "${PRIOR_FOOTPRINTS:-0}" = "1" ]; then
  PF=()
  echo "[$(date -Is)] $TAG: prior-footprint tripwire ENABLED (opted in)"
fi

echo "[$(date -Is)] $TAG: $(wc -l < "$SNAP") dumps from $SNAP"
echo "[$(date -Is)] $TAG: withdrawal=$WD  manifest=$MAN  P47_SLOTS=${P47_SLOTS:-3}"

exec env \
  DUMP_LIST="$SNAP" \
  WITHDRAWN_PAIRS_FILE="$WD" \
  "${PF[@]}" \
  FOOTPRINTS_OUT="$B/_p48_${TAG}_footprints.json" \
  COVERAGE_CHECKPOINT="$B/_p48_${TAG}_coverage.ckpt.jsonl" \
  ACHK_CHECKPOINT="$B/_p48_${TAG}_probes.ckpt.jsonl" \
  ACHK_INDEX_CHECKPOINT="$B/_p48_${TAG}_index.ckpt.jsonl" \
  ACHK_CONF_PROFILES=500 \
  ACHK_PROBE_BATCH=4 \
  P47_SLOTS="${P47_SLOTS:-3}" \
  CONCOLIC_PROBE_WORKERS="${CONCOLIC_PROBE_WORKERS:-3}" \
  MAX_MISSING_PER_CLIQUE="${MAX_MISSING_PER_CLIQUE:-4}" \
  HEARTBEAT_SECS=300 \
  JAVA_TOOL_OPTIONS= \
  PYTHONPATH=/home/dev/project/src \
  /usr/bin/time -v -o "$B/_p48_${TAG}.time" \
  python3 -u "$B/coverage_report.py"
