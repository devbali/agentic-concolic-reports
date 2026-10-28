#!/usr/bin/env python3
"""C20 scan 2 — (a) the SITE at which each `exists?` compare is recorded,
grouped by the canonical name the C20 candidate alias gives the ordinal;
(b) the identity-compare pair's joint realisability in the corpus.

Read-only.  usage: python3 _c20_scan2.py <dump_list> <out.json> [N]
"""
import json, os, re, sys, collections
from multiprocessing import Pool

sys.path.insert(0, "/home/dev/project/src")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from concolic_engine.assumptions import AliasAssumption, _alias_core   # noqa: E402

EXISTS_PAT = r"SYM_RESULT_ActiveRecord__FinderMethods_exists__\d+"
_ORD_RE = re.compile(r"^SYM_RESULT_ActiveRecord__FinderMethods_exists__(\d+)$")
_EXVAR_RE = re.compile(r"SYM_RESULT_ActiveRecord__FinderMethods_exists__(\d+)_exists")
FB = "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id"
DV = "SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id"
EQ = f"({FB} == {DV})"
SELF = f"({FB} == {FB})"
_KV = re.compile(r'^"([a-z_]+)": (.*?),?$')
_ALIASES = None


def _aliases():
    import coverage_assumptions as ca
    return list(ca.ALIASES) + [AliasAssumption(result_pattern=EXISTS_PAT, key="statement")]


def parse(path):
    """-> (events[(rn,note)], pcs[(expr,taken,site)], seed_keys, values)"""
    evs, pcs, seeds, vals = [], [], set(), {}
    cur, depth, section = None, 0, None
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            s = ln.strip()
            if ln.startswith('  "') and ln[3:].split('"')[0] in (
                    "symbolic_vars", "events", "symbolic_results", "concolic_seeds",
                    "schema_version", "label", "script", "concolic_scenario"):
                section = ln[3:].split('"')[0]
                cur = None
                continue
            if section == "concolic_seeds":
                m = re.match(r'"([^"]+)":', s)
                if m:
                    seeds.add(m.group(1))
                continue
            if s in ("{",):
                cur = {}; depth = 0; continue
            if s.startswith("{"):
                cur = {}; depth = 0; continue
            if s.startswith("}") and cur is not None:
                if depth:
                    depth -= 1; continue
                if section == "events":
                    if cur.get("type") == "symbolic_call" and cur.get("result_name") and cur.get("note"):
                        evs.append((cur["result_name"], cur["note"]))
                    elif cur.get("type") == "path_condition" and cur.get("expr") is not None:
                        pcs.append((cur["expr"], bool(cur.get("taken")),
                                    (os.path.basename(str(cur.get("file", ""))),
                                     cur.get("lineno"), cur.get("function"))))
                elif section == "symbolic_vars" and cur.get("name") in (FB, DV):
                    vals[cur["name"]] = cur.get("value")
                cur = None
                continue
            if cur is None:
                continue
            m = _KV.match(s)
            if not m:
                if s.endswith("{"):
                    depth += 1
                continue
            k, v = m.group(1), m.group(2)
            if v == "{":
                depth += 1; continue
            try:
                cur[k] = json.loads(v)
            except Exception:
                cur[k] = v.strip('"')
    return evs, pcs, seeds, vals


def work(path):
    global _ALIASES
    if _ALIASES is None:
        _ALIASES = _aliases()
    try:
        evs, pcs, seeds, vals = parse(path)
    except Exception as exc:                                   # noqa: BLE001
        return {"err": f"{type(exc).__name__}: {exc}"}
    amap, _keys = _alias_core(evs, _ALIASES)
    canon = {}
    for rn, c in amap.items():
        m = _ORD_RE.match(rn)
        if m:
            canon[m.group(1)] = c
    sites = collections.Counter()
    for expr, taken, site in pcs:
        for m in _EXVAR_RE.finditer(expr):
            sites[(canon.get(m.group(1), "?" + m.group(1)), m.group(1), site)] += 1
    eq = selfc = None
    for expr, taken, _s in pcs:
        if expr == EQ:
            eq = taken if eq is None else (eq, taken) if eq != taken else eq
        elif expr == SELF:
            selfc = taken if selfc is None else (selfc if selfc == taken else "BOTH")
    return {"sites": {f"{c}|{o}|{s[0]}:{s[1]}:{s[2]}": n for (c, o, s), n in sites.items()},
            "eq": eq, "self": selfc, "fb_seeded": FB in seeds,
            "vals": {k: v for k, v in vals.items()}}


def main():
    lst, outp = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    files = open(lst).read().split()
    if n:
        files = files[:n]
    sites = collections.Counter()
    joint = collections.Counter()
    valpairs = collections.Counter()
    ex_by_canon = collections.defaultdict(collections.Counter)
    runs = errs = 0
    hits = []
    with Pool(int(os.environ.get("JOBS", "2"))) as pool:
        for i, (p, r) in enumerate(zip(files, pool.imap(work, files, chunksize=64))):
            if "err" in r:
                errs += 1
                continue
            runs += 1
            for k, c in r["sites"].items():
                sites[k] += c
                canon, o, site = k.split("|", 2)
                ex_by_canon[canon][site] += c
            joint[(str(r["eq"]), str(r["self"]), r["fb_seeded"])] += 1
            if r["eq"] is True and r["self"] is False:
                if len(hits) < 200:
                    hits.append(os.path.basename(p))
            v = r.get("vals") or {}
            valpairs[(str(r["self"]), str(v.get(FB)), str(v.get(DV)))] += 1
            if (i + 1) % 20000 == 0:
                print(f"  [{i+1}/{len(files)}] runs={runs} errs={errs} eq&notself={len(hits)}", flush=True)
    res = {"runs": runs, "errors": errs,
           "sites_per_canonical": {c: dict(v) for c, v in ex_by_canon.items()},
           "identity_joint": [{"eq": a, "self_compare": b, "fb_seeded": c, "runs": n}
                              for (a, b, c), n in joint.most_common()],
           "identity_values": [{"self_compare": a, "find_by_1_person_id": b,
                                "devise_person_id": c, "runs": n}
                               for (a, b, c), n in valpairs.most_common(40)],
           "eq_true_and_self_false_examples": hits}
    with open(outp, "w") as fh:
        json.dump(res, fh, indent=2)
    print(f"SCAN2 runs={runs} errors={errs} canonicals={len(ex_by_canon)} "
          f"eq_true_and_self_false={len(hits)}(capped 200)")
    print(f"C20-SCAN2-DONE {outp}")


if __name__ == "__main__":
    main()
