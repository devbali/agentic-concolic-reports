"""Lever 3 extraction runner for variant_d.

Runs the SAME `queries_from_runs.dump` CLI the standardized diff protocol
calls for, with ONE addition: `assoc_fold.patch_dump_module()` swaps in
`AssocFoldingTransformer` (Lever 1) before the CLI's own `dump_all_endpoints`
runs. `queries_from_runs/dump.py` itself is never edited -- see
assoc_fold.py's docstring for why (this experiment's own
MOCK_RULE_EXPERIMENT.md forbids touching src/).

Usage (mirrors the task's literal `python -m queries_from_runs.dump`
invocation, argument-for-argument):

    cd /home/dev/project && unset JAVA_TOOL_OPTIONS
    PYTHONPATH=src:reports/diaspora/results3/_experiment/variant_d \
      venvs/queries_from_runs/bin/python \
      reports/diaspora/results3/_experiment/variant_d/run_extraction.py \
      --results reports/diaspora/results3/_experiment \
      --out reports/diaspora/results3/_experiment/variant_d/queries_out \
      --endpoint variant_d \
      --summary-json reports/diaspora/results3/_experiment/variant_d/queries_out/_summary.json \
      --verbose
"""
import sys

import assoc_fold

assoc_fold.patch_dump_module()

from queries_from_runs import dump  # noqa: E402  (patch must land first)

if __name__ == "__main__":
    sys.exit(dump.main(sys.argv[1:]))
