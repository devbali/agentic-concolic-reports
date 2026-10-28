"""VARIANTS differential (§94.5a). Compares, per scenario, the dumps the runner
wrote under ALL FOUR scenarios (cond A) against the dumps it wrote under that
ONE scenario (cond B), in the CHECKER'S OWN CURRENCY:
  * dump-SET cardinality and membership (basename modulo LABEL_SUFFIX)
  * the ProbeCache key: seeds_as_written(dump)
  * the ProbeCache VALUE: probe_record(dump) -- trace/trace_b/amap/exprs/
    outcomes/values, i.e. everything a verdict reads.
Nothing is compared by hand; both sides go through _load_dump_uncached with the
batch's own gate_canon hook installed, exactly as the gate does.
"""
import glob, json, os, sys, re
S = os.path.dirname(os.path.abspath(__file__))
BATCH = "/home/dev/project/reports/diaspora/results3/posts_show"
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, BATCH)
import importlib
ac = importlib.import_module("end_to_end_completion_checker.assumption.assumption_checker")
gc_ = importlib.import_module("gate_canon")
ac._CANON_FN = gc_.canonicalize_for_gate
ac._ALIASES = []          # the re-gate declares 0 aliases (log line confirms)

SCEN = ["auth_html", "anon_html", "auth_json", "anon_json"]

def load(suffix, scen):
    out = {}
    for p in sorted(glob.glob(os.path.join(S, f"dump_{scen}*{suffix}.json"))):
        d = ac._load_dump_uncached(p)
        base = os.path.basename(p)[:-len(suffix)-5] + ".json"   # strip suffix
        out[base] = d
    return out

def norm(x):
    if isinstance(x, (set, frozenset)):
        return sorted(norm(v) for v in x)
    if isinstance(x, (list, tuple)):
        return [norm(v) for v in x]
    if isinstance(x, dict):
        return {str(k): norm(v) for k, v in sorted(x.items(), key=lambda kv: str(kv[0]))}
    return x

ok_all = True
for sc in SCEN:
    A = load("_difA", sc)
    B = load(f"_difB{sc}", sc)
    print(f"\n=== {sc} ===")
    print(f"  dumps: A(4-scenario)={len(A)}  B(1-scenario)={len(B)}")
    same_names = set(A) == set(B)
    print(f"  basename-modulo-suffix SET identical: {same_names}"
          + ("" if same_names else f"  onlyA={sorted(set(A)-set(B))[:5]} onlyB={sorted(set(B)-set(A))[:5]}"))
    ok_all &= same_names and len(A) == 200 and len(B) == 200
    # keyed on the ProbeCache key, not on the filename
    kA = {json.dumps(norm(ac.seeds_as_written(d)), sort_keys=True): (n, d) for n, d in A.items()}
    kB = {json.dumps(norm(ac.seeds_as_written(d)), sort_keys=True): (n, d) for n, d in B.items()}
    print(f"  distinct seeds_as_written keys: A={len(kA)} B={len(kB)}  identical set: {set(kA)==set(kB)}")
    ok_all &= (set(kA) == set(kB)) and len(kA) == 200
    scA = {(d.get("concolic_scenario") or {}).get("name") for d in A.values()}
    scB = {(d.get("concolic_scenario") or {}).get("name") for d in B.values()}
    print(f"  derived concolic_scenario: A={scA} B={scB}")
    ok_all &= scA == scB == {sc}
    diffs, fieldcount = [], {}
    for k in sorted(set(kA) & set(kB)):
        nA, dA = kA[k]; nB, dB = kB[k]
        rA = norm(ac.probe_record(dA)); rB = norm(ac.probe_record(dB))
        if rA != rB:
            bad = [f for f in rA if rA[f] != rB[f]]
            for f in bad: fieldcount[f] = fieldcount.get(f, 0) + 1
            diffs.append((nA, bad))
        if nA != nB:
            diffs.append((nA, ["FILENAME:" + nB]))
    print(f"  probe_record IDENTICAL for {len(set(kA)&set(kB))-len([d for d in diffs if not d[1][0].startswith('FILENAME')])} of {len(set(kA)&set(kB))} keys")
    if diffs:
        print(f"  DIFFERING fields: {fieldcount}")
        for n, b in diffs[:5]: print(f"    {n}: {b}")
    ok_all &= not diffs
    # the full raw dump, modulo `label` and the derived scenario, as a stronger check
    rawdiff = 0
    for k in sorted(set(kA) & set(kB)):
        a = dict(kA[k][1]); b = dict(kB[k][1])
        for z in (a, b):
            z.pop("label", None); z.pop("concolic_scenario", None)
        if norm(a) != norm(b):
            rawdiff += 1
    print(f"  FULL dump (modulo label): {len(set(kA)&set(kB))-rawdiff} identical, {rawdiff} differing")

print("\nVERDICT:", "PASS — the lever is sound" if ok_all else "FAIL — DO NOT TAKE THE LEVER")
