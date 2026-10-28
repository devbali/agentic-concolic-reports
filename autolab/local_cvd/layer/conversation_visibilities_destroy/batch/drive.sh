#!/bin/bash
# usage: drive.sh <dumpdir> <log> [extra env assignments via env]
unset JAVA_TOOL_OPTIONS
export XDG_RUNTIME_DIR=/run/user/1000 LANG=C.UTF-8 LC_ALL=C.UTF-8
mkdir -p "$1"
DUMP_OUT="$1" systemd-run --user --scope -p MemoryMax=10G --quiet /home/dev/project/reports/autolab/entrypoints/scaffold/conversation_visibilities_destroy/launch.sh > "$2" 2>&1
echo EXIT $? >> "$2"
