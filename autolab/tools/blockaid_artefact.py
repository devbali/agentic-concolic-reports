#!/usr/bin/env python3
"""blockaid_artefact.py — run the blockaid/subsume checker over a finished run.

WHAT THE ARTEFACT IS
--------------------
`domains/ruby_rails_sql/` wraps a JVM checker built on blockaid (Calcite + H2 +
Z3): `subsume_harness/check_subsumed.sh`, `subsume_solver.py`,
`subsume.py`.  Given a set of SQL views it answers, with a proof or a
counterexample, questions of the form "is THIS query answerable from THOSE
views".  That is the only blockaid question the repo's harness exposes, and it
is asked in two shapes:

    pairwise   in  {"queries": [v0, v1, …]}
               out {"subsumed": [[i, j], …], "errors": {"i": "why not"}}
               `[i, j]` = view i is answerable from view j, so i is redundant.

    coverage   in  {"views": [...], "queries": [...]}
               out {"covered": [true|false|null, …], "view_errors": {…}}

This tool produces the PAIRWISE shape over an endpoint's rendered policy
views, because that is the shape whose inputs this corpus actually has.  Two
things fall out of one call and both are the artefact:

  * **loadability** — which rendered views blockaid can load and type at all.
    A view it rejects is reported in `errors` with blockaid's own message, and
    it is quarantined: it takes no part in any verdict.
  * **redundancy** — which loadable views are subsumed by another, solver-
    proved rather than string-matched.  Every `rendered.sql` in this corpus
    says in its own header that its subsumption is SYNTACTIC ONLY and that
    "the solver-backed checker is not run from a render".  This is that run.

WHAT IS NOT PRODUCED, AND WHY
-----------------------------
The coverage shape is not produced, because the QUERY side does not exist in a
form blockaid can read.  The SELECTs the endpoint actually issued are recorded
in the dumps as notes of the form

    {"refs": {"p0": "SYM_PARAM_id"}, "text": "SELECT ... WHERE id = $$(p0)"}

— every one of them carries unresolved symbolic binds, so a query set could
only be built by declaring each bind an unconstrained constant, which asserts
"this could be any value" where the run proves it is one specific join target.
That is over-permissive in the direction that matters, so this tool refuses to
build it and records the refusal instead.  See `blockaid/README.md`.

MODES
-----
`asis`                views exactly as rendered.  The honest measurement.
`binds_as_constants`  each `` `_cN.field` `` bind rewritten to a declared
                      constant `_CN_FIELD`, so that the views blockaid
                      quarantined in `asis` can be loaded and the redundancy
                      question can be asked of the WHOLE policy.  This is a
                      DIAGNOSTIC, explicitly over-permissive, and it is
                      labelled as such in the output.  It is what isolates
                      "blockaid cannot read this" from "the policy is
                      unloadable for some other reason".

Usage:
    blockaid_artefact.py <finished-run-dir> [<finished-run-dir> …]
                         [--timeout-ms N] [--threads N]
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path("/home/dev/project")
HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "blockaid"
CONFIG = OUT / "config" / "app.json"
#: the src/ harness, not src_new's: `src_new/domains/ruby_rails_sql/blockaid/`
#: is an uninitialised git submodule (its working directory is empty), so the
#: src_new script cannot find the jar and dies with NoClassDefFoundError on
#: org/apache/calcite/sql/validate/SqlConformance.  Same checker, same
#: classes; this one's sibling `blockaid/target/` holds the built jar.
CHECKER = ROOT / "src/queries_from_runs/subsume/check_subsumed.sh"

#: the three bind spellings the renderer emits: `_c1.id`, the
#: element form `_c2[any].author_id`, and the row form
#: `_c5.row2_person_id` (the last needs no extra rule -- `row2_x`
#: is already an identifier after the dot).
_BIND = re.compile(r"`(_c\d+)(\[any\])?\.([A-Za-z_][A-Za-z0-9_]*)`")


def views_of(sql_path: Path) -> list[str]:
    """Every rendered view, one per statement, comments and `;` stripped."""
    out = []
    for line in sql_path.read_text().splitlines():
        s = line.split("--")[0].strip().rstrip(";").strip()
        if s.upper().startswith("SELECT"):
            out.append(s)
    return out


def rewrite_binds(views: list[str]) -> tuple[list[str], dict[str, str]]:
    consts: dict[str, str] = {}

    def sub(m):
        any_ = "_ANY" if m.group(2) else ""
        name = f"_{m.group(1)[1:].upper()}{any_}_{m.group(3).upper()}"
        # every bind this corpus emits is an id or a foreign key
        consts[name] = "int"
        return name

    return [_BIND.sub(sub, v) for v in views], consts


def const_decls(extra: dict[str, str]) -> str:
    base = {"_MY_UID": "int"}
    base.update(extra)
    return "".join(f"{k}:{v};\n" for k, v in sorted(base.items()))


def run_checker(views: list[str], extra_consts: dict[str, str],
                timeout_ms: int, threads: int) -> dict:
    decls = OUT / "config" / "resources" / "const-decls.txt"
    prev = decls.read_text()
    decls.write_text(const_decls(extra_consts))
    env = dict(os.environ)
    env.pop("JAVA_TOOL_OPTIONS", None)      # a leaked value breaks the JVM run
    env["QFR_APP_CONFIG"] = str(CONFIG)
    env["SUBSUME_TIMEOUT_MS"] = str(timeout_ms)
    env["SUBSUME_SOLVER_THREADS"] = str(threads)
    payload = json.dumps({"queries": views})
    t0 = _dt.datetime.now()
    try:
        p = subprocess.run([str(CHECKER)], input=payload.encode(),
                           capture_output=True, env=env, timeout=3600)
        raw = p.stdout.decode("utf8", "replace").strip()
        try:
            res = json.loads(raw)
        except Exception:
            res = {"_harness_error": "checker produced no JSON",
                   "_stdout": raw[-2000:],
                   "_stderr": p.stderr.decode("utf8", "replace")[-2000:],
                   "_rc": p.returncode}
    finally:
        decls.write_text(prev)
    res["_wall_seconds"] = round((_dt.datetime.now() - t0).total_seconds(), 1)
    return res


def artefact(run_dir: Path, timeout_ms: int, threads: int) -> dict:
    sql = run_dir / "rendered.sql"
    if not sql.exists():
        return {"ok": False, "reason": "the run has no rendered.sql"}
    views = views_of(sql)
    rec: dict = {
        "views_in_policy": len(views),
        "checker": str(CHECKER.relative_to(ROOT)),
        "app_config": str(CONFIG.relative_to(ROOT)),
        "timeout_ms": timeout_ms,
        "solver_threads": threads,
        "modes": {},
    }
    for mode in ("asis", "binds_as_constants"):
        if mode == "asis":
            vs, extra = views, {}
        else:
            vs, extra = rewrite_binds(views)
            if vs == views:
                rec["modes"][mode] = {
                    "skipped": "no `_cN.field` bind appears in these views, so "
                               "this mode would be identical to `asis`"}
                continue
        out = run_checker(vs, extra, timeout_ms, threads)
        errs = out.get("errors") or {}
        pairs = out.get("subsumed") or []
        rec["modes"][mode] = {
            "over_permissive_diagnostic": mode == "binds_as_constants",
            "declared_constants": sorted(extra),
            "views_submitted": len(vs),
            "views_blockaid_could_load": len(vs) - len(errs),
            "views_quarantined": len(errs),
            "quarantine": {k: v for k, v in sorted(errs.items(),
                                                   key=lambda kv: int(kv[0]))},
            "subsumed_pairs": pairs,
            "redundant_views": sorted({i for i, _ in pairs}),
            "reading_subsumed_pairs": (
                "a pair ABSENT from `subsumed_pairs` was NOT PROVED subsumed "
                "within the timeout. The checker does not report which pairs "
                "it decided and which it abandoned, and an undecided pair and "
                "a proved-distinct pair are the same absence here, so an empty "
                "list means `nothing proved redundant`, never `nothing is`. "
                "A non-subsumed pair costs the FULL timeout, so the wall time "
                "below is the only hint at how many were abandoned: an "
                "all-decided run finishes well under "
                "n*(n-1)*timeout/threads."),
            "wall_seconds": out.get("_wall_seconds"),
            "checker_output_verbatim": {k: v for k, v in out.items()
                                        if not k.startswith("_wall")},
            "views": vs,
        }
    return {"ok": True, **rec}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir", nargs="+")
    ap.add_argument("--timeout-ms", type=int, default=5000)
    ap.add_argument("--threads", type=int, default=3)
    args = ap.parse_args()
    for rd in args.run_dir:
        run_dir = Path(rd).resolve()
        parts = run_dir.relative_to(OUT.parent / "endpoints").parts
        ep, prov, rid = parts[0], parts[1], parts[2]
        dst = OUT / "endpoints" / ep / prov / rid
        dst.mkdir(parents=True, exist_ok=True)
        rec = artefact(run_dir, args.timeout_ms, args.threads)
        rec.update({
            "endpoint": ep, "provenance": prov, "run_id": rid,
            "produced_at": _dt.datetime.now(_dt.timezone.utc)
                               .strftime("%Y-%m-%dT%H:%M:%SZ"),
            "produced_by": "reports/autolab/tools/"
                           "blockaid_artefact.py",
            "input": str(run_dir.relative_to(ROOT)) + "/rendered.sql",
            "coverage_shape_not_produced": (
                "the query side of the coverage shape does not exist in a form "
                "blockaid can read: every SELECT the endpoint issued is "
                "recorded in the dumps with unresolved symbolic binds "
                "($$(pN)), and declaring each one an unconstrained constant "
                "would assert `any value` where the run proves one specific "
                "join target. See blockaid/README.md."),
        })
        (dst / "blockaid.json").write_text(json.dumps(rec, indent=1) + "\n")
        for mode, m in (rec.get("modes") or {}).items():
            if "views" in m:
                (dst / f"views.{mode}.sql").write_text(
                    "".join(v + ";\n" for v in m["views"]))
        print(f"{ep}/{prov}/{rid}: "
              + "  ".join(f"{k}: loadable "
                          f"{v.get('views_blockaid_could_load')}/"
                          f"{v.get('views_submitted')} redundant "
                          f"{len(v.get('redundant_views') or [])}"
                          for k, v in (rec.get("modes") or {}).items()
                          if "views_submitted" in v))
    write_index()
    return 0


def write_index() -> None:
    """Regenerate `blockaid/INDEX.md` from every blockaid.json on disk."""
    rows = []
    for f in sorted((OUT / "endpoints").rglob("blockaid.json")):
        d = json.loads(f.read_text())
        a = (d.get("modes") or {}).get("asis") or {}
        b = (d.get("modes") or {}).get("binds_as_constants") or {}
        rows.append((d["endpoint"], d["provenance"], d["run_id"],
                     d.get("views_in_policy"),
                     a.get("views_blockaid_could_load"),
                     len(a.get("subsumed_pairs") or []),
                     b.get("views_blockaid_could_load"),
                     len(b.get("subsumed_pairs") or [])
                     if "views_submitted" in b else None,
                     str(f.parent.relative_to(OUT))))
    L = ["# blockaid artefacts produced so far", "",
         f"Generated {_dt.datetime.now(_dt.timezone.utc):%Y-%m-%dT%H:%M:%SZ} by "
         "`reports/autolab/tools/blockaid_artefact.py`. "
         "Read `README.md` in this directory before reading the numbers.", "",
         "`loadable` = views blockaid could load and type. `proved redundant` = "
         "pairs the solver PROVED subsumed; absence is never proof of "
         "distinctness (see `reading_subsumed_pairs` in each blockaid.json). "
         "The `binds` columns are the OVER-PERMISSIVE diagnostic mode, not a "
         "policy claim.", "",
         "| endpoint | provenance | views | loadable (as-is) | proved "
         "redundant | loadable (binds) | proved redundant (binds) | path |",
         "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        L.append(f"| `{r[0]}` | {r[1]} | {r[3]} | {r[4]}/{r[3]} | {r[5]} | "
                 + (f"{r[6]}/{r[3]} | {r[7]} | " if r[6] is not None
                    else "n/a | n/a | ")
                 + f"`{r[8]}` |")
    L.append("")
    (OUT / "INDEX.md").write_text("\n".join(L))


if __name__ == "__main__":
    raise SystemExit(main())
