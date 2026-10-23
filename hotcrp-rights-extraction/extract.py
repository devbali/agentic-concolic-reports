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

import json
import logging
import pathlib
import subprocess
import sys

import z3

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "agentic_concolic_engine"))

from concolic.coverage import CoverageChecker              # noqa: E402
from concolic.model.run import Run                         # noqa: E402
from concolic.solver import machine_integers               # noqa: E402
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
#: Row data: the columns `load_into` would have produced.
ROW_DATA = {
    "conflictType": 0, "reviewType": 0, "rflags": 0, "roles": 0,
    "timeSubmitted": 0, "timeWithdrawn": 0, "outcome": 0,
    "pdf": False, "bits": 1,
}

#: CONFERENCE CONFIGURATION (`ConcolicConf` in harness.php). Every one of
#: these answered identically on every run while the Conf was a default one,
#: so `rights()` branched on them without ever DECIDING anything -- 15
#: distinct symbolic decisions measured against ~71 branch points. These are
#: the questions it actually asks.
CONFERENCE = {
    "has_tracks": False, "track_view_sensitive": False,
    "track_view": False, "track_viewpdf": False,
    "allow_conflicted_pc_view": False,
    "time_pc_view": False, "time_pc_view_pdf": False,
    "time_reviewer_view_decision": False,
    "setting_viewrev_ext": 0, "setting_pc_confpdf": 0,
}

#: TWO ARMS, BOTH REPRODUCIBLE, because the comparison between them IS the
#: result. `--rows` measures row data against a default conference and
#: renders views; `--conference` adds the ten questions above, roughly
#: doubles the decisions, and renders almost nothing -- because conference
#: configuration is not row data and no view can express it. Overwriting one
#: corpus with the other would leave that claim uncheckable.
ARMS = {"rows": ROW_DATA, "conference": ROW_DATA | CONFERENCE}

ARM = "conference"
DEFAULTS = ARMS[ARM]

#: Stop expanding one entrypoint after this many distinct traces. A budget,
#: not a target: hitting it is reported, never silently accepted.
TRACE_BUDGET = 6000


def php_int_width() -> int:
    """PHP's integer width, ASKED rather than assumed.

    It is the citation `machine_integers` demands, and asking the same
    interpreter that produced the dumps is a stronger citation than a
    constant in this file: a build with 32-bit integers would answer 4, and
    the declaration below would be wrong in the direction that reports
    coverage that is not there.
    """
    out = subprocess.run(["php", "-r", "echo PHP_INT_SIZE;"],
                         capture_output=True, text=True, check=True)
    return int(out.stdout.strip()) * 8


#: Opened around `check_coverage` and nothing else. Seed generation already
#: lowers masks exactly (`lower()`, below) because a seed must replay in real
#: PHP; the coverage query did NOT, and the asymmetry was the whole defect --
#: the demand universe contained combinations PHP arithmetic forbids
#: (`roles & 4 != 0` with `roles & 15 == 0`, with ROLE_CHAIR inside
#: ROLE_PCLIKE), which no seed could ever discharge. This corpus is one
#: language, so it HAS a width to declare; the shared default stays
#: uninterpreted for corpora that do not.
WIDTH = php_int_width()


class _SolverWarnings(logging.Handler):
    """Fail loudly if the solver drops a constraint it could not parse.

    `check_satisfiability` logs a warning and returns UNSATISFIABLE for an
    expression it cannot evaluate, and under a coverage query an unsat demand
    reads as "nothing missing". That is false completeness arriving by way of
    a log line nobody reads, so the log line is collected and reported.
    """

    def __init__(self) -> None:
        super().__init__(level=logging.WARNING)
        self.seen: list[str] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.seen.append(record.getMessage()[:200])


#: Inputs the harness declares `int?` (see harness.php's `$types`).
#: `Conf::setting()` returns `?int`, and HotCRP reads it as `(… ?? 0)`, so
#: ABSENT is a distinct decision from any integer value. The engine
#: synthesises a companion boolean `__concolic_null__<name>` when it lowers a
#: comparison against null; it is not a declared `symbolic_var`, so a driver
#: that only models the integers can never propose the absent side -- which
#: is exactly what `tree_missing` reported.
NULLABLE = ("setting_viewrev_ext", "setting_pc_confpdf")


def null_sym(name: str) -> str:
    return f"__concolic_null__{name}"


def _null_test(term):
    """`(x == null)` / `(x != null)` -> (symbol, is_equality), else None."""
    if term.get("op") not in ("==", "!="):
        return None
    args = term.get("args") or []
    if len(args) != 2:
        return None
    lits = [a for a in args if "lit" in a and a["lit"].get("sort") == "null"]
    syms = [a for a in args if "sym" in a]
    if len(lits) != 1 or len(syms) != 1:
        return None
    return syms[0]["sym"], term["op"] == "=="


def lower(term, env):
    """Policy-IR term -> a z3 expression, with PHP's signed 64-bit masks.

    Report-local, and deliberately so: the shared solvers treat masks as
    uninterpreted functions, which is right for THEM -- a coverage claim must
    not depend on one language's integer width. Here the job is the opposite,
    generating a seed the PHP will actually replay, so the mask has to mean
    what PHP means. Lifted from ../hotcrp-typed-policies/run_concolic.py.
    """
    probe = _null_test(term)
    if probe is not None:
        name, equality = probe
        absent = env[null_sym(name)]        # KeyError -> skipped by the caller
        return absent if equality else z3.Not(absent)
    if "sym" in term:
        return env[term["sym"]]
    if "lit" in term:
        lit = term["lit"]
        if lit["sort"] == "null":
            # Only ever meaningful against a symbol, which `_null_test`
            # handled above. Anywhere else this report cannot lower it.
            raise KeyError("bare null literal")
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
    inputs = [v for v in dump["symbolic_vars"]
              if v.get("origin", {}).get("kind") == "input"]
    env = {v["name"]: (z3.Bool(v["name"]) if v["type"] == "bool"
                       else z3.Int(v["name"])) for v in inputs}
    # The null companions, so the ABSENT side of a nullable is reachable.
    env.update({null_sym(v["name"]): z3.Bool(null_sym(v["name"]))
                for v in inputs if v["type"].endswith("?")})
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
            yield _seed_from(solver.model(), env)
        solver.pop()
        solver.add(observed)


def _seed_from(model, env) -> dict:
    """A model -> the seed dict the harness takes.

    A nullable whose companion is true is seeded as `None`, which reaches the
    harness as PHP `null` -- the whole point of modelling the companion.
    """
    def value(name):
        got = model.eval(env[name], model_completion=True)
        return z3.is_true(got) if type(DEFAULTS[name]) is bool else got.as_long()

    seed = {}
    for name in DEFAULTS:
        if name not in env:
            continue
        absent = null_sym(name)
        if absent in env and z3.is_true(model.eval(env[absent],
                                                   model_completion=True)):
            seed[name] = None
        else:
            seed[name] = value(name)
    return seed


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


def witness_seeds(coverage) -> list[dict]:
    """The checker's own witness for each missing demand, as a seed.

    `MissingCoverage.concrete_values` is "a VERDICT plus an actionable
    witness" (`concolic/coverage.py`) -- the assignment that reaches the
    combination no run took. Under the declared width those values are
    representable PHP integers, so they can be handed straight back to the
    harness; under the uninterpreted default they could not, which is why
    this feedback edge only became usable with the lowering.

    An `untracked` miss is excluded by a declared assumption and is not a
    gap to drive, so it is not seeded.
    """
    out = []
    for m in coverage.missing:
        if m.untracked or not m.concrete_values:
            continue
        seed = dict(DEFAULTS)
        for name, value in m.concrete_values.items():
            if name in seed:
                seed[name] = (bool(value) if type(seed[name]) is bool
                              else int(value))
            elif name.startswith("__concolic_null__") and value:
                # the checker is asking for the ABSENT side of a nullable
                bare = name[len("__concolic_null__"):]
                if bare in seed:
                    seed[bare] = None
        out.append(seed)
    return out


def measure(kept: list[dict]):
    """`check_coverage` under PHP's integer semantics, with the solver watched."""
    runs = [Run.from_dict(x) for x in kept]
    guard = _SolverWarnings()
    logging.getLogger("concolic.solver").addHandler(guard)
    try:
        with machine_integers(WIDTH, signed=True,
                              cite=f"php -r 'echo PHP_INT_SIZE' == {WIDTH // 8}"):
            # SUB-CONJUNCTION FORECLOSURE, and why this corpus needs it.
            # Pairwise foreclosure cannot see a decision that only two gates
            # ACTING TOGETHER remove from the path, and that is exactly what
            # HotCRP does: an unconflicted chair returns before `outcome` is
            # ever read, so neither `roles & 4` nor `conflictType <= 1` alone
            # forecloses it. The flag is an INFERENCE over the corpus, not a
            # declaration -- any run matching the prefix that DOES evaluate
            # the member removes it on the next pass -- and it is reported
            # non-provisional only while `tree_complete` holds, which is the
            # precondition the lowering above is what finally established.
            checker = CoverageChecker(runs, foreclosure_conjunctions=True,
                                      foreclosure_subconjunctions=True)
            return checker.check_coverage(), guard.seen
    finally:
        logging.getLogger("concolic.solver").removeHandler(guard)


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

        # THE FEEDBACK EDGE. Prefix negation flips ONE decision against the
        # path that preceded it, so a demand that needs several decisions to
        # line up at once is not a seed it can propose. The coverage checker
        # computes exactly that assignment, so when the queue runs dry its
        # witnesses refill it -- and the loop ends when driving them stops
        # producing a trace nobody has seen.
        if not queue and kept:
            coverage, _ = measure(kept)
            queue = witness_seeds(coverage)

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
    coverage, warnings = measure(kept)
    row["complete"] = coverage.complete
    row["tree_complete"] = coverage.tree_complete
    row["truncated"] = coverage.truncated
    row["solver_lost"] = coverage.solver_lost
    row["subconjunction_foreclosures"] = coverage.subconjunction_foreclosures
    row["foreclosures_provisional"] = coverage.subconjunction_foreclosures_provisional
    row["nodes"] = coverage.total_nodes
    row["missing"] = len(coverage.missing)
    row["dropped_constraints"] = len(warnings)
    if warnings:
        # Not a warning to skim: a dropped constraint makes a demand look
        # discharged, so `complete` here would be a claim this run cannot make.
        row["complete"] = False
        row["solver_warning"] = warnings[0]
    policy = normalize(build_policy(runs, entrypoint=entry))
    (d / "policy.json").write_text(print_json(policy) + "\n")

    domain = load("php_hotcrp_sql")
    (d / "policy.sql").write_text(domain.render(policy))
    rendering = render_views(policy, domain.cfg)
    return row | {"atoms": len(policy.atoms), "rendered": len(rendering.views),
                  "refused": [{"atom": i, "symbol": sym, "reason": r}
                              for i, sym, r in rendering.unsupported]}


def main() -> int:
    global ARM, DEFAULTS
    args = sys.argv[1:]
    for flag in list(args):
        if flag.startswith("--") and flag[2:] in ARMS:
            ARM, args = flag[2:], [a for a in args if a != flag]
    DEFAULTS = ARMS[ARM]
    only = args[0] if args else None
    # One directory per arm, so neither overwrites the other.
    out = HERE / ("results" if ARM == "rows" else f"results_{ARM}")
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

    summary = {"arm": ARM, "symbolic_inputs": sorted(DEFAULTS),
               "entrypoints": len(rows), "atoms": atoms, "rendered": rendered,
               "integer_semantics": {"width": WIDTH, "signed": True,
                                     "cite": "php -r 'echo PHP_INT_SIZE'"},
               "complete": sum(1 for r in rows if r.get("complete")),
               "refusals_by_symbol": dict(sorted(blockers.items(), key=lambda kv: -kv[1])),
               "entries": rows}
    (HERE / f"summary_{ARM}.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"\n{len(rows)} entrypoints, {atoms} atoms: {rendered} rendered, "
          f"{summary['complete']} with complete coverage")
    print("refusals by symbol:", summary["refusals_by_symbol"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
