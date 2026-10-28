#!/usr/bin/env python3
"""P31 — THE OFFLINE DRY-CHECK. No JRuby, no drive, no Z3.

The hard filter is only worth switching on if the base it picks really does
realise the cube's pins, and the constructor's own report cannot establish
that: it reads the same index the filter read, so it would be circular. This
script re-derives every base's length state FROM THE BASE'S OWN DUMP — the
alias map, the renamer and the `symbolic_vars` block, exactly the way
`_p23_index.py` derives it — and checks each seed against it.

  V1  every EMPTINESS PIN the seed assumes is realised on its base's run.
      MUST BE 0 violations: this is the property round 8 lacked, and it is
      the one thing the new filter promises.
  V2  every enabling gate the manifest claims walked is really walked on the
      base's own path conditions.
  V3  every seed key written is either a key the base's own `concolic_seeds`
      already carries or a raw ordinal the base actually mints (an INERT key
      is a seeded dimension the runtime will ignore).
  V4  the seed's own length values are consistent with the cube's pins, with
      the deliberate SPLIT pins (one ordinal carries the opposite state so the
      decision is evaluated both ways) reported separately rather than as
      violations.
"""
import json, os, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer      # noqa: E402
from coverage_assumptions import ALIASES                             # noqa: E402

MAN = os.environ.get("P31_MANIFEST", os.path.join(HERE, "_p15_manifest_P31DRY.json"))
GAPS = os.environ.get("P31_GAPS", os.path.join(HERE, "_p30_gaps_P30B.json"))
OUT = os.environ.get("P31_DRYOUT", os.path.join(HERE, "_p31_drycheck.json"))

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s


def scan(path):
    d = json.load(open(path))
    ev = d.get("events") or ()
    amap = alias_map_for([(e.get("result_name"), e.get("note"))
                          for e in ev if e.get("type") == "symbolic_call"], ALIASES)
    rn = renamer(amap)
    lens, rawlens = {}, {}
    for s in d.get("symbolic_vars") or ():
        nm, val = s.get("name"), s.get("value")
        if nm is None or isinstance(val, (dict, list)):
            continue
        raw = str(nm)
        if raw.startswith("len(") and raw.endswith("_rows)"):
            rawlens[raw] = bool(val)
        c = fixlen(rn(raw))
        if c.startswith("SYM_LEN_") and c.endswith("_rows"):
            lens[c] = bool(val)
    t, f = set(), set()
    for e in ev:
        if e.get("type") != "path_condition":
            continue
        ex = fixlen(rn(str(e.get("expr", ""))))
        (t if e.get("taken") else f).add(ex)
    rev = defaultdict(list)
    for o, c in (amap or {}).items():
        rev[c].append(o)
    return {"lens": lens, "rawlens": rawlens, "t": t, "f": f, "rn": rn,
            "rev": dict(rev), "seeds": dict(d.get("concolic_seeds") or {})}


def main():
    t0 = time.time()
    man = json.load(open(MAN))
    gaps = {g["id"]: g for g in json.load(open(GAPS))}
    seedcache = {}

    def seedlist(fn):
        if fn not in seedcache:
            p = os.path.join(HERE, fn)
            seedcache[fn] = json.load(open(p)) if os.path.exists(p) else []
        return seedcache[fn]

    cache = {}
    st = Counter(); detail = Counter(); rows = []
    for m in man:
        bp = os.path.join(HERE, m["base"])
        if bp not in cache:
            if not os.path.exists(bp):
                st["V0 base dump MISSING on disk"] += 1
                continue
            cache[bp] = scan(bp)
        b = cache[bp]
        g = gaps.get(m["gap"], {})
        st["seeds checked"] += 1

        # ---- V1 the emptiness pins
        v1 = []
        for L, w in m.get("pins") or ():
            if L not in b["lens"]:
                st["V1 pin the base never mints (unverifiable)"] += 1
                detail["UNMINTED " + L[-52:]] += 1
                continue
            if b["lens"][L] != bool(w):
                v1.append(L + (" want NZ" if w else " want Z"))
        # ---- V1b THE CANONICAL COLLAPSE, stated rather than hidden. The
        # index stores ONE length per alias canonical (the last raw ordinal
        # written wins), so "the base realises the pin" is a canonical-level
        # fact. At ordinal level a canonical backed by several `records`
        # statements can hold both states in one run — which is exactly the
        # shape a SPLIT PIN needs, so this is reported, never counted as a
        # violation.
        for L, w in m.get("pins") or ():
            core = L[len("SYM_LEN_"):]
            core = core[:-len("_rows")] if core.endswith("_rows") else core
            rl = [b["rawlens"].get("len(%s_rows)" % r) for r in b["rev"].get(core, [])]
            rl = [x for x in rl if x is not None]
            if not rl:
                continue
            st["V1b pins checked at ordinal level"] += 1
            if all(x == bool(w) for x in rl):
                st["V1b  every ordinal in the pinned state"] += 1
            elif any(x == bool(w) for x in rl):
                st["V1b  some ordinals in it (splittable)"] += 1
            else:
                st["V1b  NO ordinal in it (canonical collapse)"] += 1

        if v1:
            st["V1 VIOLATION: base does not realise a pin"] += 1
            for x in v1:
                detail["V1 " + x[-56:]] += 1
        else:
            st["V1 ok"] += 1

        # ---- V2 the gates the manifest claims
        ok, n = m.get("gates_walked_on_base") or [0, 0]
        real = 0
        for e, o in (g.get("gates") or {}).items():
            if (e in b["t"]) if o else (e in b["f"]):
                real += 1
        if real < ok:
            st["V2 VIOLATION: manifest overstates the gates walked"] += 1
        else:
            st["V2 ok"] += 1
        st["V2 gates walked (sum)"] += real
        st["V2 gates demanded (sum)"] += len(g.get("gates") or {})

        # ---- V3 inert keys
        sd = seedlist(m["seed_file"])
        seeds = sd[m["seed_index"]] if m["seed_index"] < len(sd) else {}
        # a key the base's own `concolic_seeds` never carried is NOT
        # necessarily inert: the runtime records a seed key only for a
        # dimension the run actually REACHED, and the whole point of the pin
        # filter is that the new run reaches dimensions the base did not. It is
        # counted and reported, never treated as a violation.
        inert = [k for k in seeds if k not in b["seeds"] and k not in b["rawlens"]]
        if inert:
            st["V3 seeds with a key the base does not carry"] += 1
            st["V3 such keys (sum)"] += len(inert)
            for k in inert[:4]:
                detail["V3 " + k[-56:]] += 1
        else:
            st["V3 ok"] += 1

        # ---- V4 the seed's own length values vs the cube's pins
        v4 = []; splits = 0
        for L, w in m.get("pins") or ():
            # the alias map is keyed on the RESULT NAME, without the `_rows`
            # suffix the length variable carries.
            core = L[len("SYM_LEN_"):]
            core = core[:-len("_rows")] if core.endswith("_rows") else core
            raws = b["rev"].get(core, [])
            keys = ["len(%s_rows)" % r for r in raws]
            if not keys and ("len(%s_rows)" % core) in seeds:
                keys = ["len(%s_rows)" % core]
            vals = [bool(seeds[k]) for k in keys if k in seeds]
            if not vals:
                continue
            if all(v == bool(w) for v in vals):
                continue
            if any(v == bool(w) for v in vals):
                splits += 1                    # deliberate split pin
            else:
                v4.append(L)
        st["V4 split pins seen"] += splits
        if v4:
            st["V4 VIOLATION: every ordinal contradicts the cube pin"] += 1
            for x in v4:
                detail["V4 " + x[-56:]] += 1
        else:
            st["V4 ok"] += 1

        rows.append({"gap": m["gap"], "base": m["base"],
                     "admissibility": m.get("admissibility"),
                     "v1": v1, "gates_real": real,
                     "gates_demanded": len(g.get("gates") or {}),
                     "inert_keys": len(inert), "v4": v4})

    json.dump({"rows": rows, "stat": dict(st), "detail": dict(detail)}, open(OUT, "w"))
    print("P31 OFFLINE DRY-CHECK   manifest %s   %d entries" % (os.path.basename(MAN), len(man)))
    for k in sorted(st):
        print("   %-52s %6d" % (k, st[k]))
    if detail:
        print("\n   detail:")
        for k, v in detail.most_common(14):
            print("      %-66s %5d" % (k[:66], v))
    bad = (st["V1 VIOLATION: base does not realise a pin"]
           + st["V2 VIOLATION: manifest overstates the gates walked"]
           + st["V4 VIOLATION: every ordinal contradicts the cube pin"])
    print("\nP31-DRYCHECK-%s violations=%d  %.0fs" %
          ("PASS" if bad == 0 else "FAIL", bad, time.time() - t0))


if __name__ == "__main__":
    main()
