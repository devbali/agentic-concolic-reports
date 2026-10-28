#!/usr/bin/env python3
"""pipeline.py — the PYTHON half of the auto-lab shakedown, for ONE endpoint.

Reads the dumps a single endpoint's runner wrote (under
`shakedown/runs/<id>/`) and pushes them through the whole downstream stack,
one stage at a time, recording where each stage stood:

    dump IR      Run.from_dict + concolic.model.provenance.validate_provenance
                 (the same gate `concolic.checks.run.load_runs` applies; done
                 per-file here so a refusal is attributed to ITS dump)
    reach        |declared target_functions  ∩  targets actually called|
                 measured from the dump, per §4.1.1f: `declarations` is a
                 dict  name -> {"kind": …}.  NOT the flat string the stale
                 doc comment at concolic/model/run.py:979 shows.
    run_complete concolic.check.run_complete  (a NEGATIVE verdict is a PASS)
    build_policy dumps_to_policy.build.build_policy, then normalize_detailed
    render       domains.ruby_rails_sql.render.render_sql

plus two free by-products the shakedown was asked to measure:

    profiles     which endpoints read `profiles`, and which columns — the
                 RC-1 blast radius.  Measured from the SQL text of every
                 recorded note, parsed with sqlglot.
    opaque       whether an `opaque` type reached the built policy.

Usage:  pipeline.py <endpoint_id> <run_dir> <out_json>

Never writes to src/ or src_new/.  The three local printer widenings below
are the ones reports/diaspora/tools/build_policy_example.py already
documents; they are applied AT RUNTIME, in this driver only.
"""
from __future__ import annotations

import glob
import json
import os
import re
import sys
import traceback

sys.path.insert(0, "/home/dev/project/src_new")


# --------------------------------------------------------------------------
# local, runtime-only printer widenings (see module docstring)
# --------------------------------------------------------------------------

def _widen_printer():
    from dumps_to_policy.syntax import policy_text
    from dumps_to_policy.predicate import Lit as _Lit
    policy_text._QNAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*[?!=]?"
                                    r"((\.|#|::)[A-Za-z_][A-Za-z0-9_]*[?!=]?)*")
    _orig = policy_text.print_term

    def _print_term(term):
        if isinstance(term, _Lit) and isinstance(term.value, (tuple, list)):
            return "[" + ", ".join(_print_term(_Lit(v)) for v in term.value) + "]"
        return _orig(term)

    policy_text.print_term = _print_term


# --------------------------------------------------------------------------
# stage helpers
# --------------------------------------------------------------------------

def err(e: BaseException) -> dict:
    return {"type": type(e).__name__,
            "message": str(e).replace("\n", " ")[:600],
            "trace": traceback.format_exc()[-1200:]}


def reach_of(raw: dict) -> dict:
    """Distinct declared target_functions this dump actually called."""
    decl = raw.get("declarations") or {}
    tf, shim, bad = set(), set(), []
    for name, spec in decl.items():
        if isinstance(spec, dict):
            kind = spec.get("kind")
        else:                       # the flat-string shape, if one ever appears
            kind = spec
            bad.append(name)
        if kind == "target_function":
            tf.add(name)
        elif kind == "shim":
            shim.add(name)
    called = {e.get("target") for e in raw.get("events", ())
              if e.get("type") in ("call", "symbolic_call")}
    called.discard(None)
    return {"declared_target_functions": len(tf),
            "declared_shims": len(shim),
            "calls_distinct": len(called),
            "reach": len(tf & called),
            "reached": sorted(tf & called),
            "shim_reach": len(shim & called),
            "called_undeclared": sorted(called - tf - shim),
            "flat_string_declarations": bad}


_PROFILE_COLS = ("bio", "gender", "birthday", "location")


def _shape(cols: set, star: bool, sql: str) -> dict:
    """One `profiles` statement, classified NARROW vs WIDE.

    Under `RAILS_ENV=concolic_mod` the app's own default scope is the
    14-column narrow projection (measured: `Profile.all.to_sql` excludes
    bio/gender/birthday/location).  A statement is WIDE if it names any of
    those four, or if it projects `profiles.*` — and a `profiles.*` appearing
    HERE is the interesting case, because it means a mock synthesized an
    unconditional full-width read where the real app would have had to take
    the lazy `#reload` path to get those columns."""
    cols = {c for c in cols if c != "*"}
    lazy = sorted(set(_PROFILE_COLS) & cols)
    return {"wide": bool(star or lazy),
            "star": star,
            "lazy_columns": lazy,
            "n_columns": (None if star else len(cols)),
            "columns": sorted(cols),
            "sql": sql[:300]}


def profiles_of(raw: dict) -> dict:
    """RC-1 blast radius: does any recorded statement touch `profiles`, and
    with which columns.  Every note's `text` is SQL; parsed, not grepped."""
    import sqlglot
    from sqlglot import exp

    texts = []
    for sv in raw.get("symbolic_vars", ()):
        if sv.get("note"):
            texts.append(sv["note"])
    for ev in raw.get("events", ()):
        if ev.get("note"):
            texts.append(ev["note"])

    # `$$(p0)` is a NOTE BIND MARKER, not SQL.  Left in place sqlglot either
    # fails on it or parses `p0` as a column, which would show up as a
    # profiles column that no statement ever read.  Every marker is replaced
    # by a string literal before parsing, so binds can never be mistaken for
    # columns and the statement parses as SQL.
    stmts, unparsed = [], 0
    for n in texts:
        t = n
        if isinstance(n, str) and n.lstrip().startswith("{"):
            try:
                t = json.loads(n).get("text", "")
            except Exception:
                t = n
        elif isinstance(n, dict):
            t = n.get("text", "")
        if t:
            t = re.sub(r"\$\$\(([^)]*)\)", "'__BIND__'", t)
            # Rails inlines a bare Time into the note text
            # (`created_at < 2026-09-11 05:55:41 +0000`), which is not SQL.
            t = re.sub(r"(?<![\'\"])\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?"
                       r"(?: ?[+-]\d{2}:?\d{2}| UTC)?", "'__TS__'", t)
            stmts.append(t)

    touched, cols, star, prose = False, set(), False, 0
    shapes = []          # one entry per DISTINCT profiles statement
    for s in set(stmts):
        if not re.search(r"\b(SELECT|INSERT|UPDATE|DELETE)\b", s, re.I):
            # a note that is not a statement at all — the runtime also
            # publishes prose notes ("Person (current user's person)",
            # boundary decisions).  Not an unparsed statement.
            prose += 1
            continue
        try:
            tree = sqlglot.parse_one(s)
        except Exception:
            unparsed += 1
            if re.search(r'"?profiles"?\.', s) or re.search(r'\bprofiles\b', s):
                touched = True
                here_star = bool(re.search(r'"?profiles"?\."?\*', s))
                star = star or here_star
                here = {m.group(1) for m in
                        re.finditer(r'"?profiles"?\."?([a-z_][a-z0-9_]*)"?', s)}
                here.discard("*")
                cols |= here
                shapes.append(_shape(here, here_star, s))
            continue
        if tree is None:
            continue
        tabs = {t.name for t in tree.find_all(exp.Table)}
        if "profiles" not in tabs:
            continue
        touched = True
        only_profiles = tabs == {"profiles"}
        here, here_star = set(), False
        for c in tree.find_all(exp.Column):
            q = c.table or ("profiles" if only_profiles else "")
            if q == "profiles":
                here.add(c.name)
        for st in tree.find_all(exp.Star):
            parent = st.parent
            if isinstance(parent, exp.Column):
                if (parent.table or ("profiles" if only_profiles else "")) == "profiles":
                    here_star = True
            elif only_profiles:
                here_star = True
        cols |= here
        star = star or here_star
        shapes.append(_shape(here, here_star, s))
    return {"reads_profiles": touched,
            "profiles_shapes": shapes,
            "profiles_wide_shapes": sum(1 for sh in shapes if sh["wide"]),
            "profiles_narrow_shapes": sum(1 for sh in shapes if not sh["wide"]),
            "profiles_select_star": star,
            "profiles_columns": sorted(cols),
            "lazy_load_columns_exposed": (list(_PROFILE_COLS) if star
                                          else sorted(set(_PROFILE_COLS) & cols)),
            "statements": len(set(stmts)) - prose,
            "prose_notes": prose,
            "unparsed_statements": unparsed}


def has_opaque(policy) -> list:
    """Every place an `opaque` type reached the policy.

    STRUCTURAL, not a grep of the printed text: §5's `opaque` ("declared
    structureless") and the printer's legacy `[opaque]` spelling of `?` are
    two different statements that share a word, and only `Type.kind` tells
    them apart.  `Policy` is `(entry, signatures, atoms, certificate)` with
    `signatures` a TUPLE of `Signature(name, params, returns, …)`."""
    hits = []

    def _is_opaque(ty) -> bool:
        return getattr(ty, "kind", None) == "opaque"

    entry = getattr(policy, "entry", None)
    for pn, pt in (getattr(entry, "params", None) or ()):
        if _is_opaque(pt):
            hits.append(f"entry {getattr(entry, 'name', '?')}.{pn}")
    for sig in (getattr(policy, "signatures", None) or ()):
        for pn, pt in (getattr(sig, "params", None) or ()):
            if _is_opaque(pt):
                hits.append(f"sig {sig.name}({pn})")
        if _is_opaque(getattr(sig, "returns", None)):
            hits.append(f"sig {sig.name}->returns")
    return hits


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main() -> int:
    endpoint_id, run_dir, out_json = sys.argv[1], sys.argv[2], sys.argv[3]
    res: dict = {"endpoint": endpoint_id, "run_dir": run_dir,
                 "stages": {}, "failures": []}

    def fail(stage, e, extra=None):
        d = {"stage": stage, **err(e)}
        if extra:
            d.update(extra)
        res["failures"].append(d)

    files = sorted(glob.glob(os.path.join(run_dir, "dump_*.json")))
    res["dumps_on_disk"] = len(files)

    summary_path = os.path.join(run_dir, "exploration_summary.json")
    if os.path.exists(summary_path):
        try:
            res["exploration_summary"] = json.load(open(summary_path))
        except Exception as e:
            fail("exploration_summary", e)

    if not files:
        res["stages"]["dump_ir"] = "no_dumps"
        res["verdict"] = "no_paths"
        json.dump(res, open(out_json, "w"), indent=2)
        return 0

    # ---- stage: dump IR (parse + provenance R1–R4) ------------------------
    from concolic.model.run import Run
    from concolic.model.provenance import validate_provenance

    per_dump, runs = [], []
    ir_ok = True
    for f in files:
        rec = {"file": os.path.basename(f)}
        try:
            raw = json.load(open(f))
        except Exception as e:
            rec["ir"] = "unparseable_json"
            fail("dump_ir", e, {"file": os.path.basename(f)})
            ir_ok = False
            per_dump.append(rec)
            continue
        rec.update(reach_of(raw))
        rec["path_conditions"] = sum(1 for e in raw.get("events", ())
                                     if e.get("type") == "path_condition")
        try:
            rec["profiles"] = profiles_of(raw)
        except Exception as e:
            fail("profiles_scan", e, {"file": os.path.basename(f)})
            rec["profiles"] = {"reads_profiles": None}
        try:
            run = Run.from_dict(raw)
            validate_provenance(run, where=os.path.basename(f))
            rec["ir"] = "ok"
            runs.append((f, run, rec))
        except Exception as e:
            rec["ir"] = "refused"
            fail("dump_ir", e, {"file": os.path.basename(f)})
            ir_ok = False
        per_dump.append(rec)

    res["per_dump"] = per_dump
    res["stages"]["dump_ir"] = "ok" if ir_ok else "failed"
    res["reach_best"] = max((d.get("reach", 0) for d in per_dump), default=0)
    res["reach_worst"] = min((d.get("reach", 0) for d in per_dump), default=0)
    res["declared_target_functions"] = max(
        (d.get("declared_target_functions", 0) for d in per_dump), default=0)
    res["path_conditions_max"] = max((d.get("path_conditions", 0)
                                      for d in per_dump), default=0)
    res["reads_profiles"] = any((d.get("profiles") or {}).get("reads_profiles")
                                for d in per_dump)
    pcols, pstar, wide, narrow, shapes = set(), False, 0, 0, []
    for d in per_dump:
        p = d.get("profiles") or {}
        pcols |= set(p.get("profiles_columns") or ())
        pstar = pstar or bool(p.get("profiles_select_star"))
        wide += p.get("profiles_wide_shapes") or 0
        narrow += p.get("profiles_narrow_shapes") or 0
        shapes.extend(p.get("profiles_shapes") or ())
    res["profiles_columns"] = sorted(pcols)
    res["profiles_select_star"] = pstar
    res["profiles_wide_shapes"] = wide
    res["profiles_narrow_shapes"] = narrow
    res["profiles_shapes"] = shapes

    if not runs:
        res["verdict"] = "failed"
        json.dump(res, open(out_json, "w"), indent=2)
        return 0

    # ---- choose the dump: MAXIMUM target-function reach -------------------
    best_f, best_run, best_rec = max(runs, key=lambda t: (t[2]["reach"],
                                                          t[2]["shim_reach"]))
    res["chosen_dump"] = os.path.basename(best_f)
    res["chosen_reach"] = best_rec["reach"]

    # ---- stage: run_complete ---------------------------------------------
    # NO `config=`, and that is a measured decision, not an omission.
    # `CompletionConfig(batch_dir=…)`'s docstring says "a step whose keys are
    # absent is skipped", but `checks/run.py:run_completion` calls
    # `extract_shims(config)` unconditionally and `checks/shims.py:47` does
    # `config["extract_cmd"]` -> KeyError on any config that does not name a
    # shim extractor.  A scaffolded endpoint HAS no shim extractor, no audit
    # commands, no concrete run and no assumption driver, so there is no
    # honest config to pass; `run_complete(runs)` with no config is the
    # documented path for exactly that ("same as a batch with no
    # completion_config.json") and marks every gate NOT RUN via
    # `gate_not_run`.  This is a HARNESS choice; it is reported, not hidden.
    from concolic.check import run_complete
    try:
        summary = run_complete([best_run])
        res["completion"] = {
            k: summary.get(k) for k in
            ("coverage_complete", "tree_complete", "missing_branches",
             "truncated", "solver_lost", "total_runs", "complete")
        }
        res["completion"]["blocking"] = (summary.get("completion") or {}).get("blocking")
        res["completion"]["gates"] = "not run (no completion config; see pipeline.py)"
        res["completion"]["path_conditions_in_chosen_dump"] = sum(
            1 for e in json.load(open(best_f)).get("events", ())
            if e.get("type") == "path_condition")
        res["stages"]["run_complete"] = "ok"
        if summary.get("complete") is None:
            res["failures"].append(
                {"stage": "run_complete", "type": "NoVerdict",
                 "message": "run_complete produced no `complete` verdict"})
        elif summary.get("complete") is True:
            res["failures"].append(
                {"stage": "run_complete", "type": "CompleteOnOneDump",
                 "message": "complete: true on a single dump — the shakedown "
                            "spec names that as the defect, not a pass"})
        if (summary.get("coverage_complete") is True
                and res["completion"]["path_conditions_in_chosen_dump"] > 0):
            res["failures"].append(
                {"stage": "run_complete", "type": "CoverageCompleteOnOneDump",
                 "message": "coverage_complete: true on ONE dump that carries "
                            f"{res['completion']['path_conditions_in_chosen_dump']} "
                            "path conditions — every decision has an unexplored "
                            "side, so this cannot be right"})
    except Exception as e:
        res["stages"]["run_complete"] = "failed"
        fail("run_complete", e)

    # ---- stage: build_policy ---------------------------------------------
    _widen_printer()
    from dumps_to_policy.build import build_policy
    from dumps_to_policy.normalize import normalize_detailed
    from dumps_to_policy.certificate import Certificate
    import dataclasses

    entrypoint = (res.get("exploration_summary") or {}).get("entrypoint") or endpoint_id
    policy = normed = None
    try:
        cert = Certificate(app=f"autolab/shakedown/{endpoint_id}")
        policy = build_policy([best_run], entrypoint=entrypoint, certificate=cert)
        res["policy"] = {"atoms_unmerged": len(policy.atoms),
                         "signatures": len(policy.signatures or {})}
        op = has_opaque(policy)
        if op:
            res["policy"]["opaque"] = op
            res["failures"].append(
                {"stage": "build_policy", "type": "OpaqueInPolicy",
                 "message": "opaque reached the policy at: " + "; ".join(op[:10])})
        res["stages"]["build_policy"] = "ok"
    except Exception as e:
        res["stages"]["build_policy"] = "failed"
        fail("build_policy", e)

    if policy is not None:
        try:
            normed, report = normalize_detailed(policy)
            base = normed.certificate or policy.certificate
            normed = dataclasses.replace(
                normed, certificate=base.with_atoms(len(normed.atoms))
                                        .with_minimal(report.minimal))
            res["policy"]["atoms_normalized"] = len(normed.atoms)
            res["policy"]["minimal"] = report.minimal
            res["stages"]["normalize"] = "ok"
        except Exception as e:
            res["stages"]["normalize"] = "failed"
            fail("normalize", e)

    # the policy text is an acceptance check of its own: print_policy
    # re-checks the certificate's atom count and refuses a policy it cannot
    # spell (§10.2).
    if normed is not None:
        try:
            from dumps_to_policy.syntax import policy_text
            text = policy_text.print_policy(normed)
            with open(os.path.join(os.path.dirname(out_json),
                                   f"{endpoint_id}.policy.txt"), "w") as fh:
                fh.write(text if text.endswith("\n") else text + "\n")
            res["stages"]["policy_text"] = "ok"
            res["policy"]["policy_text_lines"] = len(text.splitlines())
        except Exception as e:
            res["stages"]["policy_text"] = "failed"
            fail("policy_text", e)

    # ---- stage: SQL render ------------------------------------------------
    if normed is not None:
        try:
            from domains.ruby_rails_sql.render import render_sql, render_views
            sql = render_sql(normed, app_config=None)
            r = render_views(normed, app_config=None)
            with open(os.path.join(os.path.dirname(out_json),
                                   f"{endpoint_id}.sql"), "w") as fh:
                fh.write(sql if sql.endswith("\n") else sql + "\n")
            res["render"] = {"views": len(r.views),
                             "unsupported_atoms": len(r.unsupported),
                             "unrendered_atoms": len(r.unrendered),
                             "dropped_conditions": len(r.dropped_conditions),
                             "sql_lines": len(sql.splitlines())}
            res["stages"]["render_sql"] = "ok"
        except Exception as e:
            res["stages"]["render_sql"] = "failed"
            fail("render_sql", e)

    stages = res["stages"]
    res["verdict"] = "ran_clean" if (not res["failures"] and
                                     all(v == "ok" for v in stages.values())) \
                     else "failed"
    json.dump(res, open(out_json, "w"), indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
