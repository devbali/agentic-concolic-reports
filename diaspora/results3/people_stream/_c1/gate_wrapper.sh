#!/bin/bash
# The engine keeps only a TAIL of the assumption driver's stdout, so a driver
# that dies leaves no traceback in coverage_summary.json. This wrapper tees the
# full stream to disk and preserves the driver's own exit status.
# (Ported from comments_index/_c12/gate_wrapper.sh.)
L=/home/dev/project/reports/diaspora/results3/people_stream/_c1/_gate_engine.log
python3 /home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py \
  "$1" --declared "$2" --json-out "$3" 2>&1 | tee "$L"
exit "${PIPESTATUS[0]}"
