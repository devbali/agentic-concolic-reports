#!/usr/bin/env python3
"""build_store.py — (re)build `reports/autolab/endpoints/` and `stats/`.

WHAT THIS PRODUCES
------------------
One directory per endpoint holding the FINISHED artefacts of every run that
produced a complete set, with both IRs in both of their forms:

    endpoints/<endpoint>/stats.json                  rollup for the endpoint
    endpoints/<endpoint>/<provenance>/<run-id>/
        traces/json/<dump>.json         the dump IR, JSON   (copied)
        traces/text/<dump>.run.txt      the dump IR, text   (GENERATED)
        policy/policy.txt               the policy IR, text (copied)
        policy/policy.json              the policy IR, JSON (GENERATED)
        rendered.sql                    the SQL the domain layer renders
                                        from policy/policy.txt (GENERATED
                                        at build time, not copied -- see
                                        `_render_from_policy`)
        evidence/                       everything else the store holds for
                                        this run, copied verbatim (result,
                                        exploration summary, and for a cloud
                                        box its packet / assumptions / shim
                                        tests / box record), plus the store's
                                        own upstream_provenance.json
        stats.json                      provenance + every verification verdict

    stats/INDEX.json  stats/INDEX.md            the corpus rollup
    stats/EXCEPTIONS.json  stats/EXCEPTIONS.md  what was seen and NOT shipped

RENAMED 2026-09-30.  This tool was `finished/tools/build_finished.py` and wrote
`finished/endpoints/<…>/{dump_ir,policy_ir,run.json}`.  The lab was flattened
to one endpoint-first store at the lab root; `dump_ir` became `traces`,
`policy_ir` became `policy`, `run.json` and `endpoint.json` became `stats.json`,
the rollup moved into `stats/`, and `evidence/` was added so the deliverable is
not a lossy view of the store it is built from.  Nothing about WHAT is verified
changed.  See `reports/autolab/README.md`.

WHERE THE INPUTS COME FROM
--------------------------
the evidence store, and ONLY from there.  It lives at
`reports/autolab/evidence_store/`, which is the default, so a bare run works.
Its path has moved twice: `reports/autolab/results/` until 2026-09-30, then
`reports/autolab/archive/results_evidence_store/`, and the copy retired in that
move is still at
`_trash/autolab_history_20260930/archive/results_evidence_store/` -- that one is
history, NOT the input.  `--store` overrides.  That store is the single source
of truth for what
exists and where it came from; this tool adds the two missing forms and drops
everything that does not verify.  It never reads the sweep or the e2e round directly, so the two
directories cannot come to disagree about what evidence exists — re-sync the
store first, then re-run this.

The one exception is declared in `DOWNSTREAM_BUILDS` below: a cloud box whose
policy was built, from that box's own dumps, by a locally-run pipeline whose
output does not live in the box.  The mapping is checked against the box's
dumps directory before it is used.

HOW THE TEXT FORMS ARE PRODUCED, AND WHAT IS CHECKED
----------------------------------------------------
dump IR      `concolic.model.syntax.print_run(to_text_domain(run))`, and
             checked: `parse_run(text) == to_text_domain(run)` and
             `print_run(parse_run(text)) == text`.  Also recorded, per dump,
             is whether `to_text_domain` was the IDENTITY on that run.  When
             it was not, the text form is equivalent to the PROJECTION and
             not to the JSON — a non-scalar `result_value`, argument or seed
             (an ActiveRecord row, a list, a hash, an object repr) becomes
             `<opaque>` and its term is dropped.  That is a property of the
             IR's text form, not of this tool, and it is why `text_fidelity`
             is recorded per dump rather than assumed.

policy IR    `dumps_to_policy.syntax.policy_text.parse_policy` on the stored
             text, then `dumps_to_policy.syntax.policy_json.print_policy`, and
             checked: `parse_policy(text)` succeeds VERBATIM, reprints
             byte-identically, `from_json(to_json(pol)) == pol`, and
             `print_policy(from_json(json)) == text` — so the text is
             reproducible from the JSON alone.

             BOTH FORMS ARE NOW THE ENGINE'S (2026-09-30).  This tool used to
             carry `tools/policy_json.py`, a codec written here because
             `dumps_to_policy` shipped only the text form and this tool needed
             a JSON one.  The engine owns both serialisations now
             (`dumps_to_policy/syntax/policy_json.py`, with its own suite and
             a JSON sibling for every committed example), that file is gone,
             and the engine's payload was verified byte-identical to the
             prototype's on all 164 stored policies before it was deleted.
             The lab's provenance keys (`produced_by`, `endpoint`) moved into
             the document's `meta`, which the engine form carries and ignores;
             `form` is now `policy_ir.json/1` and has no lab's name in it.

Nothing in `src_new` is imported for writing, and nothing outside
`reports/autolab/endpoints/` and `reports/autolab/stats/` is written.

Usage:
    venvs/queries_from_runs/bin/python3 \
        reports/autolab/tools/build_store.py [--dry-run]
        [--endpoint EP]...   restrict to these endpoints (repeatable)
        [--store PATH]       the evidence store. Defaults to
                             reports/autolab/evidence_store, which exists, so a
                             bare run builds. A store with no endpoints/ under
                             it is refused and nothing is deleted.
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime as _dt
import hashlib
import json
import os
import shutil
import sys
import typing as t
from pathlib import Path

ROOT = Path("/home/dev/project")
SRC_NEW = ROOT / "src_new"
HERE = Path(__file__).resolve().parent
OUT = HERE.parent                                   # reports/autolab
STATS = OUT / "stats"                               # the corpus rollup
#: The live evidence store. It is deliberately NOT repointed at the retired
#: copy under `_trash/`: `_trash/` is a place things go to be deleted, and a
#: default that silently depended on it would turn an ordinary cleanup into data
#: loss. If the path here holds no `endpoints/`, the preflight in `main()`
#: refuses, deletes nothing, and prints both the `--store` line and the "move it
#: back" line. See `_trash/autolab_history_20260930/_RETIRED.md`.
DEFAULT_STORE = ROOT / "reports/autolab/evidence_store"

sys.path.insert(0, str(SRC_NEW))
sys.path.insert(0, str(HERE))

from dumps_to_policy.syntax import policy_json      # noqa: E402  (src_new)


def _render_from_policy(policy_txt: Path):
    """`(sql, None)` from this run's stored policy IR, or `(None, "why not")`.

    Imported lazily: `render_sql` pulls in sqlglot (the SQL domain's one
    third-party dependency), and a store rebuild that only wants the two IRs
    should not fail for want of it -- it falls back to the copy instead.
    """
    try:
        from dumps_to_policy.syntax.policy_text import parse_policy
        from domains.ruby_rails_sql.render import render_sql
        return render_sql(parse_policy(policy_txt.read_text()),
                          app_config=None), None
    except Exception as exc:                       # noqa: BLE001
        return None, f"{type(exc).__name__}: {exc}"


# ---------------------------------------------------------------------------
# the one declared downstream build (see the module docstring)
# ---------------------------------------------------------------------------
#: (endpoint, store run id) -> where its policy/sql were built, and by what.
#: `dumps_must_be` is checked against the run's own dumps directory: if the
#: policy was not built from THESE dumps the mapping is refused, not guessed.
DOWNSTREAM_BUILDS: t.Dict[t.Tuple[str, str], dict] = {
    ("posts_destroy",
     "sweep_out_w4.box.20260929t190209-batch-posts_destroy-574d67-066c3ff0"): {
        "policy": ROOT / "reports/autolab/entrypoints/sweep_out_w4/chain"
                       / "posts_destroy.policy.txt",
        "sql": ROOT / "reports/autolab/entrypoints/sweep_out_w4/chain"
                    / "posts_destroy.sql",
        "result": ROOT / "reports/autolab/entrypoints/sweep_out_w4/chain"
                       / "policy.json",
        "built_by": ("reports/autolab/e2e/tools/pipeline.py, run locally on "
                     "this workstation against the cloud box's own packet "
                     "dumps (the `chain` pass, 2026-09-29)"),
        "dumps_must_be": ("reports/autolab/entrypoints/sweep_out_w4/boxes/"
                          "20260929t190209-batch-posts_destroy-574d67-066c3ff0"
                          "/out/packet/dumps"),
    },
    ("comments_index",
     "sweep_out_or.box.20260929t002039-batch-comments_index-12040f-8153fd9e"): {
        "policy": ROOT / "reports/autolab/entrypoints/sweep_out_or/chain"
                       / "20260929t002039-batch-comments_index-12040f-8153fd9e"
                       / "comments_index.policy.txt",
        "sql": ROOT / "reports/autolab/entrypoints/sweep_out_or/chain"
                    / "20260929t002039-batch-comments_index-12040f-8153fd9e"
                    / "comments_index.sql",
        "result": ROOT / "reports/autolab/entrypoints/sweep_out_or/chain"
                       / "20260929t002039-batch-comments_index-12040f-8153fd9e"
                       / "policy_result.json",
        "built_by": ("reports/autolab/e2e/tools/pipeline.py, run locally on "
                     "this workstation against the cloud box's own packet "
                     "dumps (2026-09-29, while building this directory)"),
        "dumps_must_be": ("reports/autolab/entrypoints/sweep_out_or/boxes/"
                          "20260929t002039-batch-comments_index-12040f-8153fd9e"
                          "/out/packet/dumps"),
    },
    ("comments_index",
     "sweep_out_or.box.20260929t040141-batch-comments_index-74faa4-ba5d8bbf"): {
        "policy": ROOT / "reports/autolab/entrypoints/sweep_out_or/chain"
                       / "20260929t040141-batch-comments_index-74faa4-ba5d8bbf"
                       / "comments_index.policy.txt",
        "sql": ROOT / "reports/autolab/entrypoints/sweep_out_or/chain"
                    / "20260929t040141-batch-comments_index-74faa4-ba5d8bbf"
                    / "comments_index.sql",
        "result": ROOT / "reports/autolab/entrypoints/sweep_out_or/chain"
                       / "20260929t040141-batch-comments_index-74faa4-ba5d8bbf"
                       / "policy_result.json",
        "built_by": ("reports/autolab/e2e/tools/pipeline.py, run locally on "
                     "this workstation against the cloud box's own packet "
                     "dumps (2026-09-29, while building this directory)"),
        "dumps_must_be": ("reports/autolab/entrypoints/sweep_out_or/boxes/"
                          "20260929t040141-batch-comments_index-74faa4-ba5d8bbf"
                          "/out/packet/dumps"),
    },
}


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel(p: Path) -> str:
    try:
        return str(Path(p).resolve().relative_to(ROOT))
    except ValueError:
        return str(p)


def write(path: Path, text: str, dry: bool) -> None:
    if dry:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def copy(src: Path, dst: Path, dry: bool) -> None:
    if dry:
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


# ---------------------------------------------------------------------------
# the IR verifiers / generators
# ---------------------------------------------------------------------------

def _opaque_census(before, after) -> dict:
    """How much `to_text_domain` mapped, as counts rather than a bare bool."""
    from concolic.model.syntax import OPAQUE
    n_vals = n_terms = 0
    for a, b in zip(before.events, after.events):
        for k, v in getattr(b, "args", {}).items():
            if v is OPAQUE and getattr(a, "args", {}).get(k) is not OPAQUE:
                n_vals += 1
        if (getattr(b, "result_value", None) is OPAQUE
                and getattr(a, "result_value", None) is not OPAQUE):
            n_vals += 1
        n_terms += (len(getattr(a, "arg_terms", {}) or {})
                    - len(getattr(b, "arg_terms", {}) or {}))
        if getattr(a, "result_term", None) is not None \
                and getattr(b, "result_term", None) is None:
            n_terms += 1
    for a, b in zip(before.symbolic_vars, after.symbolic_vars):
        if b.value is OPAQUE and a.value is not OPAQUE:
            n_vals += 1
    for d in ("concrete_values", "symbolic_results"):
        ba, bb = getattr(before, d), getattr(after, d)
        for k in bb:
            if bb[k] is OPAQUE and ba.get(k) is not OPAQUE:
                n_vals += 1
    return {"values_mapped_to_opaque": n_vals, "terms_dropped": max(n_terms, 0)}


def do_dump(src: Path) -> t.Tuple[t.Optional[str], dict]:
    """Return (text or None, record). `record["ok"]` decides shipping."""
    from concolic.model.run import Run
    from concolic.model.provenance import validate_provenance
    from concolic.model.syntax import print_run, parse_run, to_text_domain

    rec: dict = {"file": src.name, "bytes": src.stat().st_size,
                 "sha256": sha256(src), "ok": False}
    try:
        raw = json.loads(src.read_text())
    except Exception as e:
        rec["error"] = f"json: {type(e).__name__}: {e}"
        return None, rec
    try:
        run = Run.from_dict(raw)
        validate_provenance(run, where=src.name)
        rec["loads_through_ir"] = True
    except Exception as e:
        rec["loads_through_ir"] = False
        rec["error"] = f"load_run_dump gate: {type(e).__name__}: {e}"[:400]
        return None, rec
    try:
        td = to_text_domain(run)
        identity = (td == run)
        text = print_run(td)
        back = parse_run(text)
        rec.update({
            "text_bytes": len(text.encode()),
            "parse_back_equals_printed_object": back == td,
            "reprint_byte_identical": print_run(back) == text,
            "to_text_domain_is_identity": identity,
            "text_fidelity": "exact" if identity else "projected",
            "text_equivalent_to": ("the JSON" if identity else
                                   "to_text_domain(JSON) — see `projection`"),
        })
        if not identity:
            rec["projection"] = _opaque_census(run, td)
    except Exception as e:
        rec["error"] = f"text form: {type(e).__name__}: {e}"[:400]
        return None, rec
    rec["ok"] = bool(rec["parse_back_equals_printed_object"]
                     and rec["reprint_byte_identical"])
    if not rec["ok"]:
        rec["error"] = "the text form does not round-trip"
    return text, rec


def do_policy(src: Path, endpoint: str) -> t.Tuple[t.Optional[str], dict]:
    from dumps_to_policy.syntax.policy_text import print_policy, parse_policy

    text = src.read_text()
    rec: dict = {"file": src.name, "bytes": len(text.encode()),
                 "sha256": sha256(src), "ok": False}
    if not text.startswith("policy "):
        rec["error"] = "does not begin `policy `"
        return None, rec
    try:
        pol = parse_policy(text)
        rec["parse_verbatim"] = True
    except Exception as e:
        rec["parse_verbatim"] = False
        rec["error"] = f"parse_policy: {type(e).__name__}: {e}"[:400]
        return None, rec
    try:
        rec["reprint_byte_identical"] = (print_policy(pol) == text)
        # The engine's canonical JSON, with this tool's provenance in `meta`
        # (carried, and not read back — it is not policy content).
        blob = policy_json.print_policy(pol, meta={
            "produced_by": "reports/autolab/tools/build_store.py",
            "endpoint": endpoint,
            "note": ("the canonical form of this IR is the text beside it, "
                     "and this document is checked against it "
                     "(print_policy(from_json(this)) == that text)"),
        })
        rec["json_form"] = policy_json.FORM
        pol2 = policy_json.parse_policy(blob)
        rec["json_object_round_trip"] = (pol2 == pol)
        rec["text_reproducible_from_json"] = (print_policy(pol2) == text)
        rec["json_bytes"] = len(blob.encode())
        rec["atoms"] = len(pol.atoms)
        rec["signatures"] = len(pol.signatures)
        rec["entry"] = pol.entry.name
        cert = pol.certificate
        rec["certificate"] = (dataclasses.asdict(cert)
                              if dataclasses.is_dataclass(cert) else None)
    except Exception as e:
        rec["error"] = f"json form: {type(e).__name__}: {e}"[:400]
        return None, rec
    rec["ok"] = bool(rec["reprint_byte_identical"]
                     and rec["json_object_round_trip"]
                     and rec["text_reproducible_from_json"])
    if not rec["ok"]:
        rec["error"] = "the two forms of the policy IR do not correspond"
    return blob, rec


# ---------------------------------------------------------------------------
# discovery — from the store, and only from the store
# ---------------------------------------------------------------------------

def discover(store: Path) -> t.List[dict]:
    runs = []
    epdir = store / "endpoints"
    for ep in sorted(p.name for p in epdir.iterdir() if p.is_dir()):
        for prov in sorted(p.name for p in (epdir / ep).iterdir()
                           if p.is_dir()):
            for run in sorted(p.name for p in (epdir / ep / prov).iterdir()
                              if p.is_dir()):
                d = epdir / ep / prov / run
                pf = d / "provenance.json"
                if not pf.exists():
                    continue
                runs.append({"endpoint": ep, "provenance": prov,
                             "run_id": run, "dir": d,
                             "store_provenance": json.loads(pf.read_text())})
    return runs


def roles(store: Path, upstream: dict) -> t.Dict[str, t.List[Path]]:
    out: t.Dict[str, t.List[Path]] = {}
    for a in upstream.get("artifacts", ()):
        if not a.get("ok"):
            continue
        p = store / a["path"]
        if p.exists():
            out.setdefault(a["role"], []).append(p)
    return out


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", default=str(DEFAULT_STORE))
    ap.add_argument("--endpoint", action="append", default=None)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    store = Path(args.store)
    dry = args.dry_run
    started = _dt.datetime.now(_dt.timezone.utc)

    # PREFLIGHT, and it must come BEFORE the rmtree below.
    #
    # `endpoints/` is rebuilt from scratch on every run, so the rmtree destroys
    # the whole deliverable and `discover()` then repopulates it. If the store
    # is not there, the old order deleted 161 endpoints and died on
    # `FileNotFoundError` a moment later, leaving nothing at all. That is not a
    # theoretical risk: on 2026-09-30 the evidence store was retired to
    # `_trash/autolab_history_20260930/archive/results_evidence_store/` and this
    # tool's default was left pointing at its old path, so the very next
    # unqualified run would have wiped the store it was meant to rebuild.
    if not (store / "endpoints").is_dir():
        sys.stderr.write(
            f"build_store.py: no endpoints/ under the store at\n"
            f"    {store}\n"
            f"so there is nothing to build from, and NOTHING WAS DELETED.\n\n"
            f"The evidence store was retired on 2026-09-30. Either point at it\n"
            f"where it now lives:\n"
            f"    --store {ROOT}/_trash/autolab_history_20260930/archive/"
            f"results_evidence_store\n"
            f"or move that directory back to {DEFAULT_STORE} and re-run.\n"
            f"See _trash/autolab_history_20260930/_RETIRED.md.\n")
        return 2

    # THE RMTREE IS SCOPED TO WHAT WILL BE REBUILT.  It used to clear the whole
    # of `endpoints/` and `stats/` unconditionally, including under
    # `--endpoint`, which rebuilds only the named ones -- so a restricted run
    # deleted all 161 endpoints and put 1 back.  A full run still clears both
    # (the rollup is only meaningful when every endpoint was walked); a
    # restricted run clears only the named subtrees and LEAVES `stats/` alone,
    # saying that the rollup it did not recompute is now stale.
    if not dry:
        if args.endpoint:
            for ep in args.endpoint:
                shutil.rmtree(OUT / "endpoints" / ep, ignore_errors=True)
            print(f"[--endpoint] rebuilding {len(args.endpoint)} endpoint(s); "
                  f"the rest of endpoints/ is untouched and stats/ is NOT "
                  f"regenerated — it now describes a corpus that has moved. "
                  f"Re-run without --endpoint to refresh the rollup.")
        else:
            shutil.rmtree(OUT / "endpoints", ignore_errors=True)
            shutil.rmtree(STATS, ignore_errors=True)

    endpoints: t.Dict[str, dict] = {}
    exceptions: t.List[dict] = []
    tot = {"runs_seen": 0, "runs_finished": 0, "runs_excluded": 0,
           "dumps_stored": 0, "dumps_rejected": 0,
           "dumps_text_exact": 0, "dumps_text_projected": 0,
           "policies_stored": 0, "policies_rejected": 0,
           "renders_generated": 0, "renders_copied": 0,
           "renders_identical_to_upstream_copy": 0}

    for run in discover(store):
        ep, prov, rid = run["endpoint"], run["provenance"], run["run_id"]
        if args.endpoint and ep not in args.endpoint:
            continue
        tot["runs_seen"] += 1
        r = roles(store, run["store_provenance"])
        down = DOWNSTREAM_BUILDS.get((ep, rid))
        note = None

        # ---- the policy this run's dumps produced ------------------------
        pol_src = (r.get("policy") or [None])[0]
        sql_src = (r.get("sql") or [None])[0]
        res_src = (r.get("result") or [None])[0]
        if down is not None:
            dumps_dir = {p.parent for p in r.get("dump", ())}
            want = ROOT / down["dumps_must_be"]
            store_dumps = {store / a["path"]
                           for a in run["store_provenance"]["artifacts"]
                           if a["role"] == "dump"}
            if not store_dumps:
                exceptions.append({
                    "endpoint": ep, "provenance": prov, "run_id": rid,
                    "reason": "a downstream build is declared for this run but "
                              "the run stores no dumps to attribute it to"})
                tot["runs_excluded"] += 1
                continue
            # the declared source dumps must be the ones this run mirrors
            got = sorted(p.name for p in store_dumps)
            exp = sorted(p.name for p in want.glob("*.json")) if want.is_dir() \
                else []
            if got != exp:
                exceptions.append({
                    "endpoint": ep, "provenance": prov, "run_id": rid,
                    "reason": "the declared downstream build was made from a "
                              "different set of dumps than this run stores; "
                              f"stored={len(got)} declared={len(exp)}"})
                tot["runs_excluded"] += 1
                continue
            pol_src, sql_src, res_src = (down["policy"], down["sql"],
                                         down["result"])
            note = down["built_by"]
            del dumps_dir

        if pol_src is None or not Path(pol_src).exists():
            exceptions.append({
                "endpoint": ep, "provenance": prov, "run_id": rid,
                "dumps_in_run": len(r.get("dump", ())),
                "reason": (
                    "a SUPERSEDED attempt: the round re-ran this endpoint and "
                    "this attempt produced no policy, so only one of the two "
                    "IRs exists for it. Its dumps are kept upstream in "
                    "_trash/autolab_history_20260930/archive/results_evidence_store/ (retired there 2026-09-30; see its _RETIRED.md)."
                    if ".superseded-" in rid else
                    "a shared batch mount, not one box's output: it mirrors "
                    "dumps that a box also submitted, and nothing downstream "
                    "consumed it, so only one of the two IRs exists for it"
                    if rid.endswith(".batch") else
                    "no policy was produced for this run — the dumps exist "
                    "but nothing downstream consumed them, so only one of "
                    "the two IRs could be shipped")})
            tot["runs_excluded"] += 1
            continue

        dst = OUT / "endpoints" / ep / prov / rid
        dump_recs, kept = [], 0
        for src in sorted(r.get("dump", ())):
            text, rec = do_dump(src)
            dump_recs.append(rec)
            if rec["ok"] and text is not None:
                copy(src, dst / "traces/json" / src.name, dry)
                write(dst / "traces/text" / (src.stem + ".run.txt"),
                      text, dry)
                kept += 1
                tot["dumps_text_exact" if rec["to_text_domain_is_identity"]
                    else "dumps_text_projected"] += 1
            else:
                tot["dumps_rejected"] += 1
                exceptions.append({
                    "endpoint": ep, "provenance": prov, "run_id": rid,
                    "artifact": rec["file"],
                    "reason": "dump rejected: " + str(rec.get("error"))})
        tot["dumps_stored"] += kept

        pol_json, pol_rec = do_policy(Path(pol_src), ep)
        if not pol_rec["ok"] or pol_json is None or kept == 0:
            tot["policies_rejected"] += 0 if pol_rec["ok"] else 1
            tot["runs_excluded"] += 1
            if not dry:
                shutil.rmtree(dst, ignore_errors=True)
            exceptions.append({
                "endpoint": ep, "provenance": prov, "run_id": rid,
                "reason": ("no dump in this run survived verification"
                           if kept == 0 else
                           "policy rejected: " + str(pol_rec.get("error")))})
            continue

        render_rec = None
        copy(Path(pol_src), dst / "policy/policy.txt", dry)
        write(dst / "policy/policy.json", pol_json, dry)
        tot["policies_stored"] += 1
        if sql_src and Path(sql_src).exists():
            # RE-RENDERED, NOT COPIED.  The store's `rendered.sql` is frozen at
            # whatever `render.py` did on the day its pipeline ran, so copying
            # it made the deliverable describe a renderer that may no longer
            # exist -- and after the 2026-10-01 bind-resolution fixes, 120 of
            # 164 copies were stale.  Rendering here from `policy/policy.txt`
            # instead makes the build IDEMPOTENT: the policy IR round-trips
            # verbatim, so the IR -> SQL hook is the only thing that can move,
            # and a rebuild can no longer silently revert a refresh.
            # `tools/rerender.py` does the same thing in place, without a
            # rebuild.  A render that RAISES falls back to the copy and says so
            # in `stats.json` -- never a silently absent view set.
            sql, err = _render_from_policy(Path(pol_src))
            same_as_copy = (sql is not None
                            and sql == Path(sql_src).read_text())
            if same_as_copy:
                tot["renders_identical_to_upstream_copy"] += 1
            if sql is not None:
                write(dst / "rendered.sql", sql, dry)
            else:
                copy(Path(sql_src), dst / "rendered.sql", dry)
            tot["renders_generated" if sql is not None
                else "renders_copied"] += 1
            render_rec = {
                "source": ("policy/policy.txt, re-rendered at build time"
                           if sql is not None else
                           "COPIED from the evidence store: re-render raised"),
                "renderer": "domains.ruby_rails_sql.render.render_sql",
                "upstream_copy_byte_identical": same_as_copy,
                "error": err,
            }

        # Everything else the evidence store holds for this run, carried over
        # verbatim so the deliverable is not a lossy view of it: the pipeline
        # result, the exploration summary, and — for a cloud box — its packet,
        # declared assumptions, shim tests and box record.  Copied, never
        # generated; `upstream_provenance.json` is the store's own record of
        # where each file came from and its sha256.
        for role in ("result", "exploration_summary", "assumptions",
                     "assumption_manifest", "packet", "box", "other"):
            for src in sorted(r.get(role, ())):
                copy(src, dst / "evidence" / src.name, dry)
        up_prov = (store / "endpoints" / ep / prov / rid / "provenance.json")
        if up_prov.exists():
            copy(up_prov, dst / "evidence/upstream_provenance.json", dry)

        stages = {}
        if res_src and Path(res_src).exists():
            try:
                res = json.loads(Path(res_src).read_text())
                stages = {"stages": res.get("stages"),
                          "failures": [{k: f.get(k) for k in
                                        ("stage", "type", "severity",
                                         "message")}
                                       for f in res.get("failures") or ()]}
            except Exception as e:
                stages = {"error": f"{type(e).__name__}: {e}"}

        run_rec = {
            "endpoint": ep,
            "provenance": prov,
            "run_id": rid,
            "built_at": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "built_by": "reports/autolab/tools/build_store.py",
            "what_finished_means": FINISHED_MEANS,
            "certified_complete": False,
            "certified_complete_reason": CERT_REASON,
            "evidence": {
                "dumps_produced_by": run["store_provenance"]["source"],
                "policy_and_sql_produced_by": (
                    note or "the same run that produced the dumps "
                            "(reports/autolab/e2e/tools/pipeline.py, locally)"),
                "upstream_store": rel(store / "endpoints" / ep / prov / rid),
            },
            "pipeline": stages,
            "evidence_dir": {
                "dir": "evidence",
                "what": ("everything the evidence store holds for this run "
                         "besides the two IRs and the SQL, copied verbatim: "
                         "the pipeline result, the exploration summary, and "
                         "for a cloud box its packet, declared assumptions, "
                         "shim tests and box record, plus the store's own "
                         "provenance record as upstream_provenance.json"),
                "files": sorted(
                    {src.name for role in ("result", "exploration_summary",
                                           "assumptions",
                                           "assumption_manifest", "packet",
                                           "box", "other")
                     for src in r.get(role, ())}
                    | ({"upstream_provenance.json"}
                       if (store / "endpoints" / ep / prov / rid
                           / "provenance.json").exists() else set())),
            },
            "traces": {
                "json_dir": "traces/json",
                "text_dir": "traces/text",
                "generator": "concolic.model.syntax.print_run("
                             "to_text_domain(run))",
                "stored": kept,
                "rejected": len(dump_recs) - kept,
                "text_exact": sum(1 for d in dump_recs if d["ok"]
                                  and d["to_text_domain_is_identity"]),
                "text_projected": sum(1 for d in dump_recs if d["ok"]
                                      and not d["to_text_domain_is_identity"]),
                "dumps": dump_recs,
            },
            "policy": {
                "text": "policy/policy.txt",
                "json": "policy/policy.json",
                "text_generator": "as printed upstream by "
                                  "dumps_to_policy.syntax.policy_text."
                                  "print_policy",
                "json_generator": "dumps_to_policy.syntax.policy_json."
                                  "print_policy",
                **pol_rec,
            },
        }
        if render_rec is not None:
            run_rec["rendered_sql"] = render_rec
        write(dst / "stats.json", json.dumps(run_rec, indent=1) + "\n", dry)
        tot["runs_finished"] += 1

        e = endpoints.setdefault(ep, {"endpoint": ep, "runs": [],
                                      "certified_complete": False,
                                      "certified_complete_reason":
                                          CERT_REASON})
        e["runs"].append({
            "provenance": prov, "run_id": rid,
            "path": f"endpoints/{ep}/{prov}/{rid}",
            "dumps": kept,
            "dump_text_exact": run_rec["traces"]["text_exact"],
            "dump_text_projected": run_rec["traces"]["text_projected"],
            "policy_atoms": pol_rec["atoms"],
            "policy_round_trips": True,
            "dumps_produced_by": run["store_provenance"]["source"]
                                    .get("kind", prov),
            "policy_produced_by": ("locally-run pipeline against cloud dumps"
                                   if note else "local pipeline"),
            "cert_line_outcome": (pol_rec["certificate"] or {}).get("outcome"),
        })

    # WHAT EACH ENDPOINT'S CLOUD ATTEMPTS USED. The three files holding this
    # -- `workers.jsonl`, the queue's box records and the price catalog -- are
    # none of them keyed by endpoint, so nothing joined them and the store
    # could not say what any endpoint cost. `tools/cost.py` does the join;
    # it is written HERE rather than by its own pass because a full rebuild
    # clears `endpoints/` and would otherwise delete it.
    try:
        import cost as cost_mod
        cloud_recs, cloud_prov = cost_mod.records(OUT)
    except Exception as exc:                            # noqa: BLE001
        cloud_recs, cloud_prov = {}, {
            "error": f"{type(exc).__name__}: {exc}",
            "effect": "no endpoint got a cloud.json; the join did not run"}

    for ep, e in endpoints.items():
        e["sources"] = sorted({r["provenance"] for r in e["runs"]})
        e["run_count"] = len(e["runs"])
        e["dumps"] = sum(r["dumps"] for r in e["runs"])
        e["policies"] = len(e["runs"])
        e["both_ir_forms"] = True
        rec = cloud_recs.get(ep)
        if rec is not None:
            write(OUT / "endpoints" / ep / "cloud.json",
                  json.dumps(rec, indent=1) + "\n", dry)
            e["cloud"] = {k: v for k, v in rec.items()
                          if k != "attempt_detail"}
            e["cloud"]["detail"] = "cloud.json"
        else:
            e["cloud"] = {"attempts": 0, "detail": (
                "no cloud box was ever launched for this endpoint; its "
                "artefacts came from the local verification round")}
        write(OUT / "endpoints" / ep / "stats.json",
              json.dumps(e, indent=2) + "\n", dry)

    # endpoints in the corpus that produced nothing finished at all
    corpus = sorted(p.name for p in
                    (ROOT / "reports/autolab/entrypoints/scaffold").iterdir()
                    if p.is_dir())
    for ep in corpus:
        if ep not in endpoints and not (args.endpoint and ep not in
                                        args.endpoint):
            exceptions.append({"endpoint": ep, "reason":
                               "no run of this endpoint produced a finished "
                               "artefact set"})

    index = {
        "generated_at": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generator": "reports/autolab/tools/build_store.py",
        "input_store": rel(store),
        "what_finished_means": FINISHED_MEANS,
        "what_finished_does_not_mean": CERT_REASON,
        "corpus_endpoints": len(corpus),
        "totals": {
            **tot,
            "endpoints_finished": len(endpoints),
            "endpoints_with_cloud_dumps": sum(
                1 for e in endpoints.values() if "cloud" in e["sources"]),
            "endpoints_certified_complete": 0,
            "endpoints_with_a_cloud_attempt": len(
                [ep for ep in endpoints if ep in cloud_recs]),
            "cloud_attempts": sum(r["attempts"] for r in cloud_recs.values()),
            "cloud_box_hours": round(
                sum(r["vm"]["box_hours"] for r in cloud_recs.values()), 4),
            "policies_produced_by_a_cloud_agent": 0,
        },
        "endpoints": {ep: {k: v for k, v in e.items() if k != "runs"}
                      for ep, e in sorted(endpoints.items())},
        "exceptions": exceptions,
        "cloud_cost_provenance": cloud_prov,
    }
    # The rollup is a CORPUS-level claim, so it is written only by a run that
    # walked the whole corpus. A `--endpoint` run would otherwise overwrite
    # "161 endpoints" with "1 endpoint" and the stale-rollup warning above
    # would be describing a file it had just destroyed.
    if args.endpoint:
        print("[--endpoint] stats/ not written (a partial walk cannot make a "
              "corpus-level claim)")
    else:
        write(STATS / "INDEX.json", json.dumps(index, indent=2) + "\n", dry)
        write(STATS / "EXCEPTIONS.json", json.dumps(
            {"generated_at": index["generated_at"],
             "count": len(exceptions), "exceptions": exceptions}, indent=2)
            + "\n", dry)
        write(STATS / "INDEX.md", index_md(index, endpoints), dry)
        write(STATS / "EXCEPTIONS.md", exceptions_md(index, exceptions), dry)

    print(f"endpoints finished={len(endpoints)}/{len(corpus)}  "
          f"runs finished={tot['runs_finished']} excluded={tot['runs_excluded']}")
    print(f"dumps stored={tot['dumps_stored']} rejected={tot['dumps_rejected']}"
          f"  (text exact={tot['dumps_text_exact']} "
          f"projected={tot['dumps_text_projected']})")
    print(f"policies stored={tot['policies_stored']} "
          f"rejected={tot['policies_rejected']}")
    print(f"exceptions recorded={len(exceptions)}"
          + ("   [DRY RUN]" if dry else ""))
    return 0


FINISHED_MEANS = (
    "every dump in this run loads through concolic.model.run's own gate and "
    "its text form round-trips; the policy parses VERBATIM through "
    "dumps_to_policy.syntax.policy_text.parse_policy, reprints byte-"
    "identically, and its text is reproducible from its JSON alone; the "
    "pipeline recorded no error-severity failure. In one sentence: both IRs "
    "are present in both forms and the forms agree."
)

#: NULLIFIED 2026-10-07 (owner). Every endpoint in this store is void, and not
#: merely uncertified: four things the evidence rests on changed on that date,
#: three of them in the direction that the old artefacts were accepted too
#: easily.
#:
#:   1. The shape predicate carried NO STATEMENT KIND, and a DELETE normalises
#:      to an empty projection, so `proj >= r_proj` was vacuous: any read on a
#:      table covered every write to it.
#:   2. The predicate comparison RAN BACKWARDS (`pred >= r_pred`). A WHERE
#:      conjunct narrows a read, so a note predicated on
#:      `person_id = <principal> AND conversation_id = ?` was covering a real
#:      statement that omits `person_id` -- a cross-principal read passing as
#:      the principal's own.
#:   3. The `destroy` mock SKIPPED the after_destroy callback chain, so any
#:      endpoint reaching `.destroy` recorded neither the callbacks' statements
#:      nor a `dependent: :destroy` cascade.
#:   4. The gates no longer answer PASS without evidence: a PASS now needs a
#:      proof or a launched, realising probe with route-diverse witnesses, and
#:      two unprobed PASSes became OUTSTANDING.
#:
#: So no dump, policy or review item produced before 2026-10-07 is evidence
#: about this application, whichever way it reads. Re-driving is the only way
#: back, and the reason is carried HERE rather than in a hand-edited
#: `stats.json` because the store is regenerated in full on every build.
NULLIFIED_ON = "2026-10-07"

CERT_REASON = (
    f"NULLIFIED {NULLIFIED_ON}: VOID, not merely uncertified. The shape "
    "predicate carried no statement kind (so any read on a table covered "
    "every write to it), its predicate comparison ran backwards (so a "
    "per-principal note covered a cross-principal read), the destroy mock "
    "skipped the after_destroy callback chain, and the gates stopped "
    "answering PASS without a proof or a launched probe. Nothing produced "
    "before that date is evidence about this application; re-drive. "
    "Separately and still true: no endpoint config in this corpus carries a "
    "`completion` block, so every completeness gate reports NOT CONFIGURED "
    "and every certificate line reads report=none outcome=UNDECIDED. A "
    "policy here is evidence that a policy was produced and is internally "
    "consistent — never that the endpoint's execution tree was explored, "
    "that any branch was proved covered or unreachable, or that the "
    "endpoint is done."
)


def exceptions_md(index: dict, exceptions: list) -> str:
    """The exception list, as prose. Everything NOT in the finished set."""
    L = [
        "# What is excluded from `finished/`, and why",
        "",
        f"Generated {index['generated_at']} by `{index['generator']}`. "
        "Regenerated in full on every build; do not hand-edit.",
        "",
        "This is the whole of what the build saw and did not ship. An empty "
        "section below means nothing fell into it.",
        "",
        f"- endpoints in the corpus: **{index['corpus_endpoints']}**",
        f"- endpoints with a finished artefact set: "
        f"**{index['totals']['endpoints_finished']}**",
        f"- runs excluded: **{index['totals']['runs_excluded']}** of "
        f"{index['totals']['runs_seen']} seen",
        f"- individual artefacts rejected by a verifier: "
        f"**{index['totals']['dumps_rejected']}** dumps, "
        f"**{index['totals']['policies_rejected']}** policies",
        "",
        "## Excluded runs",
        "",
    ]
    ep_only = [e for e in exceptions if "run_id" not in e]
    runs = [e for e in exceptions if "run_id" in e and "artifact" not in e]
    arts = [e for e in exceptions if "artifact" in e]
    if runs:
        L += ["| endpoint | provenance | run | reason |", "|---|---|---|---|"]
        for e in sorted(runs, key=lambda e: (e["endpoint"], e["run_id"])):
            L.append(f"| `{e['endpoint']}` | {e['provenance']} | "
                     f"`{e['run_id']}` | {e['reason']} |")
    else:
        L.append("None.")
    L += ["", "## Rejected artefacts", "",
          "A dump that did not load through the IR gate, or whose text form "
          "did not round-trip; a policy that did not parse verbatim or whose "
          "two forms disagreed. None of these is copied into "
          "`reports/autolab/endpoints/`.", ""]
    if arts:
        L += ["| endpoint | run | artefact | reason |", "|---|---|---|---|"]
        for e in arts:
            L.append(f"| `{e['endpoint']}` | `{e['run_id']}` | "
                     f"`{e.get('artifact')}` | {e['reason']} |")
    else:
        L.append("None.")
    L += ["", "## Endpoints with nothing finished at all", ""]
    if ep_only:
        for e in sorted(ep_only, key=lambda e: e["endpoint"]):
            L.append(f"- `{e['endpoint']}` — {e['reason']}")
    else:
        L.append("None: every endpoint in the corpus has at least one "
                 "finished run.")
    L.append("")
    return "\n".join(L)


def index_md(index: dict, endpoints: dict) -> str:
    t_ = index["totals"]
    L = [
        "# `reports/autolab/` — endpoint store index",
        "",
        "The store is `reports/autolab/endpoints/<endpoint>/<provenance>/"
        "<run>/` with `policy/`, `traces/`, `evidence/`, `rendered.sql` and "
        "`stats.json` in each run. This file and `EXCEPTIONS.md` are the "
        "corpus-level rollup; `../README.md` is the map.",
        "",
        f"Generated {index['generated_at']} by `{index['generator']}`. "
        "Regenerated in full on every build; do not hand-edit.",
        "",
        f"- endpoints in the corpus: **{index['corpus_endpoints']}**",
        f"- endpoints with a finished artefact set: "
        f"**{t_['endpoints_finished']}**",
        f"- runs finished: **{t_['runs_finished']}** "
        f"(excluded {t_['runs_excluded']} — see `EXCEPTIONS.json`)",
        f"- dump IR stored: **{t_['dumps_stored']}** in both forms "
        f"(rejected {t_['dumps_rejected']})",
        f"  - text equivalent to the JSON: **{t_['dumps_text_exact']}**; "
        f"text equivalent to `to_text_domain(JSON)`: "
        f"**{t_['dumps_text_projected']}** — see README, *Fidelity*",
        f"- policy IR stored: **{t_['policies_stored']}** in both forms, all "
        "round-tripping verbatim",
        f"- `rendered.sql` GENERATED from the stored policy at build time: "
        f"**{t_['renders_generated']}**"
        + (f" (and {t_['renders_copied']} fell back to the evidence store's "
           f"copy because the render raised)" if t_['renders_copied'] else "")
        + f"; of these **{t_['renders_identical_to_upstream_copy']}** came "
          "out byte-identical to the evidence store's frozen copy and the "
          "rest did not — the copy had stopped matching the renderer",
        f"- endpoints whose dumps came from a cloud box: "
        f"**{t_['endpoints_with_cloud_dumps']}**",
        f"- policies produced BY a cloud agent: "
        f"**{t_['policies_produced_by_a_cloud_agent']}** — every policy here "
        "was built by a locally-run pipeline",
        f"- cloud attempts recorded: **{t_['cloud_attempts']}** across "
        f"**{t_['endpoints_with_a_cloud_attempt']}** endpoints, "
        f"**{t_['cloud_box_hours']}** box hours "
        f"— per endpoint in its `cloud.json`; an attempt is a box launched FOR "
        "an endpoint, NOT the provenance of its artefacts",
        f"- **certified-complete endpoints: "
        f"{t_['endpoints_certified_complete']}**, and this cannot be anything "
        "else here; see README.",
        "",
        "| endpoint | sources | runs | dumps | atoms | outcome |",
        "|---|---|---|---|---|---|",
    ]
    for ep, e in sorted(endpoints.items()):
        atoms = ", ".join(str(r["policy_atoms"]) for r in e["runs"])
        out = ", ".join(sorted({str(r["cert_line_outcome"])
                                for r in e["runs"]}))
        L.append(f"| `{ep}` | {'+'.join(e['sources'])} | {e['run_count']} "
                 f"| {e['dumps']} | {atoms} | {out} |")
    L.append("")
    return "\n".join(L)


if __name__ == "__main__":
    raise SystemExit(main())
