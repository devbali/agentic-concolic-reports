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

ENTRY = "Contact::can_view_paper"

#: The seed grid. `conflictType` spans unconflicted / conflicted / author,
#: `rflags` spans "no review" and "submitted", and the role flags span the
#: four combinations -- which between them is every shape `rights()` branches
#: on for this entrypoint.
GRID = {
    "conflictType": [0, 2, 32, 64],
    "reviewType": [0, 1],
    "rflags": [0, 4096],
    # ContactInfo.roles: none, PC, chair+PC. The masks HotCRP takes off it
    # are ROLE_PC = 1, ROLE_ADMIN = 2, ROLE_CHAIR = 4.
    "roles": [0, 1, 5],
    "timeSubmitted": [0, 100],
    "timeWithdrawn": [0],
    "outcome": [0],
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


def main() -> int:
    out = HERE / "results"
    out.mkdir(exist_ok=True)
    for stale in out.glob("dump_*.json"):
        stale.unlink()

    keys = list(GRID)
    requests = [
        {"entry": ENTRY, "label": f"run_{i:03}",
         "seeds": dict(zip(keys, combo))}
        for i, combo in enumerate(itertools.product(*GRID.values()))
    ]
    print(f"{len(requests)} seeds over {ENTRY}")

    seen, kept, errors = set(), [], []
    for item in php(requests):
        dump = item["dump"]
        if dump.get("error"):
            errors.append(dump["error"]["type"] + ": " + dump["error"]["message"][:120])
            continue
        sig = trace(dump)
        if not sig or sig in seen:
            continue
        seen.add(sig)
        kept.append(dump)

    if errors:
        print(f"  {len(errors)} errored run(s); first: {errors[0]}")
    print(f"{len(kept)} distinct traces, "
          f"{sum(len(trace(d)) for d in kept)} path conditions")

    for dump in kept:
        (out / f"dump_{dump['label']}.json").write_text(json.dumps(dump, indent=2))

    runs = [Run.from_dict(d) for d in kept]
    coverage = CoverageChecker(runs).check_coverage()
    policy = normalize(build_policy(runs, entrypoint=ENTRY))
    (HERE / "policy.json").write_text(print_json(policy) + "\n")

    domain = load("php_hotcrp_sql")
    artifact = domain.render(policy)
    (HERE / "policy.sql").write_text(artifact)

    rendering = render_views(policy, domain.cfg)
    print(f"coverage: complete={coverage.complete} nodes={coverage.total_nodes}")
    print(f"policy: {len(policy.atoms)} atoms -> "
          f"{len(rendering.views)} rendered, {len(rendering.unsupported)} refused")
    print()
    print(artifact)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
