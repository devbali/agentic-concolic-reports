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
GRID = {
    # unconflicted / conflicted / author / contact-author
    "conflictType": [0, 2, 32, 64],
    "reviewType": [0, 1],
    # 0, RF_SUBMITTED (0x1000), RF_SELF_ASSIGNED (0x20000). Without the
    # last one `self_assigned` has no allowed run and so yields no atom --
    # a gap in the GRID, not in the application.
    "rflags": [0, 4096, 131072],
    # ContactInfo.roles: none, PC, chair+PC. The masks HotCRP takes off it
    # are ROLE_PC = 1, ROLE_ADMIN = 2, ROLE_CHAIR = 4.
    "roles": [0, 1, 5],
    "timeSubmitted": [0, 100],
    "timeWithdrawn": [0],
    "outcome": [0],
    # Arguments, not data: `can_view($pdf)` and `scope_allows($bits)`.
    "pdf": [False, True],
    "bits": [1],
}


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
    """Explore one entrypoint and render its policy."""
    keys = list(GRID)
    requests = [
        {"entry": entry, "label": f"run_{i:03}", "seeds": dict(zip(keys, combo))}
        for i, combo in enumerate(itertools.product(*GRID.values()))
    ]

    seen, kept, errors = set(), [], []
    for item in php(requests):
        dump = item["dump"]
        if dump.get("error"):
            errors.append(dump["error"]["type"] + ": " + dump["error"]["message"][:160])
            continue
        sig = trace(dump)
        if not sig or sig in seen:
            continue
        seen.add(sig)
        kept.append(dump)

    slug = entry.replace("::", "__")
    row: dict = {"entrypoint": entry, "seeds": len(requests), "traces": len(kept),
           "errored": len(errors), "error": errors[0] if errors else None,
           "path_conditions": sum(len(trace(d)) for d in kept)}
    if not kept:
        return row | {"atoms": 0, "rendered": 0, "refused": []}

    d = out / slug
    d.mkdir(parents=True, exist_ok=True)
    for stale in d.glob("dump_*.json"):
        stale.unlink()
    for dump in kept:
        (d / f"dump_{dump['label']}.json").write_text(json.dumps(dump, indent=2))

    runs = [Run.from_dict(x) for x in kept]
    # Coverage is reported, never assumed. These policies are sound AS
    # OBSERVED -- every disjunct is a path some run really took -- but a
    # disjunction is only the WHOLE policy if every path was explored, and
    # the grid is a grid, not a solver. An incomplete entrypoint's view may
    # be NARROWER than the application, which is the dangerous direction.
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
