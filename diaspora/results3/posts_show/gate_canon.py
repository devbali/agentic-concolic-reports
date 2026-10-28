#!/usr/bin/env python3
"""Gate-side load hook for posts_show (2026-09-10 completion drive).

`assumption_checker.py` selects a probe dump by the SCENARIO its snapshot ran
in — `dump["concolic_scenario"]["name"]`. notifications_index's runner records
that key; this batch's `run_dse.rb` never has. VERIFIED on a real dump of this
corpus, not assumed: a dump's top-level keys are
`schema_version, label, symbolic_vars, events, symbolic_results, script,
concolic_seeds` and `dump["concolic_scenario"]` is None, while `label` is
`auth_json0001_<suffix>`. With the key absent every dump's scenario reads as
None, so a probe replayed for an `auth_json` snapshot could be matched back
against the `anon_html` dump of the same launch — a verdict earned on the
wrong run.

Rather than change the runner (which would leave the 96 365-dump corpus without
the key while new probe dumps had it — the same mismatch, inverted), the batch
supplies the scenario at the gate's own load point. `canonicalize` in
`assumption_manifest.json` names this function; the checker calls it on EVERY
dump it reads, before any comparison, and it delegates to the exact
canonicalization the coverage report uses — INCLUDING `fix_len_names`, so the
names the gate compares are the names the engine built its universe from.
Identical in mechanism and reason to people_stream's `gate_canon.py`.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)

from coverage_report import canonicalize_ordinals, fix_len_names  # noqa: E402

# run_dse.rb SCENARIOS, longest first so a shorter name cannot shadow a longer.
SCENARIOS = ("auth_html", "anon_html", "auth_json", "anon_json")


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
    amap = canonicalize_ordinals(dump) if aliases is None else \
        canonicalize_ordinals(dump, aliases)
    # Mirror the engine's load path: `len(X)` is not a valid Python identifier
    # and the checker renames it before building its universe. `fix_len_names`
    # returns a NEW dict, so apply it in place on the caller's object.
    fixed = fix_len_names(dump)
    dump.clear()
    dump.update(fixed)
    return amap
