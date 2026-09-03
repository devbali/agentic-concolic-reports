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
STR_RE  = re.compile(r"^\((SYM_[A-Za-z0-9_]+) == (?:StringVal\('([^']*)'\)|'([^']*)')\)$")
INT_RE  = re.compile(r"^\((SYM_[A-Za-z0-9_]+) (>|<|>=|<=|==|!=) (-?\d+)\)$")
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
        # the checker names a length `SYM_LEN_X`; the dump records `len(X)`.
        # Without this the seeder never saw a length expr as RECORDED (every
        # `> 1` conjunct read as missing, every base scored one short).
        pcs = {re.sub(r"\(len\((\w+)\)", r"(SYM_LEN_\1", e["expr"]): bool(e["taken"])
               for e in (d.get("events") or []) if e.get("type") == "path_condition"}
        vals = {sv["name"]: sv.get("value") for sv in (d.get("symbolic_vars") or [])}
        dumps.append((v, base, pcs, vals, d.get("concolic_seeds") or {}))
    print(f"[mk_hand_seeds2] {len(dumps)} dumps, {len(missing)} missing")

    per_variant = defaultdict(list)
    per_variant_map = {}
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
        # (2) the checker's own model — for THIS COMBINATION'S variables ONLY.
        # `concrete_values` is a full Z3 model: every solver var gets a value,
        # and unconstrained ones get 0 — including the PREFIX-ROUTING lengths
        # (`SYM_LEN_..._to_a_1_rows: 0` empties the inbox, so the conversation's
        # `records_1` decisions are never reached). Overlaying all of them
        # replaced the base's route with a dead one: 27/27 SEEDS_ONLY replays
        # recorded NONE of the five target exprs. Only vars named in the target
        # exprs may come from the model; everything else stays the base's.
        # ... and only to vars of exprs the base does NOT already satisfy: the
        # model's value for a satisfied expr is just ONE satisfying value, and
        # for a length it is usually 0 — which deletes the row every other
        # conjunct needs (round 5: `len(records_1_rows) := 0` under a satisfied
        # `> 1` False left has_mention/author_id unrecorded, 3 rounds stalled).
        target_vars = set()
        for e, t in want:
            if pcs.get(e) == t:
                continue
            for nm in re.findall(r"(?:SYM_LEN_)?SYM_[A-Za-z0-9_]+", e):
                target_vars.add(unfix(nm))
        for k, val in (m.get("concrete_values") or {}).items():
            if unfix(k) in target_vars:
                if val == "":  # A6-12: Z3 artifact for an unconstrained
                    continue   # string var; step (3) sets real demands
                s[unfix(k)] = to_seed(val)
        # (2b) DONOR GATES — an expr the chosen dump does NOT record is
        # unreachable from its seeds: it sits behind a GATE the base never
        # opened (`_text_dlink_is_post` is recorded only when `_text_has_dlink`
        # is TRUE — 2,126/2,126 corpus-wide; the mirrored uniq identity only on
        # the multi-row participants path). Step (3) can flip a recorded expr
        # but cannot make an unrecorded one appear, so 20/32 assignments of the
        # records_1 clique stayed missing across three rounds. For each lacking
        # expr, take the dump that DOES record it (the one whose seeds agree
        # most with the root so far) and copy its seeds for every var sharing
        # the expr's ROW PREFIX (the gate vars live there) and its length var.
        def prefixes_of(expr):
            out = set()
            for nm in re.findall(r"SYM_RESULT_[A-Za-z0-9_]+", expr):
                out.add(re.sub(r"_row_.*$", "_row_", nm) if "_row_" in nm else nm)
                out.add(re.sub(r"_rows.*$", "_rows", nm))
            return out
        for e, t in want:
            if e in pcs: continue
            pf = prefixes_of(e)
            donor = None
            for v2, base2, pcs2, vals2, seeds2 in dumps:
                if e not in pcs2 or v2 != v: continue
                agree2 = sum(1 for k2, x2 in seeds2.items() if s.get(k2) == x2)
                if donor is None or agree2 > donor[0]: donor = (agree2, base2, seeds2)
            if donor is None:
                print(f"[no donor] {e[:90]}"); continue
            copied = 0
            for k2, x2 in donor[2].items():
                kk = k2[4:-1] if k2.startswith("len(") else k2
                if any(kk.startswith(px) for px in pf):
                    s[k2] = x2; copied += 1
            print(f"[donor] {e[:70]} <- {donor[1]} ({copied} gate seeds)")
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
            # a plain INT compare on a value var — the mobile layout's badge
            # counts (`unread_notifications.size > 0`, `unread_message_count > 0`:
            # a COUNT / SUM var against a literal). Same seeding rule as LEN_RE.
            # a STRING-literal compare on a value var — `(X == StringVal('lit'))`
            # / `(X == '')`: seed the literal to take it, a different string to
            # refuse it (trackable's `current_sign_in_ip == '0.0.0.0'`, the
            # conversation subject's blank check).
            ms = STR_RE.match(e)
            if ms:
                nm = ms.group(1); lit = ms.group(2) if ms.group(2) is not None else ms.group(3)
                s[nm] = lit if t else (lit + "x" if lit else "nonblank")
                continue
            mi = INT_RE.match(e)
            if mi:
                nm, op, n = mi.group(1), mi.group(2), int(mi.group(3))
                if op == ">":    s[nm] = (n + 1) if t else n
                elif op == "<":  s[nm] = (n - 1) if t else n
                elif op == ">=": s[nm] = n if t else n - 1
                elif op == "<=": s[nm] = n if t else n + 1
                elif op == "==": s[nm] = n if t else n + 1
                elif op == "!=": s[nm] = (n + 1) if t else n
                continue
            mv = VV_RE.match(e)
            if mv:
                l, r = mv.group(1), mv.group(2)
                principal = lambda x: ("person_id" in x) or ("devise_user_first" in x)
                tgt, other = (l, r) if principal(r) else (r, l)
                # A6-12: anchor on what the REPLAY will actually use for
                # `other` — the root's own seed when it has one, else the
                # base dump's recorded runtime value. And honor STRING vars:
                # `last_sign_in_ip == current_sign_in_ip` is a string
                # equality; the old int-only fallback seeded `1`, so every
                # combo demanding the equality True was unreachable by
                # construction (round-6 n1/n2: 0/200 closed).
                ov = s.get(other, vals.get(other))
                tv = vals.get(tgt)
                if isinstance(ov, bool): ov = int(ov)
                if isinstance(ov, str) and ov == "": ov = None
                if ov is None and isinstance(tv, str):
                    ov = tv if tv else "198.51.100.77"
                    if t: s[other] = ov  # no anchor at all: pin BOTH ends
                if isinstance(ov, str):
                    s[tgt] = ov if t else ov + "x"
                else:
                    if not isinstance(ov, int): ov = 1
                    s[tgt] = ov if t else ov + 1
                continue
            print(f"[skip conjunct] {e}")
        per_variant[v].append(s)
        per_variant_map.setdefault(v, []).append(
            {"combo": m["node_constraint"], "base": base})
        print(f"[{v}] from {base} (records {present}/{len(want)}, agrees {agree}) -> {len(s)} seeds")

    for v in VARIANTS:
        out = os.path.join(HERE, f"_hand_{v}.json")
        if per_variant.get(v):
            json.dump(per_variant[v], open(out, "w"), indent=1)
            json.dump(per_variant_map[v], open(out.replace(".json", "_map.json"), "w"), indent=1)
            print(f"{v}: {len(per_variant[v])} hand roots")
        elif os.path.exists(out):
            os.remove(out)


if __name__ == "__main__":
    main()
