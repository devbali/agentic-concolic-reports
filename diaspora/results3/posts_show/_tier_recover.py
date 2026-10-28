#!/usr/bin/env python3
"""COORDINATOR RULING 2026-09-11, steps 1-2: recover the deleted tier, classify
it, and size the tier posts_show never had.

Nothing here is declared. This is a PROPOSAL pass (Rule T3): it measures, writes
the candidate pair list, and stops. `coverage_assumptions.py` is untouched.

THREE questions, all answered on the SAME p5 load:

 1. TIER 0 (`_tier0_scenario_exclusivity`, deleted 2026-09-10, recovered from
    reports@f75f9c2) — is it the NEVER-CO-EVALUATED kind (genuinely subsumed by
    §16) or the CO-EVALUATED-but-independent kind? Its own criterion is
    "these two exprs' observed SCENARIO SETS are disjoint", so the structural
    answer is "never co-evaluated"; it is MEASURED here rather than argued,
    against the same co-evaluation relation `build()`'s filter uses.

 2. TIER 2 DISJOINT-REPS — posts_show has NEVER had one. notifications_index
    and conversations_index both do (`_tier2_disjoint_reps`). This ports its
    criterion: two decisions on DIFFERENT symbolic reps, neither gating the
    other. Under W-E every LENGTH x anything pair stays dependent, and the
    dispatch compare stays dependent, exactly as in the source tier.

 3. How many of the tier-2 candidates are CO-EVALUATED (i.e. actually carry a
    demand), how many are already declared by the surviving tiers, and what the
    NET NEW count is — broken down by REP-PAIR CLASS, because that is the unit
    a gate probe and a declaration are written at.
"""
import json, os, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
import _exact_enum_emit as EE                                    # noqa: E402
from concolic_engine.coverage import maximal_sets                # noqa: E402
from concolic_engine.assumptions import IndependenceAssumption   # noqa: E402
import coverage_assumptions as CA                                # noqa: E402

# --------------------------------------------------------------------------
# TIER 0, verbatim from reports@f75f9c2 (only the IndependenceAssumption
# construction is replaced by the bare pair, since nothing is declared here).
# --------------------------------------------------------------------------
_SCEN = ("auth_html", "anon_html", "auth_json", "anon_json")


def _scenario_of(label):
    label = label or ""
    for scen in _SCEN:
        if label.startswith(scen):
            return scen
    return "auth" if label.startswith("auth") else "anon"


def tier0_pairs(runs):
    expr_scenarios = {}
    for r in runs:
        scen = _scenario_of(getattr(r, "label", "") or "")
        for pc in r.path_conditions:
            expr_scenarios.setdefault(pc.expr, set()).add(scen)
    by_set = {}
    for e, s in expr_scenarios.items():
        by_set.setdefault(frozenset(s), []).append(e)
    groups = sorted(by_set.items(), key=lambda kv: sorted(kv[0]))
    out = []
    for i, (sa, ea) in enumerate(groups):
        for sb, eb in groups[i + 1:]:
            if sa & sb:
                continue
            for a in ea:
                for b in eb:
                    out.append(frozenset((a, b)))
    return out, {k: len(v) for k, v in by_set.items()}


# --------------------------------------------------------------------------
# TIER 2 DISJOINT-REPS, ported. The rep key is the LEFT VARIABLE with this
# endpoint's attribute suffixes stripped — the same construction as
# notifications_index `_rep_key`, with posts_show's own suffix vocabulary
# (derived from the corpus's 101/137 distinct left variables, not guessed).
# --------------------------------------------------------------------------
_ATTR_SUFFIXES = ("_status_message_guid", "_text_has_mention", "_text_empty",
                  "_not_found", "_public", "_guid", "_nsfw")
# LENGTH / CARDINALITY class — W-E: a length determines statement SHAPE, so
# length x anything is NEVER declared here. Kept out by the same rule the
# source tier uses, not by omission.
_LEN_RE = re.compile(r"^\(\s*(?:len\(|SYM_LEN_)|_rows\b|_size\b|_ids\b")
_LEFT = re.compile(r"^\(\s*(?:len\()?([A-Za-z_][A-Za-z0-9_]*)")


def leftvar(e):
    m = _LEFT.match(e.strip())
    return m.group(1) if m else None


def is_length(e):
    v = leftvar(e) or ""
    return ("SYM_LEN_" in e or v.startswith("SYM_LEN_")
            or v.endswith("_rows") or v.endswith("_size") or v.endswith("_ids"))


def is_dispatch(e):
    # the post_key dispatch (`Length(SYM_PARAM_id) < 16`) is this endpoint's
    # equivalent of notifications' STI compare: it ROUTES, so it stays
    # dependent on everything, exactly as _DISPATCH_RE is skipped there.
    return e.strip().startswith("(Length(")


def is_selfcompare(e):
    m = re.match(r"^\(([A-Za-z_][A-Za-z0-9_]*) != ([A-Za-z_][A-Za-z0-9_]*)\)$", e.strip())
    return bool(m and m.group(1) == m.group(2))


def rep_key(e):
    v = leftvar(e)
    if not v:
        return None
    for s in _ATTR_SUFFIXES:
        if v.endswith(s):
            return v[: -len(s)]
    return v


_FAMRX = [(re.compile(r"_[0-9a-f]{8}(?![0-9a-f])"), "_<hash>"),
          (re.compile(r"_[0-9]+(?![0-9])"), "_<n>")]


def fam(k):
    for rx, rep in _FAMRX:
        k = rx.sub(rep, k)
    return k


def main():
    t0 = time.time()
    runs = EE.load_runs()
    print(f"loaded in {time.time()-t0:.0f}s", flush=True)

    # the co-evaluation relation, IDENTICAL construction to build()'s filter
    sets = set()
    for r in runs:
        e = frozenset(pc.expr for pc in r.path_conditions)
        if e:
            sets.add(e)
    coeval = set()
    for e in maximal_sets(sets):
        es = sorted(e)
        for i, a in enumerate(es):
            for b in es[i + 1:]:
                coeval.add(frozenset((a, b)))
    print(f"maximal evaluation sets={len(maximal_sets(sets))}  "
          f"CO-EVALUATED pairs={len(coeval)}", flush=True)

    all_exprs = sorted({pc.expr for r in runs for pc in r.path_conditions})
    print(f"distinct exprs={len(all_exprs)}", flush=True)

    # ---- what the SURVIVING tiers already declare --------------------------
    aset = CA.build(runs)
    declared_now = {frozenset((a.expr_a, a.expr_b)) for a in aset.assumptions
                    if isinstance(a, IndependenceAssumption)}
    print(f"surviving tiers declare (post-filter): {len(declared_now)} pairs", flush=True)

    # ---- Q1: TIER 0 --------------------------------------------------------
    t0p, groups = tier0_pairs(runs)
    t0_coeval = [p for p in t0p if p in coeval]
    print("\n=== Q1. TIER 0 (recovered from reports@f75f9c2) ===")
    print(f"  scenario-set groups: " +
          ", ".join(f"{sorted(k)}={v}" for k, v in sorted(groups.items(), key=lambda kv: sorted(kv[0]))))
    print(f"  pairs it would declare            : {len(t0p)}")
    print(f"  of those CO-EVALUATED on p5       : {len(t0_coeval)}")
    print(f"  of those NEVER co-evaluated       : {len(t0p) - len(t0_coeval)}")
    print(f"  => SUBSUMED BY §16: {len(t0_coeval) == 0}")

    # ---- Q2/Q3: TIER 2 disjoint reps --------------------------------------
    cand = [e for e in all_exprs
            if not is_length(e) and not is_dispatch(e) and not is_selfcompare(e)]
    skipped = dict(length=sum(1 for e in all_exprs if is_length(e)),
                   dispatch=sum(1 for e in all_exprs if is_dispatch(e)),
                   selfcmp=sum(1 for e in all_exprs if is_selfcompare(e)))
    reps = {e: rep_key(e) for e in cand}
    nrep = len(set(reps.values()))
    pairs = []
    for i, a in enumerate(cand):
        for b in cand[i + 1:]:
            ka, kb = reps[a], reps[b]
            if not ka or not kb or ka == kb:
                continue
            pairs.append((a, b, ka, kb))
    pset = {frozenset((a, b)) for a, b, _, _ in pairs}
    co = [p for p in pairs if frozenset((p[0], p[1])) in coeval]
    new = [p for p in co if frozenset((p[0], p[1])) not in declared_now]
    print("\n=== Q2/Q3. TIER 2 DISJOINT-REPS (ported; posts_show never had one) ===")
    print(f"  exprs considered                  : {len(cand)} of {len(all_exprs)}")
    print(f"  EXCLUDED by rule                  : length/cardinality={skipped['length']} "
          f"(W-E), dispatch={skipped['dispatch']}, self-compare={skipped['selfcmp']}")
    print(f"  distinct REPS                     : {nrep}")
    print(f"  cross-rep decision pairs          : {len(pairs)}")
    print(f"  of those CO-EVALUATED on p5       : {len(co)}")
    print(f"  of those already declared         : {len(co) - len(new)}")
    print(f"  NET NEW candidate declarations    : {len(new)}")
    cls = Counter(tuple(sorted((fam(ka), fam(kb)))) for _, _, ka, kb in new)
    print(f"  REP-PAIR CLASSES (the gate unit)  : {len(cls)}")
    for (fa, fb), n in cls.most_common(15):
        print(f"     {n:5d}  {fa.split('__')[-1][:48]}  x  {fb.split('__')[-1][:48]}")

    # one REPRESENTATIVE pair per class — what the gate will actually probe
    rep_pair = {}
    for a, b, ka, kb in new:
        k = tuple(sorted((fam(ka), fam(kb))))
        rep_pair.setdefault(k, (a, b))
    json.dump({"net_new": [[a, b, ka, kb] for a, b, ka, kb in new],
               "classes": [[list(k), v] for k, v in cls.most_common()],
               "class_representative": {" || ".join(k): list(v)
                                        for k, v in rep_pair.items()},
               "tier0": {"pairs": len(t0p), "coevaluated": len(t0_coeval),
                         "subsumed": len(t0_coeval) == 0},
               "skipped": skipped, "reps": nrep,
               "declared_now": len(declared_now)},
              open(os.path.join(HERE, "_tier_recover.json"), "w"), indent=1)
    print(f"\nwrote _tier_recover.json  ({time.time()-t0:.0f}s)")


if __name__ == "__main__":
    main()
