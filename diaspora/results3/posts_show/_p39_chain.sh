#!/bin/bash
# P39 — wait out the drive legs, then run the re-pass. One unit, one verdict.
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
cd "$B" || exit 2
L="$B/_p39_chain.log"; : > "$L"
say(){ echo "[$(date -Is)] $*" >> "$L"; }
say "CHAIN: waiting for the four drive legs"
w=0
while [ "$(systemctl --user list-units 'posts-p39-drv-*' --state=running --no-legend | wc -l)" != 0 ]; do
  sleep 30; w=$((w+30))
  [ $((w % 300)) -eq 0 ] && say "  still driving (${w}s): $(grep -h 'DONE consumed' _chunk_drive_P39D3*.log 2>/dev/null | wc -l)/32 chunks"
  [ "$w" -gt 7200 ] && { say "CHAIN-ABORT: drive exceeded 2 h"; exit 9; }
done
nch=$(grep -h 'DONE consumed' _chunk_drive_P39D3*.log 2>/dev/null | wc -l)
ntox=$(grep -h 'toxic=' _chunk_drive_P39D3*.log 2>/dev/null | grep -vc 'toxic=0')
say "DRIVE FINISHED: $nch/32 chunks, $ntox chunk(s) with a toxic seed, corpus $(ls | grep -c '^dump_.*\.json$')"
for V in auth_html anon_html auth_json anon_json; do
  say "  leg $V result=$(systemctl --user show posts-p39-drv-$V -p Result --value)"
done
if [ "$nch" -lt 32 ]; then say "CHAIN: NOT all chunks finished -- re-pass runs anyway on what landed"; fi
say "CHAIN: launching the re-pass"
bash "$B/_p39_repass.sh" >> "$L" 2>&1
say "CHAIN-DONE rc=$?"
