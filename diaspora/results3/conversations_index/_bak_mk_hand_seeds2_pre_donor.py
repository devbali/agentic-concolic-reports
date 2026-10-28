#!/usr/bin/env python3
"""Targeted seeds, generalized — for a missing combination that NO SINGLE DUMP
records in full.

`demand_round.py` replays only the checker's Z3 model, so every variable
outside the clique falls back to the runner's DEFAULTS and the run lands on the
default path. `mk_hand_seeds.py` fixes that by starting from a dump that
already records EVERY expr of the combination — but when the combination spans
two decision families that no run has yet evaluated together, no such dump
exists and it prints `[skip] no dump records all exprs` forever (cycle 8: the
residue sat at 6 for three rounds, k5/k6/k7, with nothing to do).

This builds the root from BOTH sources:
  1. pick the dump that records the MOST of the combination's exprs (ties
     broken by how many it already agrees with) — that dump's consumed seed
     dict is what put the run in the enabling region;
  2. overlay the checker's own Z3 model for the combination's variables, so the
     exprs that dump never evaluated still get the assignment the solver says
     satisfies them;
  3. flip the conjuncts the dump records but disagrees with, exactly as
     mk_hand_seeds does (booleans direct, var-vs-var by seeding the NON-principal
     operand to the other's value or one off it).

Writes `_hand_<variant>.json`, the same contract run_dse.rb's EXTRA_SEEDS_JSON
expects, so the existing hand-round driver runs it unchanged.
"""
import glob, json, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
VARIANTS = ("html_plain", "html_withcid", "json_plain", "json_withcid", "mobile_plain", "mobile_withcid", "js_plain", "js_withcid", "xml_plain", "xml_withcid")  # C-8: ten variants (js/xml added, adversary round 3)
BOOL_RE = re.compile(r"^\((\w+) == True\)$")
VV_RE   = re.compile(r"^\((\w+) == (\w+)\)$")
LEN_RE  = re.compile(r"^\((?:len\((\w+)\)|SYM_LEN_(\w+))\s*([<>=!]+)\s*(-?\d+)\)$")


def unfix(name):
    return "len(%s)" % name[8:] if name.startswith("SYM_LEN_") else name


def split_and(nc):
    parts, depth, cur, i = [], 0, "", 0
    while i < len(nc):
        if nc[i] == "(": depth += 1
        elif nc[i] == ")": depth -= 1
        if depth == 0 and nc[i:i + 5] == " AND ":
            parts.append(cur.strip()); cur = ""; i += 5; continue
        cur += nc[i]; i += 1
    if cur.strip(): parts.append(cur.strip())
    out = []
    for p in parts:
        if p.startswith("Not(") and p.endswith(")"): out.append((p[4:-1], False))
        else: out.append((p, True))
    return out


def to_seed(v):
    if isinstance(v, bool) or v is None: return v
    if isinstance(v, (int, float)): return int(v)
    s = str(v)
    if s in ("True", "False"): return s == "True"
    try: return int(s)
    except ValueError: return s.strip('"')


def main():
    summary = json.load(open(os.path.join(HERE, "coverage_summary.json")))
    missing = [m for m in summary.get("missing", []) if not m.get("untracked")]
    dumps = []
    for p in glob.glob(os.path.join(HERE, "dump_*.json")):
        if "_achk" in p: continue
        base = os.path.basename(p)
        v = next((x for x in VARIANTS if base.startswith("dump_" + x)), None)
        try: d = json.load(open(p))
        except Exception: continue
        pcs = {e["expr"]: bool(e["taken"]) for e in (d.get("events") or [])
               if e.get("type") == "path_condition"}
        vals = {sv["name"]: sv.get("value") for sv in (d.get("symbolic_vars") or [])}
        dumps.append((v, base, pcs, vals, d.get("concolic_seeds") or {}))
    print(f"[mk_hand_seeds2] {len(dumps)} dumps, {len(missing)} missing")

    per_variant = defaultdict(list)
    for m in missing:
        want = split_and(m["node_constraint"])
        exprs = [e for e, _ in want]
        best = None
        for v, base, pcs, vals, seeds in dumps:
            present = sum(1 for e in exprs if e in pcs)
            if present == 0: continue
            agree = sum(1 for e, t in want if pcs.get(e) == t)
            key = (present, agree)
            if best is None or key > best[0]: best = (key, v, base, pcs, vals, seeds)
        if best is None:
            print(f"[skip] no dump records ANY expr of: {m['node_constraint'][:80]}")
            continue
        (present, agree), v, base, pcs, vals, seeds = best
        s = dict(seeds)
        # (2) the checker's own model for this combination's variables
        for k, val in (m.get("concrete_values") or {}).items():
            s[unfix(k)] = to_seed(val)
        # (3) flip whatever the chosen dump records but disagrees with
        for e, t in want:
            if pcs.get(e) == t: continue
            mb = BOOL_RE.match(e)
            if mb: s[mb.group(1)] = bool(t); continue
            ml = LEN_RE.match(e)
            if ml:
                nm = ml.group(1) or ml.group(2); op, n = ml.group(3), int(ml.group(4))
                if op == ">":  s["len(%s)" % nm] = (n + 1) if t else n
                elif op == "!=": s["len(%s)" % nm] = (n + 1) if t else n
                elif op == "==": s["len(%s)" % nm] = n if t else n + 1
                continue
            mv = VV_RE.match(e)
            if mv:
                l, r = mv.group(1), mv.group(2)
                principal = lambda x: ("person_id" in x) or ("devise_user_first" in x)
                tgt, other = (l, r) if principal(r) else (r, l)
                ov = vals.get(other)
                if not isinstance(ov, int): ov = 1
                s[tgt] = ov if t else ov + 1
                continue
            print(f"[skip conjunct] {e}")
        per_variant[v].append(s)
        print(f"[{v}] from {base} (records {present}/{len(want)}, agrees {agree}) -> {len(s)} seeds")

    for v in VARIANTS:
        out = os.path.join(HERE, f"_hand_{v}.json")
        if per_variant.get(v):
            json.dump(per_variant[v], open(out, "w"), indent=1)
            print(f"{v}: {len(per_variant[v])} hand roots")
        elif os.path.exists(out):
            os.remove(out)


if __name__ == "__main__":
    main()
