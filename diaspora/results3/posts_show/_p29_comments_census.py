#!/usr/bin/env python3
"""P29 step 1 — the D1 comments family, measured over the WHOLE pruned corpus.

Answers, per the brief:
  (a) LEGEND: what statement each `*_comments_<hash>` canonical denotes —
      the raw note, the alias statement key, the call site, the target.
  (b) JOINT OUTCOME TABLE: for every ordered pair of comments-length
      canonicals, over all profiles, TT/TF/FT/FF counts of their length
      decisions (and how often each is evaluated at all).
  (c) The VALUE table: what len() value each canonical is ever seen at.

Reads only; writes one JSON + a text report. Nothing under src/.
"""
import json, os, re, sys, collections, pickle
from concurrent.futures import ProcessPoolExecutor

sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import (AliasAssumption, alias_map_for,
                                         alias_keys_for, renamer, _alias_core)

B = "/home/dev/project/reports/diaspora/results3/posts_show"
ALIAS_PATTERN = (r"SYM_RESULT_ActiveRecord__(?:Associations__CollectionProxy_records"
                 r"|Relation_records|Relation_to_ary)_\d+")
ALIASES = [AliasAssumption(result_pattern=ALIAS_PATTERN, key="statement",
                           description="x", agent_notes="x")]

LEN_RE = re.compile(r"len\((SYM_RESULT_[A-Za-z0-9_]*_comments_[0-9a-f]{8})_rows\)")
ANY_COMMENTS = re.compile(r"(SYM_RESULT_[A-Za-z0-9_]*_comments_[0-9a-f]{8})")


def one(path):
    try:
        d = json.load(open(path))
    except Exception:
        return None
    ev = d.get("events", [])
    pairs = [(e.get("result_name"), e.get("note")) for e in ev
             if e.get("type") == "symbolic_call"]
    amap, keys = _alias_core(pairs, ALIASES)
    ren = renamer(amap)
    # legend rows: canonical -> (raw note, key, target, file:line, function, ordinal)
    legend = {}
    for e in ev:
        if e.get("type") != "symbolic_call":
            continue
        rn = e.get("result_name")
        if rn not in amap:
            continue
        canon = amap[rn]
        if "_comments_" not in canon:
            continue
        legend.setdefault(canon, set()).add((
            str(e.get("note")), keys.get(rn, ""), str(e.get("target")),
            "%s:%s" % (os.path.basename(str(e.get("file"))), e.get("lineno")),
            str(e.get("function")), rn))
    # decisions on comments length
    dec = {}          # canonical -> set of (expr, taken)
    exprs = collections.Counter()
    for e in ev:
        if e.get("type") != "path_condition":
            continue
        ex = ren(e.get("expr") or "")
        if "_comments_" not in ex:
            continue
        m = LEN_RE.search(ex)
        if m:
            dec.setdefault(m.group(1), set()).add((ex, bool(e.get("taken"))))
            exprs[ex] += 1
        else:
            exprs["OTHER:" + ex] += 1
    # seed values actually offered / observed length
    seeds = d.get("concolic_seeds") or {}
    seedvals = {}
    for k, v in (seeds.items() if isinstance(seeds, dict) else []):
        kk = ren(k)
        if "_comments_" in kk:
            seedvals[kk] = v
    return (path, {c: sorted(v) for c, v in legend.items()},
            {c: sorted(v) for c, v in dec.items()}, dict(exprs), seedvals)


def main():
    lst = sys.argv[1] if len(sys.argv) > 1 else B + "/_snapshot_pruned_P26F2.txt"
    paths = [l.strip() for l in open(lst) if l.strip()]
    print("dumps:", len(paths), flush=True)
    LEG = collections.defaultdict(collections.Counter)
    EXPRS = collections.Counter()
    # per-canonical: evaluated-count, true-count, false-count, both-ways runs
    EVAL = collections.Counter(); TRUE = collections.Counter(); FALSE = collections.Counter()
    BOTHWAYS = collections.Counter()
    JOINT = collections.defaultdict(collections.Counter)   # (a,b) -> (ta,tb) counter
    COEVAL = collections.Counter()
    SEEDVALS = collections.defaultdict(collections.Counter)
    nbad = 0
    with ProcessPoolExecutor(max_workers=int(os.environ.get("W", "6"))) as ex:
        for i, r in enumerate(ex.map(one, paths, chunksize=200)):
            if r is None:
                nbad += 1; continue
            path, legend, dec, exprs, seedvals = r
            for c, rows in legend.items():
                for row in rows:
                    LEG[c][row] += 1
            EXPRS.update(exprs)
            for c, v in seedvals.items():
                SEEDVALS[c][json.dumps(v)] += 1
            # per-run outcome per canonical: set of takens
            out = {}
            for c, pairs in dec.items():
                tk = set(t for _, t in pairs)
                EVAL[c] += 1
                if True in tk: TRUE[c] += 1
                if False in tk: FALSE[c] += 1
                if len(tk) == 2: BOTHWAYS[c] += 1
                out[c] = tk
            cs = sorted(out)
            for i1 in range(len(cs)):
                for i2 in range(i1 + 1, len(cs)):
                    a, b = cs[i1], cs[i2]
                    COEVAL[(a, b)] += 1
                    for ta in out[a]:
                        for tb in out[b]:
                            JOINT[(a, b)][(ta, tb)] += 1
            if (i + 1) % 5000 == 0:
                print("  ..", i + 1, flush=True)
    res = dict(
        n_dumps=len(paths), n_unparseable=nbad,
        legend={c: [[list(k), n] for k, n in cnt.most_common()] for c, cnt in LEG.items()},
        exprs=EXPRS.most_common(60),
        eval=dict(EVAL), true=dict(TRUE), false=dict(FALSE), bothways=dict(BOTHWAYS),
        coeval={f"{a}||{b}": n for (a, b), n in COEVAL.items()},
        joint={f"{a}||{b}": {f"{ta},{tb}": n for (ta, tb), n in c.items()}
               for (a, b), c in JOINT.items()},
        seedvals={c: cnt.most_common(20) for c, cnt in SEEDVALS.items()},
    )
    out = B + "/_p29_comments_census.json"
    json.dump(res, open(out, "w"), indent=1)
    print("wrote", out)
    print("P29-CENSUS-DONE")


if __name__ == "__main__":
    main()
