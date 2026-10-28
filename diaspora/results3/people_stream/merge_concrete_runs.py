#!/usr/bin/env python3
"""Merge the per-scenario concrete runs (one manifest per process for JVM
crash isolation) into the single concrete_run.json completion_config.json
points the note check at. Pure concatenation of scenario entries.

cycle 11: the file list used to be HARDCODED, and adding
`concrete_manifest_r6.rb` (the M-15/M-16 ground truth) silently produced a
merge that did not contain it — the same "a copied list goes stale silently"
class as DISCIPLINE §14's A3-12. The list is now DERIVED from the directory,
every input is NAMED in the output, and a `concrete_manifest_*.rb` with no
matching run is reported as MISSING rather than skipped in silence.
"""
import glob, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
# `*_exec.json` are the M-18 executor-wrapped ground truth (cycle 12). They are
# the SAME requests measured inside `Rails.application.executor.wrap`, so
# merging them in would double every scenario. They are kept as a separate
# ground truth and named explicitly wherever they are judged.
runs = sorted(p for p in glob.glob(os.path.join(HERE, "concrete_run_*.json"))
              if not os.path.basename(p).startswith(("_bak", "concrete_run.json"))
              and not os.path.basename(p).endswith("_exec.json"))
manifests = sorted(os.path.basename(p)[len("concrete_manifest_"):-3]
                   for p in glob.glob(os.path.join(HERE, "concrete_manifest_*.rb")))
have = {os.path.basename(p)[len("concrete_run_"):-5] for p in runs}
missing = [m for m in manifests if m not in have]

out = []
for p in runs:
    out += json.load(open(p))
    print(f"[merge] + {os.path.basename(p)}")
if missing:
    print(f"[merge] MISSING run(s) for manifest(s): {', '.join(missing)}", file=sys.stderr)
json.dump(out, open(os.path.join(HERE, "concrete_run.json"), "w"), indent=1)
print(f"merged {len(out)} scenario(s) from {len(runs)} file(s) -> concrete_run.json")
sys.exit(1 if missing else 0)
