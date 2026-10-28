#!/usr/bin/env python3
"""Build DESIGN_SWEEP §6.3's `in/policy.json` from an APPROVED packet's corpus.

    build_policy_ir.py <dumps-dir> <out.json> [--entrypoint NAME]

§6.3 mounts `in/policy.json` — "the policy IR — the normalised atom list the
SQL is rendered from" (the domain's own concrete brief) — and names no producer
for it, because producing one is the CALLER's: `sweep/` may not import
`dumps_to_policy` any more than it may import `domains`, and the corpus a
policy is built from is the one the pre-gate just approved, which only the
campaign knows. So this sits beside `drive.py` and not in `src_new/`.

It is `dumps_to_policy`'s own pipeline and adds nothing to it:

    dump_*.json  -> Run.from_dict        (the dump IR's own reader)
                 -> build_policy         (§6: atoms, unmerged)
                 -> normalize_detailed   (§6.3: merge, then simplify)
                 -> policy_json.to_json  (§10's wire form)

WHY NORMALIZED AND NOT RAW. `domains/ruby_rails_sql/checks.py::_corpus_shapes`
walks `policy.atoms[].events[].note`, and the brief calls `in/policy.json` "the
NORMALISED atom list". An unmerged policy carries the same note under several
atoms, which changes no shape (the right-hand side is a SET of shapes) but does
make the document several times larger than the one the SQL is rendered from —
and the document a check reads should be the document that ships.

THE CERTIFICATE'S ATOM COUNT IS RE-STAMPED after normalization, exactly as
`reports/autolab/shakedown/tools/pipeline.py` does it: `print_policy` and
`to_json` both re-check `certificate.atoms` against `len(policy.atoms)` (§10.2)
and normalization changes that count, so a policy carrying the pre-merge count
is refused by its own codec.

Needs `/home/dev/project/venvs/queries_from_runs/bin/python3` — `dumps_to_policy`
pulls in `z3` and `sqlglot`.
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import sys
from pathlib import Path

sys.path.insert(0, "/home/dev/project/src_new")

from concolic.model import Run                                    # noqa: E402
from dumps_to_policy.build import build_policy                    # noqa: E402
from dumps_to_policy.certificate import Certificate               # noqa: E402
from dumps_to_policy.normalize import normalize_detailed          # noqa: E402
from dumps_to_policy.syntax.policy_json import to_json            # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dumps")
    ap.add_argument("out")
    ap.add_argument("--entrypoint", default="")
    ap.add_argument("--app", default="")
    args = ap.parse_args(argv)

    files = sorted(Path(args.dumps).glob("dump_*.json"))
    if not files:
        print(f"error: no dump_*.json under {args.dumps}", file=sys.stderr)
        return 2
    runs = []
    for f in files:
        runs.append(Run.from_dict(json.loads(f.read_text())))
    entrypoint = args.entrypoint or (getattr(runs[0], "entrypoint", "") or "")
    if not entrypoint:
        print("error: no --entrypoint and no dump names one", file=sys.stderr)
        return 2

    policy = build_policy(runs, entrypoint=entrypoint,
                          certificate=Certificate(app=args.app or entrypoint))
    normed, report = normalize_detailed(policy)
    base = normed.certificate or policy.certificate
    normed = dataclasses.replace(
        normed, certificate=base.with_atoms(len(normed.atoms))
                                .with_minimal(report.minimal))
    doc = to_json(normed, meta={
        "produced_by": "reports/autolab/local_cvd4/tools/build_policy_ir.py",
        "dumps": [f.name for f in files],
        "entrypoint": entrypoint})
    Path(args.out).write_text(json.dumps(doc, indent=1, sort_keys=True))
    n_notes = sum(1 for a in normed.atoms for e in a.events
                  if getattr(e, "note", None))
    print(f"[policy] runs={len(runs)} atoms_unmerged={len(policy.atoms)} "
          f"atoms={len(normed.atoms)} minimal={report.minimal} "
          f"notes={n_notes} -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
