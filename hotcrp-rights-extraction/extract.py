#!/usr/bin/env python3
"""Drive can_view_paper with rights() computing, then build and render the policy.

A deliberately small driver: a seed grid over the viewer's role and the row
columns, deduplicated by trace, then `build_policy` and the `php_hotcrp_sql`
domain. The sibling `../hotcrp-typed-policies/run_concolic.py` has the full
solver-driven exploration; this one exists to answer a narrower question --
does letting `rights()` compute turn the policy relational -- and a grid
answers that without a second exploration engine.
"""

from __future__ import annotations

import itertools
import json
import pathlib
import subprocess
import sys

import z3

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "agentic_concolic_engine"))

from concolic.coverage import CoverageChecker              # noqa: E402
from concolic.model.run import Run                         # noqa: E402
from domains import load                                   # noqa: E402
from domains.php_hotcrp_sql.render import render_views     # noqa: E402
from dumps_to_policy.build import build_policy             # noqa: E402
from dumps_to_policy.normalize import normalize            # noqa: E402
from dumps_to_policy.syntax.policy_json import print_policy as print_json  # noqa: E402

#: The same 40 entrypoints the sibling corpus covers, so the two are
#: comparable atom for atom: 23 PaperContactInfo predicates and 17 Contact
#: methods.
PCI = ("is_author is_reviewer conflicted unconflicted self_assigned "
       "review_submitted scope_allows can_view allow_admin is_admin "
       "allow_manage can_manage allow_manage_reviews can_manage_reviews "
       "can_manage_tags allow_pc_broad allow_pc allow_author_edit "
       "is_author_view is_conflict_view allow_author_view act_author_view "
       "can_view_decision").split()
CONTACT = ("allow_admin is_admin allow_manage can_manage allow_manage_reviews "
           "can_manage_reviews can_manage_tags act_pc is_author_view "
           "is_conflict_view act_author_view can_view_paper can_view_pdf "
           "can_view_document_history can_view_decision can_view_comment_tags "
           "can_set_decision").split()
ENTRIES = [f"PaperContactInfo::{m}" for m in PCI] + [f"Contact::{m}" for m in CONTACT]

#: The seed grid. `conflictType` spans unconflicted / conflicted / author,
#: `rflags` spans "no review" and "submitted", and the role flags span the
#: four combinations -- which between them is every shape `rights()` branches
#: on for this entrypoint.
#: The starting point. Everything at its zero; the solver finds the rest.
DEFAULTS = {
    "conflictType": 0, "reviewType": 0, "rflags": 0, "roles": 0,
    "timeSubmitted": 0, "timeWithdrawn": 0, "outcome": 0,
    "pdf": False, "bits": 1,
}

#: Stop expanding one entrypoint after this many distinct traces. A budget,
#: not a target: hitting it is reported, never silently accepted.
TRACE_BUDGET = 400


def lower(term, env):
    """Policy-IR term -> a z3 expression, with PHP's signed 64-bit masks.

    Report-local, and deliberately so: the shared solvers treat masks as
    uninterpreted functions, which is right for THEM -- a coverage claim must
    not depend on one language's integer width. Here the job is the opposite,
    generating a seed the PHP will actually replay, so the mask has to mean
    what PHP means. Lifted from ../hotcrp-typed-policies/run_concolic.py.
    """
    if "sym" in term:
        return env[term["sym"]]
    if "lit" in term:
        lit = term["lit"]
        return z3.BoolVal(lit["value"]) if lit["sort"] == "bool" else z3.IntVal(lit["value"])
    args = [lower(a, env) for a in term["args"]]
    op = term["op"]
    if op in ("&", "|", "^", "<<", ">>", "~"):
        a = [z3.Int2BV(x, 64) for x in args]
        b = {"&": lambda: a[0] & a[1], "|": lambda: a[0] | a[1],
             "^": lambda: a[0] ^ a[1], "<<": lambda: a[0] << a[1],
             ">>": lambda: a[0] >> a[1], "~": lambda: ~a[0]}[op]()
        return z3.BV2Int(b, is_signed=True)
    return {"==": lambda: args[0] == args[1], "!=": lambda: args[0] != args[1],
            ">": lambda: args[0] > args[1], ">=": lambda: args[0] >= args[1],
            "<": lambda: args[0] < args[1], "<=": lambda: args[0] <= args[1],
            "not": lambda: z3.Not(args[0]), "and": lambda: z3.And(*args),
            "or": lambda: z3.Or(*args)}[op]()


def candidates(dump):
    """One seed per branch this run took the other way.

    Walks the trace in order, negating each condition against the prefix that
    preceded it -- the standard concolic expansion. A seed is yielded only
    when the solver says the flipped prefix is satisfiable, so every candidate
    is reachable rather than a guess.
    """
    env = {v["name"]: (z3.Bool(v["name"]) if v["type"] == "bool" else z3.Int(v["name"]))
           for v in dump["symbolic_vars"]
           if v.get("origin", {}).get("kind") == "input"}
    if not env:
        return
    solver = z3.Solver()
    solver.set(timeout=10000)
    for name, value in DEFAULTS.items():
        if type(value) is int and name in env:
            solver.add(env[name] >= -(2 ** 63), env[name] < 2 ** 63)
    for event in (e for e in dump["events"] if e["type"] == "path_condition"):
        try:
            condition = lower(event["expr"], env)
        except (KeyError, TypeError):
            continue          # a term this report cannot lower; skip, do not guess
        observed = condition if event["taken"] else z3.Not(condition)
        solver.push()
        solver.add(z3.Not(observed))
        if solver.check() == z3.sat:
            model = solver.model()
            yield {name: (z3.is_true(model.eval(sym, model_completion=True))
                          if type(DEFAULTS[name]) is bool
                          else model.eval(sym, model_completion=True).as_long())
                   for name, sym in env.items()}
        solver.pop()
        solver.add(observed)


def php(requests: list[dict]) -> list[dict]:
    p = subprocess.run(["php", str(HERE / "harness.php")],
                       input=json.dumps(requests), capture_output=True,
                       text=True, timeout=900)
    if p.returncode != 0:
        raise SystemExit(f"harness failed:\n{p.stderr[-2000:]}")
    return json.loads(p.stdout)


def trace(dump: dict) -> tuple:
    return tuple((json.dumps(e["expr"], sort_keys=True), e["taken"])
                 for e in dump["events"] if e["type"] == "path_condition")


def one(entry: str, out: pathlib.Path) -> dict:
    """Drive one entrypoint until the solver offers nothing new."""
    queue = [dict(DEFAULTS)]
    seen_seeds, traces, kept, errors = set(), set(), [], []
    rounds = 0

    while queue and len(kept) < TRACE_BUDGET:
        batch, fresh = [], []
        for seed in queue:
            key = json.dumps(seed, sort_keys=True)
            if key in seen_seeds:
                continue
            seen_seeds.add(key)
            fresh.append(seed)
        if not fresh:
            break
        # ONE php process per round, not per seed: the HotCRP boot costs more
        # than every run in a round put together.
        batch = [{"entry": entry, "label": f"run_{len(seen_seeds) - len(fresh) + i:04}",
                  "seeds": seed} for i, seed in enumerate(fresh)]
        rounds += 1

        queue = []
        for item in php(batch):
            dump = item["dump"]
            if dump.get("error"):
                errors.append(dump["error"]["type"] + ": " + dump["error"]["message"][:160])
                continue
            sig = trace(dump)
            if not sig or sig in traces:
                continue
            traces.add(sig)
            kept.append(dump)
            queue.extend(candidates(dump))

    slug = entry.replace("::", "__")
    row: dict = {"entrypoint": entry, "rounds": rounds, "seeds": len(seen_seeds),
                 "traces": len(kept), "errored": len(errors),
                 "error": errors[0] if errors else None,
                 "budget_hit": len(kept) >= TRACE_BUDGET,
                 "path_conditions": sum(len(trace(d)) for d in kept)}
    if not kept:
        return row | {"atoms": 0, "rendered": 0, "refused": [], "complete": False}

    d = out / slug
    d.mkdir(parents=True, exist_ok=True)
    for stale in d.glob("dump_*.json"):
        stale.unlink()
    for dump in kept:
        (d / f"dump_{dump['label']}.json").write_text(json.dumps(dump, indent=2))

    runs = [Run.from_dict(x) for x in kept]
    coverage = CoverageChecker(runs).check_coverage()
    row["complete"] = coverage.complete
    row["nodes"] = coverage.total_nodes
    row["missing"] = len(coverage.missing)
    policy = normalize(build_policy(runs, entrypoint=entry))
    (d / "policy.json").write_text(print_json(policy) + "\n")

    domain = load("php_hotcrp_sql")
    (d / "policy.sql").write_text(domain.render(policy))
    rendering = render_views(policy, domain.cfg)
    return row | {"atoms": len(policy.atoms), "rendered": len(rendering.views),
                  "refused": [{"atom": i, "symbol": sym, "reason": r}
                              for i, sym, r in rendering.unsupported]}


def main() -> int:
    only = sys.argv[1] if len(sys.argv) > 1 else None
    out = HERE / "results"
    out.mkdir(exist_ok=True)

    rows, atoms, rendered = [], 0, 0
    blockers: dict[str, int] = {}
    for entry in ENTRIES:
        if only and only not in entry:
            continue
        row = one(entry, out)
        rows.append(row)
        atoms += row["atoms"]
        rendered += row["rendered"]
        for r in row["refused"]:
            blockers[r["symbol"]] = blockers.get(r["symbol"], 0) + 1
        flag = "" if not row["errored"] else f"  ERRORED {row['errored']}"
        cov = "complete" if row.get("complete") else f"{row.get('missing', '?')} missing"
        print(f"{row['entrypoint']:46} {row['traces']:3} traces  "
              f"{row['atoms']:2} atoms  {row['rendered']:2} rendered  {cov}{flag}")

    summary = {"entrypoints": len(rows), "atoms": atoms, "rendered": rendered,
               "complete": sum(1 for r in rows if r.get("complete")),
               "refusals_by_symbol": dict(sorted(blockers.items(), key=lambda kv: -kv[1])),
               "entries": rows}
    (HERE / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"\n{len(rows)} entrypoints, {atoms} atoms: {rendered} rendered, "
          f"{summary['complete']} with complete coverage")
    print("refusals by symbol:", summary["refusals_by_symbol"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
