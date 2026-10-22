#!/usr/bin/env python3
"""Extract HotCRP's access-control policy: policy IR -> rendered artifact.

The last stage of the pipeline. The corpus and its policy IR already exist in
`../hotcrp-typed-policies/results/*/policy.json`; this renders them through
the `php_hotcrp_sql` domain and writes what came out, including everything
that did not.

    python3 extract.py                 # writes views/, review_items.json, summary.json
    python3 extract.py --print         # also dump each artifact to stdout

NOTHING HERE DECIDES ANYTHING. The domain renders and refuses; this script
collects. A refusal is written out with its reason, never dropped -- an
extraction that silently emitted only its successes would read as a complete
policy and be a false one.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.environ.get(
    "CONCOLIC_ENGINE",
    os.path.join(os.path.dirname(os.path.dirname(HERE)), "agentic_concolic_engine"),
)
CORPUS = os.path.join(os.path.dirname(HERE), "hotcrp-typed-policies", "results")

sys.path.insert(0, ENGINE)

from domains import load                                    # noqa: E402
from domains.php_hotcrp_sql.render import render_views      # noqa: E402
from dumps_to_policy.syntax.policy_json import parse_policy  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--print", action="store_true", dest="show")
    args = ap.parse_args()

    if not os.path.isdir(CORPUS):
        raise SystemExit(f"no corpus at {CORPUS}")

    domain = load("php_hotcrp_sql")
    out_views = os.path.join(HERE, "views")
    os.makedirs(out_views, exist_ok=True)

    entries, items, totals = [], [], {"atoms": 0, "rendered": 0, "refused": 0}
    blockers: dict[str, int] = {}

    for d in sorted(os.listdir(CORPUS)):
        path = os.path.join(CORPUS, d, "policy.json")
        if not os.path.isfile(path):
            continue
        with open(path) as fh:
            policy = parse_policy(fh.read())

        artifact = domain.render(policy)
        rendering = render_views(policy, domain.cfg)

        with open(os.path.join(out_views, f"{d}.sql"), "w") as fh:
            fh.write(artifact)
        if args.show:
            print(artifact)

        for item in domain.check(policy):
            items.append(dict(entrypoint=policy.entry.name, **item.to_dict()))
        for _, sym, _ in rendering.unsupported:
            blockers[sym] = blockers.get(sym, 0) + 1

        totals["atoms"] += len(policy.atoms)
        totals["rendered"] += len(rendering.views)
        totals["refused"] += len(rendering.unsupported)
        entries.append({
            "entrypoint": policy.entry.name,
            "file": f"views/{d}.sql",
            "atoms": len(policy.atoms),
            "rendered": len(rendering.views),
            "refused": [{"atom": i, "symbol": s, "reason": r}
                        for i, s, r in rendering.unsupported],
        })

    summary = {
        "domain": domain.name,
        "corpus": os.path.relpath(CORPUS, HERE),
        "entrypoints": len(entries),
        **totals,
        "refusals_by_symbol": dict(sorted(blockers.items(),
                                          key=lambda kv: -kv[1])),
        "entries": entries,
    }
    with open(os.path.join(HERE, "summary.json"), "w") as fh:
        json.dump(summary, fh, indent=2)
        fh.write("\n")
    with open(os.path.join(HERE, "review_items.json"), "w") as fh:
        json.dump(items, fh, indent=2)
        fh.write("\n")

    print(f"{summary['entrypoints']} entrypoints, {summary['atoms']} atoms: "
          f"{summary['rendered']} rendered, {summary['refused']} refused")
    print("refusals by symbol:", summary["refusals_by_symbol"])
    print(f"blocking review items: {sum(1 for i in items if i['blocking'])} "
          f"({sum(1 for i in items if not i['blocking'])} advisory)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
