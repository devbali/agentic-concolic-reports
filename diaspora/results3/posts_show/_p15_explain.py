#!/usr/bin/env python3
"""P15 — EXPLAIN A DRIVEN ROUND PER KEY (RUNBOOK Phase 2: honoured /
contradicted / never evaluated).

WHY THIS EXISTS. "Nothing is residue until construction was tried AND the
driven run explained per key." The coverage pass answers "is the set still
missing"; it does NOT say whether a seed was ignored, flipped, or simply never
reached. Those are different diagnoses with different next moves, and only the
last one is evidence about the program rather than about the constructor.

THE KEY. Not the seed dict entry — a constructed seed is the BASE's whole seed
dict with the cube's constrained values overlaid, so most of its keys are
context, not demand. The demand is the CUBE: every literal of the gap's
`node_constraint`, with its polarity. For each literal `(expr)` at polarity p:

    honoured         the dump evaluated `expr` and took p
    contradicted     the dump evaluated `expr` and took not-p
    never evaluated  the dump never evaluated `expr` at all

A gap is WALKED iff every one of its literals is honoured — that is the leaf
the checker asked for, measured on the dump itself, with no Z3 and no pass.

JOIN. Dump -> gap by SEED-DICT IDENTITY (blake2b over the sorted seed dict, the
exact dict handed to `EXTRA_SEEDS_JSON`), never by parsing the label's chunk
index: the chunk worker restarts on the remainder after a native abort, so
label order is not seed order. Dumps whose seed dict matches no seed, and seeds
with no dump, are both COUNTED and reported — a silent drop is the defect class
§77.4 was about.

Names are joined the way the checker joins them: alias canonicalization
(`alias_map_for`/`renamer`) then `len(X) -> SYM_LEN_X`, both directions, per
the RUNBOOK `len` SPELLING rule.

  env: P15_TAG (label substring, default P15A) · P15_SET (A/B, default A)
       P15_GAPS · P15_MANIFEST · P15_OUT
"""
import glob, hashlib, json, os, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402

TAG   = os.environ.get("P15_TAG", "P15A")
SET   = os.environ.get("P15_SET", "A")
GAPS  = os.environ.get("P15_GAPS", os.path.join(HERE, "_p15_gaps.json"))
MAN   = os.environ.get("P15_MANIFEST", os.path.join(HERE, "_p15_manifest.json"))
OUT   = os.environ.get("P15_OUT", os.path.join(HERE, f"_p15_explain_{TAG}.json"))

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s

# ---------------------------------------------------------------- literals
def literals(nc):
    """`A AND Not(B) AND C` -> [(expr, polarity)], top level only.

    The printer emits each conjunct as `(...)` or `Not((...))`; a conjunct
    never contains a top-level ` AND ` inside its own parentheses, so a
    depth-aware split on ' AND ' is exact."""
    out, depth, cur = [], 0, []
    i, n = 0, len(nc or "")
    while i < n:
        c = nc[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if depth == 0 and nc.startswith(" AND ", i):
            out.append("".join(cur)); cur = []; i += 5; continue
        cur.append(c); i += 1
    if cur:
        out.append("".join(cur))
    res = []
    for t in out:
        t = t.strip()
        if not t:
            continue
        pol = True
        while t.startswith("Not(") and t.endswith(")"):
            t = t[4:-1].strip(); pol = not pol
        res.append((t, pol))
    return res


_FAM = [(r"as_api_response_\d+_row_guid", "guid"),
        (r"^\(SYM_LEN_.*_rows != 0\)$", "length gate (rows)"),
        (r"^\(SYM_LEN_.*_ids != 0\)$", "length gate (ids)"),
        (r"_text_empty == True", "text (empty)"),
        (r"_text_has_mention == True", "text (has_mention)"),
        (r"find_by_\d+_not_found", "find_by not_found"),
        (r"findpublic_.*_not_found", "findpublic not_found"),
        (r"findpublic_.*_public == True", "public gate"),
        (r"_not_found == True", "evilq not_found"),
        (r"CollectionProxy_size_\d+_size", "size gate"),
        (r"Anonymous_process_\d+ == ''", "text (rendered)"),
        (r"assoc_profile_nsfw", "nsfw gate"),
        (r"Length\(SYM_PARAM_id\)", "param id length"),
        (r"_row_status_message_guid !=", "guid self-compare"),
        (r"_row_pending", "pending gate"),
        (r"_row_public", "public row gate")]
def family(e):
    for pat, name in _FAM:
        if re.search(pat, e):
            return name
    return "other"


def sdig(d):
    return hashlib.blake2b(
        json.dumps(d, sort_keys=True, separators=(",", ":")).encode(),
        digest_size=16).hexdigest()


def main():
    t0 = time.time()
    gaps = {g["id"]: g for g in json.load(open(GAPS))}
    man = [m for m in json.load(open(MAN)) if m["seed_set"] == SET]
    print(f"gaps {len(gaps)}   manifest rows (set {SET}) {len(man)}", flush=True)

    # seed digest -> [gap ids]   (a digest can serve more than one gap only if
    # two cubes produced an identical seed dict; both are then credited)
    by_dig = defaultdict(list)
    seeds_by_file = {}
    for m in man:
        f = m["seed_file"]
        if f not in seeds_by_file:
            seeds_by_file[f] = json.load(open(os.path.join(HERE, f)))
        by_dig[sdig(seeds_by_file[f][m["seed_index"]])].append(m["gap"])
    del seeds_by_file
    print(f"distinct seed dicts: {len(by_dig)}", flush=True)

    # cube literals per gap, precomputed
    lits = {gid: literals(g["node_constraint"]) for gid, g in gaps.items()}

    files = sorted(glob.glob(os.path.join(HERE, f"dump_*{TAG}*.json")))
    print(f"dumps labelled *{TAG}*: {len(files)}", flush=True)

    per_gap = {}            # gap -> {"h":n,"c":n,"n":n,"walked":bool,...}
    KEY = Counter()         # (family, verdict)
    VER = Counter()
    unmatched_dumps = 0
    err_dumps = 0
    seen_dig = set()
    for i, p in enumerate(files):
        if i and i % 1000 == 0:
            print(f"  {i}/{len(files)}  {time.time()-t0:.0f}s", flush=True)
        try:
            d = json.load(open(p))
        except Exception:
            err_dumps += 1
            continue
        cs = d.get("concolic_seeds") or {}
        dg = sdig(cs)
        gids = by_dig.get(dg)
        if not gids:
            unmatched_dumps += 1
            del d
            continue
        seen_dig.add(dg)
        ev = d.get("events") or ()
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in ev if e.get("type") == "symbolic_call"], ALIASES)
        rn = renamer(amap)
        taken = defaultdict(set)
        for e in ev:
            if e.get("type") == "path_condition":
                taken[fixlen(rn(str(e.get("expr", ""))))].add(bool(e.get("taken")))
        for gid in gids:
            rec = per_gap.get(gid)
            if rec and rec["walked"]:
                continue          # already walked by an earlier dump of this seed
            h = c = nev = 0
            bad = []
            for expr, pol in lits[gid]:
                t = taken.get(expr)
                if t is None:
                    v = "never_evaluated"; nev += 1
                elif pol in t:
                    v = "honoured"; h += 1
                else:
                    v = "contradicted"; c += 1
                if v != "honoured":
                    bad.append((expr, v))
                KEY[(family(expr), v)] += 1
                VER[v] += 1
            per_gap[gid] = {"h": h, "c": c, "n": nev, "walked": (c == 0 and nev == 0),
                            "first_bad": bad[0][0][:120] if bad else None,
                            "first_bad_v": bad[0][1] if bad else None,
                            "dump": os.path.basename(p)}
        del d

    driven = len(per_gap)
    walked = sum(1 for r in per_gap.values() if r["walked"])
    print()
    print(f"=== P15 ROUND EXPLANATION  tag={TAG} set={SET} "
          f"({time.time()-t0:.0f}s) ===")
    print(f"dumps labelled *{TAG}*        : {len(files)}  "
          f"(unparseable {err_dumps}, seed dict matched no seed {unmatched_dumps})")
    print(f"gaps with at least one dump  : {driven} / {len(gaps)}")
    print(f"gaps NOT driven (no dump)    : {len(gaps)-driven}")
    print(f"gaps WALKED (every literal honoured, measured on the dump): {walked}")
    print()
    tot = sum(VER.values())
    print("PER-KEY VERDICT over every cube literal of every driven gap "
          f"({tot} keys):")
    for v in ("honoured", "contradicted", "never_evaluated"):
        print(f"   {v:16s} {VER[v]:8d}  {100.0*VER[v]/max(tot,1):5.1f} %")
    print()
    print("PER-KEY VERDICT BY DECISION FAMILY:")
    fams = sorted({f for f, _ in KEY}, key=lambda f: -sum(KEY[(f, v)] for v in
                  ("honoured", "contradicted", "never_evaluated")))
    print(f"   {'family':26s} {'honoured':>9s} {'contra':>8s} {'never':>9s} {'%hon':>6s}")
    for f in fams:
        h, c, n = (KEY[(f, "honoured")], KEY[(f, "contradicted")],
                   KEY[(f, "never_evaluated")])
        t = h + c + n
        print(f"   {f:26s} {h:9d} {c:8d} {n:9d} {100.0*h/max(t,1):5.1f}%")
    print()
    print("FIRST FAILING LITERAL, by verdict (why a driven gap did not walk):")
    fb = Counter((r["first_bad_v"], family(r["first_bad"] or ""))
                 for r in per_gap.values() if not r["walked"])
    for (v, f), n in fb.most_common(25):
        print(f"   {v:16s} {f:26s} {n:6d}")
    json.dump({"tag": TAG, "set": SET, "dumps": len(files),
               "unmatched_dumps": unmatched_dumps, "err_dumps": err_dumps,
               "gaps": len(gaps), "driven": driven, "walked": walked,
               "verdicts": dict(VER),
               "by_family": {f"{f}|{v}": n for (f, v), n in KEY.items()},
               "per_gap": per_gap}, open(OUT, "w"))
    print()
    print(f"P15-EXPLAIN-DONE {OUT} ({os.path.getsize(OUT)/1e6:.1f} MB)")


main()
