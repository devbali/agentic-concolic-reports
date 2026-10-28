#!/bin/bash
# Caged runner for ANY analysis script (coordinator note, 2026-09-11 19:0x):
# the memory invariant applies to analysis too, not only passes. Never a
# heredoc / `python3 -` on stdin: write the script to a file, run it here.
#   _caged_py.sh <unit> <cap> <script.py> [args...]
set +e; unset JAVA_TOOL_OPTIONS
B=/home/dev/project/reports/diaspora/results3/posts_show
. "$B/_cage.sh"
U="$1"; CAP="$2"; shift 2
cage "$U" "$CAP" env PYTHONPATH=/home/dev/project/src JAVA_TOOL_OPTIONS= python3 -u "$@"
