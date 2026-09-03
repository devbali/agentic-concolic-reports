#!/bin/bash
# Run people_show coverage report (wrapper to satisfy exec preflight).
cd /home/dev/project
export PYTHONPATH=src
exec python3 reports/diaspora/results3/people_show/coverage_report.py "$@"