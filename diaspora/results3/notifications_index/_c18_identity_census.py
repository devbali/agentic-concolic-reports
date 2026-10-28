#!/usr/bin/env python3
"""C18 — corpus census for the RE-MINT-IDENTITY and PRINCIPAL-IDENTITY
declarations (campaign §31).

For every run of the corpus, after `coverage_report.canonicalize_ordinals`
(the SAME rewriting the coverage pass applies, so the names counted here are
the CHECKER's spellings):

  (a) every `preloaded association #<assoc>` re-minted length variable
      `len(<ownerbase>_<assoc>_row_rows)` is paired with the upstream
      `len(SYM_RESULT_..._CollectionProxy_records_<table>_<hash>_rows)`
      whose statement note BINDS that same owner, and the two VALUES are
      compared.  eq / ne are counted per canonical PAIR.
  (b) `SYM_RESULT_..._find_by_1_person_id` vs
      `SYM_RESULT_..._devise_user_first_1_person_id` — both present, eq / ne.
  (c) co-occurrence of the two photos STATEMENT VARIANTS that share a
      re-mint (the real read and the empty-scope `AND (1=0)` read), so a
      pair of declarations over the same re-mint cannot silently equate two
      names the corpus never records together.

Falsifier for (a): any run recording a re-mint and its upstream with
DIFFERENT values.  Falsifier for (b): any run recording the two person ids
with different values.  This script IS that falsifier, run over the whole
corpus.

  usage: [DUMP_LIST=..] [WORKERS=4] python3 -u _c18_identity_census.py [out.json]
"""
import json, os, re, sys
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src"); sys.path.insert(0, HERE)
import coverage_report as CR                      # noqa: E402
import coverage_assumptions as CA                 # noqa: E402

LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_c16_R2.txt"))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_c18_identity_census.json")
W = int(os.environ.get("WORKERS", "4"))

REMINT = re.compile(r"^preloaded association #([a-z_]+):")
BIND = re.compile(r"\$\$\(([A-Za-z0-9_]+)\)")
CP = "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_"
# association name -> the TABLE the upstream statement reads (they differ for
# `followed_tags`, which is a has_many :through onto `tags`).
TABLE = {"followed_tags": "tags"}
PID_A = "SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_id"
PID_B = "SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id"


def one(fp):
    eq = Counter(); ne = Counter(); noup = Counter(); multi = Counter()
    remint = Counter(); upseen = Counter(); cooc = Counter()
    pid = Counter()
    try:
        d = json.load(open(fp))
    except Exception:
        return ("BAD", eq, ne, noup, multi, remint, upseen, cooc, pid)
    try:
        CR.canonicalize_ordinals(d, CA.ALIASES)
    except Exception:
        return ("CANONFAIL", eq, ne, noup, multi, remint, upseen, cooc, pid)
    svs = {sv.get("name"): sv for sv in (d.get("symbolic_vars") or ()) if sv.get("name")}
    if PID_A in svs and PID_B in svs:
        pid["eq" if svs[PID_A].get("value") == svs[PID_B].get("value") else "NE"] += 1
    elif PID_A in svs or PID_B in svs:
        pid["one-only"] += 1
    cps = [(n, sv) for n, sv in svs.items() if n.startswith(CP)]
    for n, sv in cps:
        upseen[n[4:-1]] += 1
    per_remint_ups = defaultdict(list)
    for n, sv in svs.items():
        m = REMINT.match(sv.get("note") or "")
        if not (m and n.startswith("len(")):
            continue
        assoc = m.group(1); base = n[4:-1]
        tail = f"_{assoc}_row_rows"
        if not base.endswith(tail):
            noup[base + " <BAD-TAIL>"] += 1; continue
        owner = base[:-len(tail)]
        tbl = TABLE.get(assoc, assoc)
        remint[base] += 1
        cands = [(n2, sv2) for n2, sv2 in cps
                 if n2.startswith(CP + tbl + "_")
                 and any(b.startswith(owner) for b in BIND.findall(sv2.get("note") or ""))]
        if not cands:
            noup[base] += 1; continue
        if len(cands) > 1:
            multi[(base, tuple(sorted(x[0][4:-1] for x in cands)))] += 1
        for n2, sv2 in cands:
            per_remint_ups[base].append(n2[4:-1])
            k = (base, n2[4:-1])
            (eq if sv.get("value") == sv2.get("value") else ne)[k] += 1
    for base, ups in per_remint_ups.items():
        if len(set(ups)) > 1:
            cooc[(base, tuple(sorted(set(ups))))] += 1
    return ("OK", eq, ne, noup, multi, remint, upseen, cooc, pid)


def main():
    files = [l.strip() for l in open(LIST) if l.strip()]
    tot = Counter(); EQ = Counter(); NE = Counter(); NOUP = Counter()
    MULTI = Counter(); RM = Counter(); UP = Counter(); COOC = Counter(); PID = Counter()
    with ProcessPoolExecutor(max_workers=W) as ex:
        for i, r in enumerate(ex.map(one, files, chunksize=200)):
            tot[r[0]] += 1
            EQ.update(r[1]); NE.update(r[2]); NOUP.update(r[3]); MULTI.update(r[4])
            RM.update(r[5]); UP.update(r[6]); COOC.update(r[7]); PID.update(r[8])
            if (i + 1) % 20000 == 0:
                print(f"[census] {i+1}/{len(files)}", flush=True)
    print(f"\ncorpus: {len(files)} dumps   {dict(tot)}")
    print(f"\nPRINCIPAL IDENTITY  {PID_A}\n                 == {PID_B}")
    for k, v in PID.most_common():
        print(f"   {v:8d}  {k}")
    print("\n=== RE-MINT / UPSTREAM PAIRS ===")
    rows = []
    for k in sorted(set(EQ) | set(NE)):
        e, n = EQ[k], NE[k]
        rows.append({"remint": k[0], "upstream": k[1], "eq": e, "ne": n})
        print(f"  eq={e:7d}  ne={n:7d}   {k[0]}\n                       || {k[1]}")
    print(f"\nTOTAL pair observations: eq={sum(EQ.values())}  ne={sum(NE.values())}  "
          f"pairs={len(rows)}")
    print("\nre-mint minted with NO upstream in the run:")
    for k, v in NOUP.most_common():
        print(f"   {v:8d}  {k}")
    print("\nre-mints with >1 upstream candidate IN THE SAME RUN:")
    for k, v in MULTI.most_common(20):
        print(f"   {v:8d}  {k}")
    print("\nruns where ONE re-mint pairs with TWO DIFFERENT upstream names:")
    for k, v in COOC.most_common(20):
        print(f"   {v:8d}  {k}")
    json.dump({"list": LIST, "dumps": len(files), "status": dict(tot),
               "pid": dict(PID), "pairs": rows,
               "no_upstream": {k: v for k, v in NOUP.items()},
               "multi_upstream": {f"{k[0]}||{','.join(k[1])}": v for k, v in MULTI.items()},
               "cooccurring_upstreams": {f"{k[0]}||{','.join(k[1])}": v
                                         for k, v in COOC.items()},
               "remint_mintings": dict(RM), "upstream_mintings": dict(UP)},
              open(OUT, "w"), indent=1)
    print(f"\nC18-IDENTITY-CENSUS-DONE {OUT}")


if __name__ == "__main__":
    main()
