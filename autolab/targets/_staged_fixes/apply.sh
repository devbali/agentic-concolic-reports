#!/usr/bin/env bash
#
# apply.sh — copy the staged D1-D8 fixes over the LIVE target library.
#
# WHY THIS EXISTS. A shakedown was driving 161 endpoints against
# `reports/autolab/targets/core.rb` while these fixes were built, and editing
# those files in place would have silently corrupted a multi-hour run. Every
# fix was therefore built and verified in `_staged_fixes/`, which mirrors the
# live layout. This script is the only thing that touches the live files.
#
#   RUN IT ONLY WHEN NO RUN IS IN FLIGHT.
#
# It is:
#   * pre-flighted   — every source is syntax-checked and every destination's
#                      current content is recorded before anything is written;
#   * atomic per file — each destination is written by `mv` of a temp file in
#                      the same directory, so no reader ever sees a half file;
#   * reversible     — every replaced file is copied to a timestamped backup
#                      directory, and `apply.sh --revert <dir>` puts them back;
#   * idempotent     — re-running it changes nothing once applied.
#
# WHAT IT TOUCHES, and nothing else:
#   reports/autolab/targets/core.rb
#   reports/autolab/targets/endpoints/aspect_memberships_create.rb
#   reports/diaspora/results4/aspect_memberships_create/concolic_targets.rb   (= core.rb)
#   reports/diaspora/results4/comments_index/concolic_targets.rb              (= core.rb)
#   reports/diaspora/results4/aspect_memberships_create/targets.rb            (= the endpoint layer)
#   reports/autolab/targets/registry.json                                     (md5 fields only)
#
# It does NOT touch reports/diaspora/results3/ (explicit instruction), src/,
# src_new/, shared_shims.rb (unchanged), or endpoints/comments_index.rb
# (unchanged). It does not run git.
set -euo pipefail

# ROOT is overridable ONLY so this script can be exercised end-to-end against a
# sandbox copy of the tree before it is ever pointed at the live one. Leave it
# unset for a real apply.
ROOT="${APPLY_ROOT:-/home/dev/project}"
STAGE="$ROOT/reports/autolab/targets/_staged_fixes"
LIVE="$ROOT/reports/autolab/targets"
R4="$ROOT/reports/diaspora/results4"

# source -> destination, one pair per line
MAP=(
  "$STAGE/core.rb|$LIVE/core.rb"
  "$STAGE/core.rb|$R4/aspect_memberships_create/concolic_targets.rb"
  "$STAGE/core.rb|$R4/comments_index/concolic_targets.rb"
  "$STAGE/endpoints/aspect_memberships_create.rb|$LIVE/endpoints/aspect_memberships_create.rb"
  "$STAGE/endpoints/aspect_memberships_create.rb|$R4/aspect_memberships_create/targets.rb"
)

die() { echo "apply.sh: $*" >&2; exit 1; }

# ---------------------------------------------------------------- revert
if [ "${1:-}" = "--revert" ]; then
  BK="${2:-}"
  [ -n "$BK" ] && [ -d "$BK" ] || die "usage: apply.sh --revert <backup-dir>"
  while IFS= read -r line; do
    src="${line%%|*}"; dst="${line##*|}"
    [ -f "$src" ] || die "backup missing: $src"
    cp -p "$src" "$dst.tmp.$$" && mv -f "$dst.tmp.$$" "$dst"
    echo "reverted  $dst"
  done < "$BK/MANIFEST"
  echo "revert complete from $BK"
  exit 0
fi

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

# ---------------------------------------------------------------- preflight
echo "== preflight =="

# 1. no concolic run may be in flight: editing these files under a running
#    sweep is exactly what staging existed to prevent.
if pgrep -fa "diaspora-concolic|sweep.py" >/dev/null 2>&1; then
  echo "WARNING: a concolic runner or sweep appears to be running:" >&2
  pgrep -fa "diaspora-concolic|sweep.py" >&2 || true
  if [ "${FORCE:-0}" != "1" ]; then
    die "refusing to write the live target library while a run is in flight (FORCE=1 to override)"
  fi
fi

# 2. every source exists and parses
for pair in "${MAP[@]}"; do
  src="${pair%%|*}"; dst="${pair##*|}"
  [ -f "$src" ] || die "staged source missing: $src"
  [ -d "$(dirname "$dst")" ] || die "destination directory missing: $(dirname "$dst")"
  case "$src" in
    *.rb) ruby -c "$src" >/dev/null || die "staged source does not parse: $src" ;;
  esac
done
echo "   all sources present and parse"

# 3. the live files are what we branched from — if someone else changed them
#    since, stop rather than clobber.
# A destination is acceptable if it is EITHER the baseline this staging
# branched from, OR already exactly the staged source (a re-run — this is what
# makes the script idempotent). Anything else means someone edited the live
# file since staging, and the right answer is to stop, not to clobber it.
BASE="$STAGE/BASELINE_MD5"
if [ -f "$BASE" ]; then
  for pair in "${MAP[@]}"; do
    src="${pair%%|*}"; dst="${pair##*|}"
    got="$(md5sum "$dst" | awk '{print $1}')"
    srcmd5="$(md5sum "$src" | awk '{print $1}')"
    key="${dst/#$ROOT/\/home\/dev\/project}"
    want="$(awk -v k="$key" '$2 == k {print $1}' "$BASE" | head -1)"
    [ -n "$want" ] || die "BASELINE_MD5 has no entry for $key — re-stage before applying"
    if [ "$got" != "$want" ] && [ "$got" != "$srcmd5" ]; then
      die "live file changed since staging: $dst (have $got, expected baseline $want or staged $srcmd5) — re-stage before applying"
    fi
  done
  echo "   every destination is either the staged baseline or already applied"
else
  die "BASELINE_MD5 missing — refusing to apply without a drift check"
fi

if [ "$DRY" = "1" ]; then
  echo "== dry run: nothing written =="
  for pair in "${MAP[@]}"; do echo "   would write ${pair##*|}"; done
  exit 0
fi

# ---------------------------------------------------------------- backup
BK="$STAGE/_backup_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BK"
: > "$BK/MANIFEST"
i=0
for pair in "${MAP[@]}"; do
  dst="${pair##*|}"
  i=$((i + 1))
  b="$BK/$(printf '%02d' "$i")_$(basename "$dst")"
  cp -p "$dst" "$b"
  echo "$b|$dst" >> "$BK/MANIFEST"
done
echo "== backed up $i file(s) to $BK =="

# ---------------------------------------------------------------- write
for pair in "${MAP[@]}"; do
  src="${pair%%|*}"; dst="${pair##*|}"
  if cmp -s "$src" "$dst"; then
    echo "unchanged $dst"
    continue
  fi
  tmp="$(dirname "$dst")/.apply.$$.$(basename "$dst")"
  cp -p "$src" "$tmp"
  mv -f "$tmp" "$dst"          # same filesystem -> atomic rename
  echo "wrote     $dst"
done

# ---------------------------------------------------------------- registry
# registry.json records the md5 of the file each layer was copied from. The
# copies just changed, so the recorded md5s must change with them or the
# registry asserts a provenance that is no longer true.
CORE_MD5="$(md5sum "$LIVE/core.rb" | awk '{print $1}')"
EP_MD5="$(md5sum "$LIVE/endpoints/aspect_memberships_create.rb" | awk '{print $1}')"
python3 - "$LIVE/registry.json" "$CORE_MD5" "$EP_MD5" <<'PY'
import json, sys
p, core_md5, ep_md5 = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
d["core"]["source_md5"] = core_md5
d["endpoints"]["aspect_memberships_create"]["source_md5"] = ep_md5
with open(p + ".tmp", "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
import os
os.replace(p + ".tmp", p)
print("registry.json md5s updated")
PY

# ---------------------------------------------------------------- verify
echo "== verify =="
fail=0
for pair in "${MAP[@]}"; do
  src="${pair%%|*}"; dst="${pair##*|}"
  cmp -s "$src" "$dst" || { echo "MISMATCH $dst" >&2; fail=1; }
done
# the two files the brief requires to stay byte-identical
cmp -s "$LIVE/endpoints/aspect_memberships_create.rb" \
       "$R4/aspect_memberships_create/targets.rb" \
  || { echo "MISMATCH: autolab endpoint layer != results4 targets.rb" >&2; fail=1; }
[ "$fail" = "0" ] || die "post-apply verification FAILED — revert with: $0 --revert $BK"
echo "   every destination matches its staged source"
echo "   autolab endpoint layer and results4 targets.rb are byte-identical"
echo
echo "applied. revert with:  $0 --revert $BK"
