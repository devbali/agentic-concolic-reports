#!/usr/bin/env bash
B=/home/dev/project/reports/diaspora/results3/posts_show
until grep -q "### ALL DONE" "$B/_p46_seq.log" 2>/dev/null; do sleep 15; done
bash "$B/_p46_emptydiff.sh"
