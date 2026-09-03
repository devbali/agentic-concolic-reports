#!/usr/bin/env python3
"""notifications_index — batch-local AssumptionSet (COMPLETION_BRIEF.md).

Empty to start. notifications_index's exploration surfaces exactly ONE PC
expression, `(SYM_PARAM_show == StringVal('unread'))`, and both of its
outcomes are directly observed across the 6 regenerated dumps (no other
expression exists to combine it with, so there is no missing combination to
assume away). No assumption has been needed to reach genuine
coverage_complete=true — see notifications_index/coverage_summary.json and
the batch report for the full argument.

If a future rerun of this entrypoint (e.g. making `type`/`page`/`per_page`
symbolic, which REPORT.md documents as hitting real framework walls today)
surfaces additional PC expressions, extend this AssumptionSet here — never
in src/.
"""
from __future__ import annotations

import sys

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.assumptions import AssumptionSet  # noqa: E402


def build() -> AssumptionSet:
    return AssumptionSet()
