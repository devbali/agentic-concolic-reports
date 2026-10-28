#!/usr/bin/env python3
"""reconcile_with_app.py -- the probe's MAXIMAL set vs what the booted app installs.

Every count in inventory/ comes from tools/declaration_probe.rb, which runs the
real `install!` against the real `CallInterceptor` but in a STUB WORLD where
Rails and the diaspora app are auto-vivifying modules that answer
`defined?`, `respond_to?`, `method_defined?` and `instance_methods.include?`
affirmatively. That is deliberate -- it is the only way to see every guarded
declaration -- and its documented cost is that the probe measures the MAXIMAL
set: what a config declares when every guard is true.

This tool closes that gap empirically. A real run's dump carries the §4.1.1f
declaration table, so a corpus of real dumps says exactly which declarations
the booted app installs. Diffing the two answers the only question the probe
cannot: *is a guard false in the real app, and which one?*

It writes inventory/app_reconciliation.json and exits non-zero if the diff is
anything other than the known, pinned dormant set.

    /home/dev/project/venvs/queries_from_runs/bin/python3 \\
        tools/reconcile_with_app.py [dump-glob ...]

Default corpus: reports/autolab/shakedown/runs/*/dump_*.json (161 endpoints).
"""
import collections
import glob
import json
import os
import subprocess
import sys

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(LAB, "tools")
INV = os.path.join(LAB, "inventory")
DEFAULT_GLOB = os.path.join(LAB, "shakedown", "runs", "*", "dump_*.json")

# A core declare_target site whose guard is FALSE in the booted app, so the
# declaration never installs. Pinned, with the reason, because "the probe says
# 87 and the app says 86" must never again be an open question.
KNOWN_DORMANT = {
    "ActionController::Metal#head": {
        "site": "targets/core.rb, section W2",
        "guard": "defined?(ActionController::Metal) && "
                 "ActionController::Metal.instance_methods.include?(:head)",
        "why_false": (
            "`head` is defined in its own module, ActionController::Head "
            "(actionpack-5.2.4.3/lib/action_controller/metal/head.rb:21), and that "
            "module is never mixed into Metal. So Metal.instance_methods does not "
            "include :head and the guard is false. The stub world's "
            "instance_methods answers every include? affirmatively, which is why "
            "the probe sees the site and the app does not."),
        "harmless_because": (
            "The core declares `ActionController::Head#head` separately, with the "
            "same SHIM kind and the same `:head_reached` marker, and THAT one is "
            "present in every real run. Nothing is lost -- the W2 site is "
            "redundant, not load-bearing. Removing it would be a change to a "
            "verified file for no behavioural gain, so it is recorded here "
            "instead."),
    },
}


def probe_core():
    """The MAXIMAL core declaration set, from tools/declaration_probe.rb."""
    core = os.path.join(LAB, "targets", "core.rb")
    consts = json.loads(subprocess.run(
        ["ruby", os.path.join(TOOLS, "scrape_constants.rb"), core],
        capture_output=True, text=True, check=True).stdout)
    spec = os.path.join(os.environ.get("TMPDIR", "/tmp"), "autolab_reconcile_spec.json")
    json.dump({"lenient": False, "consts": consts,
               "steps": [{"file": core, "modules": ["ConcolicTargets"]}]},
              open(spec, "w"))
    out = subprocess.run(
        ["ruby", os.path.join(TOOLS, "declaration_probe.rb"), spec],
        capture_output=True, text=True, check=True).stdout
    d = json.loads(out)
    if d.get("fatal") or d["errors"]:
        sys.exit("probe failed: %s" % (d.get("fatal") or d["errors"]))
    return {c["target"]: c["kind"] for c in d["calls"]}


def kind_of(v):
    return v["kind"] if isinstance(v, dict) else v


def main(argv):
    patterns = argv[1:] or [DEFAULT_GLOB]
    probe = probe_core()

    by_endpoint = {}
    for pat in patterns:
        for f in sorted(glob.glob(pat)):
            ep = os.path.basename(os.path.dirname(f))
            by_endpoint.setdefault(ep, f)
    if not by_endpoint:
        sys.exit("no dumps matched %s" % patterns)

    sizes = collections.Counter()
    missing = collections.Counter()
    extra = collections.Counter()
    kind_conflicts = collections.Counter()
    core_only = []
    for ep, f in sorted(by_endpoint.items()):
        table = json.load(open(f))["declarations"]
        names = set(table)
        sizes[len(names)] += 1
        miss = probe.keys() - names
        ext = names - probe.keys()
        for x in miss:
            missing[x] += 1
        for x in ext:
            extra[x] += 1
        for t in names & probe.keys():
            if kind_of(table[t]) != probe[t]:
                kind_conflicts["%s: app=%s probe=%s" % (t, kind_of(table[t]), probe[t])] += 1
        if not ext:
            core_only.append(ep)

    verdict_ok = set(missing) == set(KNOWN_DORMANT)
    out = {
        "_what_this_is": [
            "The probe's MAXIMAL core declaration set vs the declaration tables of",
            "real runs. The probe forces every `if defined?(...)` guard true so it",
            "can see every declaration; a booted app does not. This is the diff.",
            "It is why registry.json and manifest.json report a MAXIMAL count and",
            "an OBSERVED count and do not pretend they are the same number.",
        ],
        "dump_corpus": patterns,
        "endpoints_sampled": len(by_endpoint),
        "core_only_endpoints": len(core_only),
        "probe_core_declarations": len(probe),
        "observed_declaration_table_sizes": dict(sizes),
        "in_probe_not_in_app": {t: {"seen_missing_in_n_endpoints": n} for t, n in missing.items()},
        "in_app_not_in_probe_by_endpoint": {
            "_note": "these are the ENDPOINT-LOCAL layers, expected: the probe here "
                     "ran core.rb alone.",
            "names": sorted(extra),
        },
        "kind_conflicts": dict(kind_conflicts),
        "kind_conflicts_note": [
            "A kind conflict is NOT a defect by itself -- it means the dump and the",
            "current core.rb disagree, and there are two innocent reasons.",
            "(1) THE DUMP IS OLDER THAN A KIND CHANGE. The shakedown dumps predate",
            "    the 2026-09-26 D7a fixes, so they still record",
            "    CollectionProxy#create and PostService#mark_user_notifications as",
            "    shim. Re-running the shakedown would clear these.",
            "(2) AN ENDPOINT LAYER OVERRODE THE CORE. This probe installs core.rb",
            "    ALONE, so a target an endpoint redeclares with a different kind",
            "    shows up here. `User#blocks` on aspect_memberships_create is the",
            "    only one, and it is the documented C1 conflict: the core mock IS",
            "    the access (target_function), the endpoint restores the real",
            "    association reader so the call stops being one (shim).",
        ],
        "known_dormant": KNOWN_DORMANT,
        "verdict": ("the only difference is the pinned dormant set"
                    if verdict_ok else "UNEXPECTED DIFFERENCE -- see in_probe_not_in_app"),
    }
    json.dump(out, open(os.path.join(INV, "app_reconciliation.json"), "w"), indent=2)

    print("endpoints sampled          : %d (%d core-only)" % (len(by_endpoint), len(core_only)))
    print("probe core declarations    : %d  (MAXIMAL)" % len(probe))
    print("observed table sizes       : %s" % dict(sizes))
    print("in probe, never in the app : %s" % (dict(missing) or "none"))
    if kind_conflicts:
        print("kind conflicts (dumps predate a kind change?):")
        for k, n in sorted(kind_conflicts.items()):
            print("    x%-4d %s" % (n, k))
    print("verdict: %s" % out["verdict"])
    return 0 if verdict_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
