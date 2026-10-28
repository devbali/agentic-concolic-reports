#!/usr/bin/env python3
"""C29 step 2 — the DISPATCH characterisation, from `_c29_scan.pkl`.

Answers, for the ON cube (width 12) and the OFF cube (width 15), both over the
`3aa8587a` to_ary variant:

  * how many runs of the corpus take `(SYM_NOTE_TYPE_PROFILE == k)` at all,
    per k, and what they evaluate;
  * per member `d`: evaluated-anywhere, A/B under the rest of the cube, and the
    MINIMUM-cardinality conditioning set C with A(C) > 0 and B(C, d) = 0 --
    exactly `_c25_mincond.py`'s reading (a run matches (e, o) iff it recorded e
    with o at least once), so A and B can only be OVERSTATED;
  * the pairwise co-realisation table against the dispatch literal.

Read-only, no corpus re-read.
"""
import itertools, json, os, pickle, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
S = pickle.load(open(os.environ.get("SCAN", os.path.join(HERE, "_c29_scan.pkl")), "rb"))
N, T, F, META, FILES = S["n"], S["T"], S["F"], S["meta"], S["files"]
ALL = (1 << N) - 1
P = "SYM_NOTE_TYPE_PROFILE"
V = "SYM_RESULT_ActiveRecord__Relation_to_ary_notifications_3aa8587a"
DV = "SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1"
PH = "SYM_LEN_SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_photos_aa895602_rows"

ON = [(f"({P} == 2)", True)] + [(f"({P} == {k})", False) for k in (3, 4, 5, 6, 7)] + [
    (f"({DV}_person_not_found == True)", False),
    (f"({V}_row_target_not_found == True)", False),
    (f"(SYM_LEN_{V}_row_actors_row_rows > 1)", True),
    (f"({V}_row_target_author_profile_not_found == True)", False),
    (f"({DV}_person_profile_not_found == True)", True),
    (f"({PH} > 1)", False)]

OFF = [(f"({P} == {k})", False) for k in (0, 1, 2)] + [(f"({P} == 3)", True)] + \
      [(f"({P} == {k})", False) for k in (4, 5, 6, 7)] + [
    (f"({DV}_person_not_found == True)", False),
    (f"(SYM_LEN_{V}_rows > 1)", True),
    (f"({V}_row_target_not_found == True)", False),
    (f"(SYM_LEN_{V}_row_actors_row_rows > 1)", True),
    (f"({V}_row_target_author_profile_not_found == True)", False),
    (f"({DV}_person_profile_not_found == True)", False),
    (f"({PH} > 1)", True)]

tb = lambda e: T.get(e, 0)
fb = lambda e: F.get(e, 0)
eb = lambda e: tb(e) | fb(e)
mask = lambda lit: tb(lit[0]) if lit[1] else fb(lit[0])
pc = lambda x: x.bit_count()


def bits(m):
    """indices of the set bits of m, without an O(N^2) shift loop"""
    out = []
    b = m.to_bytes((N + 7) // 8, "little")
    for bi, byte in enumerate(b):
        if not byte:
            continue
        for k in range(8):
            if byte & (1 << k):
                out.append(bi * 8 + k)
    return out


def minimal(cands, d, cap=4):
    jd = eb(d)
    if not jd:
        return ("NEVER-EVALUATED", [], 0)
    for r in range(0, min(cap, len(cands)) + 1):
        for sub in itertools.combinations(cands, r):
            m = ALL
            for lit in sub:
                m &= mask(lit)
                if not m:
                    break
            if not m:
                continue
            a = pc(m)
            if a and not (m & jd):
                return ("FOUND", list(sub), a)
    return ("NONE", [], 0)


def report(name, cube):
    print(f"\n{'='*78}\n=== {name}  (width {len(cube)})\n{'='*78}")
    m_all = ALL
    for lit in cube:
        m_all &= mask(lit)
    print(f"runs matching the WHOLE cube (per-literal reading): {pc(m_all)}")
    rows = []
    for pos, (e, o) in enumerate(cube):
        others = [x for x in cube if x[0] != e]
        m = ALL
        for lit in others:
            m &= mask(lit)
        A, B = pc(m), pc(m & eb(e))
        R = pc(m & mask((e, o)))
        st, C, Ac = minimal(others, e)
        rows.append((pos, e, o, pc(eb(e)), pc(tb(e)), pc(fb(e)), A, B, R, st, C, Ac))
        print(f"\n pos{pos:2d} want={'T' if o else 'F'}  {e}")
        print(f"      corpus: eval={pc(eb(e)):7d}  T={pc(tb(e)):7d}  F={pc(fb(e)):7d}")
        print(f"      under the OTHER {len(others)} literals:  A={A:7d}  "
              f"B(evaluated)={B:7d}  realised={R:7d}")
        if st == "FOUND":
            print(f"      MIN C (|C|={len(C)}, A={Ac}, B=0):")
            for x, y in C:
                print(f"          {'T' if y else 'F'}  {x}")
        else:
            print(f"      MIN C: {st}")
    return rows


def profile_census():
    print(f"\n{'='*78}\n=== DISPATCH CENSUS — every (P == k) literal over {N} runs\n{'='*78}")
    print(f"{'k':>3} {'evaluated':>10} {'TAKEN':>8} {'not_taken':>10}")
    taken = {}
    for k in range(8):
        e = f"({P} == {k})"
        taken[k] = tb(e)
        print(f"{k:>3} {pc(eb(e)):>10} {pc(tb(e)):>8} {pc(fb(e)):>10}")
    oor = ALL
    for k in range(8):
        oor &= fb(f"({P} == {k})")
    ev = 0
    for k in range(8):
        ev |= eb(f"({P} == {k})")
    print(f"\nruns evaluating the dispatch at all : {pc(ev)}")
    print(f"runs OUT OF RANGE (all eight not_taken): {pc(oor)}")
    print(f"runs never evaluating it              : {N - pc(ev)}")
    # what a P==k run evaluates, per interesting member
    mem = [f"{V}_row_target_not_found", f"SYM_LEN_{V}_row_actors_row_rows",
           f"{V}_row_target_author_profile_not_found", PH,
           f"SYM_LEN_{V}_rows", f"{DV}_person_profile_not_found",
           f"{DV}_person_not_found", f"{V}_row_target_is_photo"]
    print(f"\n--- what runs with (P == k) TAKEN evaluate ({V[-8:]} chain) ---")
    hdr = "  ".join(f"{x.split('_')[-1][:9]:>9}" for x in mem)
    print(f"{'k':>3} {'runs':>7}  " + hdr)
    for k in range(8):
        m = taken[k]
        cells = []
        for x in mem:
            cand = [e for e in set(T) | set(F) if e.startswith("(" + x) or
                    e.startswith("(" + x + " ")]
            u = 0
            for e in cand:
                u |= eb(e)
            cells.append(f"{pc(m & u):>9}")
        print(f"{k:>3} {pc(m):>7}  " + "  ".join(cells))
    print(f"\n{'k':>3} {'runs':>7}  " + hdr + "   <- OUT OF RANGE row")
    cells = []
    for x in mem:
        cand = [e for e in set(T) | set(F) if e.startswith("(" + x)]
        u = 0
        for e in cand:
            u |= eb(e)
        cells.append(f"{pc(oor & u):>9}")
    print(f"{'oor':>3} {pc(oor):>7}  " + "  ".join(cells))


def drivers(litset, label):
    """which drive tags / scenarios produced the runs matching a literal set"""
    m = ALL
    for lit in litset:
        m &= mask(lit)
    tags = collections.Counter(); scen = collections.Counter()
    for i in bits(m):
        tags[META[i][0]] += 1; scen[META[i][1]] += 1
    print(f"\n--- {label}: {pc(m)} runs; top tags {tags.most_common(8)}")
    print(f"    scenarios {scen.most_common()}")
    return m


if __name__ == "__main__":
    print(f"corpus {N} runs from {os.path.basename(S['list'])}; "
          f"{len(set(T) | set(F))} filtered exprs")
    profile_census()
    on = report("ON  blocking cube (conf ON, ON3 missing[0])", ON)
    off = report("OFF blocking cube (conf OFF, OFF6 missing[0])", OFF)
    for k in (2, 3):
        drivers([(f"({P} == {k})", True)], f"(P == {k}) TAKEN")
        drivers([(f"({P} == {k})", True),
                 (f"(SYM_LEN_{V}_row_actors_row_rows > 1)", True)],
                f"(P == {k}) TAKEN and actors_row_rows>1 recorded True")
        drivers([(f"({P} == {k})", True), (f"({PH} > 1)", False)],
                f"(P == {k}) TAKEN and photos>1 recorded False")
        drivers([(f"({P} == {k})", True), (f"({PH} > 1)", True)],
                f"(P == {k}) TAKEN and photos>1 recorded True")
    json.dump({"on": [[r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9],
                       [[x, y] for x, y in r[10]], r[11]] for r in on],
               "off": [[r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9],
                        [[x, y] for x, y in r[10]], r[11]] for r in off]},
              open(os.path.join(HERE, "_c29_dispatch.json"), "w"), indent=1)
    print("\nC29-DISPATCH-DONE")
