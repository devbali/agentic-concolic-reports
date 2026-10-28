#!/usr/bin/env python3
"""C20 — census of the `FinderMethods#exists?` call ORDINALS.

Reads every dump of a list, line-scans out (result_name, note) for every
symbolic_call and (expr, taken) for every path_condition, then applies the
ENGINE's own `_alias_core` (concolic_engine.assumptions) with

    the endpoint's declared ALIASES  (+ optionally a candidate alias over
    SYM_RESULT_ActiveRecord__FinderMethods_exists__\\d+, key from EXISTS_KEY)

so the statement key / canonical name an `exists?` ordinal would get is the
one the engine would compute, binds rewritten to the producing chain.

Emits, over the corpus:
  * ordinal -> {statement key: count}, and key -> {ordinal: count}
  * per run, the ordinals that co-occur and their outcomes (the joint table)
  * disagreements: within one run, two ordinals with the SAME key and
    DIFFERENT recorded outcomes  (0 required)
  * per-run recorded outcome per canonical name.

Read-only. Usage: python3 _c20_exists_census.py <dump_list> <out.json> [N]
"""
import json, os, re, sys, collections
from multiprocessing import Pool

sys.path.insert(0, "/home/dev/project/src")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from concolic_engine.assumptions import AliasAssumption, _alias_core  # noqa: E402

EXISTS_PAT = r"SYM_RESULT_ActiveRecord__FinderMethods_exists__\d+"
EXISTS_KEY = os.environ.get("EXISTS_KEY", "statement")
WITH_CANDIDATE = os.environ.get("NO_CANDIDATE") != "1"

def _aliases():
    import coverage_assumptions as ca
    al = list(ca.ALIASES)
    if WITH_CANDIDATE:
        al = al + [AliasAssumption(result_pattern=EXISTS_PAT, key=EXISTS_KEY,
                                   description="C20 candidate: exists? by statement")]
    return al

_ALIASES = None
_ORD_RE = re.compile(r"^SYM_RESULT_ActiveRecord__FinderMethods_exists__(\d+)$")
_EXVAR_RE = re.compile(r"SYM_RESULT_ActiveRecord__FinderMethods_exists__(\d+)_exists")

def scan(path):
    """-> (events[(rn,note)], pcs[(expr,taken)])"""
    evs, pcs = [], []
    rn = expr = None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                s = ln.strip()
                if s.startswith('"result_name": "'):
                    rn = s[16:].rstrip(",").rstrip('"')
                elif s.startswith('"note": "'):
                    if rn is not None:
                        evs.append((rn, json.loads(s[8:].rstrip(","))))
                        rn = None
                elif s.startswith('"expr": "'):
                    expr = json.loads(s[8:].rstrip(","))
                elif s.startswith('"taken": '):
                    if expr is not None:
                        pcs.append((expr, s[9:].rstrip(",") == "true"))
                        expr = None
                elif s.startswith('"result_value"') or s.startswith('"result_sort"'):
                    pass
                elif s.startswith('"type": "') and rn is not None:
                    rn = None   # event ended with no note
    except Exception as exc:                                   # noqa: BLE001
        return ("ERR", f"{type(exc).__name__}: {exc}")
    return (evs, pcs)

def work(path):
    global _ALIASES
    if _ALIASES is None:
        _ALIASES = _aliases()
    r = scan(path)
    if r[0] == "ERR":
        return {"err": r[1]}
    evs, pcs = r
    amap, keys = _alias_core(evs, _ALIASES)
    # ordinal -> (canonical, key) for the exists family only
    ex = {}
    for rn, canon in amap.items():
        m = _ORD_RE.match(rn)
        if m:
            ex[m.group(1)] = (canon, keys.get(rn, ""))
    # the raw statement note per exists ordinal (unrewritten), for the census
    raw = {}
    for rn, note in evs:
        m = _ORD_RE.match(rn)
        if m and m.group(1) not in raw:
            raw[m.group(1)] = note
    # recorded outcomes of the `_exists == True` compare, per ordinal
    out = collections.defaultdict(set)
    for expr, taken in pcs:
        for m in _EXVAR_RE.finditer(expr):
            out[m.group(1)].add(bool(taken))
    return {"ex": ex, "raw": raw, "out": {k: sorted(v) for k, v in out.items()},
            "n_ev": len(evs), "n_pc": len(pcs)}

def main():
    lst, outp = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    files = open(lst).read().split()
    if n:
        files = files[:n]
    ordkey = collections.Counter()          # (ordinal, key)
    keyord = collections.defaultdict(collections.Counter)
    rawkey = {}                             # key -> a sample raw note
    canon_ord = collections.defaultdict(collections.Counter)
    coeval = collections.Counter()          # frozenset of ordinals in a run
    joint = collections.Counter()           # (canonical, ordinal, outcome)
    same_key_disagree = []
    joint_pair = collections.Counter()      # (key, ord_a:out, ord_b:out)
    runs = errs = 0
    ord_present = collections.Counter()
    ord_decided = collections.Counter()
    with Pool(int(os.environ.get("JOBS", "3"))) as pool:
        for i, r in enumerate(pool.imap_unordered(work, files, chunksize=64)):
            if "err" in r:
                errs += 1
                continue
            runs += 1
            ex, out = r["ex"], r["out"]
            for o, (canon, key) in ex.items():
                ordkey[(o, key)] += 1
                keyord[key][o] += 1
                canon_ord[canon][o] += 1
                ord_present[o] += 1
                rawkey.setdefault(key, r["raw"].get(o, ""))
            if ex:
                coeval[tuple(sorted(ex, key=int))] += 1
            # per-key outcomes inside this run
            bykey = collections.defaultdict(dict)
            for o, (canon, key) in ex.items():
                if o in out:
                    ord_decided[o] += 1
                    vals = out[o]
                    bykey[key][o] = tuple(vals)
                    joint[(canon, o, str(vals))] += 1
            for key, d in bykey.items():
                if len(d) > 1:
                    vs = {v for v in d.values()}
                    joint_pair[(key, tuple(sorted(d.items())))] += 1
                    if len(vs) > 1:
                        if len(same_key_disagree) < 40:
                            same_key_disagree.append({"key": key[:200], "outcomes": {k: list(v) for k, v in d.items()}})
                        joint_pair[("DISAGREE:" + key, tuple(sorted(d.items())))] += 1
            if (i + 1) % 20000 == 0:
                print(f"  [{i+1}/{len(files)}] runs={runs} errs={errs}", flush=True)
    res = {
        "list": lst, "files": len(files), "runs": runs, "errors": errs,
        "candidate_alias": WITH_CANDIDATE, "exists_key": EXISTS_KEY,
        "ordinal_x_key": [{"ordinal": o, "key": k, "runs": c} for (o, k), c in ordkey.most_common()],
        "key_to_ordinals": {k: dict(v) for k, v in keyord.items()},
        "canonical_to_ordinals": {c: dict(v) for c, v in canon_ord.items()},
        "sample_note_per_key": {k: v[:400] for k, v in rawkey.items()},
        "coevaluation": {",".join(k): v for k, v in coeval.most_common()},
        "ordinal_present": dict(ord_present), "ordinal_decided": dict(ord_decided),
        "joint_outcomes": [{"canonical": c, "ordinal": o, "outcome": v, "runs": n}
                           for (c, o, v), n in joint.most_common()],
        "same_key_pairs": [{"key": k[:200], "assignment": str(a), "runs": n}
                           for (k, a), n in joint_pair.most_common()],
        "disagreements": same_key_disagree,
        "n_disagreements": sum(n for (k, a), n in joint_pair.items() if k.startswith("DISAGREE:")),
    }
    with open(outp, "w") as fh:
        json.dump(res, fh, indent=2)
    print(f"CENSUS runs={runs} errors={errs} "
          f"ordinals={sorted(ord_present, key=int)} keys={len(keyord)} "
          f"DISAGREEMENTS={res['n_disagreements']}")
    print(f"C20-CENSUS-DONE {outp}")

if __name__ == "__main__":
    main()
