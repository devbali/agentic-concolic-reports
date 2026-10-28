#!/usr/bin/env python3
"""MOCK-MANIFEST COMPLETENESS GATE (runbook rule adopted 2026-08-25 after
the comments_index reference check: the mock checker passed 4/4 while the
Person#name violation sat unprobed — because the manifest listed 4 of the
13 live mocks. A checker run is only as complete as its manifest).

    python3 mock_coverage_audit.py <batch_dir> <mock_manifest.rb>

LEFT:  every target function that actually FIRES in the corpus (distinct
       `symbolic_call` event targets with a result), i.e. the live mocks.
RIGHT: the manifest's probe surface — parsed from the Ruby manifest:
       `targets:` pairs and `coverage_of:` owners of :shim entries, the
       names of :target_note entries, plus an optional WAIVERS list:
           WAIVERS = { "Mod.meth" => "why no probe is needed" }
       (walls and rig plumbing get waivers WITH REASONS, never silence).

Verdict per live target: PROBED (a shim/target_note entry exercises it),
WAIVED (reason printed), or UNPROBED <-- RED. Exit 1 on any UNPROBED.
Matching is by method name against the manifest's declared pairs and by
substring against probe names — deliberately generous; the gate's job is
"nothing unlisted", not exact bookkeeping.
"""
import glob
import json
import os
import re
import sys
from collections import defaultdict


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: mock_coverage_audit.py <batch_dir> <mock_manifest.rb>")
    batch, manifest_path = sys.argv[1], sys.argv[2]

    live = defaultdict(int)
    for f in glob.glob(os.path.join(batch, "dump_*.json")):
        d = json.load(open(f))
        for ev in d.get("events") or []:
            if ev.get("type") == "symbolic_call" and ev.get("result_name"):
                live[str(ev.get("target") or "")] += 1

    m = open(manifest_path).read()
    pair_methods = set(re.findall(r"\[\s*[A-Za-z0-9_:]+\s*,\s*:([a-z_0-9?!]+)", m))
    probe_names = set(re.findall(r'name:\s*"([^"]+)"', m))
    waivers = dict(re.findall(r'"([^"]+)"\s*=>\s*"([^"]+)"', m))

    print(f"== mock_coverage_audit: {len(live)} live targets in corpus, "
          f"{len(pair_methods)} probed methods, {len(waivers)} waivers ==\n")
    red = False
    for tgt, n in sorted(live.items(), key=lambda kv: -kv[1]):
        meth = tgt.rsplit(".", 1)[-1].rsplit("#", 1)[-1]
        if tgt in waivers:
            print(f"  WAIVED    {tgt:<66} x{n:<6} ({waivers[tgt][:60]})")
        elif meth in pair_methods or any(meth in pn or pn in tgt for pn in probe_names):
            print(f"  PROBED    {tgt:<66} x{n}")
        else:
            red = True
            print(f"  UNPROBED  {tgt:<66} x{n:<6} <-- RED (no manifest entry, no waiver)")
    print()
    print("RESULT: RED — live mocks without probes above." if red else "RESULT: complete.")
    sys.exit(1 if red else 0)


if __name__ == "__main__":
    main()
