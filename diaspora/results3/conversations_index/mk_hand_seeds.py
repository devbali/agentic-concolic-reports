#!/usr/bin/env python3
"""Targeted seeds for a missing combination the demand round cannot reach.

`demand_round.py` replays the checker's Z3 model as a seed dict, but that model
names only the clique's variables: everything else falls back to the runner's
DEFAULTS, so a combination whose enabling conditions (a non-empty list, a
`_text_has_dlink` that mints `_text_dlink_is_post` at all) are not themselves in
the clique is replayed as the default path and the round adds nothing
(coordinator, 2026-08-28).

This builds the root the prefix-directed DSE actually needs: take the corpus
dump that ALREADY records every expr of the combination and agrees with it on
the most conjuncts, take THAT run's consumed seed dict (which is what put the
run in the enabling region), and flip only the disagreeing conjuncts.

    python3 mk_hand_seeds.py            # writes _hand_<variant>.json
"""
import glob, json, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
VARIANTS = ("html_plain", "html_withcid", "json_plain", "json_withcid", "mobile_plain", "mobile_withcid", "js_plain", "js_withcid", "xml_plain", "xml_withcid")  # C-8: ten variants (js/xml added, adversary round 3)
UNFIX = lambda n: f"len({n[8:]})" if n.startswith("SYM_LEN_") else n


def conjuncts(nc):
    """`A AND Not(B) AND C` -> [(expr, wanted_taken), ...]"""
    out, depth, cur = [], 0, ""
    for ch in nc:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        cur += ch
        if depth == 0 and cur.strip().endswith(")"):
            t = cur.strip()
            cur = ""
            if t.startswith("Not(") and t.endswith(")"):
                out.append((t[4:-1], False))
            elif t:
                out.append((t, True))
    return [(e.strip(), t) for e, t in out if e.strip() and e.strip() != "AND"]


def split_and(nc):
    parts, depth, cur = [], 0, ""
    i = 0
    while i < len(nc):
        if nc[i] == "(":
            depth += 1
        elif nc[i] == ")":
            depth -= 1
        if depth == 0 and nc[i:i + 5] == " AND ":
            parts.append(cur.strip()); cur = ""; i += 5; continue
        cur += nc[i]; i += 1
    if cur.strip():
        parts.append(cur.strip())
    out = []
    for p in parts:
        if p.startswith("Not(") and p.endswith(")"):
            out.append((p[4:-1], False))
        else:
            out.append((p, True))
    return out


BOOL_RE = re.compile(r"^\((\w+) == True\)$")
VV_RE = re.compile(r"^\((\w+) == (\w+)\)$")


def main():
    summary = json.load(open(os.path.join(HERE, "coverage_summary.json")))
    missing = [m for m in summary.get("missing", []) if not m.get("untracked")]
    dumps = []
    for p in glob.glob(os.path.join(HERE, "dump_*.json")):
        if "_achk" in p:
            continue
        base = os.path.basename(p)
        v = next((x for x in VARIANTS if base.startswith("dump_" + x)), None)
        try:
            d = json.load(open(p))
        except Exception:
            continue
        pcs = {e["expr"]: bool(e["taken"]) for e in (d.get("events") or [])
               if e.get("type") == "path_condition"}
        vals = {sv["name"]: sv.get("value") for sv in (d.get("symbolic_vars") or [])}
        dumps.append((v, base, pcs, vals, d.get("concolic_seeds") or {}))

    per_variant = defaultdict(list)
    for m in missing:
        want = split_and(m["node_constraint"])
        exprs = [e for e, _ in want]
        best = None
        for v, base, pcs, vals, seeds in dumps:
            if not all(e in pcs for e in exprs):
                continue
            agree = sum(1 for e, t in want if pcs[e] == t)
            if best is None or agree > best[0]:
                best = (agree, v, base, pcs, vals, seeds)
        if best is None:
            print(f"[skip] no dump records all exprs of: {m['node_constraint'][:90]}")
            continue
        agree, v, base, pcs, vals, seeds = best
        s = dict(seeds)
        for e, t in want:
            if pcs[e] == t:
                continue
            mb = BOOL_RE.match(e)
            if mb:
                s[mb.group(1)] = bool(t)
                continue
            mv = VV_RE.match(e)
            if mv:
                l, r = mv.group(1), mv.group(2)
                principal = "person_id" in r or "devise_user_first" in r
                tgt, other = (l, r) if principal else (r, l)
                ov = vals.get(other)
                if not isinstance(ov, int):
                    ov = 1
                s[tgt] = ov if t else ov + 1
                continue
            print(f"[skip conjunct] {e}")
        per_variant[v].append(s)
        print(f"[{v}] from {base} (agreed {agree}/{len(want)}) -> {len(s)} seeds")

    for v in VARIANTS:
        out = os.path.join(HERE, f"_hand_{v}.json")
        if per_variant.get(v):
            json.dump(per_variant[v], open(out, "w"), indent=1)
            print(f"{v}: {len(per_variant[v])} hand roots")
        elif os.path.exists(out):
            os.remove(out)


if __name__ == "__main__":
    main()
