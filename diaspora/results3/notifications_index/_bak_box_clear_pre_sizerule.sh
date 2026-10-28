#!/bin/bash
# Heavy jobs anywhere on the box. Match the PROCESS, never a command line my own
# waiting shell also contains. Covers coverage passes, exact enumerations,
# confinement censuses, the ASSUMPTION GATE and its JRuby replays, and
# blockaid/subsume JVMs. (The name list is only an optimisation — the binding
# rule is _wait_mem.sh's two numbers.)
ps -eo pid=,rss=,comm=,args= | awk '
  ($3=="python3" && $2>400000 &&
   ($0 ~ /coverage_report\.py/ || $0 ~ /_exact_enum\.py/ ||
    $0 ~ /confinement_census\.py/ || $0 ~ /assumption_checker\.py/)) ||
  ($3=="java" && $2>400000 &&
   ($0 ~ /subsume/ || $0 ~ /blockaid/ || $0 ~ /run_dse/ || $0 ~ /jruby/)) \
  { print $1, int($2/1024)"MB", $3 }'
