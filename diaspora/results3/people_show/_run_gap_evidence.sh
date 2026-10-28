#!/bin/bash
# Wrapper for _gap_evidence.py (exec preflight pattern: bash wrapper -> python3 file)
cd /home/dev/project/reports/diaspora/results3/people_show
exec python3 _gap_evidence.py "$@"