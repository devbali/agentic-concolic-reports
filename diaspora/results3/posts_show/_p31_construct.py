#!/usr/bin/env python3
"""P31 — CONSTRUCT with the BASE CHOICE as a HARD FILTER on the cube's
upstream EMPTINESS PINS (successor to `_p23_construct.py`, which is NOT edited).

WHAT ROUND 8 LOCALISED (§89.10). Three rounds of the same demand, three
constructors:

    round   constructor        gaps  walked   contradicted literals
     6      base search         744  293 39%   4 912  (11.6 %)
     7      ordinal fixpoint    451    8  2%       0  ( 0.0 %)
     8      base search         569  187 33%   1 636  ( 7.7 %)  all on the
                                                                length gate

Round 7 drove the contradicted class to ZERO by basing every seed on the gap's
OWN previous dump; round 8, on a demand for which no such dump exists, went
back to base search and the class came back — 1 636 / 1 636 on the length
gate, the same family and the same shape §88.2 diagnosed as ORDINAL SHIFT.
566 of round 8's 569 seeds sat on a base that does not walk the cube's
enabling gates. **THE SEED WRITER WAS NEVER THE PROBLEM** — `_p23_construct.py`
already writes every value at the BASE's own raw ordinal, resolved through
that base's alias map. **THE BASE CHOICE IS.**

THE RULE THIS SCRIPT IMPLEMENTS. A base is ADMISSIBLE for a cube only if it
ALREADY REALISES the cube's upstream emptiness pins: every list the cube pins
EMPTY is empty in the base's own run and every list it pins NON-EMPTY is
non-empty. If it does not, the cube's own overlay changes which reads happen,
every later raw ordinal shifts, and the length seed lands on a NEIGHBOUR —
which is exactly the contradicted length gate, measured twice.

Round 7 satisfied this property by ACCIDENT of having the gap's own dump;
round 8 shows the property, not the provenance, is what matters. So:

  HARD-1  EMPTINESS PINS (`P31_PIN_HARD`, default ON). Measured feasible for
          569/569 of round 8's gaps (`_p31_basecompat.py`): every gap has at
          least one pin-realising base, median 153 of 48 497, minimum 14.
  HARD-2  D1 BOTH-WAYS (inherited from P23), applied INSIDE HARD-1.
  HARD-3  ENABLING GATES (`P31_GATE_HARD`, default ON) — applied only when a
          base satisfying it EXISTS, because for 380 of the 569 it does not:
          the whole shortfall is 1-2 `as_api_response_<n>_row_guid` gates, all
          of them SEEDABLE, so the base has to REACH them, not already take
          them (`_p31_gapdiag.py`). Relaxations are COUNTED, never hidden.
  RANK-0  THE GAP'S OWN ROUND DUMP (`P31_OWN_FIRST`, default ON) when it is in
          the corpus AND passes HARD-1/3 — the ordinal-fixpoint branch of
          §88.7, now a PREFERENCE inside the rule rather than the method
          itself. Matched by NODE_CONSTRAINT, never by gap id (ids are
          enumeration-order and do not survive a re-emission).

Everything below HARD-3 is `_p23_construct.py` unchanged: the same rank order
(alias coverage, governor compatibility, unsteerable, gate match, cube
literals evaluated, members walked), the same governor / split / zeroed-ordinal
pin layers, the same seed writer, which §89.10 exonerated. The grouping key
gains the cube's PIN SIGNATURE, because a hard filter over a group whose
members disagree on a pin is not well defined.

--- the original P23/P18 docstring follows, unchanged ---
P18 — CONSTRUCT one seed per P17 gap (RUNBOOK Phase 2, construct-not-sample).


P18 ADDS ONE THING, AND IT IS THE ONLY THING ROUND P17 STILL FAILED ON (§80).
Every one of the 340 P17 witnesses failed on a literal that was NEVER
EVALUATED and none on a literal that was contradicted, so no seed was being
refused — the runs did not REACH the decision. Measured (`_p18_diag.py`,
`_p18_index.py`):

  * A `_row_<field>` member is a read of a ROW OF A LIST, and it is evaluated
    only when that list is in the right state. For `..._row_guid` the list must
    be NON-EMPTY; for `..._row_text_has_mention` / `_text_empty` at api ordinals
    1 and 4 it must be EMPTY (the has-mention scan is the fallback the empty
    list takes). Zero exceptions in 2 661 / 2 066 / 1 669 runs respectively.
  * WHICH list governs an api row read is a property of the RUN, not of the
    name: `as_api_response_<n>` is ORDINAL-keyed (the AliasAssumption covers
    only the AR record readers), and the collection it projects is the
    `records` call immediately preceding it. Ordinal 2 has SIX bindings in this
    corpus, ordinal 1 four, ordinal 4 one.
  * So the governing length is resolved PER BASE, from that base's own binding,
    and then PINNED — which is exactly what P15 never did: it wrote only the
    variables the cube CONSTRAINS, and the governing length is almost never one
    of them (it is free, so the seed left it at the base's value, and 227 of
    320 failing gaps had a base that evaluated every cube literal before the
    overlay zeroed the governor).

Two mechanisms, both derived from the corpus and neither declared:

  (G1) THE NECESSITY TABLE (`_p18_index.necess`). For a demand-universe
       expression `e` and a length variable `L`: if no run in the corpus ever
       evaluated `e` while `L` was empty (over at least MIN_RUNS runs that had
       `L` empty), then `L != 0` is a measured PRECONDITION of `e`, and the
       seed pins it. Symmetrically for `L != 0` -> `e` unevaluated. This is
       §16b's foreclosure epistemics one value-level down; it is computed at
       the DRIVER and nothing in `src/` is touched.
  (G2) THE PER-BASE API BINDING (`_p18_index.binds` + `bindstat`). The
       disjunctive case G1 cannot see: `as_api_response_1_row_guid` is not
       foreclosed by any single mentions list being empty, because four
       different lists can bind ordinal 1. Once the BASE is fixed the binding
       is fixed, so the requirement becomes a single length and is pinned.

Base choice gains one term, ranked SECOND, directly under alias coverage
(which §78.6c measured to be the optimum first key): the number of the cube's
row-read members whose governing length, ON THAT BASE, is compatible with what
the cube itself demands, minus the number that are not. A base whose binding
makes the cube self-contradictory (the cube empties the very list the row read
needs) is therefore avoided when another base exists, and COUNTED when none
does.

Successor to `_construct_by_gate.py` (2026-09-11) via `_p15_construct.py`.
Same rules, four repairs
that this drive measured on that script's own output:

 (1) BOTH `len` SPELLINGS. `_construct_by_gate.py` looked a checker-side name
     (`SYM_LEN_X`) up in a dump-side map (`len(X)`), so every SYM_LEN value it
     was handed was DROPPED with no error — 4 720 of 25 580 constructed values
     (18.5 %) in round OD0911, i.e. every length gate the cubes demanded. This
     module derives the reverse map instead of guessing it: every key of a
     base's `concolic_seeds` is pushed through the SAME two transforms the
     checker's loader applies (alias canonicalization, then `len(X)` ->
     `SYM_LEN_X`) and the result is the key the model is joined on. A name the
     base cannot seed is COUNTED, never silently dropped.

 (2) MODEL COMPLETION IS NOT A DEMAND (§16d). With one query per demand set
     the witness model assigns EVERY variable, including the ones the cube
     leaves free — `model.eval(..., model_completion=True)` hands those Z3's
     default (`''`, 0, False). Seeding a default the corpus never produces is
     exactly the out-of-domain foreclosure §72.1 measured. Only variables the
     cube's `node_constraint` actually CONSTRAINS are written; a free variable
     keeps the base run's own value, which is what makes the base a context.

 (3) OUT-OF-DOMAIN RESOLUTION, VERIFIED, FOR NEGATIVES AND FOR PREDICATES.
     §72.1 resolved a negated variable to its most-observed value. That left
     `SYM_PARAM_id`'s `Length(...) < 16` unfixed (the model's invented
     16-character string survived). Here a substitute is accepted only if it
     SATISFIES every literal the cube puts on that variable (`==`, `!=`,
     `Length(v) < n`), so a predicate-constrained variable is resolved too and
     an unverifiable substitution is never made.

 (4) NEGATIVES BEFORE POSITIVES (§72.2), kept.

`__prior` keys are UNSEEDED (absence is the signal). posts_show mints none —
the rule is carried anyway so a future target that does is handled.

Bases are chosen BY GATE MATCH, not by token overlap: a base must already walk
the enabling gates the leaf group needs, then walk as much of the demand set as
possible. That is the "enabling gates fixed from the summary's foreclosure
structure, not solved again" half of the RUNBOOK rule; the cube already carries
an outcome for every foreclosing gate on its path, so no Z3 call is made here.
"""
import json, os, pickle, re, sys, time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, "/home/dev/project/src")
from concolic_engine.assumptions import alias_map_for, renamer      # noqa: E402
from coverage_assumptions import ALIASES                             # noqa: E402

GAPS  = os.environ.get("P15_GAPS",  os.path.join(HERE, "_p15_gaps.json"))
INDEX = os.environ.get("P18_INDEX", os.path.join(HERE, "_p23_index.pkl"))
PARTS = os.environ.get("PARTS_IN",  os.path.join(HERE, "_parts_OD0911.json"))
K     = int(os.environ.get("BASES_PER_GAP", "2"))
GROUPBY = os.environ.get("P23_GROUP", "gates")   # "gates" (P18) or "set" (S1)
HARD_SPLIT = os.environ.get("P23_HARD_SPLIT", "1") != "0"
PREFIX  = os.environ.get("P15_PREFIX",  "_p15_seeds_")
PREFIXB = os.environ.get("P15_PREFIXB", "_p15_seedsB_")
LABELA  = os.environ.get("P23_LABEL_A", "A")
LABELB  = os.environ.get("P23_LABEL_B", "B")

# BASES_PER_GAP/K may exceed 2 (§ the P44 rank-naming fix, 2026-09-16): rank 0
# keeps PREFIX and rank 1 keeps PREFIXB UNCHANGED for backward compatibility
# (every existing caller that reads "the B file" still gets exactly rank 1),
# and rank >= 2 gets its OWN file so it can no longer silently collide with
# rank 1's (the collision produced an IndexError in `_p15_explain.py` the
# first time K=3 was tried: two ranks shared one seed file and one manifest's
# `seed_index` values ran past the surviving rank's list).
def _seed_pref(rank):
    if rank == 0:
        return PREFIX
    if rank == 1:
        return PREFIXB
    return f"{PREFIXB}{rank}_"
MANOUT  = os.environ.get("P15_MANIFEST", "_p15_manifest.json")
MIN_BIND = int(os.environ.get("P18_MIN_BIND", "60"))
# ---------------------------------------------------------------- P31 knobs
PIN_HARD  = os.environ.get("P31_PIN_HARD",  "1") != "0"
GATE_HARD = os.environ.get("P31_GATE_HARD", "1") != "0"
OWN_FIRST = os.environ.get("P31_OWN_FIRST", "1") != "0"
OWN_GAPS  = os.environ.get("P31_OWN_GAPS", "")     # a previous round's gaps json
OWN_EXPLN = os.environ.get("P31_OWN_EXPLAIN", "")  # ... and its _p15_explain output
PINREPORT = os.environ.get("P31_PINREPORT", "_p31_pins.json")
GROUP_GATES = os.environ.get("P31_GROUP_GATES", "1") != "0"
# the exhausted-split release (§91.4). A knob only so the P23 behaviour can be
# reproduced exactly as a control; it is a correctness repair, keep it ON.
SPLIT_RELEASE = os.environ.get("P31_SPLIT_RELEASE", "1") != "0"
# ------------------------------------------------ P44 (2026-09-18): §123, THE
# EMPTY CANONICAL PIN IS AN EXISTENTIAL, NOT A UNIVERSAL.
#
# `seedkeys()` implements the "many-ordinal rule": a pin on a canonical length
# is written to EVERY raw ordinal backing that canonical (line ~1000). For a
# NON-EMPTY pin that is right — the canonical is non-empty iff some ordinal is,
# and writing them all is the cheapest way to get one. For an EMPTY pin it is
# strictly STRONGER than the cube demands, and measurably fatal:
#
#   `_p23_index.py` realises `SYM_LEN_<canonical>_rows` by renaming every
#   backing ordinal to the canonical into ONE dict (`sv[nm] = val`), so the
#   indexed length is a last-wins COLLAPSE over the ordinals. "Canonical empty"
#   is therefore an EXISTENTIAL over ordinals, and a real base can satisfy it
#   while another ordinal of the same canonical is non-empty.
#
# Measured on CLASSBV1 (§123): base `dump_auth_html0525_BV3C0910auht0001r0`
# backs `records_photos_9930492e` with records_1/2/4, has records_4 EMPTY (so
# the cube's pin is realised) and records_2 NON-EMPTY — and that non-empty
# ordinal is what `post.photos.present?` reads at `blank.rb`, which is what
# reaches the `.size` call site in `posts_helper.rb:8-18`. The base takes BOTH
# demanded size-gate sides. The constructor then wrote 0 to records_1/2/4
# alike, `.photos.present?` went false, and the size gate was never evaluated
# in ANY of the 4111 driven runs (0/4111 walked, 3 rounds running).
#
# The split machinery already encodes the dual rule for the api/necessity paths
# ("one ordinal always keeps the cube's state", §91.4) but never fires here:
# the size gate has no api-governor member, and `_p23_index.py`'s necessity
# filter DROPS `records_2` because it appears in both the nz and z lists.
#
# ON: an empty canonical pin is written to ONE ordinal only — preferring one
# the base ALREADY holds empty, so the base's own ordinal map shifts least (the
# same tie-break the exhausted-split release uses). Every other ordinal keeps
# the base's value. OFF: byte-for-byte the previous behaviour.
#
# MEASURED, single-variable differential on the 4111 CLASSBV1 gaps (identical
# index UNION2, identical parts _p44_parts_UNION.json, identical gaps file,
# identical base choice and seed counts — the construct logs differ ONLY in
# this knob's report block):
#
#                            OFF (= CLASSBV1r3)      ON (= CLASSBV1U2X2r1)
#     gaps WALKED            0 / 4111   (0.0 %)      2501 / 4111  (60.8 %)
#     size gate honoured     0 / 7049   (0.0 %)      4936 / 6469  (76.3 %)
#     length gate (rows)     100 % hon, 0 contra     100 % hon, 0 contra
#     contradicted (total)   112                     112   (unchanged)
#
# The cube's own emptiness literals stay 100 % honoured with zero
# contradictions, which is the soundness check this repair had to pass: a
# sibling left non-empty does NOT cost the empty reading, because
# `_p15_explain.py` judges a literal honoured when the demanded polarity was
# taken AT LEAST ONCE (`taken` is a set, the test is `pol in t`) — the same
# existential the index's own last-wins collapse implements.
#
# Default ON for the same reason `P31_SPLIT_RELEASE` is: it is a correctness
# repair, and the knob exists so the previous behaviour can be reproduced
# exactly as a control (`P31_EMPTY_EXISTENTIAL=0`).
EMPTY_EXIST = os.environ.get("P31_EMPTY_EXISTENTIAL", "1") != "0"
# §123.7 REACH TIER (2026-09-18). A base that never EVALUATES a cube literal
# cannot produce a run that walks it, and no seed can repair that — it is a
# property of the base's own execution. The rank tuple already carries it as
# term 5, where it loses to alias coverage, the governor, the unsteerable term
# and the gate match.
#
# MEASURED on the 4111 CLASSBV1 gaps (same index/parts/gaps; differs from the
# §123 run only in this knob), applied at BOTH the `scored_pin_gate` and the
# `scored_pin` level — nesting it under `scored_pin_gate` alone changed 0 of
# 4111 rank-0 bases, because the gaps it is for live in the `pins only` tier:
#
#                          OFF (= U2X2r1)        ON (= U2R2r1)
#     gaps WALKED          2501 / 4111           3014 / 4111  (+513)
#     size gate honoured   76.3 %                85.0 %
#     length gate (rows)   100 %, 0 contra       99.4 %, 38 contra
#
# The 38 new contradictions are NOT a regression: all 38 are on gaps whose base
# changed, all 38 were `never_evaluated` with the knob OFF, and all 38 failed to
# walk either way. Strict dominance was checked directly — gaps walked with the
# knob OFF but not ON: **0**; ON but not OFF: **513**. So the knob only re-labels
# the verdict on gaps that were already failing, and costs no walk anywhere.
# Default ON on that evidence; OFF reproduces the previous behaviour as a
# control.
REACH_TIER = os.environ.get("P31_REACH_TIER", "1") != "0"
VARIANTS = ("auth_html", "anon_html", "auth_json", "anon_json")

_LEN = re.compile(r"len\(([^()]+)\)")
fixlen = lambda s: _LEN.sub(r"SYM_LEN_\1", s) if s else s
_PRIOR = re.compile(r"__prior\b")

def cube_literals(nc):
    """`A AND Not(B) AND C` -> [(expr, polarity)], top level only. The printer
    never puts a top-level ` AND ` inside a conjunct's own parentheses, so a
    depth-aware split is exact."""
    out, depth, cur, i, n = [], 0, [], 0, len(nc or "")
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


_ID = r"[A-Za-z_][A-Za-z0-9_]*"
_EQ  = re.compile(rf"^\(\s*({_ID})\s*==\s*(.+?)\s*\)$")
_NE  = re.compile(rf"^\(\s*({_ID})\s*!=\s*(.+?)\s*\)$")
_LN  = re.compile(rf"^\(\s*Length\(({_ID})\)\s*<\s*(\d+)\s*\)$")


def lit(tok):
    """Parse a Z3-printed literal into the python value a seed carries."""
    tok = tok.strip()
    m = re.match(r"^StringVal\((.*)\)$", tok)
    if m:
        tok = m.group(1).strip()
    if tok in ("True", "False"):
        return tok == "True"
    if re.match(r"^-?\d+$", tok):
        return int(tok)
    if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "'\"":
        return tok[1:-1]
    return tok


def literals(nc):
    """node_constraint -> {var: [(kind, value, want), ...]}. A self-compare
    (`(X != X)`) constrains nothing and is dropped: it is the render family's
    always-false companion, and treating it as a constraint is what makes the
    model's completion default look demanded."""
    out = defaultdict(list)
    for part in (nc or "").split(" AND "):
        part = part.strip(); want = True
        m = re.match(r"^Not\((.*)\)$", part, re.S)
        if m:
            part, want = m.group(1).strip(), False
        for rx, kind in ((_EQ, "eq"), (_NE, "ne"), (_LN, "lenlt")):
            m = rx.match(part)
            if not m:
                continue
            v, rhs = m.group(1), m.group(2)
            if kind in ("eq", "ne") and rhs.strip() == v:
                break                      # self-compare: no constraint
            out[v].append((kind, lit(rhs) if kind != "lenlt" else int(rhs), want))
            break
    return dict(out)


def satisfies(val, cons):
    for kind, rhs, want in cons:
        if kind == "eq":
            ok = (val == rhs)
        elif kind == "ne":
            ok = (val != rhs)
        else:
            try:
                ok = (len(val) < rhs)
            except TypeError:
                return False
        if ok != want:
            return False
    return True


def to_seed(v):
    if isinstance(v, bool) or v is None or isinstance(v, int):
        return v
    s = str(v)
    if s in ("True", "False"):
        return s == "True"
    try:
        return int(s)
    except ValueError:
        return s.strip('"')


# ---------------------------------------------------------------- §40.5a
_DISCRIM_PATH = os.environ.get("P34_DISCRIM", "")
_DISCRIM_SEP = float(os.environ.get("P34_DISCRIM_SEP", "0.99"))
_DISCRIM = {}
_DISCRIM_HITS = Counter()
if _DISCRIM_PATH:
    _d = json.load(open(_DISCRIM_PATH))
    for _fam, _fv in (_d.get("families") or {}).items():
        for _sib, _sv in (_fv.get("per_sibling") or {}).items():
            rows = [(r["expr"], bool(r["taken"])) for r in _sv.get("discriminators") or []
                    if float(r.get("sep") or 0) >= _DISCRIM_SEP]
            if rows:
                _DISCRIM[_sib] = rows
    print(f"[§40.5a] {len(_DISCRIM)} sibling statement(s) carry a discriminator "
          f"at sep >= {_DISCRIM_SEP} (from {os.path.basename(_DISCRIM_PATH)})")


def _discrim_gates(gates, grp):
    """Add every exposed alias sibling's route decisions to this group's gates.

    A gate is only added when the group's OWN cubes name the sibling, and a
    gate already present (either polarity) is never duplicated or flipped --
    the cube's own literal always wins, and a CONFLICT is counted and
    reported rather than silently resolved.
    """
    have = {e for e, _o in gates}
    add = []
    for g in grp:
        blob = (g.get("node_constraint") or "") + " " + json.dumps(g.get("gates") or {})
        for sib, rows in _DISCRIM.items():
            if sib not in blob:
                continue
            for e, o in rows:
                if e in have:
                    if (e, o) not in gates:
                        _DISCRIM_HITS["conflict"] += 1
                    continue
                add.append((e, o)); have.add(e)
                _DISCRIM_HITS["added"] += 1
    if not add:
        return gates
    _DISCRIM_HITS["groups_enriched"] += 1
    return tuple(sorted(set(tuple(gates)) | set(add)))


def main():
    t0 = time.time()
    idx = pickle.load(open(INDEX, "rb"))
    exprs = idx["exprs"]; eidx = {e: i for i, e in enumerate(exprs)}
    dumps = idx["dumps"]; domain = idx["domain"]
    raw = {tuple(k.split("\x00", 1)): v for k, v in idx["raw"].items()}

    # ------------------------------------------------ P18: the two new layers
    LENS = idx["lens"]; LIDX = {L: i for i, L in enumerate(LENS)}
    BINDS = [b[0] for b in idx["binds"]]
    BINDRAW = [b[1] for b in idx["binds"]]
    BSTAT = {}
    for k, v in idx["bindstat"].items():
        a, b, c = k.split("\x00")
        BSTAT[(int(a), b, None if c == "None" else c)] = v
    BSTAT_RAW = {}
    for k, v in (idx.get("bindstat_raw") or {}).items():
        a, b = k.split("\x00")
        BSTAT_RAW[(int(a), b)] = v
    # THE NECESSITY TABLE, with the one filter its raw form needs. A length
    # variable that appears in BOTH lists is not a precondition: it is a
    # variable whose PRESENCE is anti-correlated with the expression (the four
    # `tags_*` statements are mutually exclusive, so each is unminted in most
    # runs and both of its states co-occur with the expression zero times).
    # Dropping the intersection leaves only conditions that are statements
    # about the length's VALUE, and each is applied only to a base that
    # actually mints that length — which is what makes it the conditional it
    # was measured as.
    # P23 — THE MINTING TABLE (`_p23_index.mintnec`). Keyed by the RAW ordinal
    # seed key the split machinery writes; the value is the aliased length
    # variables that must be non-empty / empty for that ordinal to be MINTED at
    # all. §80.13's D1 remedy, second half: "pin the zeroed ordinal's enabling
    # gates so its length decision is still reached when it is set to 0."
    MINTNEC = idx.get("mintnec") or {}
    MINTCNT = idx.get("rawmint_counts") or {}
    print(f"P23 minting table: {len(MINTNEC)} raw ordinals with a measured "
          f"precondition (HARD_SPLIT={HARD_SPLIT}, GROUPBY={GROUPBY})", flush=True)

    NEC = {}
    for e, v in (idx.get("necess") or {}).items():
        nzs, zs = set(v["nz"]), set(v["z"])
        both = nzs & zs
        NEC[e] = {"nz": sorted(nzs - both), "z": sorted(zs - both)}
    print(f"P18 layers: {len(LENS)} length variables, {len(BSTAT)} api-binding cells, "
          f"{sum(1 for v in NEC.values() if v['nz'] or v['z'])} expressions with a "
          f"measured length precondition", flush=True)

    _APIROW = re.compile(r"SYM_RESULT_ActsAsApi__Collection_as_api_response_(\d+)_row_([a-z_]+)")

    def bind_req(n, field, canon):
        """What state the collection bound to api ordinal `n` must be in for
        `<field>` to be read at all, ON A BASE WITH THIS BINDING. Measured, not
        assumed: `NEVER` = this binding has never once read that field."""
        c = BSTAT.get((n, field, canon))
        if not c:
            return "UNSEEN"
        tot = sum(c.values())
        reads = c.get((True, True), 0) + c.get((False, True), 0)
        if tot < MIN_BIND:
            return "UNSEEN"
        if reads == 0:
            return "NEVER"
        if c.get((False, True), 0) == 0:
            return "NZ"
        if c.get((True, True), 0) == 0:
            return "Z"
        # THE CANONICAL SAYS "EITHER" WHERE THE RAW ORDINAL IS EXACT. An alias
        # canonical collapses several `records` statements whose lengths differ
        # in one run, so `SYM_LEN_<canonical>_rows` is not a function of the one
        # collection the api call projects. Round 4 measured the cost: 120 of
        # the 267 gaps that did not walk failed on exactly this — an
        # `as_api_response_2_row_guid` whose canonical (`mentions_66022a8b`)
        # returns EITHER while, conditioned on the RAW ordinal's own length, the
        # read is 2 019/2 019 when non-empty and 0/435 when empty. So when the
        # canonical is not decisive the RAW-ordinal table is consulted, and the
        # pin lands on the raw ordinal the split machinery already writes.
        r = BSTAT_RAW.get((n, field))
        if r:
            tot = sum(r.values())
            reads = r.get((True, True), 0) + r.get((False, True), 0)
            if tot >= MIN_BIND and reads:
                if r.get((False, True), 0) == 0:
                    return "NZ"
                if r.get((True, True), 0) == 0:
                    return "Z"
        return None

    def cube_len_state(g):
        """The length states the CUBE ITSELF demands: `(SYM_LEN_X != 0)` true
        means non-empty, false means empty. These are never overwritten."""
        out = {}
        for e, o in cube_literals(g["node_constraint"]):
            m = re.match(r"^\(\s*(SYM_LEN_[A-Za-z0-9_]+)\s*!=\s*0\s*\)$", e)
            if m:
                out[m.group(1)] = bool(o)
        return out

    def api_members(g):
        out = set()
        for e, _o in cube_literals(g["node_constraint"]):
            for m in _APIROW.finditer(e):
                out.add((int(m.group(1)), m.group(2)))
        return out

    gaps = json.load(open(GAPS))
    parts = {p["i"]: p for p in json.load(open(PARTS))["parts"]}
    print(f"gaps {len(gaps)}   bases indexed {len(dumps)}   K={K}", flush=True)
    NOSEED_GLOBAL = {v for g in gaps for v in g.get("not_seedable", ())}
    print(f"variables the corpus can NEVER seed (derived, stated not dropped): "
          f"{sorted(NOSEED_GLOBAL)}", flush=True)

    # ---------------------------------------------------------- base choice
    # UNSTEERABLE LITERALS (2026-09-12, §78.7 — measured, not assumed). A cube
    # literal over a variable the corpus can never seed cannot be honoured by
    # any seed: it is whatever the BASE's own run renders. On posts_show those
    # are the two derived render outputs, and round 2 measured that they alone
    # block 198 of the 643 gaps that did not walk — while 192 of those 198
    # cubes pin ZERO `*_text_empty` literals, so §77.3's "the cube already pins
    # the members that produce it" is false for 97 % of them and the producer
    # is a FREE variable the seed leaves at the base's value. BOTH SIDES ARE
    # OBSERVED IN THE CORPUS (`_3 == ''` was taken 70 times where False was
    # demanded and False 26 times where True was demanded, and symmetrically
    # for `_2`), so this is not impossibility — it is BASE CHOICE. Therefore:
    # the demanded outcome of every unsteerable literal joins the GROUP KEY,
    # and satisfying it is scored ABOVE the gate match.
    def unsteerable(e):
        return any(v in e for v in NOSEED_GLOBAL)

    unst = {}
    for g in gaps:
        unst[g["id"]] = tuple(sorted((e, o) for e, o in
                                     cube_literals(g["node_constraint"])
                                     if unsteerable(e)))
    nun = sum(1 for v in unst.values() if v)
    print(f"gaps with >=1 UNSTEERABLE literal (no seed key exists): {nun}", flush=True)

    # ------------------------------------------------------------------ P31
    # THE GAP'S OWN PREVIOUS DUMP, matched by NODE_CONSTRAINT. Gap ids are
    # enumeration-order and do not survive a re-emission; the cube does. With
    # the inputs absent the branch is simply off, and that is COUNTED.
    own_by_nc = {}
    if OWN_FIRST and OWN_GAPS and OWN_EXPLN and \
            os.path.exists(OWN_GAPS) and os.path.exists(OWN_EXPLN):
        try:
            og = {x["id"]: x["node_constraint"] for x in json.load(open(OWN_GAPS))}
            pg = json.load(open(OWN_EXPLN)).get("per_gap") or {}
            for gid, rec in pg.items():
                nc, dp = og.get(gid), (rec or {}).get("dump")
                if nc and dp:
                    own_by_nc[nc] = os.path.basename(dp)
        except Exception as exc:                                   # noqa: BLE001
            print(f"P31 own-dump map UNUSABLE ({exc}) -- branch off", flush=True)
            own_by_nc = {}
    byname = {os.path.basename(d[0]): i for i, d in enumerate(dumps)}
    own_idx, own_stat = {}, Counter()
    for g in gaps:
        nm = own_by_nc.get(g["node_constraint"])
        if not nm:
            own_stat["no own dump for this cube"] += 1
        elif nm not in byname:
            own_stat["own dump NOT in the corpus index"] += 1
        else:
            own_idx[g["id"]] = byname[nm]
            own_stat["own dump available as a base"] += 1
    print(f"P31 own-dump branch (OWN_FIRST={OWN_FIRST}): {dict(own_stat)}", flush=True)

    # THE PIN SIGNATURE joins the group key: a hard filter over a group whose
    # members disagree on a pin has no well-defined candidate set, and
    # `grp_len` already threw such a disagreement away (it stored None).
    # ...and only when the filter is ON, so `P31_PIN_HARD=0 P31_GATE_HARD=0
    # P31_OWN_FIRST=0 P31_GROUP_GATES=0 P31_SPLIT_RELEASE=0` reproduces
    # `_p23_construct.py`'s grouping and therefore its base choice exactly.
    PINSIG = ({g["id"]: tuple(sorted(cube_len_state(g).items())) for g in gaps}
              if PIN_HARD else {g["id"]: () for g in gaps})

    groups = defaultdict(list)
    for g in gaps:
        if GROUPBY == "set" and not GROUP_GATES:
            # S1 (notifications, 1.16 closed/run): ONE compatible base per SET,
            # every cube of the set by overlay. Cheaper by the number of gate
            # combinations and it is the shape DISCIPLINE's driver-level
            # batching names. The gate match is term 4 of base choice, so what
            # is given up is a tie-break, not the reach terms.
            # P31 MEASURED WHAT IT ACTUALLY GAVE UP: with an EMPTY gate tuple in
            # the key, `gt`/`gf` are 0, so term 4 is 0 for every candidate and
            # the gate match is not a tie-break — it is ABSENT. That is round
            # 8's "566 of 569 seeds on a base that does not walk the enabling
            # gates" (§89.10), and it is why GROUP_GATES defaults ON here: the
            # gates go back into the key, at the cost of more groups (569 vs
            # 244 on round 8's demand, ~100 s vs 43 s of base choice).
            groups[(g["set"], (), unst[g["id"]], PINSIG[g["id"]])].append(g)
        else:
            groups[(g["set"], tuple(sorted(g["gates"].items())),
                    unst[g["id"]], PINSIG[g["id"]])].append(g)
    print(f"groups ({GROUPBY}): {len(groups)}", flush=True)

    setmask = {}
    for i, p in parts.items():
        m = 0
        for e in p["members"]:
            j = eidx.get(e)
            if j is not None:
                m |= 1 << j
        setmask[i] = m
    UNIV = (1 << len(exprs)) - 1

    canon = idx.get("canon") or []
    cbit = {c: i for i, c in enumerate(canon)}
    _need_cache = {}

    def canon_need(v):
        """Which alias canonicals a checker name is spelled with. A base whose
        run never minted that canonical cannot be given an ORDINAL seed key for
        it, so the seed would be written under the canonical name and the
        runtime would ignore it — an inert key. Measured on the first P15 build:
        46 % of seeds carried at least one. This makes it part of base choice."""
        m = _need_cache.get(v)
        if m is None:
            m = 0
            dn = f"len({v[8:]})" if v.startswith("SYM_LEN_") else v
            for c, j in cbit.items():
                if re.search(re.escape(c) + r"(?![0-9])", dn):
                    m |= 1 << j
            _need_cache[v] = m
        return m

    chosen = {}
    SPLITSTAT = Counter()
    TIERSTAT = Counter()
    GROUPTIER = {}
    OWNROW = {}
    OWNSTAT = Counter()
    n = 0
    for key, grp in groups.items():
        n += 1
        if n % 500 == 0:
            print(f"  base choice {n}/{len(groups)}  {time.time()-t0:.0f}s", flush=True)
        sid, gates, unsteer, gpins = key
        # ---- §40.5a / §102.4  A STATEMENT-KEYED ALIAS IS ITSELF A CONDITION.
        # When an alias FAMILY resolves to several statements, the run issues
        # them ALTERNATIVELY and which one it issues is decided by some OTHER
        # decision.  A group whose cubes name `..._mentions_a0ff45d4` without
        # `(findpublic_act_1_public == True)` asks for a run on one finder
        # route while pinning another: the member's variable is then never
        # MINTED, the seed "takes", the demand is unrealised, and the leaf
        # reads unconstructible.  posts_show is the worst-exposed endpoint
        # measured (6 of 7 families; mentions 6 siblings, photos 5).
        # The discriminators come from `_p34_alias_discriminate.py`'s
        # matched-context differential, NOT from reading the app: each is a
        # literal that separates the runs minting this sibling from the runs
        # minting one of ITS siblings, at >= P34_DISCRIM_SEP (default 0.99,
        # i.e. only the total 100 %-vs-0 % separators).
        # OFF unless P34_DISCRIM names the table, so the round is a
        # ground-truth differential against itself.
        if _DISCRIM:
            gates = _discrim_gates(gates, grp)
        # ---- P18: what this group's cubes need from the ROW-READ governors
        grp_api = set()
        grp_len = {}
        for g in grp:
            grp_api |= api_members(g)
            for L, st in cube_len_state(g).items():
                if L in grp_len and grp_len[L] != st:
                    grp_len[L] = None          # the group disagrees; no signal
                else:
                    grp_len.setdefault(L, st)
        grp_api = sorted(grp_api)
        # P23 — SPLITS THE NECESSITY TABLE ALREADY IMPLIES, computed at GROUP
        # level (they need no base: the precondition is on the canonical, and
        # the cube's own demand is what contradicts it). These join the api
        # splits in the hard both-ways filter below.
        grp_split_nec = set()
        for g in grp:
            cl = cube_len_state(g)
            for e, _o in cube_literals(g["node_constraint"]):
                nv = NEC.get(e)
                if not nv:
                    continue
                for L in nv["nz"]:
                    if cl.get(L) is False:
                        grp_split_nec.add(L)
                for L in nv["z"]:
                    if cl.get(L) is True:
                        grp_split_nec.add(L)
        nec_split_bits = []
        for L in sorted(grp_split_nec):
            j = eidx.get(f"({L} != 0)")
            if j is not None:
                nec_split_bits.append(j)
        need = 0
        cube = 0
        for g in grp:
            for v in g.get("constrained", ()):
                need |= canon_need(v)
            # the cube's OWN literals: a base that already EVALUATES them is a
            # base from which the seeded decision can be reached at all. The
            # old score counted members of the SET, which is a superset and is
            # not what "never evaluated" is about.
            for e, _o in cube_literals(g["node_constraint"]):
                j = eidx.get(e)
                if j is not None:
                    cube |= 1 << j
        nt = nf = 0
        for e, o in unsteer:
            j = eidx.get(e)
            if j is None:
                continue
            if o:
                nt |= 1 << j
            else:
                nf |= 1 << j
        nneed = need.bit_count()
        sm = setmask.get(sid, 0)
        gt = gf = 0
        for e, o in gates:
            j = eidx.get(e)
            if j is None:
                continue
            if o:
                gt |= 1 << j
            else:
                gf |= 1 << j
        # ---- P31 HARD-1: THE CUBE'S UPSTREAM EMPTINESS PINS.
        # `dl1` / `dl0` are the base run's OWN length state (non-empty /
        # empty), taken straight off its `symbolic_vars`, so this is a
        # property of the base's EXECUTION, not of its seed dict — which is
        # what "already realises the pin" has to mean. A pinned length the
        # index does not carry (no base in the corpus ever minted it) cannot
        # be filtered on and is REPORTED, not silently enforced.
        pin_bits, pin_unminted = [], []
        for L, w in gpins:
            j = LIDX.get(L)
            if j is None:
                pin_unminted.append(L)
            else:
                pin_bits.append((j, bool(w)))
        n_gate_bits = sum(1 for e, _o in gates if e in eidx)

        own_want = {own_idx[g["id"]] for g in grp if g["id"] in own_idx}
        scored = []
        scored_hard = []
        scored_pin = []
        scored_pin_gate = []
        scored_pin_gate_reach = []          # §123.7, gated by P31_REACH_TIER
        scored_pin_reach = []               # §123.9, same filter one tier down
        for di, (path, var, em, tm, ns, cm, dl0, dl1, dfm) in enumerate(dumps):
            if sm and not (em & sm):
                continue
            fm = em & ~tm & UNIV
            pin_ok = True
            for j, w in pin_bits:
                if ((dl1 >> j) & 1) if w else ((dl0 >> j) & 1):
                    continue
                pin_ok = False
                break
            # ---- P23 HARD BOTH-WAYS FILTER (§80.13, D1). A base that does not
            # take a to-be-SPLIT length expression BOTH WAYS in its own run
            # cannot supply the second reading the split needs, and P18 round 5
            # measured the cost of leaving this as one score term among six:
            # 201 of 3 826 keys CONTRADICTED, 102 gaps first-failing on exactly
            # this, and 76 of them on a base that DID take the expression both
            # ways but lost to another term. So it is a FILTER, not a term.
            # Relaxed only when it empties the candidate list, and counted when
            # it is (a gap with no both-ways base is reported, never hidden).
            hard_ok = True
            for j in nec_split_bits:
                if not ((em & tm & dfm) >> j) & 1:
                    hard_ok = False
                    break
            match = ((em & gt & tm).bit_count() + (em & gf & fm).bit_count())
            conflict = ((em & gt & fm).bit_count() + (em & gf & tm).bit_count())
            # UNSTEERABLE first (after alias coverage): no seed can fix it.
            nsat = ((em & nt & tm).bit_count() + (em & nf & fm).bit_count())
            ncon = ((em & nt & fm).bit_count() + (em & nf & tm).bit_count())
            # ---- P18 GOVERNOR COMPATIBILITY (ranked SECOND, under alias
            # coverage). `as_api_response_<n>` is ordinal-keyed, so WHICH
            # collection its `_row_*` fields come from is a property of THIS
            # base; the row is read only when that collection is in the state
            # the corpus says it must be in, and a base whose binding the cube
            # contradicts can never walk the leaf however it is seeded.
            gsc = 0
            bnd = BINDS[di]
            for (an, af) in grp_api:
                canon = bnd.get(an)
                if canon is None:
                    gsc -= 2                     # base never makes that api call
                    continue
                rq = bind_req(an, af, canon)
                if rq == "NEVER":
                    gsc -= 3                     # this binding never reads it
                elif rq in ("NZ", "Z"):
                    L = f"SYM_LEN_{canon}_rows"
                    want_nz = (rq == "NZ")
                    want_cube = grp_len.get(L)
                    j = LIDX.get(L)
                    if want_cube is not None and want_cube != want_nz:
                        # Constructible by a SPLIT PIN — one ordinal of the
                        # canonical carries the required state, the others the
                        # cube's — but only a run that actually EVALUATES the
                        # length decision both ways supplies both outcomes.
                        # Round 1 of P18 measured the cost of ignoring that: 76
                        # of the 301 gaps that did not walk failed on a
                        # CONTRADICTED length gate, all of them on a split
                        # canonical, because the zeroed ordinal's decision was
                        # never reached. A base that already takes this
                        # expression both ways is therefore scored ABOVE one
                        # that does not.
                        lj = eidx.get(f"(SYM_LEN_{canon}_rows != 0)")
                        both = (lj is not None and ((em & tm & dfm) >> lj) & 1)
                        if BINDRAW[di].get(an):
                            gsc += 1 if both else 0
                            if not both:
                                hard_ok = False     # P23: the D1 filter
                        else:
                            gsc -= 3
                            hard_ok = False         # nothing to split on
                    elif j is None or not ((dl0 | dl1) >> j) & 1:
                        gsc -= 1                 # base does not mint the length
                    else:
                        gsc += 2
                else:
                    gsc += 1
            # RANK ORDER (2026-09-12, round 4, §78.8 — each place is a measured
            # cost, not a preference):
            #  1 UNSTEERABLE satisfaction. FATAL and unfixable by any seed, and
            #    measured to carry: on P15D, where the chosen base took the
            #    demanded render side the driven run honoured it 224/227 =
            #    98.7 %, and where it did not the run contradicted it 201/201.
            #    Round 3 ranked this SECOND, behind alias coverage, so it never
            #    bound (render honoured 52.3 % -> 51.4 %, i.e. unchanged) — and
            #    for all 201 misses a run taking the demanded side EXISTS in
            #    the corpus. An inert key costs ONE seeded dimension; an
            #    unsteerable conflict costs the whole leaf. Hence first.
            #  2 alias coverage (inert keys).
            #  3 cube literals the base already EVALUATES — "never evaluated"
            #    is 16.3 % of keys and the largest first-failure class, and it
            #    is a REACH property of the base, not of the seed.
            #  4 gate match, which the SEED pins anyway.
            # REVERTED to the round-3 order (2026-09-12, after round 4 MEASURED
            # the promotion): putting UNSTEERABLE first bought nothing on the
            # class it was for — the render family honoured 51.4 % (round 3)
            # vs 51.6 % (round 4) — because for 142 of the 227 gaps that carry
            # one, the cube demands that the TWO render ordinals DISAGREE, and
            # no base can satisfy that (§78.9: 0 of 35 563 profiles ever has).
            # Meanwhile it cost alias coverage: seeds carrying an inert key went
            # from 525/1496 (35 %) to 869/1078 (81 %), gaps walked from 7.9 % to
            # 4.1 %, and the round's closure rate from 0.273 to 0.020 per run.
            # Alias coverage first is the measured optimum; the unsteerable term
            # is kept SECOND, where it breaks ties among equally-spellable bases.
            row = ((need & cm).bit_count(), gsc, nsat - ncon,
                   match - conflict, (em & cube).bit_count(),
                   (em & sm).bit_count(), ns, di)
            if di in own_want:
                OWNROW[di] = (row, pin_ok, match == n_gate_bits, hard_ok, nneed)
            scored.append(row)
            if hard_ok:
                scored_hard.append(row)
                if pin_ok:
                    scored_pin.append(row)
                    # §123.9: the SAME reach filter one tier down. Measured:
                    # the reach tier nested under `scored_pin_gate` changed 0 of
                    # 4111 rank-0 bases, because 983 of the 990 gaps it was
                    # built for sit in the "pins only" tier, where
                    # `scored_pin_gate` is EMPTY and the nested filter can never
                    # apply. So the filter is offered at the `scored_pin` level
                    # too, with the same counted fall-through.
                    if REACH_TIER and cube and (em & cube) == cube:
                        scored_pin_reach.append(row)
                    if match == n_gate_bits:
                        scored_pin_gate.append(row)
                        # §123.7 REACH TIER. Term 3 above ("cube literals the
                        # base already EVALUATES") is a REACH property no seed
                        # can repair, but it sits FIFTH in the sort tuple and
                        # loses to alias coverage / governor / unsteerable /
                        # gate match. Measured after the §123 seed repair: of
                        # the 990 auth_html gaps still failing on the size gate,
                        # 981 sat on a base that NEVER evaluates it, and 983
                        # were in the weaker "pins only" tier. So: prefer bases
                        # that evaluate EVERY cube literal the index carries.
                        # Fall-through is counted, never silent, so a group with
                        # no such base is exactly as before.
                        if REACH_TIER and cube and (em & cube) == cube:
                            scored_pin_gate_reach.append(row)
        if HARD_SPLIT and len(scored_hard) < len(scored):
            # the filter actually bit on this group
            if scored_hard:
                SPLITSTAT["groups_hard_filtered"] += 1
                SPLITSTAT["bases_rejected"] += len(scored) - len(scored_hard)
                scored = scored_hard
            else:
                SPLITSTAT["groups_hard_filter_relaxed"] += 1
                SPLITSTAT["gaps_hard_filter_relaxed"] += len(grp)
                scored_pin = scored_pin_gate = scored_pin_gate_reach = []
                scored_pin_reach = []
        # ---- P31: THE TIERS, most demanding first. Every fall-through is
        # COUNTED and lands in the manifest as `admissibility`, so a round can
        # be read as "how many seeds sat on a base that actually realised the
        # cube's pins" without re-deriving anything.
        tier = "pins+gates"
        if not PIN_HARD:
            tier = "P23 (no hard pin)"
        elif scored_pin_gate_reach and GATE_HARD:
            tier = "pins+gates+reach"
            scored = scored_pin_gate_reach
        elif scored_pin_gate and GATE_HARD:
            if REACH_TIER:
                TIERSTAT["reach tier EMPTY, fell through to pins+gates"] += len(grp)
            scored = scored_pin_gate
        elif scored_pin_reach:
            tier = "pins+reach (no base walks every gate)"
            scored = scored_pin_reach
        elif scored_pin:
            tier = "pins only (no base walks every gate)"
            if REACH_TIER:
                TIERSTAT["reach tier EMPTY at the pins-only level"] += len(grp)
            scored = scored_pin
        elif pin_bits:
            tier = "RELAXED: no base realises the pins"
        else:
            tier = "no pins to filter on"
        if pin_unminted:
            tier += " [+%d unminted pin]" % len(pin_unminted)
        TIERSTAT[tier.split(" [")[0]] += len(grp)
        GROUPTIER[key] = (tier, len(scored_pin_gate), len(scored_pin), len(scored),
                          n_gate_bits, pin_unminted)
        scored.sort(reverse=True)
        picks, seen_var = [], set()
        for s in scored:
            v = dumps[s[-1]][1]
            if len(picks) >= K:
                break
            if v in seen_var and len(seen_var) < min(K, 4) and len(picks) < K:
                continue
            picks.append(s); seen_var.add(v)
        if len(picks) < K:
            for s in scored:
                if len(picks) >= K:
                    break
                if s not in picks:
                    picks.append(s)
        chosen[key] = [(p, nneed) for p in picks]
    print(f"base choice done {time.time()-t0:.0f}s", flush=True)

    # ------------------------------------------------------- build the seeds
    work = defaultdict(list)                     # base dump index -> [(gap, rank, score)]
    GAPTIER = {}
    for key, grp in groups.items():
        gtier = GROUPTIER.get(key, ("?", 0, 0, 0, 0, []))[0]
        for g in grp:
            # ---- P31 RANK-0: THE GAP'S OWN ROUND DUMP, when it is at least as
            # admissible as what the search found. §88.7's ordinal fixpoint,
            # demoted from THE method to a preference inside the rule — the
            # property (pins already realised) is what round 8 showed matters,
            # and a dump of the gap's own previous attempt has it by
            # construction whenever that attempt reached the same prefix.
            oi = own_idx.get(g["id"])
            orow = OWNROW.get(oi) if oi is not None else None
            used_own = False
            if orow is not None:
                row, opin, ogate, ohard, onneed = orow
                if ohard and opin and (ogate or gtier != "pins+gates"):
                    work[oi].append((g, 0, row, onneed))
                    used_own = True
                    OWNSTAT["own dump USED as rank-0 base"] += 1
                    OWNSTAT["  ...and it walks every gate too"] += bool(ogate)
                    for r, (sc, nneed) in enumerate(chosen[key]):
                        if r == 0:
                            continue
                        work[sc[-1]].append((g, r, sc, nneed))
                elif not opin:
                    OWNSTAT["own dump REJECTED: does not realise the pins"] += 1
                elif not ohard:
                    OWNSTAT["own dump REJECTED: fails the D1 both-ways filter"] += 1
                else:
                    OWNSTAT["own dump REJECTED: search found a gate-walking base"] += 1
            if not used_own:
                for r, (sc, nneed) in enumerate(chosen[key]):
                    work[sc[-1]].append((g, r, sc, nneed))
            GAPTIER[g["id"]] = ("own dump (ordinal fixpoint)" if used_own else gtier)
    print(f"distinct base runs used: {len(work)}", flush=True)

    def _pins_ok(clen, dl0, dl1):
        for L, w in clen.items():
            j = LIDX.get(L)
            if j is None:
                continue                       # unminted anywhere: unverifiable
            if (((dl1 >> j) & 1) if w else ((dl0 >> j) & 1)):
                continue
            return False
        return True

    def _pins_bad(clen, dl0, dl1):
        out = []
        for L, w in sorted(clen.items()):
            j = LIDX.get(L)
            if j is None:
                out.append(L + " (unminted in the corpus)"); continue
            if (((dl1 >> j) & 1) if w else ((dl0 >> j) & 1)):
                continue
            out.append(L + (" (want NZ, base is Z)" if w else " (want Z, base is NZ)"))
        return out

    def _gates_ok(g, em, tm, dfm):
        n = ok = 0
        for e, o in (g.get("gates") or {}).items():
            j = eidx.get(e)
            if j is None:
                continue
            n += 1
            ok += 1 if ((((em & tm) >> j) & 1) if o else (((em & dfm) >> j) & 1)) else 0
        return [ok, n]

    per_variant = defaultdict(list)
    manifest = []
    stat = Counter()
    # Names the CORPUS has never carried as a seed key: the render outputs.
    # They are DERIVED (a rendered string), not a seedable dimension — the cube
    # reaches them through the `*_text_empty` members it already pins, so the
    # constructor states them instead of writing a key nothing consumes.
    seedable = set(idx.get("seedable") or ())
    NOSEED = NOSEED_GLOBAL
    unresolved_names = Counter()
    gov_conflict_names = Counter()
    subbed_names = Counter()
    kept_ood = Counter()
    exist_kept = Counter()          # §123: ordinals LEFT ALONE by an empty pin
    for bi, jobs in work.items():
        path, variant, em, tm, ns, cm, dl0, dl1, dfm = dumps[bi]
        d = json.load(open(path))
        amap = alias_map_for([(e.get("result_name"), e.get("note"))
                              for e in d.get("events") or ()
                              if e.get("type") == "symbolic_call"], ALIASES)
        rn = renamer(amap)
        base_seeds = dict(d.get("concolic_seeds") or {})
        base_bind = BINDS[bi]
        base_bindraw = BINDRAW[bi]
        # REVERSE the loader's rename instead of looking the checker name up in
        # the base's OWN seed dict. `_construct_by_gate.py` did the latter
        # (`inv.get(k) or ([k] if k in seeds else [])`) and therefore resolved a
        # name only when (a) it was EXACTLY an alias-map canonical — never true
        # for a suffixed name like `<canonical>_row_text_empty` — or (b) the
        # base happened to carry a seed for it already. A dimension the base has
        # never been seeded on could not be written at all, which is a large
        # part of round OD0911's 68 % UNEVALUATED. The reverse map is exact:
        # `SYM_LEN_X -> len(X)`, then every canonical occurring in the name is
        # replaced by EVERY ordinal backing it (the many-ordinal rule).
        rev = defaultdict(list)
        for o, c in (amap or {}).items():
            rev[c].append(o)
        rev_sorted = sorted(rev, key=len, reverse=True)
        del d

        _cache = {}

        def seedkeys(k):
            if k in _cache:
                return _cache[k]
            dn = f"len({k[8:]})" if k.startswith("SYM_LEN_") else k
            outs = [dn]
            for c in rev_sorted:
                if re.search(re.escape(c) + r"(?![0-9])", dn):
                    outs = [re.sub(re.escape(c) + r"(?![0-9])", o.replace("\\", "\\\\"), dn)
                            for o in rev[c]]
                    break
            outs = [o for o in outs if fixlen(rn(o)) == k] or outs
            _cache[k] = outs
            return outs
        for g, rank, score, nneed in jobs:
            cons = literals(g["node_constraint"])
            seeds = dict(base_seeds)
            nsub = nunres = nwrit = nkept = nexist = 0
            # (4) negatives (no `eq` literal) FIRST, positives LAST
            items = [(v, g["concrete_values"][v]) for v in cons
                     if v in g["concrete_values"]]
            items.sort(key=lambda kv: 0 if not any(k == "eq" and w
                                                   for k, _r, w in cons[kv[0]]) else 1)
            for v, val in items:
                sks = [] if v in NOSEED else seedkeys(v)
                if _PRIOR.search(v):
                    for sk in sks:
                        seeds.pop(sk, None)
                    continue
                use = val
                dom = domain.get(v)
                if dom is not None and repr(val) not in dom:
                    cand = [r for r, _c in sorted(dom.items(), key=lambda x: -x[1])
                            if satisfies(raw[(v, r)], cons[v])]
                    if cand:
                        use = raw[(v, cand[0])]; nsub += 1; subbed_names[v] += 1
                    else:
                        nkept += 1; kept_ood[v] += 1
                if not sks:
                    nunres += 1; unresolved_names[v] += 1
                    continue
                # §123: an EMPTY canonical length pin is an EXISTENTIAL over the
                # ordinals backing it (see P31_EMPTY_EXISTENTIAL above). Write it
                # to one ordinal, not all, and say which — the others keep the
                # base's value, which is what preserves downstream reach.
                if (EMPTY_EXIST and len(sks) > 1 and v.startswith("SYM_LEN_")
                        and not use):
                    already = [sk for sk in sks if not base_seeds.get(sk, 1)]
                    target = already[0] if already else sorted(sks)[-1]
                    seeds[target] = to_seed(use)
                    nexist += 1
                    exist_kept[v] += len(sks) - 1
                    if already:
                        stat["empty_pin_existential_base_already_empty"] += 1
                    else:
                        stat["empty_pin_existential_one_ordinal_zeroed"] += 1
                else:
                    for sk in sks:
                        seeds[sk] = to_seed(use)
                nwrit += 1

            # ---------------------------------------------- P18 GOVERNOR PINS
            # The cube says which DECISIONS the leaf takes; it almost never
            # says which LISTS have to be non-empty for those decisions to be
            # reached, because the governing length is a FREE variable of the
            # query and §16d's model completion gives a free variable Z3's
            # default. P15 therefore left it at the base's value and 24.3 % of
            # its keys were never evaluated. Here every row-read member's
            # governing length is pinned to the state the corpus says it must
            # be in — resolved through THIS base's binding for the api reads
            # (G2) and through the measured necessity table for the rest (G1) —
            # and a value the corpus has actually produced is used, never a
            # synthesised one. A length the CUBE constrains is never touched.
            clen = cube_len_state(g)
            reqs, rconf, splits = {}, [], {}

            def _want(L, state, why, ordinal_key=None):
                """`ordinal_key` is the DUMP-side seed key of the single ordinal
                that actually feeds the row read. When the cube demands the
                CANONICAL be in the other state, the two are not in conflict:
                a canonical is backed by several ordinals in the same run, the
                length decision is then evaluated BOTH ways in that one run, and
                the corpus does exactly this (mentions_66022a8b: 588 of 1 535
                runs that take the gate false also read api ordinal 3's guid).
                So the cube's state is written to every OTHER ordinal and the
                required state to this one — a SPLIT PIN. Without the ordinal
                key there is nothing to split and the conflict is recorded."""
                if L in clen and clen[L] != state:
                    if ordinal_key:
                        splits[ordinal_key] = (state, why, L)
                    else:
                        rconf.append((L, state, why))
                    return
                if L in clen:
                    return
                if L in reqs and reqs[L][0] != state:
                    rconf.append((L, state, why)); return
                reqs.setdefault(L, (state, why))

            # P31 DETERMINISM. `api_members` returns a SET, and Python
            # randomises string hashing per process, so the ORDER in which two
            # api reads of the SAME canonical reach `_want` — and therefore
            # WHICH ordinal `splits.setdefault` claims — varied run to run.
            # Measured on this demand with the P31 knobs OFF: two processes,
            # identical inputs, identical base choice for 569/569 gaps, and
            # 1 235 vs 1 207 split pins / 462 vs 410 necessity splits (the
            # second reproducing round 8 exactly). Sorting makes the seed batch
            # a function of its inputs, which a construct-not-sample round has
            # to be if its explain is to mean anything.
            for (an, af) in sorted(api_members(g)):
                canon = base_bind.get(an)
                if canon is None:
                    stat["gov_no_binding"] += 1; continue
                rq = bind_req(an, af, canon)
                if rq == "NEVER":
                    stat["gov_binding_never_reads"] += 1; continue
                if rq in ("NZ", "Z"):
                    rawo = base_bindraw.get(an)
                    ordkey = f"len({rawo}_rows)" if rawo else None
                    _want(f"SYM_LEN_{canon}_rows", rq == "NZ", f"api_{an}_{af}", ordkey)
                    # and pin the RAW ordinal directly even when the cube leaves
                    # the canonical free: writing the canonical writes every
                    # ordinal backing it, which is right for a plain pin, but the
                    # ordinal that actually feeds the read is the one that must
                    # carry the state, so it is stated explicitly.
                    if ordkey and f"SYM_LEN_{canon}_rows" not in clen:
                        splits.setdefault(ordkey, (rq == "NZ", f"api_{an}_{af}",
                                                   f"SYM_LEN_{canon}_rows"))
                else:
                    stat["gov_binding_unconstrained"] += 1
            for e, _o in cube_literals(g["node_constraint"]):
                nv = NEC.get(e)
                if not nv:
                    continue
                for L in nv["nz"]:
                    j = LIDX.get(L)
                    if j is not None and ((dl0 | dl1) >> j) & 1:
                        _want(L, True, "necessity")
                for L in nv["z"]:
                    j = LIDX.get(L)
                    if j is not None and ((dl0 | dl1) >> j) & 1:
                        _want(L, False, "necessity")

            npin = ninert = 0
            for L, (state, why) in reqs.items():
                dom = domain.get(L) or {}
                if state:
                    cand = [r for r, _c in sorted(dom.items(), key=lambda x: -x[1])
                            if raw.get((L, r))]
                    val = raw[(L, cand[0])] if cand else 1
                else:
                    val = 0
                sks = seedkeys(L)
                if not sks:
                    ninert += 1; continue
                wrote = False
                for sk in sks:
                    if sk in seeds and seeds[sk] == to_seed(val):
                        continue
                    seeds[sk] = to_seed(val); wrote = True
                npin += 1 if wrote else 0
                if not wrote:
                    stat["gov_pin_already_right"] += 1
            # A NECESSITY conflict has no api ordinal attached, but the same
            # many-ordinal fact applies: if the base backs the canonical with
            # TWO OR MORE ordinals, one of them can carry the required state
            # while the others carry the cube's, and the length decision is then
            # evaluated both ways in one run — which is what the corpus does.
            # With a single ordinal there is nothing to split and the conflict
            # stands, unpinned; the cube's demand is never overwritten.
            for L, state, why in list(rconf):
                sks = seedkeys(L)
                if len(sks) < 2:
                    continue
                pick = None
                for sk in sks:
                    bv = base_seeds.get(sk)
                    if bv is not None and bool(bv) == state:
                        pick = sk; break
                pick = pick or sks[-1]
                splits.setdefault(pick, (state, why, L))
                rconf.remove((L, state, why))
                stat["gov_necessity_splits"] += 1

            # ------------------------------------- P23: THE ZEROED ORDINAL
            # A split writes the REQUIRED state to the feeding ordinal and the
            # CUBE's state to every other ordinal of the canonical. When the
            # cube's state is EMPTY, those other ordinals carry the 0 — and the
            # cube's own literal is only HONOURED if the run actually reaches
            # them, because "an empty list's length decision is only recorded
            # when that list is reached" (§80.13, D1: 76 of 102 one-sided
            # splits sat on a both-ways base and still lost the empty reading).
            # So every zeroed ordinal's own measured MINTING preconditions are
            # pinned as well. A precondition that contradicts the cube, an
            # existing pin or a split is DROPPED and counted, never overwritten.
            zpin = zskip = 0
            zreqs = {}
            for sk, (state, why, L) in list(splits.items()):
                cube_state = clen.get(L)
                if cube_state is not False:
                    continue                  # nothing is being zeroed
                for zk in seedkeys(L):
                    if zk == sk:
                        continue              # the feeder, not a zeroed ordinal
                    mn = MINTNEC.get(zk)
                    if not mn:
                        stat["z_ordinal_no_minting_table"] += 1
                        continue
                    for L2, want in ([(x, True) for x in mn["nz"]] +
                                     [(x, False) for x in mn["z"]]):
                        j2 = LIDX.get(L2)
                        if j2 is None or not ((dl0 | dl1) >> j2) & 1:
                            continue          # the base never mints it
                        if L2 in clen and clen[L2] != want:
                            zskip += 1; stat["z_pin_vs_cube"] += 1; continue
                        if L2 in reqs and reqs[L2][0] != want:
                            zskip += 1; stat["z_pin_vs_governor"] += 1; continue
                        if L2 == L:
                            zskip += 1; stat["z_pin_self"] += 1; continue
                        if L2 in clen or L2 in reqs or L2 in zreqs:
                            continue          # already right
                        zreqs[L2] = want
            # written HERE, not through `reqs` — the governor pins were already
            # flushed to `seeds` above, so a late addition to `reqs` would be
            # silently dropped (the §80 trap of a value that looks written and
            # is not). Same value rule: an OBSERVED value, never a synthesised
            # one; 0 for the empty side.
            for L2, want in zreqs.items():
                if want:
                    dom2 = domain.get(L2) or {}
                    cand2 = [r for r, _c in sorted(dom2.items(), key=lambda x: -x[1])
                             if raw.get((L2, r))]
                    val2 = raw[(L2, cand2[0])] if cand2 else 1
                else:
                    val2 = 0
                sks2 = seedkeys(L2)
                if not sks2:
                    stat["z_pin_inert"] += 1; continue
                for sk2 in sks2:
                    seeds[sk2] = to_seed(val2)
                zpin += 1
            stat["z_ordinal_pins"] += zpin
            stat["z_ordinal_pins_skipped"] += zskip

            # ------------------------------------ P31: THE EXHAUSTED SPLIT
            # A SPLIT PIN writes the REQUIRED state to the ONE ordinal that
            # feeds a row read and leaves the CUBE's state on every other
            # ordinal of the canonical — that is what makes the length
            # decision evaluate both ways in one run. When TWO api reads bind
            # TWO ordinals of the SAME canonical and both need it non-empty
            # while the cube pins it EMPTY, every ordinal is flipped and the
            # cube's own literal is contradicted BY CONSTRUCTION. Measured on
            # this demand by `_p31_drycheck.py` V4: 175 of 569 seeds, all on
            # the `mentions_*` and `comments_*` canonicals — the same family
            # as round 8's 1 636 contradicted length gates.
            #
            # The design rule is already written down two blocks up ("a
            # precondition that contradicts the cube ... is DROPPED and
            # counted, never overwritten"); the split path was the one place
            # that could break it. So: one ordinal always keeps the cube's
            # state. The split released is the one whose ordinal the BASE
            # already holds in the cube's state, because releasing that one
            # shifts the base's own ordinal map least.
            nrelease = 0
            bysplit = defaultdict(list)
            if SPLIT_RELEASE:
                for sk, (state, why, L) in splits.items():
                    bysplit[L].append(sk)
            for L, sks_s in bysplit.items():
                cube_state = clen.get(L)
                if cube_state is None:
                    continue
                allk = seedkeys(L)
                if not allk or len(set(sks_s)) < len(set(allk)):
                    continue                      # an ordinal still carries it
                keep = None
                for sk in sks_s:
                    bv = base_seeds.get(sk)
                    if bv is not None and bool(bv) == bool(cube_state):
                        keep = sk; break
                keep = keep or sorted(sks_s)[-1]
                splits.pop(keep, None)
                nrelease += 1
                stat["gov_split_exhausted_released"] += 1
                gov_conflict_names[f"split exhausted on "
                                   f"{L[len('SYM_LEN_SYM_RESULT_ActiveRecord__'):][:44]}"] += 1
            stat["seeds_with_an_exhausted_split"] += 1 if nrelease else 0

            nsplit = 0
            for sk, (state, why, L) in splits.items():
                if state:
                    dom = domain.get(L) or {}
                    cand = [r for r, _c in sorted(dom.items(), key=lambda x: -x[1])
                            if raw.get((L, r))]
                    val = raw[(L, cand[0])] if cand else 1
                else:
                    val = 0
                if sk in base_seeds or sk in seeds:
                    seeds[sk] = to_seed(val); nsplit += 1
                else:
                    seeds[sk] = to_seed(val); nsplit += 1
                    stat["gov_split_new_key"] += 1
            stat["gov_split_pins"] += nsplit
            stat["gov_pins"] += npin
            stat["gov_pin_inert"] += ninert
            stat["gov_conflicts"] += len(rconf)
            if rconf:
                stat["seeds_with_a_gov_conflict"] += 1
                for L, s, why in rconf:
                    gov_conflict_names[f"{why} needs {'NZ' if s else 'Z'} on "
                                       f"{L[len('SYM_LEN_SYM_RESULT_ActiveRecord__'):][:44]}"] += 1

            per_variant[(rank, variant)].append(seeds)
            manifest.append({
                "gap": g["id"], "set": g["set"], "width": g["width"],
                "gates": len(g["gates"]), "variant": variant,
                # P23: the prefix is configurable, so the manifest must record
                # the file the seeds were ACTUALLY written to — `_p15_explain.py`
                # indexes into it by `seed_index` and a stale name is an
                # IndexError at best and a wrong join at worst.
                "seed_file": _seed_pref(rank) + variant + ".json",
                "seed_set": LABELA if rank == 0 else LABELB,
                "seed_index": len(per_variant[(rank, variant)]) - 1,
                "base": os.path.basename(path), "base_rank": rank,
                "why": {"alias_canonicals_covered": f"{score[0]}/{nneed}",
                        "governor_compatibility": score[1],
                        "unsteerable_sat_minus_conflict": score[2],
                        "gate_match_minus_conflict": score[3],
                        "cube_literals_evaluated": score[4],
                        "members_walked": score[5], "base_seeds": score[6]},
                # ---- P31: the admissibility of THIS base for THIS cube,
                # recorded per seed so a round can be read without re-deriving
                # it, and so `_p31_drycheck.py` has something to verify.
                "admissibility": GAPTIER.get(g["id"], "?"),
                "pins": [[L, bool(w)] for L, w in sorted(clen.items())],
                "pins_realised_on_base": _pins_ok(clen, dl0, dl1),
                "pins_unrealised_on_base": _pins_bad(clen, dl0, dl1),
                "gates_walked_on_base": _gates_ok(g, em, tm, dfm),
                "values_written": nwrit, "substituted": nsub,
                "empty_pins_existential": nexist,
                "kept_out_of_domain": nkept, "not_seedable": nunres,
                "governor_pins": npin, "governor_pins_inert": ninert,
                "governor_split_pins": nsplit,
                "governor_conflicts": [f"{w}:{L}:{'NZ' if s else 'Z'}"
                                       for L, s, w in rconf],
            })
            stat["seeds"] += 1
            stat["subst"] += nsub
            stat["kept_ood"] += nkept
            stat["unresolved"] += nunres
            if nunres:
                stat["seeds_with_unseedable_member"] += 1
            if score[3] < len(g["gates"]):
                stat["seeds_on_imperfect_gate_base"] += 1
            if score[0] < nneed:
                stat["seeds_with_an_inert_key"] += 1

    # SET A is the PRIMARY batch: the rank-0 base of every gap, i.e. the base
    # that covers every alias canonical the cube is spelled with (verified
    # 5 776/5 776). SET B is the K=2 backup on a second base — useful because
    # 68 % of OD0911's seeded keys were never REACHED, but it is optional and
    # 4 862 of its seeds carry a key the backup base cannot resolve to an
    # ordinal. Drive A first; B only if A leaves gaps.
    ranks_present = sorted({r for (r, _v) in per_variant.keys()}) or [0]
    for rank in ranks_present:
        pref = _seed_pref(rank)
        for v in VARIANTS:
            out = os.path.join(HERE, f"{pref}{v}.json")
            lst = per_variant.get((rank, v), [])
            json.dump(lst, open(out, "w"))
            print(f"  set {LABELA if rank == 0 else LABELB} (rank {rank}) {v}: "
                  f"{len(lst)} seeds -> {os.path.basename(out)}")
    json.dump(manifest, open(os.path.join(HERE, MANOUT), "w"))
    print(f"  manifest -> {MANOUT}")

    print(f"\nseeds built            : {stat['seeds']}  "
          f"({len(gaps)} gaps x K={K})")
    print(f"values substituted     : {stat['subst']} (out-of-domain model value "
          f"replaced by the most-observed value that SATISFIES the cube)")
    print(f"values kept out-of-dom : {stat['kept_ood']} (no observed value satisfies "
          f"the cube's literals on that variable)")
    print(f"values not seedable    : {stat['unresolved']} over "
          f"{len(unresolved_names)} variables, in {stat['seeds_with_unseedable_member']} seeds")
    for k, c in unresolved_names.most_common(10):
        print(f"     x{c:<6} {k[:84]}")
    print("\n-- P31 BASE ADMISSIBILITY (the hard filter)")
    print(f"PIN_HARD={PIN_HARD} GATE_HARD={GATE_HARD} OWN_FIRST={OWN_FIRST} "
          f"GROUP_GATES={GROUP_GATES}")
    if _DISCRIM:
        print(f"[\u00a740.5a] alias-route gates: {_DISCRIM_HITS['added']} added over "
              f"{_DISCRIM_HITS['groups_enriched']} group(s); "
              f"{_DISCRIM_HITS['conflict']} conflict(s) LEFT TO THE CUBE")
    for k, v in TIERSTAT.most_common():
        print(f"   tier {k:<44} {v:5d} gaps")
    for k, v in sorted(OWNSTAT.items()):
        print(f"   {k:<49} {v:5d}")
    npo = sum(1 for m in manifest if m["pins_realised_on_base"])
    ngw = sum(1 for m in manifest if m["gates_walked_on_base"][0] == m["gates_walked_on_base"][1])
    nb = sum(1 for m in manifest if m["pins_realised_on_base"]
             and m["gates_walked_on_base"][0] == m["gates_walked_on_base"][1])
    print(f"   seeds whose base REALISES every cube emptiness pin : "
          f"{npo}/{len(manifest)}   <== the round-8 number was 39/569")
    print(f"   seeds whose base WALKS every enabling gate         : "
          f"{ngw}/{len(manifest)}   <== the round-8 number was 176/569")
    print(f"   seeds admissible on BOTH                           : "
          f"{nb}/{len(manifest)}   <== the round-8 number was  27/569")
    badpin = Counter()
    for m in manifest:
        for x in m["pins_unrealised_on_base"]:
            badpin[x[-64:]] += 1
    for k, v in badpin.most_common(8):
        print(f"      UNREALISED PIN x{v:<5} {k[:66]}")
    json.dump({"tiers": dict(TIERSTAT), "own": dict(OWNSTAT),
               "pins_realised": npo, "gates_walked": ngw, "both": nb,
               "seeds": len(manifest),
               "unrealised": dict(badpin)},
              open(os.path.join(HERE, PINREPORT), "w"))
    print(f"   -> {PINREPORT}")

    print(f"seeds whose base does NOT walk every enabling gate: "
          f"{stat['seeds_on_imperfect_gate_base']} (expected: the gate combination is"
          f" what no run has walked — the SEED pins it, the base only supplies context)")
    print(f"seeds carrying an INERT key (base lacks an alias the name is spelled with): "
          f"{stat['seeds_with_an_inert_key']}")
    print(f"\n-- P18 GOVERNOR PINS (the row-read reach layer)")
    print(f"governor lengths PINNED       : {stat['gov_pins']}  "
          f"(already right on the base: {stat['gov_pin_already_right']})")
    print(f"pins the base cannot spell    : {stat['gov_pin_inert']}")
    print(f"api ordinal the base never makes  : {stat['gov_no_binding']}")
    print(f"api binding that NEVER reads that field: {stat['gov_binding_never_reads']}")
    print(f"api binding with no measured requirement: {stat['gov_binding_unconstrained']}")
    print(f"   of which NECESSITY splits (no api ordinal, >=2 ordinals back the "
          f"canonical): {stat['gov_necessity_splits']}")
    print(f"P31 EXHAUSTED SPLITS RELEASED (one ordinal always keeps the cube's "
          f"state): {stat['gov_split_exhausted_released']} in "
          f"{stat['seeds_with_an_exhausted_split']} seeds")
    print(f"SPLIT PINS (cube empties the canonical, the feeding ordinal is kept): "
          f"{stat['gov_split_pins']} ({stat['gov_split_new_key']} on a key the base "
          f"had no seed for)")
    print(f"P44 §123 EMPTY-PIN EXISTENTIAL (P31_EMPTY_EXISTENTIAL="
          f"{'1' if EMPTY_EXIST else '0'}): "
          f"{stat['empty_pin_existential_base_already_empty']} pins realised on an "
          f"ordinal the base ALREADY held empty, "
          f"{stat['empty_pin_existential_one_ordinal_zeroed']} realised by zeroing "
          f"ONE ordinal; {sum(exist_kept.values())} sibling ordinals LEFT at the "
          f"base's value (previously all were zeroed)")
    if exist_kept:
        for L, c in exist_kept.most_common(6):
            print(f"      kept {c:6d} siblings on "
                  f"{L[len('SYM_LEN_SYM_RESULT_ActiveRecord__'):][:60]}")
    print(f"CUBE CONTRADICTS A REQUIRED GOVERNOR STATE: {stat['gov_conflicts']} "
          f"in {stat['seeds_with_a_gov_conflict']} seeds  <- these leaves are "
          f"infeasible on the chosen base's binding")
    for k, c in gov_conflict_names.most_common(12):
        print(f"     x{c:<6} {k}")
    print("\ntop substituted variables")
    for k, c in subbed_names.most_common(8):
        print(f"     x{c:<6} {k[:84]}")
    print("top kept-out-of-domain variables")
    for k, c in kept_ood.most_common(8):
        print(f"     x{c:<6} {k[:84]}")
    print("\n-- P23 EXTENSIONS")
    print(f"D1 HARD BOTH-WAYS FILTER  groups where it bit: "
          f"{SPLITSTAT['groups_hard_filtered']} "
          f"(bases rejected {SPLITSTAT['bases_rejected']}); "
          f"RELAXED (no both-ways base exists): "
          f"{SPLITSTAT['groups_hard_filter_relaxed']} groups / "
          f"{SPLITSTAT['gaps_hard_filter_relaxed']} gaps")
    print(f"ZEROED-ORDINAL ENABLING PINS  written: {stat['z_ordinal_pins']}  "
          f"dropped (would contradict the cube/governor): "
          f"{stat['z_ordinal_pins_skipped']}  "
          f"[vs cube {stat['z_pin_vs_cube']}, vs governor {stat['z_pin_vs_governor']}, "
          f"self {stat['z_pin_self']}, inert {stat['z_pin_inert']}]")
    print(f"zeroed ordinals with NO measured minting precondition: "
          f"{stat['z_ordinal_no_minting_table']}")
    print(f"P31-CONSTRUCT-DONE {time.time()-t0:.0f}s")


main()
