#!/usr/bin/env python3
"""C7 (2026-09-01) — variant-tuple staleness check (DISCIPLINE 14, A3-12).

conversations C13 added four format scenarios in run_dse.rb while FIVE
consumers carried a private variant tuple; the seeder then attributed every
new-scenario dump to None and wrote no seeds. The rule is that a consumer
reads `concolic_scenario.name` from the dump — but where a tuple still exists,
its divergence from run_dse.rb must be a mechanical failure, not a silent one.

This compares run_dse.rb's VARIANTS hash against every `VARIANTS = (...)` /
`_VARIANTS = (...)` tuple in the batch's own python consumers, and also against
the variant names actually present in the corpus.

exit 0 = all agree.  exit 1 = a divergence (name it, do not guess).
"""
import ast, glob, json, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))

rig = re.findall(r'^\s*"([a-z_]+)"\s*=>\s*\{\s*format:', open(os.path.join(HERE, "run_dse.rb")).read(), re.M)
rig_set = set(rig)
print(f"run_dse.rb VARIANTS ({len(rig)}): {sorted(rig_set)}")

bad = []
consumers = [f for f in sorted(glob.glob(os.path.join(HERE, "*.py")))
             if not os.path.basename(f).startswith(("_bak_", "_c7_variant_tuple_check"))]
print(f"\nconsumers scanned: {len(consumers)}")
for f in consumers:
    src = open(f).read()
    for m in re.finditer(r'^_?VARIANTS\s*=\s*(\([^)]*\)|\[[^\]]*\])', src, re.M):
        try:
            got = set(ast.literal_eval(m.group(1)))
        except Exception:
            continue
        name = os.path.basename(f)
        if got != rig_set:
            bad.append((name, sorted(got - rig_set), sorted(rig_set - got)))
            print(f"  DIVERGES  {name}: extra={sorted(got-rig_set)} missing={sorted(rig_set-got)}")
        else:
            print(f"  ok        {name}")

dumps = glob.glob(os.path.join(HERE, "dump_*.json"))
seen = collections.Counter()
for p in dumps:
    try:
        seen[(json.load(open(p)).get("concolic_scenario") or {}).get("name")] += 1
    except Exception:
        pass
print(f"\ncorpus POPULATION: {len(dumps)} dumps; scenario names present: {dict(seen)}")
unknown = set(seen) - rig_set - {None}
if unknown:
    bad.append(("<corpus>", sorted(unknown), []))
    print(f"  DIVERGES  corpus carries scenario names run_dse.rb does not define: {sorted(unknown)}")
absent = rig_set - set(seen)
if dumps and absent:
    print(f"  NOTE      variants defined but not present in this corpus: {sorted(absent)} "
          f"(not a failure: a partial corpus is legal; format_coverage_audit is the gate)")

print("\nRESULT: " + ("FAIL — " + str(len(bad)) + " divergence(s)" if bad else "pass — every consumer tuple matches run_dse.rb"))
sys.exit(1 if bad else 0)
