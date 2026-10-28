#!/bin/bash
# Wrapper for _dump_missing2.py (exec preflight workaround).
cd /home/dev/project
exec python3 reports/diaspora/results3/people_show/_dump_missing2.py > reports/diaspora/results3/people_show/_missing_112.txt 2>&1
wc -l reports/diaspora/results3/people_show/_missing_112.txt