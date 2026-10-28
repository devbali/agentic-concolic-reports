#!/bin/bash
# Wrapper for _check_assns.py (exec preflight workaround).
cd /home/dev/project
export PYTHONPATH=src
exec python3 reports/diaspora/results3/people_show/_check_assns.py