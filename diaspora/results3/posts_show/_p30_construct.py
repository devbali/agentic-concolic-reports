#!/usr/bin/env python3
"""P29 round 7 — the ORDINAL-FIXPOINT re-seed.

WHY. The measured reason round 6's 308 contradicted length gates failed is NOT
that the corpus cannot take the outcome; it is that the seed for a length was
written at the BASE run's raw ordinal, the cube's own upstream pins removed an
earlier list read, every later raw ordinal shifted down, and the demanded call
inherited a NEIGHBOUR's value (308/308, `_p29_ordshift.py`).

THE FIX, and why it is a DIFFERENT METHOD (§87.3 item 3). The base is no
longer a corpus run that merely resembles the demand: it is the gap's OWN
round-6 dump — a run in which the cube's upstream pins are ALREADY REALISED,
so its raw-ordinal map is the one the next run will (almost) have. Every
demanded value is then written at the ordinal THAT dump actually minted the
canonical at, read off its own alias map. No sampling, no scoring, no base
search: the counterexample dump IS the base (memory: construct-runs-from-
counterexamples).

Also new: the RENDER_TEXT_SOURCE declaration (P29 §88) makes
`SYM_RESULT_Anonymous_process_3` STEERABLE for the first time — the demanded
render outcome is written as the act-family finder's `_text_empty` seed. Those
20 cubes were `UNSTEERABLE` in every one of the six P26 rounds.
"""
import json, os, re, sys, collections

SEEDSET = os.environ.get("SEEDSET", "P30A")

B = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, B); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for
from coverage_assumptions import ALIASES

VARIANTS = ("auth_html", "anon_html", "auth_json", "anon_json")
ACT = ("SYM_RESULT_ActiveRecord__Relation_evilq_act_vis_1",
       "SYM_RESULT_ActiveRecord__Relation_evilq_act_author_1",
       "SYM_RESULT_ActiveRecord__Relation_evilq_act_public_1",
       "SYM_RESULT_ActiveRecord__Relation_findpublic_act_1")
LEN = re.compile(r"^\(SYM_LEN_(.+?)_(rows|ids)\s*!=\s*0\)$")
BOOLD = re.compile(r"^\((SYM_RESULT_[A-Za-z0-9_]+|assoc_[A-Za-z0-9_]+)\s*==\s*True\)$")
GUID = re.compile(r"^\((SYM_RESULT_[A-Za-z0-9_]+_row_guid)\s*==\s*''\)$")
GUID2 = re.compile(r"^\((SYM_RESULT_[A-Za-z0-9_]+_row_guid)\s*!=\s*StringVal\(''\)\)$")
RENDER = re.compile(r"^\(SYM_RESULT_Anonymous_process_\d+\s*==\s*''\)$")
SELFCMP = re.compile(r"_row_status_message_guid !=")
SIZE = re.compile(r"^\((SYM_RESULT_[A-Za-z0-9_]+_size)\s*==\s*(\d+)\)$")


def variant_of(name):
    for v in VARIANTS:
        if os.path.basename(name).startswith("dump_" + v):
            return v
    return "auth_html"


def main():
    per = json.load(open(os.environ.get("P30_PERKEY", B + "/_p29_perkey_P26F.json")))
    gaps = {g["id"]: g for g in json.load(open(os.environ.get("P30_GAPS", B + "/_p26_gaps_P26F.json")))}
    out = {v: [] for v in VARIANTS}
    manifest = []
    stat = collections.Counter()
    dumpcache = {}
    for gid, r in sorted(per.items()):
        if r["walked"]:
            continue
        p = os.path.join(B, r["dump"])
        if p not in dumpcache:
            d = json.load(open(p))
            ev = d["events"]
            amap = alias_map_for([(e.get("result_name"), e.get("note"))
                                  for e in ev if e.get("type") == "symbolic_call"], ALIASES)
            rev = collections.defaultdict(list)
            for raw, canon in amap.items():
                rev[canon].append(raw)
            # which act finder is live in this run
            act = None
            for a in ACT:
                if any(e.get("type") == "path_condition"
                       and str(e.get("expr")) == "(%s_text_empty == True)" % a for e in ev):
                    act = a; break
            dumpcache[p] = (rev, dict(d.get("concolic_seeds") or {}), act)
        rev, base, act = dumpcache[p]
        s = dict(base)
        wrote = 0; unwritable = []
        for l in r["lits"]:
            e, pol = l["e"], l["p"]
            m = LEN.match(e)
            if m:
                canon, suf = m.group(1), m.group(2)
                raws = rev.get(canon) or ([canon] if canon.startswith("SYM_RESULT_") else [])
                if not raws:
                    unwritable.append(e); continue
                for raw in raws:
                    k = "len(%s_%s)" % (raw, suf)
                    cur = base.get(k)
                    s[k] = (0 if not pol
                            else (cur if isinstance(cur, int) and cur != 0 else 1))
                    wrote += 1
                stat["len@observed-ordinal"] += 1
                continue
            if RENDER.match(e):
                if act and (act + "_text_empty") in s:
                    s[act + "_text_empty"] = bool(pol)
                    wrote += 1; stat["render->act_text_empty (NEW in P29)"] += 1
                else:
                    unwritable.append(e); stat["render: no live act finder"] += 1
                continue
            m = GUID.match(e)
            if m:
                k = m.group(1)
                if k in s or True:
                    s[k] = "" if pol else "g1"
                    wrote += 1; stat["guid"] += 1
                continue
            m = GUID2.match(e)
            if m:
                # the `!= StringVal('')` spelling of the same fact, opposite sense
                s[m.group(1)] = "g1" if pol else ""
                wrote += 1; stat["guid (!= StringVal spelling)"] += 1
                continue
            m = SIZE.match(e)
            if m:
                if pol:
                    s[m.group(1)] = int(m.group(2))
                    wrote += 1; stat["size"] += 1
                else:
                    unwritable.append(e)
                continue
            if SELFCMP.search(e):
                stat["self-compare (no seed dimension)"] += 1
                continue
            m = BOOLD.match(e)
            if m:
                k = m.group(1)
                s[k] = bool(pol)
                wrote += 1; stat["bool"] += 1
                continue
            unwritable.append(e); stat["UNRECOGNISED literal"] += 1
        v = variant_of(r["dump"])
        manifest.append({"gap": gid, "seed_set": SEEDSET, "seed_file": "_p15_seeds%s_%s.json" % (SEEDSET, v),
                         "seed_index": len(out[v]), "variant": v,
                         "base": r["dump"], "base_rank": 0,
                         "values_written": wrote, "unwritable": unwritable,
                         "act": act, "why": {"method": "ordinal-fixpoint on own round-6 dump"}})
        out[v].append(s)
    for v in VARIANTS:
        json.dump(out[v], open(B + "/_p15_seeds%s_%s.json" % (SEEDSET, v), "w"))
        print("  %s: %d seeds" % (v, len(out[v])))
    json.dump(manifest, open(B + "/_p15_manifest_%s.json" % SEEDSET, "w"))
    print("\nliterals written, by kind:")
    for k, n in stat.most_common():
        print("   %-42s %6d" % (k, n))
    nun = sum(1 for m in manifest if m["unwritable"])
    print("\ngaps with >=1 unwritable literal: %d / %d" % (nun, len(manifest)))
    print("P30-CONSTRUCT-DONE seeds=%d" % sum(len(out[v]) for v in VARIANTS))


main()
