#!/bin/bash
# Heavy jobs anywhere on the box. SIZE rule (2026-09-11 19:50), replacing the
# name list: the list missed posts_show's `_part_decomp.py` and its streaming
# extractor, which is exactly the collision the cage lowering was about. Any
# python3/java holding more than 400 MB is a heavy job, whoever owns it; the
# editor's node language server is NOT included (it is outside the cage and
# never finishes — the `free -g` half of the invariant is what covers it).
ps -eo pid=,rss=,comm=,args= | awk '
  ($3=="python3" || $3=="java" || $3=="ruby" || $3=="jruby") && $2>400000 \
  { print $1, int($2/1024)"MB", $3, substr($0, index($0,$4), 60) }'
