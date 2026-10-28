#!/usr/bin/env python3
"""C20 — ORDINAL SWEEP for g0 (missing[1]), the one `exists__8` gap-set.

The cube pins `Not(to_ary_notifications_10254800_rows > 1)` — ONE notification
row — while `exists__8` requires SIX `exists?` calls before the header's
`admin?`/`moderator?` pair. In the corpus those six are always the contact
profile's bio+location dlink rendered once per notification ROW, so every one
of the 152 corpus runs that mint ordinal 8 has more than one row and the cube
looks unreachable.

But the row is not the only dlink-bearing surface: the row's ACTORS each carry
a profile whose bio/location render too, and the cube itself pins
`..._row_actors_row_rows > 1`. So the sweep drives, per base, the demanded
literals PLUS every combination of (actor count) x (which display surfaces
carry a `diaspora://` link), and MEASURES where the roles pair lands.

A run that puts the moderator probe at ordinal 8 with one notification row
realises the cube; if no combination does, the coupling is a measured fact
about the endpoint and the set is classified, not driven.

usage: python3 _c20_ord8_sweep.py <cov.json> [N_BASES]
"""
import json, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402

VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
_EQT = re.compile(r"^\((\w+) == (True|False)\)$")
_GTI = re.compile(r"^\((\w+) > (-?\d+)\)$")


def split_lits(nc):
    out = []
    for part in nc.split(" AND "):
        p, w = part.strip(), True
        if p.startswith("Not(") and p.endswith(")"):
            w, p = False, p[4:-1]
        out.append((p, w))
    return out


def main():
    cov = sys.argv[1]
    NB = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    lits = split_lits(json.load(open(cov))["missing"][1]["node_constraint"])
    rows_lit = next(e for e, _w in lits if e.endswith("_rows > 1)") and "row_" not in e[60:])
    actors_lit = next(e for e, _w in lits if "row_actors_row_rows" in e)
    bs = json.load(open(os.path.join(HERE, "_c20_exists_bases.json")))["bases"]["0"]
    per_variant, manifest = collections.defaultdict(list), []
    used = 0
    for r in bs:
        if used >= NB:
            break
        p = r["path"]
        d = json.load(open(p))
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in d.get("events") or ()
                              if e.get("type") == "symbolic_call"], ALIASES)
        rn = renamer(amap)
        rev = collections.defaultdict(list)
        for o, c in (amap or {}).items():
            rev[c].append(o)
        rev_sorted = sorted(rev, key=len, reverse=True)
        base_seeds = dict(d.get("concolic_seeds") or {})
        variant = next((v for v in VARIANTS
                        if os.path.basename(p).startswith("dump_" + v)), None)
        del d
        if variant is None:
            continue

        def seedkeys(k):
            dn = f"len({k[8:]})" if k.startswith("SYM_LEN_") else k
            outs = [dn]
            for c in rev_sorted:
                if re.search(re.escape(c) + r"(?![0-9])", dn):
                    outs = [re.sub(re.escape(c) + r"(?![0-9])",
                                   o.replace("\\", "\\\\"), dn) for o in rev[c]]
                    break
            return [o for o in outs if fixlen(rn(o)) == k]

        # the demanded literals (actors length is swept, so it is written last)
        core = {}
        for e, want in lits:
            m = _EQT.match(e)
            if m:
                val = (m.group(2) == "True") if want else (m.group(2) != "True")
                for sk in seedkeys(m.group(1)):
                    core[sk] = val
                continue
            m = _GTI.match(e)
            if m:
                rhs = int(m.group(2))
                for sk in seedkeys(m.group(1)):
                    core[sk] = rhs + 1 if want else max(0, rhs)
        # the dlink surfaces the base can carry, named through its own map
        notif = seedkeys(rows_lit[1:].split(" > ")[0])          # len(<ordinal>_rows)
        stem = notif[0][4:-6] if notif else None                # <to_ary ordinal>_rows -> stem
        toggles = []
        if stem:
            for suf in ("_row_target_text_has_dlink",
                        "_row_target_mentions_container_text_has_dlink",
                        "_row_target_mentions_container_commentable_text_has_dlink",
                        "_row_target_statusmessage_text_has_dlink",
                        "_row_actors_row_profile_row_disp_has_dlink",
                        "_row_target_author_profile_disp_has_dlink"):
                toggles.append(stem + suf)
        toggles += ["SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_profile_disp_has_dlink",
                    "SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_profile_disp_has_dlink"]
        masks = [0b00000001, 0b00000011, 0b00000101, 0b00001001, 0b00010001,
                 0b00100001, 0b01000001, 0b10000001, 0b11000001, 0b11100001,
                 0b11110001, 0b11111111]
        used += 1
        for alen in (2, 3, 4):
            for mk in masks:
                s = dict(base_seeds)
                s.update(core)
                for sk in seedkeys(actors_lit[1:].split(" > ")[0]):
                    s[sk] = alen
                for i, t in enumerate(toggles):
                    s[t] = bool(mk >> i & 1)
                    # a dlink surface also needs its text present and post-typed
                    if t.endswith("_text_has_dlink"):
                        s[t[: -len("_has_dlink")] + "_nil"] = False
                        s[t[: -len("has_dlink")] + "dlink_is_post"] = True
                    if t.endswith("_disp_has_dlink"):
                        s[t[: -len("has_dlink")] + "dlink_is_post"] = True
                per_variant[variant].append(s)
                manifest.append({"base": os.path.basename(p), "variant": variant,
                                 "actors": alen, "mask": mk})
    for v in VARIANTS:
        json.dump(per_variant.get(v, []),
                  open(os.path.join(HERE, f"_c20_ord8_seeds_{v}.json"), "w"))
    json.dump(manifest, open(os.path.join(HERE, "_c20_ord8_manifest.json"), "w"), indent=1)
    print("bases", used, "per variant:", {v: len(per_variant.get(v, [])) for v in VARIANTS})
    print(f"C20-ORD8-BUILT {sum(len(x) for x in per_variant.values())} seeds")


if __name__ == "__main__":
    main()
