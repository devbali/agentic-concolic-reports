#!/usr/bin/env python3
"""Gate-side load hook for people_stream (2026-09-10).

`assumption_checker.py` selects a probe dump by the SCENARIO its snapshot ran
in — `dump["concolic_scenario"]["name"]`. notifications_index's runner records
that key; this batch's `run_dse.rb` never has (its three scenarios are encoded
in the dump LABEL, `dump_<scenario><NNNN><suffix>.json`, and in the label field
itself). With the key absent every dump's scenario reads as None, so a probe
replayed for an `auth_json` snapshot could be matched back against the
`anon_all` dump of the same launch — a verdict earned on the wrong run.

Rather than change the runner (which would leave the 1109-dump corpus without
the key while new probe dumps had it — the same mismatch, inverted), the batch
supplies the scenario at the gate's own load point. `canonicalize` in
`assumption_manifest.json` names this function; the checker calls it on EVERY
dump it reads, before any comparison, and it delegates to the exact
canonicalization the coverage report uses so the names the gate compares are
the names the engine built its universe from.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)

from coverage_report import canonicalize_ordinals  # noqa: E402

# run_dse.rb SCENARIOS, longest first so `anon_all` cannot be read as `anon_a`.
SCENARIOS = ("anon_json", "auth_json", "anon_all")


def scenario_of(dump):
    label = str(dump.get("label") or "")
    for s in SCENARIOS:
        if label.startswith(s):
            return s
    return None


def canonicalize_for_gate(dump, aliases=None):
    if not (dump.get("concolic_scenario") or {}).get("name"):
        name = scenario_of(dump)
        if name:
            dump["concolic_scenario"] = {"name": name}
    if aliases is None:
        return canonicalize_ordinals(dump)
    return canonicalize_ordinals(dump, aliases)
