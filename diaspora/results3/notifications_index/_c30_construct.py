#!/usr/bin/env python3
"""C30 — `_c28_construct.py` with TWO changes, each of them a defect an
earlier round PAID FOR and that `_c28_construct.py` still carries.

  (A) §40.6 / C17 — THE `fix_seeds` CLOBBER. `_c17_seedkey_fix.fix_seeds`
      moves a base's own RE-MINT length demand onto the upstream key the
      runtime actually reads — which may be a key this build has just
      WRITTEN, silently overwriting the demand with the base's value. C29's
      first OFF build realised 14 of 15 literals and failed only on the one
      it had written a seed of 4 for: evaluated 44/44, realised 0/44. The fix
      is to RE-APPLY this build's own writes AFTER `fix_seeds`, so the demand
      wins. `_c28_construct.py` ends with `s, moved = fix_seeds(s, d)` and is
      exposed to this on every set whose demand names a materialize length.

  (B) §40.5a — A STATEMENT-KEYED ALIAS IS ITSELF A CONDITION. When a member's
      canonical name came from an `AliasAssumption(key="statement")` and that
      family resolves to several statements, WHICH sibling a run issues is
      decided by some OTHER decision. A build that writes the member without
      that decision builds a run in which the member's variable is never
      MINTED AT ALL — the seed "takes", the demand is unrealised, and the leaf
      reads as unreachable. Four of this endpoint's eight alias families are
      exposed (photos 6, to_ary notifications 4, Relation_records mentions 3,
      aspect_memberships 2). `ENABLING_GATES` takes the DISCRIMINATING
      decisions computed by `_c30_analyze.py`'s matched-context differential
      and writes them alongside the cube. They are written like any other
      non-hard member (ladder value, all backing seed keys, gate seeds), and
      they are re-applied after `fix_seeds` with the rest.

Both are STATED in the manifest per seed (`enabling_gates`, `reapplied`) so a
round that realises nothing can tell which of the two it was.

Everything below this note is `_c28_construct.py` verbatim.

C28 — `_c24_construct.py` with ONE change: the corpus index is matched
PER SET, by that set's own member list, instead of by whole-gap-list equality.

WHY. `INDEX_IN` keyed the whole file on `[m["members"] for m in meta]` and
raised if the gap list moved at all — so every round after a closure paid the
full corpus scan again (24 m 22 s over 135 208 dumps on 2 cores, C28 plan1).
But `work()` computes each set's observation tuple from that set's OWN member
list and nothing else, so a set whose member list is byte-identical has a
byte-identical row set whatever the other sets did. Matching per set is
therefore the SAME index, read at the granularity it was actually computed at.

The refusal is kept where it belongs: a set whose member list is NOT in the
index is not guessed at and not silently dropped — it is SCANNED, over the
corpus given on the command line, and the scan is restricted to exactly those
sets (`work()` runs with SETS = the unmatched ones, and the rows are mapped
back by index). `INDEX_MERGE` still folds a small extra file list into the
REPLAYED sets, which is what keeps a replayed set current with this round's
own driven dumps. `INDEX_OUT` writes the index back under the NEW key.

Everything else — the hard-member rules, the ladder, UNSEED, GATE_SEEDS,
`fix_seeds`, the TODO cap, the base scoring — is `_c24_construct.py`
unchanged. Verified against it: on the C27 OFF2 gap list, with INDEX_IN
replaying all 17 sets, the per-set census line (rows / eligible-bases /
SAT-space / covered / todo) is identical to `_c28_plan1.log`'s.

C22 round 1 — construct every remaining leaf of the 7 BLOCKING gap-sets of
`_cov_C21_C21R1.json`.

Ported from `_c20_round4.py` (the build that closed C20's last three sets) with
four additions, each of them a rule an earlier round paid for:

  * §33.7a rule 2 (round 4) is KEPT: a member whose NAME depends on the call
    prefix may not be overlaid — the base must already record it.
  * NEW, and the generalisation of §33.6: **a member the overlay CANNOT WRITE
    is hard too.** `_c20_round4.py` silently skipped every literal that is not
    `(<var> == True|False)` or `(<var> > <int>)` — the var-var identity compare
    and the `__prior` self-compare among them — and then let base scoring
    decide whether it happened to hold. Here they are promoted into `hard`, so
    the base is REQUIRED to carry them and the seeds are only ever written for
    literals the seeder can actually express.
  * §30/C17: `fix_seeds` — a demand on a re-minted `_<assoc>_row_rows` length
    is ALSO written at the upstream key the runtime actually reads. Two of the
    seven sets demand `..._row_actors_row_rows`, which is exactly that shape.
  * UNSEED: `Not((X == X__prior))` is realised by X being UNSEEDED (§33.6, 860
    runs, all unseeded), so X's seed keys are POPPED from the base seeds; and
    negatives are written before positives so a positive demand wins a key
    collision.

usage: python3 _c22_round1.py <cov.json> <candidate_list> [K]
"""
import json, os, re, sys, itertools, collections
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, "/home/dev/project/src")
sys.path.insert(0, HERE)
from concolic_engine.assumptions import alias_map_for, renamer   # noqa: E402
from coverage_assumptions import ALIASES                          # noqa: E402
from _c20_scan2 import parse                                      # noqa: E402
from _c17_seedkey_fix import fix_seeds                            # noqa: E402
from concolic_engine.coverage import _combo_constraint            # noqa: E402
from concolic_engine.solver import check_satisfiability           # noqa: E402

VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")
PREF = os.environ.get("C22_PREF", "_c22_r1_seeds_")
MANIFEST = os.environ.get("C22_MANIFEST", "_c22_r1_manifest.json")

# §40.5a: {"<set index>": [{"expr": "(X == True)", "want": true}, ...]}
# — the decisions that DISCRIMINATE a statement-keyed member's statement from
# its siblings, as ranked by `_c30_analyze.py`. Absent file = no gates, which
# is the old behaviour exactly.
_EG_PATH = os.environ.get("ENABLING_GATES")
ENABLING_GATES = {}
if _EG_PATH:
    with open(_EG_PATH) as _fh:
        ENABLING_GATES = {int(k): v for k, v in json.load(_fh).items()}
    print(f"[enabling-gates] {_EG_PATH}: "
          + ", ".join(f"set{k}:{len(v)}" for k, v in sorted(ENABLING_GATES.items())),
          flush=True)
_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
_CANON_RE = re.compile(r"SYM_RESULT_[A-Za-z0-9_]*?_(?:notifications|aspect_memberships|"
                       r"photos|tags|aspects|services|mentions)_[0-9a-f]{8}")
_EQT = re.compile(r"^\((\w+) == (True|False)\)$")
_EQI = re.compile(r"^\((\w+) == (-?\d+)\)$")
_GTI = re.compile(r"^\((\w+) > (-?\d+)\)$")
_PRIOR = re.compile(r"^\((\w+) == (\w+)__prior\)$")
#: THE LOADER'S SELF-COMPARE SPLIT, mirrored. `coverage_report.split_self_compare`
#: rewrites a recorded `(V == V)` to `(V == V__prior)`, and it runs INSIDE
#: `canonicalize_ordinals` — i.e. AFTER alias renaming and only when the dump
#: HAS an alias map (the function returns early otherwise) — and BEFORE
#: `fix_len_names`. A tool that joins checker-side names to dump-side ones must
#: do the same or the join fails SILENTLY as "never evaluated": measured here,
#: `(find_by_1_person_id == find_by_1_person_id__prior)` was recorded in
#: 0 of 39 529 candidate dumps before this was applied and in 4 107 after — the
#: same class of defect the RUNBOOK's Phase 2 records three times for `len`
#: spelling, one transform along. `_c20_round4.py` has it too, which is why C20
#: needed the bespoke `_c20_ident_bases.py` for that one set.
_SELFCMP = re.compile(r"\((SYM_[A-Za-z0-9_]+) == \1\)")
SETS = None

#: value ladders, in preference order. Lengths take the domain the endpoint's
#: own mocks produce (DISCIPLINE/§18: empty / one / the `< 4` arm), widened by
#: the two values a `> 1` demand needs; the dispatch integer takes its declared
#: 0-7. A value is only ever CHOSEN from a ladder, never invented, so a demand
#: the ladder cannot meet is reported (`no-ladder-value`) and not faked.
LADDER_LEN = [0, 1, 2, 4, 3, 5, 6, 7]
LADDER_INT = [0, 1, 2, 3, 4, 5, 6, 7, 8]
LADDER_BOOL = [True, False]


def lit_of(e):
    """(var, kind, rhs) for a member the overlay can WRITE, else None."""
    m = _EQT.match(e)
    if m:
        return m.group(1), "eqb", m.group(2) == "True"
    m = _EQI.match(e)
    if m:
        return m.group(1), "eqi", int(m.group(2))
    m = _GTI.match(e)
    if m:
        return m.group(1), "gt", int(m.group(2))
    return None


def holds(val, kind, rhs, want):
    if kind == "eqb":
        got = (val is rhs) or (bool(val) == bool(rhs))
    elif kind == "eqi":
        got = (val == rhs)
    else:
        got = (val > rhs)
    return bool(got) == bool(want)


def ladder_value(var, lits):
    """One value satisfying EVERY demanded literal over `var`, taken from the
    ladder — the joint solve the per-literal writer of `_c20_round4.py` could
    not do (six mutually exclusive `== k` literals over one variable)."""
    kinds = {k for k, _r, _w in lits}
    cands = (LADDER_BOOL if "eqb" in kinds
             else LADDER_LEN if var.startswith("SYM_LEN_") else LADDER_INT)
    for c in cands:
        if all(holds(c, k, r, w) for k, r, w in lits):
            return c
    return None


def split_lits(nc):
    out = []
    for part in nc.split(" AND "):
        p, w = part.strip(), True
        if p.startswith("Not(") and p.endswith(")"):
            w, p = False, p[4:-1]
        out.append((p, w))
    return out


def writable(e):
    return lit_of(e) is not None


def prefix_coupled(e):
    return ("_exists__" in e
            or (e.endswith("_rows > 1)") and "row_actors" not in e
                and "mentions" not in e and "aspect_member" not in e))


def per_row(e):
    """A decision made PER NOTIFICATION ROW (or on a per-row association).

    C22 round 1 measured why this matters: over its 336 driven runs the
    per-row members of the two width-12 sets were evaluated in as few as
    4/336 (`..._photos_aa895602_rows`) and 15-22/336
    (`..._row_target_text_dlink_is_post`), even though every base had been
    selected to RECORD them. Overlaying the row-level values changes which
    partial the row renders, and the per-row decision downstream of it then
    never happens — the same coupling §33.7a's rule 2 found for the call
    prefix, one level in. So in round 2 they are carried by the base, not
    written."""
    # C24 (2026-09-14): ONE MEASURED EXCEPTION, and it is not a relaxation.
    # `<base>_text_dlink_is_post` (targets.rb:1691) is minted ONLY inside
    # `if has_dlink == true`, whose own decision `<base>_text_has_dlink`
    # (targets.rb:1687-1688) defaults to FALSE. C22 round 1 wrote the
    # is_post literal and never the gate, so the variable was simply never
    # MINTED in 314-321 of its 336 runs — that, not per-row coupling, is why
    # `_row_target_text_dlink_is_post` realised in 15-22/336. With the gate
    # written too (GATE_SEEDS below) the member is writable, and it has to be:
    # measured on the C22R2 census, the class every one of the 16 remaining
    # leaves of sets 2-5 needs — (exists=T, notif_rows>1, row_actors>1,
    # dlink_is_post=F) — has ZERO bases in the whole 132 946-run corpus under
    # either the strict or the loose eligibility filter, so there is nothing
    # to overlay onto and the member must be written or the sets cannot move.
    if os.environ.get("WRITE_DLINK") and "dlink_is_post" in e:
        return False
    # WRITE_MEMBERS: the same exception, stated as data. A comma-separated list
    # of substrings; a per-row member matching one is WRITTEN rather than
    # carried by the base. Used for the two `_not_found` decisions of sets 0/1
    # (targets.rb:679-680 `nfn = "#{abase}_not_found"`, seeded, default false),
    # which NO run of the 132 946-run corpus has ever taken True — so there is
    # no base to carry them and the only alternatives are to write them or to
    # declare the leaves unconstructible.
    wm = [x for x in os.environ.get("WRITE_MEMBERS", "").split(",") if x]
    if wm and any(x in e for x in wm):
        return False
    return "_row_" in e or "_photos_" in e


#: GATE SEEDS — a decision that is minted only under another seeded decision.
#: Writing the child without the parent writes a variable the run never mints.
#: key = substring of the seed key, value = (replacement, value to write).
GATE_SEEDS = [("_text_dlink_is_post", "_text_has_dlink", True),
              ("_disp_dlink_is_post", "_disp_has_dlink", True)]


def gate_keys(sk):
    """Extra seed keys that must be written so `sk`'s variable is MINTED."""
    return [(sk.replace(a, b), v) for a, b, v in GATE_SEEDS if a in sk]


_DECL = {bool: "Bool", int: "Int", str: "String"}


def declarations(members, cv):
    """Z3 declarations for every variable a set's literals name, typed from the
    checker's OWN counterexample model (`concrete_values`) — not guessed."""
    out, seen = [], set()
    for e in members:
        for v in re.findall(r"SYM_[A-Za-z0-9_]*", e):
            if v in seen:
                continue
            seen.add(v)
            val = cv.get(v)
            k = _DECL.get(type(val))
            if k is None:
                k = "Int" if v.startswith("SYM_LEN_") else "Bool"
            out.append(f"{v} = {k}('{v}')")
    return out


def _init(sets):
    global SETS
    SETS = sets


def work(path):
    try:
        evs, pcs, seeds, _v = parse(path)
    except Exception:
        return None
    amap = alias_map_for(evs, ALIASES)
    mint = set(amap.values())
    rn = renamer(amap)
    seen = {}
    for expr, taken, _s in pcs:
        e = rn(expr)
        if amap:
            e = _SELFCMP.sub(r"(\1 == \1__prior)", e)
        seen.setdefault(fixlen(e), set()).add(bool(taken))
    rows = []
    for si, (members, canons, hard) in enumerate(SETS):
        if not canons <= mint:
            continue
        obs = tuple((("B" if len(seen[e]) > 1 else ("T" if True in seen[e] else "F"))
                     if e in seen else "U") for e in members)
        if all(c == "U" for c in obs):
            continue
        rows.append((si, obs))
    if not rows:
        return None
    return (path, len(seeds), rows)


def main():
    cov, lst = sys.argv[1], sys.argv[2]
    K = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    miss = [m for m in json.load(open(cov))["missing"] if not m["untracked"]]
    sets, meta = [], []
    for m in miss:
        lits = split_lits(m["node_constraint"])
        members = [e for e, _w in lits]
        canons = set()
        for e in members:
            canons |= set(_CANON_RE.findall(e))
        hard, why = [], {}
        for e in members:
            r = []
            if prefix_coupled(e):
                r.append("prefix-coupled")
            if not writable(e):
                r.append("unwritable-by-overlay")
            if os.environ.get("HARD_PER_ROW") and per_row(e):
                r.append("per-row")
            if r:
                hard.append(e); why[e] = "+".join(r)
        sets.append((members, canons, hard))
        meta.append({"members": members, "witness": [w for _e, w in lits],
                     "hard": hard, "hard_why": why})
        print(f"  set{len(sets)-1}: width {len(members)}  hard {len(hard)}")
        for e in hard:
            print(f"        HARD [{why[e]}] {e}")
    # ONE SCAN, MANY BUILDS. The corpus pass is the expensive part (132 524
    # dumps, ~20 min); the base choice and the seed values are cheap and get
    # re-tuned every round. `INDEX_OUT` saves the per-set observations,
    # `INDEX_IN` replays them — keyed by the members, so a changed gap list
    # refuses the index rather than silently mismatching it.
    key = [m["members"] for m in meta]
    idx_in = os.environ.get("INDEX_IN")
    if idx_in and os.path.exists(idx_in):
        import pickle
        blob = pickle.load(open(idx_in, "rb"))
        # PER-SET match. `blob["key"][oi]` is set `oi`'s member list as it was
        # when the index was built; `blob["rows"][oi]` are that set's rows.
        # A set of THIS gap list is replayed iff some old set has a member list
        # equal to it, element for element.
        lut = {}
        for oi, mem in enumerate(blob["key"]):
            rws = blob["rows"].get(oi, blob["rows"].get(str(oi)))
            if rws is not None:
                lut.setdefault(tuple(mem), rws)
        pool_rows = collections.defaultdict(list)
        replayed, unmatched = [], []
        for si, mem in enumerate(key):
            rws = lut.get(tuple(mem))
            if rws is None:
                unmatched.append(si)
            else:
                pool_rows[si] = list(rws)
                replayed.append(si)
        print(f"index replayed from {idx_in}: {len(replayed)}/{len(key)} sets matched "
              f"by member list: { {si: len(pool_rows[si]) for si in replayed} }",
              flush=True)
        if unmatched:
            # NOT guessed at and NOT dropped: scanned, for these sets only.
            files = [l.strip() for l in open(lst) if l.strip()]
            print(f"sets {unmatched} are NOT in the index (new or changed member "
                  f"list) — SCANNING {len(files)} candidates for them alone",
                  flush=True)
            sub = [sets[si] for si in unmatched]
            with Pool(int(os.environ.get("JOBS", "12")), initializer=_init,
                      initargs=(sub,)) as pool:
                for r in pool.imap_unordered(work, files, chunksize=32):
                    if r:
                        path, ns, rws = r
                        for j, obs in rws:
                            pool_rows[unmatched[j]].append((path, ns, obs))
            print(f"scanned: { {si: len(pool_rows[si]) for si in unmatched} }",
                  flush=True)
            # the replayed sets do not see those files yet; INDEX_MERGE below is
            # what brings them current, and it is the caller's job to pass it.
        # INDEX_MERGE: fold a SMALL extra file list (this round's own driven
        # dumps) into a replayed index, so a round does not have to re-scan
        # 132 k dumps to know what its own 336 runs walked.
        extra = os.environ.get("INDEX_MERGE")
        if extra and replayed:
            xf = [l.strip() for l in open(extra) if l.strip()]
            have = {r[0] for si in replayed for r in pool_rows[si]}
            xf = [f for f in xf if f not in have]
            print(f"merging {len(xf)} new dumps into the {len(replayed)} REPLAYED "
                  f"sets (the scanned ones already saw the whole list)", flush=True)
            sub = [sets[si] for si in replayed]
            with Pool(int(os.environ.get("JOBS", "12")), initializer=_init,
                      initargs=(sub,)) as pool:
                for r in pool.imap_unordered(work, xf, chunksize=16):
                    if r:
                        path, ns, rws = r
                        for j, obs in rws:
                            pool_rows[replayed[j]].append((path, ns, obs))
        # The index is written back under THIS round's key whenever INDEX_OUT is
        # set — not only when a merge happened — so a round that only replayed,
        # or only scanned the unmatched sets, still hands the next round an
        # index covering every set of the current gap list.
        if os.environ.get("INDEX_OUT"):
            import pickle as _pk
            _pk.dump({"key": key, "rows": dict(pool_rows)},
                     open(os.environ["INDEX_OUT"], "wb"), protocol=4)
            print(f"index written to {os.environ['INDEX_OUT']} "
                  f"({len(replayed)} replayed, {len(unmatched)} scanned)", flush=True)
    else:
        files = [l.strip() for l in open(lst) if l.strip()]
        print(f"candidates {len(files)}", flush=True)
        pool_rows = collections.defaultdict(list)
        with Pool(int(os.environ.get("JOBS", "12")), initializer=_init,
                  initargs=(sets,)) as pool:
            for r in pool.imap_unordered(work, files, chunksize=32):
                if r:
                    path, ns, rows = r
                    for si, obs in rows:
                        pool_rows[si].append((path, ns, obs))
        if os.environ.get("INDEX_OUT"):
            import pickle
            pickle.dump({"key": key, "rows": dict(pool_rows)},
                        open(os.environ["INDEX_OUT"], "wb"), protocol=4)
            print(f"index written to {os.environ['INDEX_OUT']}", flush=True)
    per_variant, manifest = collections.defaultdict(list), []
    stats = []
    TODO_CAP = int(os.environ.get("TODO_CAP", "40"))
    ONLY = os.environ.get("SETS_ONLY")
    ONLY = {int(x) for x in ONLY.split(",")} if ONLY else None
    for si, (members, canons, hard) in enumerate(sets):
        if ONLY is not None and si not in ONLY:
            print(f"  set{si}: SKIPPED (SETS_ONLY)", flush=True)
            stats.append(dict(set=si, skipped=True))
            continue
        w = len(members)
        decls = declarations(members, miss[si]["concrete_values"])
        space = set()
        for asg in itertools.product(*[[True, False]] * w):
            c = _combo_constraint(list(zip(members, asg)))
            r = check_satisfiability([c], decls, timeout_ms=5000)
            if r.satisfiable:
                space.add(asg)
        # COVERED is read from EVERY dump that minted the set's canonicals, not
        # only from the ones eligible as bases: a leaf some run already walked
        # is covered whether or not that run can serve as a base.
        covered = set()
        for _p, _n, obs in pool_rows[si]:
            if "U" in obs:
                continue
            covered |= set(itertools.product(*[[True, False] if c == "B" else [c == "T"]
                                               for c in obs]))
        todo = sorted(space - covered)
        # WIDTH CAP (C20 round 2's rule, applied by TODO count rather than by
        # width): a 12-member set has 448 satisfiable leaves and the checker
        # named ONE of them. Drive the WITNESS and its 1-flip neighbours — the
        # gap the engine actually reports, plus the ring around it — and let
        # the re-census name the next one. Driving 448 leaves x K bases is a
        # 6 000-run round for a set the engine reports as one gap.
        wit = tuple(meta[si]["witness"])
        capped = False
        if len(todo) > TODO_CAP:
            ring = {wit} | {wit[:j] + (not wit[j],) + wit[j + 1:] for j in range(w)}
            sel = sorted((ring & space) - covered)
            if sel:
                todo, capped = sel, True
        # PER-HARD-MEMBER DIAGNOSTIC: when a set has no base, say WHICH member
        # no dump records with the others, instead of reporting "bases 0".
        rec = [sum(1 for _p, _n, o in pool_rows[si] if o[members.index(h)] != "U")
               for h in hard]
        hidx = [members.index(h) for h in hard]
        # REQUIRE_ALL_MEMBERS (C20 round 3's rule): the base must CO-EVALUATE
        # the whole set, or the overlay writes seeds on decisions the run never
        # reaches — which is precisely what round 1's 13/56 realisation was.
        if os.environ.get("REQUIRE_ALL_MEMBERS"):
            eligible = [r for r in pool_rows[si] if "U" not in r[2]]
        else:
            eligible = [r for r in pool_rows[si]
                        if all(r[2][j] != "U" for j in hidx)]
        print(f"  set{si}: rows {len(pool_rows[si])}  eligible-bases {len(eligible)}  "
              f"SAT-space {len(space)}/{2**w}  covered {len(covered & space)}  "
              f"todo {len(todo)}{' (CAPPED to witness+ring)' if capped else ''}",
              flush=True)
        for h, n in zip(hard, rec):
            print(f"        hard-member recorded in {n} rows: {h[:110]}")
        stats.append(dict(set=si, width=w, rows=len(pool_rows[si]),
                          eligible=len(eligible), space=len(space),
                          covered=len(covered & space), todo=len(todo),
                          capped=capped,
                          hard_recorded=dict(zip(hard, rec))))
        if os.environ.get("PLAN"):
            stats[-1]["built"] = 0
            continue
        pool_rows[si] = eligible
        built = 0
        for asg in todo:
            cand = []
            for p, ns, obs in pool_rows[si]:
                if not all(obs[j] in ("B", "T" if asg[j] else "F") for j in hidx):
                    continue
                nm = sum(1 for j in range(w) if obs[j] in ("B", "T" if asg[j] else "F"))
                cand.append((nm, ns, p))
            cand.sort(reverse=True)
            for _nm, _ns, p in cand[:K]:
                d = json.load(open(p))
                amap = alias_map_for([(e.get("result_name"), e.get("note"))
                                      for e in d.get("events") or ()
                                      if e.get("type") == "symbolic_call"], ALIASES)
                rnm = renamer(amap)
                rev = collections.defaultdict(list)
                for o, c in (amap or {}).items():
                    rev[c].append(o)
                rev_sorted = sorted(rev, key=len, reverse=True)
                s = dict(d.get("concolic_seeds") or {})
                variant = next((v for v in VARIANTS
                                if os.path.basename(p).startswith("dump_" + v)), None)
                if variant is None:
                    del d
                    continue

                def seedkeys(k):
                    dn = f"len({k[8:]})" if k.startswith("SYM_LEN_") else k
                    outs = [dn]
                    for c in rev_sorted:
                        if re.search(re.escape(c) + r"(?![0-9])", dn):
                            outs = [re.sub(re.escape(c) + r"(?![0-9])",
                                           o.replace("\\", "\\\\"), dn) for o in rev[c]]
                            break
                    return [o for o in outs if fixlen(rnm(o)) == k]

                # ---- UNSEED: Not((X == X__prior)) is realised by X UNSEEDED.
                unseeded = []
                for j, (e, want) in enumerate(zip(members, asg)):
                    mp = _PRIOR.match(e)
                    if mp and mp.group(1) == mp.group(2) and not want:
                        for sk in seedkeys(mp.group(1)):
                            if s.pop(sk, None) is not None:
                                unseeded.append(sk)
                # ---- write PER VARIABLE, not per literal. A variable named by
                #      a HARD member is never written (the base carries it);
                #      every other variable gets ONE ladder value that
                #      satisfies all of its demanded literals jointly.
                hardvars = set()
                for j in hidx:
                    hardvars |= set(re.findall(r"SYM_[A-Za-z0-9_]*", members[j]))
                varlits = collections.defaultdict(list)
                for j, (e, want) in enumerate(zip(members, asg)):
                    if j in hidx:
                        continue
                    lo = lit_of(e)
                    if lo is None:
                        continue
                    v, k, r = lo
                    varlits[v].append((k, r, bool(want)))
                # negatives first, positives last: if two checker names share a
                # runtime seed key, the positive demand wins the collision.
                order = sorted(varlits, key=lambda v: any(w for _k, _r, w in varlits[v]))
                # ---- (B) §40.5a ENABLING GATES: the decisions that
                #      discriminate a statement-keyed member's statement from
                #      its siblings. Written as ordinary non-hard variables,
                #      and NEVER for a variable a hard member names (the base
                #      carries those) — a gate that contradicts a hard member
                #      would silently pick a different base row.
                eg_used = []
                for g in ENABLING_GATES.get(si, ()):
                    lo = lit_of(g["expr"])
                    if lo is None:
                        continue
                    v, k, r = lo
                    if v in hardvars or v in varlits:
                        continue          # the cube already decides this one
                    varlits[v].append((k, r, bool(g["want"])))
                    eg_used.append(g["expr"])
                order = sorted(varlits, key=lambda v: any(w for _k, _r, w in varlits[v]))

                wrote, nolad, gates = 0, [], []
                mywrites = {}
                for v in order:
                    if v in hardvars:
                        continue
                    val = ladder_value(v, varlits[v])
                    if val is None:
                        nolad.append(v)
                        continue
                    for sk in seedkeys(v):
                        s[sk] = val
                        mywrites[sk] = val
                        wrote += 1
                        for gk, gv in gate_keys(sk):
                            if os.environ.get("GATE_SEEDS", "1") != "0":
                                s[gk] = gv
                                mywrites[gk] = gv
                                gates.append(gk)
                # ---- C17: a re-minted length also written at the upstream key
                s, moved = fix_seeds(s, d)
                # ---- (A) §40.6: `fix_seeds` may have moved the BASE's own
                #      re-mint demand onto a key THIS BUILD just wrote. The
                #      demand wins: re-apply our own writes on top. Every key
                #      actually overwritten is recorded, so a round can see
                #      whether this fix was doing anything.
                reapplied = sorted(k for k, v in mywrites.items() if s.get(k) != v)
                for k, v in mywrites.items():
                    s[k] = v
                del d
                per_variant[variant].append(s)
                manifest.append({"set": si, "assignment": [bool(x) for x in asg],
                                 "base": os.path.basename(p), "variant": variant,
                                 "wrote": wrote, "unseeded": unseeded,
                                 "no_ladder_value": nolad,
                                 "gate_seeds": gates,
                                 "enabling_gates": eg_used,
                                 "reapplied_after_fix_seeds": reapplied,
                                 "remint_moved": [[a, b] for a, b, _v in moved]})
                built += 1
        stats[-1]["built"] = built
    for v in VARIANTS:
        json.dump(per_variant.get(v, []),
                  open(os.path.join(HERE, f"{PREF}{v}.json"), "w"))
    json.dump({"meta": meta, "stats": stats, "manifest": manifest},
              open(os.path.join(HERE, MANIFEST), "w"), indent=1)
    print("per variant:", {v: len(per_variant.get(v, [])) for v in VARIANTS})
    print(f"C30-BUILT {sum(len(x) for x in per_variant.values())} seeds")


if __name__ == "__main__":
    main()
