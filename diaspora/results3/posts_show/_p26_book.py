#!/usr/bin/env python3
"""P26 round booking harvester — reads the round artefacts already on disk and
prints the per-round table under BOTH readings. Pure log/JSON parsing: no Z3,
no corpus load, no engine import, writes nothing."""
import json, os, re, sys

B = os.path.dirname(os.path.abspath(__file__))
def rd(p):
    p = os.path.join(B, p)
    return open(p, errors="replace").read() if os.path.exists(p) else ""

def census(n):
    """The emit census keyed by emit round number N (tag P26R<N>)."""
    j = os.path.join(B, f"_p26_emit_P26R{n}.json")
    log = rd(f"_p26_enum_P26R{n}.log")
    out = {"round": f"P26R{n}"}
    if os.path.exists(j):
        d = json.load(open(j)); s = d["emit_stats"]
        out.update(cubes=s["cubes"], no_model=s["no_model"], pieces=s["pieces"],
                   mass=s["mass"], remaining=int(d.get("remaining_total", 0)))
    m = re.search(r"^  sets=(\d+) satisfiable=(\d+) covered=(\d+) REMAINING=(\d+)", log, re.M)
    if m:
        out.update(sets=int(m.group(1)), satisfiable=int(m.group(2)),
                   covered=int(m.group(3)))
    m = re.search(r"^  16b: sets=(\d+) satisfiable=(\d+) covered=(\d+) REMAINING=(\d+)", log, re.M)
    if m:
        out.update(b16_sets=int(m.group(1)), b16_remaining=int(m.group(4)))
    m = re.search(r"^universe built in (\d+)s", log, re.M)
    if m: out["universe_s"] = int(m.group(1))
    m = re.search(r"P26-EMIT-DONE in (\d+)s", log)
    if m: out["emit_s"] = int(m.group(1))
    return out

def rnd(x, runs=None):
    """Per-round construct / drive / explain / pass facts for round letter X."""
    o = {"round": f"P26{x}"}
    g = rd(f"_p26_gaps_P26{x}.log")
    for key, pat in (("constructible", r"cubes fully constructible from observed values\s*:\s*(\d+)"),
                     ("ood",           r"cubes with >=1 CONSTRAINED out-of-domain value\s*:\s*(\d+)"),
                     ("never_obs",     r"cubes with >=1 CONSTRAINED never-observed var\s*:\s*(\d+)"),
                     ("unsteerable",   r"cubes with an UNSTEERABLE constrained variable\s*:\s*(\d+)")):
        m = re.search(pat, g)
        if m: o[key] = int(m.group(1))
    c = rd(f"_p26_construct_P26{x}.log")
    for key, pat in (("seeds", r"seeds built\s*:\s*(\d+)"),
                     ("subst", r"values substituted\s*:\s*(\d+)"),
                     ("kept_ood", r"values kept out-of-dom\s*:\s*(\d+)"),
                     ("d1_groups", r"groups where it bit:\s*(\d+)"),
                     ("d1_rejected", r"bases rejected (\d+)"),
                     ("d1_relaxed", r"RELAXED \(no both-ways base exists\):\s*(\d+) groups")):
        m = re.search(pat, c)
        if m: o[key] = int(m.group(1))
    m = re.search(r"values not seedable\s*:\s*(\d+) over (\d+) variables, in (\d+) seeds", c)
    if m: o["not_seedable"] = f"{m.group(1)}/{m.group(2)}vars/{m.group(3)}seeds"
    e = rd(f"_p26_explain_P26{x}.log")
    m = re.search(r"gaps WALKED[^:]*:\s*(\d+)", e)
    if m: o["walked"] = int(m.group(1))
    m = re.search(r"over every cube literal of every driven gap \((\d+) keys\)", e)
    if m: o["literals"] = int(m.group(1))
    for key, pat in (("honoured", r"^   honoured\s+(\d+)\s+([\d.]+) %"),
                     ("contradicted", r"^   contradicted\s+(\d+)\s+([\d.]+) %"),
                     ("never_eval", r"^   never_evaluated\s+(\d+)\s+([\d.]+) %")):
        m = re.search(pat, e, re.M)
        if m: o[key] = f"{m.group(1)} ({m.group(2)}%)"
    m = re.search(r"^dumps labelled \*P26" + x + r"\*\s*:\s*(\d+)", e, re.M)
    if m: o["runs"] = int(m.group(1))
    d = rd(f"_p15_drive_P26{x}.log")
    m = re.search(r"(P15-DRIVE-DONE[^\n]*)", d)
    if m: o["drive"] = m.group(1).strip()
    p_ = rd(f"_p26_pass_P26{x}2.log")
    m = re.search(r"DUMP_LIST \S+\s+(\d+) profiles", p_)
    if m: o["profiles"] = int(m.group(1))
    for key in ("COMPLETE", "NODES", "MISSING", "BLOCKING", "GENUINE", "TRUNCATED",
                "SOLVER_LOST", "DEMAND_SETS", "TREE_COMPLETE", "TREE_MISSING",
                "FORECLOSURES", "PAIRS_CONFINED", "SPLITS", "WITHDRAWN_TRIPWIRE",
                "PROVISIONAL", "FORECL_PROVISIONAL"):
        m = re.search(r"(?:^|;)" + key + r"=([^;\n]+)", p_, re.M)
        if m: o[key] = m.group(1).strip()
    o["conf_withdrawn_lines"] = p_.count("CONF-WITHDRAWN")
    o["conf_disqualified_lines"] = p_.count("CONF-DISQUALIFIED")
    m = re.search(r"Maximum resident set size \(kbytes\): (\d+)", p_)
    if m: o["peak_MB"] = int(m.group(1)) // 1024
    m = re.search(r"Elapsed \(wall clock\)[^:]*: ([\d:.]+)", p_)
    if m: o["pass_wall"] = m.group(1)
    o["pass"] = ("DONE" if "P26-PASS-DONE" in p_ else
                 "FAILED" if "P26-PASS-FAILED" in p_ else "-")
    return o

if __name__ == "__main__":
    ns = sys.argv[1].split(",") if len(sys.argv) > 1 else ["1", "2", "3", "4", "5", "6"]
    xs = sys.argv[2].split(",") if len(sys.argv) > 2 else list("ABCDEF")
    cs = [census(n) for n in ns]
    print("=== CENSUS (emit rounds) — OR-refined and §16b ===")
    for c in cs:
        if "remaining" not in c: continue
        print(f"  {c['round']:7s} sets={c.get('sets','?'):>5} sat={c.get('satisfiable','?'):>7} "
              f"cov={c.get('covered','?'):>7} REMAIN={c['remaining']:>7} "
              f"pieces={c['pieces']:>5} EMITTED={c['cubes']:>5} MODEL-LESS={c['no_model']:>5} "
              f"| 16b sets={c.get('b16_sets','?'):>5} REMAIN={c.get('b16_remaining','?')}")
    print("\n=== RATE (closed per run), both readings ===")
    print("    runs = that round's EMITTED cubes = seeds built = dumps labelled *P26X*")
    prev = x_prev = None
    for c, x in zip(cs, xs):
        if "remaining" not in c:
            continue
        if prev is not None:
            runs = prev["cubes"]
            d_or = prev["remaining"] - c["remaining"]
            rate = (d_or / runs) if runs else float("nan")
            pb, cb = prev.get("b16_remaining"), c.get("b16_remaining")
            d16 = f"{pb - cb:+,}" if (pb and cb) else "n/a (no §16b census that round)"
            print(f"  P26{x_prev}: {runs:>5} runs  OR-refined {prev['remaining']:>7} -> "
                  f"{c['remaining']:<7} CLOSED {d_or:>6} = {rate:.3f} closed/run   §16b Δ {d16}")
        prev, x_prev = c, x

    print("\n=== PER ROUND (construct / drive / explain / pass) ===")
    for x in xs:
        r = rnd(x)
        if len(r) <= 2: continue
        print(f"  {r['round']}: " + "  ".join(f"{k}={v}" for k, v in r.items() if k != "round"))

# ---------------------------------------------------------------------------
# §84 addition: the NARROW/WIDE split of the OR-refined residue.
# Every model-less region piece lives in a demand set of width <= 10 and every
# piece in a set of width >= 11 has a Z3 model — measured, all rounds, zero
# exceptions. Reported because it decomposes the campaign rate into a drivable
# half and a frozen half.
def widths(n):
    log = rd(f"_p26_enum_P26R{n}.log")
    rows = re.findall(r"^\s{4,}(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$", log, re.M)
    nw = dict(sets=0, pieces=0, emitted=0, mass=0)
    wd = dict(sets=0, pieces=0, emitted=0, mass=0)
    for w, sets, rem, pieces, em in ((int(a) for a in r) for r in rows):
        b = nw if w <= 10 else wd
        b["sets"] += sets; b["pieces"] += pieces; b["emitted"] += em; b["mass"] += rem
    for b in (nw, wd):
        b["no_model"] = b["pieces"] - b["emitted"]
    return {"narrow_w<=10": nw, "wide_w>=11": wd}
