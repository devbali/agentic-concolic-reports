#!/usr/bin/env bash
# Adversary scenario chain. One JRuby at a time machine-wide (flock), each
# scenario its own process (JVM-crash isolation), DONE line per scenario.
ADV=/home/dev/project/reports/diaspora/results3/notifications_index/adversary
LOG=$ADV/runs/_progress.log
PROBE=/home/dev/project/src/ruby_runtime/completion_checker/concrete_run_probe.rb
for tag in "$@"; do
  mf=$(ls $ADV/${tag}_*.rb 2>/dev/null | head -1)
  if [ -z "$mf" ]; then echo "DONE $tag NOMANIFEST" >> $LOG; continue; fi
  rm -f $ADV/concrete_run.json
  systemd-run --user --pipe --wait -p MemoryMax=4000M -p MemorySwapMax=0 \
    --working-directory=/home/dev/project \
    bash -c "unset JAVA_TOOL_OPTIONS; flock /tmp/concolic-slot.lock \
      /home/dev/project/scripts/diaspora-concolic $PROBE $mf" \
    > $ADV/runs/${tag}.log 2>&1
  rc=$?
  if [ -f $ADV/concrete_run.json ]; then
    mv $ADV/concrete_run.json $ADV/runs/${tag}.json
    echo "DONE $tag rc=$rc json=yes" >> $LOG
  else
    echo "DONE $tag rc=$rc json=NO" >> $LOG
  fi
done
echo "CHAIN-COMPLETE $*" >> $LOG
