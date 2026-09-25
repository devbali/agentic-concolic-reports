#!/bin/bash
# Harness for the AUDITS_CHECKPOINT key of results3/*/_c7_audits.sh.
# It extracts the REAL checkpoint block out of the script and evaluates it
# against a sandbox batch/tools tree. No audit is ever run.
set -u
S="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-/home/dev/project/reports/diaspora/results3/posts_show/_c7_audits.sh}"
W="${HARNESS_TMP:-${TMPDIR:-/tmp}}/c7_key_harness"; rm -rf "$W"; mkdir -p "$W/B" "$W/A" "$W/T"
printf 'print("a1")\n' > "$W/A/identity_symbolicity_audit.py"
printf 'print("a2")\n' > "$W/A/noteless_call_audit.py"
printf 'print("t1")\n' > "$W/T/hardening_lint.py"
printf 'print("b1")\n' > "$W/B/_c7_count_matrix.py"
printf '{"schema": 1}\n' > "$W/app.json"
printf '{}\n' > "$W/B/dump_1.json"

# the REAL block, verbatim: from CKDIR= to the fi that closes it
sed -n '/^CKDIR=/,/^fi$/p' "$SRC" > "$W/block.sh"
[ -s "$W/block.sh" ] || { echo "could not extract the checkpoint block"; exit 2; }
cat > "$W/probe.sh" <<'PROBE'
B="$WB"; A="$WA"; T="$WT"; LOG="$WLOG"
source "$WBLOCK"
PROBE

key() {
  : > "$W/log"
  env WB="$W/B" WA="$W/A" WT="$W/T" WLOG="$W/log" WBLOCK="$W/block.sh" \
      QFR_APP_CONFIG="$W/app.json" AUDITS_CHECKPOINT=1 \
      bash "$W/probe.sh" >/dev/null 2>&1
  cat "$W/B/_c7_audits.done/_key" 2>/dev/null
}
line() { grep -o '\[checkpoint\] key inputs: .*' "$W/log" | head -1; }
P=0; F=0
chk() { # chk <label> <same|diff> <ref>
  local l="$1" mode="$2" ref="$3" k; k=$(key)
  if { [ "$mode" = same ] && [ "$k" = "$ref" ]; } || { [ "$mode" = diff ] && [ "$k" != "$ref" ]; }
  then P=$((P+1)); printf 'ok    %-46s key %s\n' "$l" "${k:0:12}"
  else F=$((F+1)); printf 'FAIL  %-46s key %s (expected %s vs %s)\n' "$l" "${k:0:12}" "$mode" "${ref:0:12}"; fi
  LASTKEY="$k"
}

echo "=== AUDITS_CHECKPOINT key harness (no audit is run) ==="
echo "script under test: $SRC"; echo
K0=$(key); printf 'ok    %-46s key %s\n' "0 baseline" "${K0:0:12}"; P=$((P+1))
touch "$W/A/identity_symbolicity_audit.py"
chk "1 audit tool mtime-only touch"            same "$K0"
printf 'print("a1 FIXED")\n' > "$W/A/identity_symbolicity_audit.py"
chk "2 src/queries_from_runs audit CHANGED"    diff "$K0"; K2=$LASTKEY
printf 'print("a1")\n'       > "$W/A/identity_symbolicity_audit.py"
chk "3 restored -> back to the baseline key"   same "$K0"
printf 'print("t1 FIXED")\n' > "$W/T/hardening_lint.py"
chk "4 reports/diaspora/tools script CHANGED"  diff "$K0"
printf 'print("t1")\n'       > "$W/T/hardening_lint.py"
printf 'print("b1 FIXED")\n' > "$W/B/_c7_count_matrix.py"
chk "5 batch-local audit script CHANGED"       diff "$K0"
printf 'print("b1")\n'       > "$W/B/_c7_count_matrix.py"
printf 'print("new")\n'      > "$W/A/brand_new_audit.py"
chk "6 a NEW audit tool appears"               diff "$K0"
rm -f "$W/A/brand_new_audit.py"
printf '{"schema": 2}\n'     > "$W/app.json"
chk "7 QFR_APP_CONFIG content CHANGED"         diff "$K0"
printf '{"schema": 1}\n'     > "$W/app.json"
printf '{}\n'                > "$W/B/dump_2.json"
chk "8 corpus grew (the pre-existing input)"   diff "$K0"
rm -f "$W/B/dump_2.json"
chk "9 corpus restored"                        same "$K0"
echo
echo "--- the transparency line ---"; line
echo
echo "RESULT: $P passed, $F failed"
[ "$F" = 0 ]
