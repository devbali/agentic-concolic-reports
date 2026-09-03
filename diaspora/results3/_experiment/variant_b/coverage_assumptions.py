#!/usr/bin/env python3
"""notifications_index — batch-local AssumptionSet (gen3, 2026-08-19).

FULL REWRITE for the gen3 corpus (all 8 STI type profiles driven; Person#name
/ as_api_response mocks removed per rule (b); see ../BUGFIXES_20260819.md and
REPORT.md). The gen2 file's hand-enumerated tiers were verified STALE on
gen3 (the first_1 ordinal no longer denotes one call site across runs once
the new code paths landed), so gen3 derives every assumption FROM THE RUNS
at check time, restricted to structurally-argued classes:

Tier 0 — TYPE-VARIANT EXCLUSIVITY (sound by construction). Every run takes
  exactly one SYM_NOTE_TYPE_PROFILE value (a per-run seeded decision,
  targets.rb §5f); exprs whose observed type-sets are disjoint can never
  co-occur in one run. Same auto-derivation as results3/posts_show's and
  conversations_index's Tier 0 — set membership of observed (expr, type)
  pairs only, no reliance on ordinal meaning.

Tier 1 — EXISTENCE-FORECLOSURE, class-restricted. A pair (guard@side, B) is
  declared independent ONLY when (a) empirically guard@side never co-occurs
  with B over the full corpus (0 violations, with both populations >= 100
  runs and B observed BOTH ways on the other side or B one-sided), AND (b)
  the pair matches one of the argued structural classes:
    - same-variable ==/!= or ==0/==1 chains (the second compare's call site
      executes only on one side of the first — value/short-circuit forced);
    - not_found gates same-prefix attribute exprs (finder_mock's if/else:
      the found-arm symbolic_instance mints the attrs; the not_found arm
      returns before they exist);
    - _persisted gates association reads on the same subject (flipped
      persistence routes Rails' null_scope?/loaded paths around the
      count/records mocks — collection_association.rb:286-294);
    - count-chain gates (count==0 short-circuits later reads of the same
      association / the i18n pluralization ==1 compare).
  Pairs failing the class filter are NOT declared, whatever the counts say
  — they stay in the demand space and block completeness honestly.

Tier 2 — ONE-SIDED VALUE-FORCED exprs: the Journey-formatter
  `guid != StringVal('')` shapes record only inside the guid-empty region
  where their outcome is value-forced False (see gen2's derivation — the
  mechanism carried to gen3 and re-verified on this corpus). Declared
  OneSideUntracked(tracked_side=not_taken).
"""
from __future__ import annotations

import re
import sys

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.assumptions import (  # noqa: E402
    AssumptionSet,
    IndependenceAssumption,
    OneSideUntrackedPathAssumption,
)

_MIN_POP = 100

_ONE_SIDED_VALUE_FORCED = (
    re.compile(r"_guid != StringVal\(''\)\)$"),
)

# ---------------------------------------------------------------------------
# variant_b T2 assumption-probe blocklist (DISCIPLINE_TESTS.md T2 + Bali's
# 2026-08-19 data-flow-divergence upgrade). Populated from
# ASSUMPTION_PROBES.md / ASSUMPTION_FLOW.json: a Tier-1 CLASS or the Tier-2
# one-sided class is declared here ONLY after a directed concrete dual-run
# probe mechanically confirms (a) the two runs' executed-line sets first
# diverge at the guard's own cited code site and (b) the foreclosed expr's
# recording-site lines are present on the recording side and absent on the
# foreclosing side. "same-var-chain" and Tier 0 (type-variant exclusivity)
# are sound BY CONSTRUCTION (identical Z3 variable / disjoint per-run type
# sets) and are not subject to this blocklist, per DISCIPLINE_TESTS.md
# ("Tier 0 ... is sound by construction but still probe ONE representative
# pair as a sanity check" — done, see ASSUMPTION_PROBES.md).
#
# PROBED AND PASSED (see ASSUMPTION_PROBES.md for the run pair + evidence):
#   - "finder-arm": SYM_RESULT_...FinderMethods_first_1_not_found forced
#     True/False; found-arm attrs (_guid/_id/_persisted) present only on
#     the not_found=False side (0/24 vs 3/27 -- clean disjoint sets).
#   - "persisted-gate": SYM_RESULT_...to_ary_1_row_persisted forced
#     False/True; the notification row's has_many-through `actors`
#     collection's count_records-derived PCs (count_3/count_4 family) are
#     present only on persisted=True. Coverage divergence confirmed at the
#     cited mechanism: targets.rb's CollectionAssociation#size shim
#     (lines ~593-597) and collection_association.rb's null_scope? build
#     (lines 287-293) diverge between the two runs; has_many_association.rb
#     count_records (lines 63-74) has 0 hits on the foreclosing side and 2
#     on the recording side.
#
# NOT PROBED WITHIN THE AVAILABLE TIME -- BLOCKED, not declared:
#   - "count-chain": no genuine cross-variable (guard-is-a-count,
#     forecloses-a-DIFFERENT-expr) instance was found in this entrypoint's
#     default scenarios to build a directed probe from. In `_same_class`
#     below, "_persisted" is checked before "_count", so a guard matching
#     BOTH (e.g. a persisted-decision var) classifies as persisted-gate;
#     a genuinely count-chain-classified pair needs a guard var whose name
#     contains "_count" but not "_persisted" -- no such guard was observed
#     active in the corpus available to this probe. Reported honestly per
#     DISCIPLINE_TESTS.md rather than declared on inspection alone.
_T2_BLOCKED_CLASSES = frozenset({"count-chain"})
_T2_ONE_SIDED_PROBED_OK = False  # Tier 2 (guid != '') -- see below.


def _var(expr: str) -> str:
    m = re.match(r"\(?(?:Not\()?\(?(\S+)\s", expr)
    return m.group(1) if m else expr


def _prefix(expr: str) -> str:
    """Result-name prefix up to the ordinal, e.g. ...FinderMethods_first_1."""
    m = re.match(r"\((SYM_RESULT_\S+?_\d+)", expr)
    return m.group(1) if m else ""


def _same_class(guard: str, side: bool, b: str) -> str | None:
    gv, bv = _var(guard), _var(b)
    if gv == bv:
        return "same-var-chain"
    gp, bp = _prefix(guard), _prefix(b)
    if "not_found" in gv and side is True and gp and gp == bp:
        return "finder-arm"
    if "_persisted" in gv:
        return "persisted-gate"
    if "_count" in gv:
        return "count-chain"
    return None


def build(runs=None) -> AssumptionSet:
    a = AssumptionSet()
    if not runs:
        return a

    per_run = []
    for r in runs:
        pcs = {}
        for pc in r.path_conditions:
            pcs.setdefault(pc.expr, pc.taken)
        t = None
        for k in range(8):
            if pcs.get(f"(SYM_NOTE_TYPE_PROFILE == {k})") is True:
                t = k
        per_run.append((pcs, t))
    exprs = sorted({e for pcs, _ in per_run for e in pcs})

    # ---- Tier 0: type-variant exclusivity --------------------------------
    tof = {}
    for pcs, t in per_run:
        for e in pcs:
            tof.setdefault(e, set()).add(t)
    n_t0 = 0
    for i, ea in enumerate(exprs):
        for eb in exprs[i + 1:]:
            if tof[ea].isdisjoint(tof[eb]):
                a.add(IndependenceAssumption(
                    expr_a=ea, expr_b=eb,
                    description=f"type-variant exclusivity: {sorted(tof[ea])} vs {sorted(tof[eb])}",
                    agent_notes=(
                        "One run takes exactly one SYM_NOTE_TYPE_PROFILE value "
                        "(targets.rb §5f seeded decision); these exprs' observed "
                        "type-sets are disjoint over the full corpus, so no "
                        "single run can record both. Set-membership argument "
                        "only — no ordinal meaning relied on."
                    ),
                ))
                n_t0 += 1

    # ---- Tier 1: class-restricted existence-foreclosure ------------------
    n_t1 = 0
    for guard in exprs:
        for side in (True, False):
            n_side = sum(1 for pcs, _ in per_run if pcs.get(guard) == side)
            if n_side < _MIN_POP:
                continue
            for b in exprs:
                if b == guard or not tof[guard] & tof[b]:
                    continue
                cls = _same_class(guard, side, b)
                if cls is None:
                    continue
                if cls in _T2_BLOCKED_CLASSES:
                    # T2 assumption-probe blocklist (see module header): this
                    # class has no mechanical directed-probe PASS on file for
                    # variant_b -- stays undeclared regardless of corpus
                    # counts, per DISCIPLINE_TESTS.md ("A class whose probe
                    # fails (either direction) is not declared").
                    continue
                viol = sum(1 for pcs, _ in per_run
                           if pcs.get(guard) == side and b in pcs)
                other = sum(1 for pcs, _ in per_run
                            if guard in pcs and pcs.get(guard) != side and b in pcs)
                if viol == 0 and other >= _MIN_POP:
                    a.add(IndependenceAssumption(
                        expr_a=guard, expr_b=b,
                        description=f"existence-foreclosure [{cls}]",
                        agent_notes=(
                            f"Class '{cls}' (module docstring): on the "
                            f"side={side} arm of the guard the code that would "
                            f"record `{b}` never runs. Corpus: 0/{n_side} "
                            f"guard-side co-occurrences; {other} recording-side "
                            "observations."
                        ),
                    ))
                    n_t1 += 1

    # ---- Tier 2: one-sided value-forced ----------------------------------
    # T2 assumption-probe blocklist: no directed dual-run probe reached the
    # `guid != StringVal('')` recording site within variant_b's available
    # probing time (see ASSUMPTION_PROBES.md) -- undeclared per
    # DISCIPLINE_TESTS.md's "or the probe is inconclusive and the
    # assumption stays undeclared."
    n_t2 = 0
    for e in exprs:
        if not _T2_ONE_SIDED_PROBED_OK:
            break
        if not any(p.search(e) for p in _ONE_SIDED_VALUE_FORCED):
            continue
        sides = {pcs[e] for pcs, _ in per_run if e in pcs}
        if sides == {False}:
            a.add(OneSideUntrackedPathAssumption(
                expr=e, tracked_side="not_taken",
                description="Journey-formatter guid != '' value-forced False "
                             "at its only recording site",
                agent_notes=(
                    "Records only inside the guid-empty region (same-var "
                    "chain), where the value forces False; taken=True is "
                    "unobservable by construction. Re-verified on the gen3 "
                    "corpus: every recording is False."
                ),
            ))
            n_t2 += 1

    print(f"[assumptions] tier0={n_t0} tier1={n_t1} tier2={n_t2}",
          file=sys.stderr)
    return a
