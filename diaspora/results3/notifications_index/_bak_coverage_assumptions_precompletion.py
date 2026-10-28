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
    n_t2 = 0
    for e in exprs:
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
