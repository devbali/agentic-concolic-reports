#!/usr/bin/env python3
"""C20 — the ACTIVE-FALSIFICATION verdict for the `exists?` alias.

Matches every driven probe dump back to `_c20_probe_manifest.json` BY ITS OWN
SEEDS (never by dump order), then, per (base, canonical name):

    effect(o) = ( added, removed )  statement multisets of the run that seeds
                ordinal `o`'s `_exists` TRUE, relative to the same base's
                ALL-FALSE reference run — `access_trace_binds`, the currency
                of the gate's own Alias test (ii).

PASS for a base iff every ordinal of that canonical has the SAME effect and
every ordinal still resolves to that canonical in the probe.
FAIL = two ordinals of one canonical with different effects  (the falsifier).
NOT-COMPARABLE = a probe is missing, or an ordinal moved to another canonical.

Also reports the recorded OUTCOME the probe realised for each ordinal, so a
seed that did not realise is visible rather than silently counted.
"""
import hashlib, json, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import (AliasAssumption, alias_map_for,  # noqa: E402
                                         statement_key)
from coverage_assumptions import ALIASES                                  # noqa: E402

EXISTS_PAT = r"SYM_RESULT_ActiveRecord__FinderMethods_exists__\d+"
_ORD_RE = re.compile(r"^SYM_RESULT_ActiveRecord__FinderMethods_exists__(\d+)$")
_EXVAR_RE = re.compile(r"SYM_RESULT_ActiveRecord__FinderMethods_exists__(\d+)_exists")
_AL = list(ALIASES) + [AliasAssumption(result_pattern=EXISTS_PAT, key="statement")]


def digest(seeds):
    return hashlib.blake2b(json.dumps(seeds, sort_keys=True, default=str).encode(),
                           digest_size=10).hexdigest()


def trace_binds(d):
    return collections.Counter(
        (str(ev.get("target") or ""), statement_key(ev.get("note") or ""))
        for ev in d.get("events") or []
        if ev.get("type") == "symbolic_call" and ev.get("result_name"))


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "C20P"
    man = json.load(open(os.path.join(HERE, "_c20_probe_manifest.json")))
    want = {d: r for d, r in man.items()}
    got = {}
    import glob
    files = glob.glob(os.path.join(HERE, f"dump_*_{tag}*.json"))
    print(f"driven dumps with tag {tag}: {len(files)}")
    for p in files:
        try:
            d = json.load(open(p))
        except Exception:
            continue
        dg = digest(d.get("concolic_seeds") or {})
        if dg not in want:
            continue
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in d.get("events") or ()
                              if e.get("type") == "symbolic_call"], _AL)
        canon = {}
        for rn, c in amap.items():
            m = _ORD_RE.match(rn)
            if m:
                canon[m.group(1)] = c
        outs = collections.defaultdict(set)
        for ev in d.get("events") or ():
            if ev.get("type") != "path_condition":
                continue
            for m in _EXVAR_RE.finditer(str(ev.get("expr", ""))):
                outs[m.group(1)].add(bool(ev.get("taken")))
        got[dg] = {"path": os.path.basename(p), "trace": trace_binds(d),
                   "canon": canon, "outs": {k: sorted(v) for k, v in outs.items()}}
    print(f"matched back to the manifest by seed digest: {len(got)}/{len(want)}")

    # group by (base, canonical)
    groups = collections.defaultdict(dict)
    for dg, r in want.items():
        groups[(r["base"], r["canonical"])][r["kind"] if r["kind"] != "flip"
                                            else f"flip:{r['flipped']}"] = dg
    verdicts = collections.Counter()
    fails, notcomp, details = [], [], []
    for (base, c), kinds in sorted(groups.items()):
        refdg = kinds.get("ref")
        if refdg is None or refdg not in got:
            verdicts["NOT-COMPARABLE"] += 1
            notcomp.append(f"{base} {c[-16:]}: no reference run")
            continue
        ref = got[refdg]
        eff, bad = {}, []
        for k, dg in sorted(kinds.items()):
            if not k.startswith("flip:"):
                continue
            o = k.split(":", 1)[1]
            if dg not in got:
                bad.append(f"ord {o}: probe missing"); continue
            g = got[dg]
            if g["canon"].get(o) != c:
                bad.append(f"ord {o}: reading moved to {str(g['canon'].get(o))[-16:]}")
                continue
            if g["outs"].get(o) != [True]:
                bad.append(f"ord {o}: seed did not realise (recorded {g['outs'].get(o)})")
                continue
            add = tuple(sorted((g["trace"] - ref["trace"]).items()))
            rem = tuple(sorted((ref["trace"] - g["trace"]).items()))
            eff[o] = (add, rem)
        if len(eff) < 2:
            verdicts["NOT-COMPARABLE"] += 1
            notcomp.append(f"{base} {c[-16:]}: {len(eff)} comparable ordinal(s); " + "; ".join(bad))
            continue
        distinct = {json.dumps(v, default=str) for v in eff.values()}
        if len(distinct) > 1:
            verdicts["FAIL"] += 1
            fails.append({"base": base, "canonical": c,
                          "effects": {o: [len(a), len(r)] for o, (a, r) in eff.items()},
                          "raw": {o: str(v)[:400] for o, v in eff.items()}})
        else:
            verdicts["PASS"] += 1
            e = next(iter(eff.values()))
            details.append({"base": base, "canonical": c, "ordinals": sorted(eff),
                            "added": len(e[0]), "removed": len(e[1]),
                            "note": "identical effect across every tested ordinal"})
        if bad:
            details.append({"base": base, "canonical": c, "partial": bad})
    out = {"tag": tag, "probes_driven": len(got), "probes_expected": len(want),
           "groups": len(groups), "verdicts": dict(verdicts),
           "fails": fails, "not_comparable": notcomp[:60], "details": details[:200]}
    json.dump(out, open(os.path.join(HERE, f"_c20_alias_verdict_{tag}.json"), "w"), indent=1)
    bycanon = collections.Counter()
    for (b, c), _k in groups.items():
        bycanon[c] += 1
    print("groups per canonical:", {k[-16:]: v for k, v in bycanon.items()})
    print(f"RESULT: PASS {verdicts['PASS']}  FAIL {verdicts['FAIL']}  "
          f"NOT-COMPARABLE {verdicts['NOT-COMPARABLE']}")
    for f in fails[:6]:
        print("  FAIL", f["base"], f["canonical"][-16:], f["effects"])
    print(f"C20-ALIASVERDICT-DONE {tag}")


if __name__ == "__main__":
    main()
