#!/usr/bin/env python3
"""build_inventory.py — turn the e2e sweep's artifacts into a PER-ENDPOINT
issue inventory, then rank the issues by how many endpoints each blocks.

Every field here is copied from an artifact; nothing is inferred from a
string frequency.  In particular an endpoint's STOPPING SITE is taken from
`exploration_summary.json:terminal_rows[*].terminal`, which the driver fills
from the live exception object (class, message, `NameError#receiver`,
`NameError#name`, and the real `backtrace`), not from matching text in a log.

Issue identity: two endpoints are given the SAME issue code only when they
agree on the tuple that names a call site —

    (exception class, missing method name, receiver class, raising frame
     file:line)

— so "the same message" is never on its own enough to merge them.  Where a
code is assigned on something weaker than that, the code says so in its own
`basis` field.

Usage: build_inventory.py <e2e_dir> [<out_prefix>]
"""
from __future__ import annotations

import collections
import json
import os
import sys

SCAFFOLD = "/home/dev/project/reports/autolab/entrypoints/scaffold"


def _frame_loc(fr):
    """'/path/file.rb:158:in `meth`' -> ('/path/file.rb:158', 'meth')."""
    if not fr:
        return None, None
    parts = fr.split(":in ")
    loc = parts[0]
    meth = parts[1].strip("`'") if len(parts) > 1 else None
    return loc, meth


def load(e2e):
    runs = os.path.join(e2e, "runs")
    results = os.path.join(e2e, "results")
    man = {}
    mpath = os.path.join(e2e, "manifest.jsonl")
    if os.path.exists(mpath):
        for line in open(mpath):
            line = line.strip()
            if line:
                try:
                    r = json.loads(line)
                    man[r["endpoint"]] = r     # last row wins (a re-drive)
                except Exception:
                    pass
    out = {}
    for eid in sorted(os.listdir(SCAFFOLD)):
        if not os.path.isdir(os.path.join(SCAFFOLD, eid)):
            continue
        rec = {"endpoint": eid}
        cfgp = os.path.join(SCAFFOLD, eid, "config.json")
        if os.path.exists(cfgp):
            c = json.load(open(cfgp))
            rec["entrypoint"] = c.get("entrypoint")
            rec["signed_in"] = c.get("signed_in")
            rec["request_format"] = c.get("request_format")
            rec["n_inputs"] = len(c.get("inputs") or ())
            rec["priority_tier"] = (c.get("autolab") or {}).get("priority_tier")
            rec["targets_tier"] = (c.get("autolab") or {}).get("targets_tier")
            rec["routes"] = (c.get("autolab") or {}).get("routes")
        rec["manifest"] = man.get(eid)
        sp = os.path.join(runs, eid, "exploration_summary.json")
        rec["exploration"] = json.load(open(sp)) if os.path.exists(sp) else None
        rp = os.path.join(results, eid + ".json")
        rec["pipeline"] = json.load(open(rp)) if os.path.exists(rp) else None
        pol = os.path.join(results, eid + ".policy.txt")
        rec["policy_text"] = open(pol).read() if os.path.exists(pol) else None
        out[eid] = rec
    return out


def summarize(rec):
    """The per-endpoint record proper: what ran, where it stopped, what it made."""
    e = rec.get("exploration") or {}
    p = rec.get("pipeline") or {}
    m = rec.get("manifest") or {}
    s = {
        "endpoint": rec["endpoint"],
        "entrypoint": rec.get("entrypoint"),
        "signed_in": rec.get("signed_in"),
        "format": rec.get("request_format"),
        "targets_tier": rec.get("targets_tier"),
        "attempted": bool(m),
    }

    # ---- stage results, each one's actual return -------------------------
    s["stages"] = {
        "run": {
            "rc": m.get("run_rc"), "timed_out": m.get("run_timeout"),
            "seconds": m.get("run_seconds"),
            "runs_executed": e.get("runs_executed"),
            "distinct_paths": e.get("distinct_paths"),
            "dumps_written": p.get("dumps_on_disk"),
            "worklist_exhausted": e.get("worklist_exhausted"),
            "stack_remaining": e.get("stack_remaining"),
            "max_runs": e.get("max_runs"),
            "dse_seconds": e.get("elapsed_seconds"),
            "harness_errors": e.get("run_errors"),
        },
        "dump_ir": {
            "verdict": (p.get("stages") or {}).get("dump_ir"),
            "dumps_accepted": p.get("accepted_dumps"),
            "refused": [d["file"] for d in (p.get("per_dump") or ())
                        if d.get("ir") != "ok"],
        },
        "run_complete": {
            "verdict": (p.get("stages") or {}).get("run_complete"),
            **{k: (p.get("completion") or {}).get(k) for k in
               ("complete", "coverage_complete", "tree_complete",
                "missing_branches", "truncated", "solver_lost", "total_runs")},
            "gate_states": ((p.get("completion") or {}).get("gates") or {}).get("gate_states"),
            "blocking": (p.get("completion") or {}).get("blocking"),
        },
        "build_policy": {
            "verdict": (p.get("stages") or {}).get("build_policy"),
            **{k: (p.get("policy") or {}).get(k) for k in
               ("atoms_unmerged", "atoms_normalized", "signatures", "minimal",
                "policy_text_lines")},
            "opaque": (p.get("policy") or {}).get("opaque"),
        },
        "normalize": {"verdict": (p.get("stages") or {}).get("normalize")},
        "policy_text": {"verdict": (p.get("stages") or {}).get("policy_text")},
        "render_sql": {"verdict": (p.get("stages") or {}).get("render_sql"),
                       **(p.get("render") or {})},
    }
    s["failures"] = p.get("failures") or []
    # THE VERDICT IS RECOMPUTED HERE, not taken from the result JSON.
    # `pipeline.py`'s severity model changed DURING sweep 2 (RenderIncomplete
    # and DumpNotRepresentable stopped flipping the verdict), so the stored
    # field is not homogeneous across the corpus. Everything it depends on IS
    # stored, so it is derived instead, by TYPE, for every endpoint alike:
    #   stage    the pipeline broke -- this and only this decides the verdict
    #   data     the pipeline handled and reported a refusal of corpus content
    #   quality  information loss in what was produced
    # `data` and `quality` findings are all still recorded and all still reach
    # the ranked issue list.
    NON_STAGE = {"RenderIncomplete": "quality",
                 "AccessWithNoStatementNote": "quality",
                 "ProseNoteOnAnAccess": "quality",
                 "DumpNotRepresentable": "data"}
    for f in s["failures"]:
        f.setdefault("severity", NON_STAGE.get(f.get("type"), "stage"))
    stage_failures = [f for f in s["failures"] if f["severity"] == "stage"]
    s["stage_failures"] = len(stage_failures)
    s["data_findings"] = sum(1 for f in s["failures"] if f["severity"] == "data")
    s["quality_findings"] = sum(1 for f in s["failures"] if f["severity"] == "quality")
    all_ok = all((st.get("verdict") in ("ok", None))
                 for st in (s["stages"][k] for k in
                            ("dump_ir", "run_complete", "build_policy",
                             "normalize", "policy_text", "render_sql")))
    s["pipeline_verdict"] = ("ran_clean" if (not stage_failures and all_ok
                                             and s["attempted"]) else
                             ("not_attempted" if not s["attempted"] else "failed"))
    s["pipeline_verdict_as_stored"] = p.get("verdict")

    # ---- where execution stopped, from the live exception ----------------
    rows = e.get("terminal_rows") or []
    stops = []
    for r in rows:
        t = r.get("terminal")
        # A HANDLED exception is a different fact from an unrescued one, and
        # it is NOT "the action ran to completion": the application raised and
        # one of its own `rescue_from` handlers rendered something instead.
        # `api_openid_connect_clients_create` is the case that forced this —
        # its dump has no terminal, 0 path conditions and exactly four events
        # (`Metal#status=` and `_set_rendered_content_type`), which is what a
        # 400-rendering handler does and not what its `create` does.
        handled = [{"type": h.get("type"),
                    "message": h.get("message_full") or h.get("message"),
                    "raising_frame": h.get("raising_frame"),
                    "handler": h.get("handler")}
                   for h in (r.get("handled") or ())]
        if not t:
            stops.append({"label": r.get("label"), "terminal": None,
                          "handled": handled,
                          "note": ("the action raised and a rescue_from handler "
                                   "took it" if handled else
                                   "run completed with no exception at all")})
            continue
        loc, meth = _frame_loc(t.get("raising_frame"))
        stops.append({
            "label": r.get("label"),
            "dump_written": r.get("dump_written"),
            "path_conditions": r.get("path_conditions"),
            "type": t.get("type"),
            "message": t.get("message_full") or t.get("message"),
            "missing_name": t.get("missing_name"),
            "receiver_class": t.get("receiver_class"),
            "receiver_inspect": t.get("receiver_inspect"),
            "raising_frame": t.get("raising_frame"),
            "raising_file_line": loc,
            "raising_method": meth,
            "first_app_frame": t.get("first_app_frame"),
            "first_autolab_frame": t.get("first_autolab_frame"),
            "backtrace": t.get("backtrace"),
            "cause": t.get("cause"),
            "param": t.get("param"),
            "handled": handled,
        })
    s["stops"] = stops
    # the endpoint's DOMINANT stop: the one most runs ended at
    key = collections.Counter(
        (st.get("type"), st.get("missing_name"), st.get("receiver_class"),
         st.get("raising_file_line"))
        for st in stops if st.get("type"))
    s["stop_site_counts"] = [{"site": list(k), "runs": v} for k, v in key.most_common()]
    s["dominant_stop"] = None
    if key:
        top = key.most_common(1)[0][0]
        for st in stops:
            if (st.get("type"), st.get("missing_name"), st.get("receiver_class"),
                    st.get("raising_file_line")) == top:
                s["dominant_stop"] = st
                break
    s["terminals_by_type"] = e.get("terminals")

    # ---- what the dumps contain ------------------------------------------
    s["dumps"] = [{
        "file": d.get("file"), "ir": d.get("ir"),
        "path_conditions": d.get("path_conditions"),
        "event_counts": d.get("event_counts"),
        "declared_target_functions": d.get("declared_target_functions"),
        "declared_shims": d.get("declared_shims"),
        "n_declarations": d.get("n_declarations"),
        "reach": d.get("reach"), "reached": d.get("reached"),
        "call_targets": d.get("call_targets"),
        "terminal_type": (d.get("terminal") or {}).get("type"),
        "pc_exprs": d.get("pc_exprs"),
    } for d in (p.get("per_dump") or ())]
    s["declaration_table_sizes"] = sorted({d.get("n_declarations")
                                           for d in (p.get("per_dump") or ())
                                           if d.get("n_declarations")})
    s["reach_best"] = p.get("reach_best")
    s["reach_union"] = p.get("reach_union")
    s["path_conditions_max"] = p.get("path_conditions_max")
    s["chosen_dump"] = p.get("chosen_dump")

    # ---- harness-side observations ---------------------------------------
    stderr = (m.get("pipeline_stderr") or "")
    s["solver"] = {
        "failed_var_decls": sorted({l.split("'")[1] for l in stderr.splitlines()
                                    if "Failed to eval var decl" in l and "'" in l}),
        "failed_constraints": sorted({l.split("'")[1] for l in stderr.splitlines()
                                      if "Failed to parse constraint" in l and "'" in l}),
    }
    s["dump_bytes"] = m.get("dump_bytes")
    return s


# --------------------------------------------------------------------------
# issue assignment — one function per issue, each stating its own evidence
# --------------------------------------------------------------------------

def issues_for(s):
    out = []

    def add(code, basis, evidence, blocking=True, note=None):
        out.append({"code": code, "basis": basis, "evidence": evidence,
                    "blocking": blocking, "note": note})

    # An endpoint with no run in this sweep gets EXACTLY ONE issue. Letting
    # the checks below run over its empty record would credit it with "zero
    # path conditions" and "zero target reach", which are statements about a
    # run that did not happen — and those two counts are the headline numbers
    # of this report.
    if not s.get("attempted"):
        add("NOT_ATTEMPTED", "no manifest row for this endpoint in this sweep", {})
        return out

    ds = s.get("dominant_stop")
    if ds and ds.get("type"):
        ty = ds["type"]
        site = ds.get("raising_file_line")
        if ty in ("NoMethodError", "NameError") and ds.get("missing_name"):
            add(f"UNMOCKED::{ds.get('receiver_class')}#{ds['missing_name']}@{site}",
                "exception class + NameError#name + NameError#receiver.class + "
                "raising backtrace frame, all read off the live exception object",
                {"type": ty, "missing_name": ds["missing_name"],
                 "receiver_class": ds.get("receiver_class"),
                 "receiver_inspect": ds.get("receiver_inspect"),
                 "raising_frame": ds.get("raising_frame"),
                 "caller_frames": (ds.get("backtrace") or [])[1:4],
                 "message": ds.get("message")})
        elif ty == "NotImplementedError":
            add(f"RUNTIME_NOTIMPL::{ds.get('message','')[:60]}@{site}",
                "exception class + message + raising frame; the symbolic "
                "runtime itself refuses the operation",
                {"type": ty, "message": ds.get("message"),
                 "raising_frame": ds.get("raising_frame"),
                 "caller_frames": (ds.get("backtrace") or [])[1:4]})
        elif ty == "ActionController::ParameterMissing":
            add(f"PARAM_MISSING::{ds.get('param')}@{site}",
                "exception class + ActionController::ParameterMissing#param "
                "+ raising frame",
                {"param": ds.get("param"), "raising_frame": ds.get("raising_frame"),
                 "message": ds.get("message")},
                note="the scaffold did not make this required param symbolic")
        else:
            add(f"TERMINAL::{ty}@{site}",
                "exception class + raising backtrace frame",
                {"type": ty, "message": ds.get("message"),
                 "raising_frame": ds.get("raising_frame"),
                 "caller_frames": (ds.get("backtrace") or [])[1:4]})

    st = s["stages"]
    for name in ("dump_ir", "run_complete", "build_policy", "normalize",
                 "policy_text", "render_sql"):
        v = st[name].get("verdict")
        if v not in ("ok", None):
            f = next((x for x in s["failures"] if x.get("stage") == name), {})
            add(f"STAGE_FAILED::{name}::{f.get('type')}",
                "the pipeline stage raised; the exception type and message are "
                "recorded in the result JSON's `failures`",
                {"stage": name, "verdict": v, "type": f.get("type"),
                 "message": f.get("message")})
    for f in s["failures"]:
        if f.get("stage") in ("build_policy",) and f.get("type") == "OpaqueAccessInPolicy":
            add("OPAQUE_ACCESS_IN_POLICY", "policy IR inspection: an opaque type "
                "reached the entry params or an atom-referenced target_function",
                {"message": f.get("message")})

    # "worklist exhausted" is NOT "the endpoint is explored". The worklist
    # holds the flips of the path conditions actually recorded, so an
    # endpoint that dies at an unmocked call has a SMALL worklist and empties
    # it quickly — bounded by the wall, not by the application. The two are
    # separated here because reading `worklist_exhausted: true` as coverage
    # is the single easiest mistake to make with these artifacts.
    if (st["run"].get("worklist_exhausted") is True
            and ds and ds.get("type")):
        add("EXHAUSTED_BEHIND_A_WALL",
            "worklist_exhausted=true, but every run ended at an unrescued "
            "exception, so the explored tree is bounded by that stopping site "
            "and not by the endpoint",
            {"runs_executed": st["run"].get("runs_executed"),
             "stop": ds.get("type"),
             "stop_frame": ds.get("raising_frame"),
             "path_conditions_max": s.get("path_conditions_max")},
            blocking=False)

    if st["run"].get("worklist_exhausted") is False:
        add("DEPTH_TRUNCATED",
            "exploration_summary: worklist_exhausted=false with "
            "stack_remaining>0 at MAX_RUNS",
            {"runs_executed": st["run"].get("runs_executed"),
             "max_runs": st["run"].get("max_runs"),
             "stack_remaining": st["run"].get("stack_remaining"),
             "dse_seconds": st["run"].get("dse_seconds")},
            blocking=False)

    if (s.get("path_conditions_max") or 0) == 0:
        # SEPARATED BY EVIDENCE, not by guesswork: a run that finished with NO
        # unrescued exception genuinely had no branch to record (a static
        # document, a redirect, a render with no decision over a symbolic
        # value).  A run that ended at a terminal exception recorded no branch
        # because it never reached one.  The two are different findings and are
        # never folded together.
        # "ran to completion" now requires NO exception at all, handled or not.
        ran_to_completion = any(
            not st.get("type") and not st.get("handled")
            for st in (s.get("stops") or ()))
        if ran_to_completion and not (ds and ds.get("type")):
            add("ZERO_PATH_CONDITIONS_NO_BRANCH_REACHED",
                "every dump records zero path_condition events AND at least "
                "one run completed with no unrescued exception, so the action "
                "ran to the end without deciding anything over a symbolic value",
                {"dumps": len(s.get("dumps") or ()),
                 "runs_without_terminal": sum(1 for st in (s.get("stops") or ())
                                              if not st.get("type"))},
                blocking=False)
        else:
            add("ZERO_PATH_CONDITIONS_DIED_FIRST",
                "every dump records zero path_condition events AND every run "
                "ended at an unrescued exception, so no branch was reached",
                {"dumps": len(s.get("dumps") or ()),
                 "dominant_stop_type": (ds or {}).get("type"),
                 "dominant_stop_frame": (ds or {}).get("raising_frame"),
                 "dominant_stop_message": (ds or {}).get("message")})

    if (s.get("reach_best") or 0) == 0:
        add("ZERO_TARGET_REACH",
            "|declared target_functions ∩ call-event targets| = 0 in every dump",
            {"declared": (s.get("dumps") or [{}])[0].get("declared_target_functions"),
             "call_targets": (s.get("dumps") or [{}])[0].get("call_targets")},
            blocking=False)

    handled_sites = collections.Counter()
    for st_ in (s.get("stops") or ()):
        for h in (st_.get("handled") or ()):
            handled_sites[(h.get("type"), (h.get("raising_frame") or "").split(":in ")[0])] += 1
    if handled_sites:
        (ty, fr), _c = handled_sites.most_common(1)[0]
        add(f"HANDLED_ERROR_PATH::{ty}@{fr}",
            "the run recorded no unrescued exception, but the application "
            "raised and one of its own rescue_from handlers took it — read "
            "off the live exception inside the driver's rescue",
            {"sites": [{"type": k[0], "frame": k[1], "runs": v}
                       for k, v in handled_sites.most_common()]},
            blocking=False,
            note="not a crash; but it is NOT the action running to completion")

    gs = st["run_complete"].get("gate_states") or {}
    nc = sorted(k for k, v in gs.items() if v == "NOT CONFIGURED")
    if nc:
        add("GATES_NOT_CONFIGURED::" + ",".join(nc),
            "run_complete was given a CompletionConfig and the section came "
            "back with those gates None; `blocking` names each one",
            {"gate_states": gs, "blocking": st["run_complete"].get("blocking")})

    if s["solver"]["failed_constraints"]:
        add("SOLVER_CONSTRAINT_UNPARSED",
            "pipeline stderr carries `Failed to parse constraint`; "
            "check_satisfiability returns UNSAT on that path, so a reachable "
            "branch can be silently reported infeasible",
            {"constraints": s["solver"]["failed_constraints"][:5]})
    if s["solver"]["failed_var_decls"]:
        add("SOLVER_VAR_DECL_UNEVALUABLE",
            "pipeline stderr carries `Failed to eval var decl`",
            {"decls": s["solver"]["failed_var_decls"][:5]}, blocking=False)

    if st["run"].get("timed_out"):
        add("RUN_TIMEOUT", "the sweep's run stage hit its wall clock timeout",
            {"seconds": st["run"].get("seconds")})
    return out


def main():
    e2e = sys.argv[1] if len(sys.argv) > 1 else "/home/dev/project/reports/autolab/e2e"
    prefix = sys.argv[2] if len(sys.argv) > 2 else os.path.join(e2e, "INVENTORY")
    raw = load(e2e)
    recs = {}
    for eid, rec in raw.items():
        s = summarize(rec)
        s["issues"] = issues_for(s)
        recs[eid] = s

    # ---- corpus-level: is `install!` really running once per process? ----
    # `install!` is not idempotent, so a reused process would show up as a
    # DECLARATION TABLE that is bigger on the later endpoints.  The table
    # size is read off each dump's own §4.1.1f `declarations` map.  The
    # expected size is the MODE over endpoints that have no target override
    # (tier == candidate); an override legitimately adds names.
    sizes = collections.Counter()
    for s in recs.values():
        if s.get("targets_tier") == "candidate":
            for n in s.get("declaration_table_sizes") or ():
                sizes[n] += 1
    mode = sizes.most_common(1)[0][0] if sizes else None
    for s in recs.values():
        if (mode and s.get("targets_tier") == "candidate"
                and s.get("declaration_table_sizes")
                and s["declaration_table_sizes"] != [mode]):
            s["issues"].append({
                "code": f"DECLARATION_TABLE_ANOMALY::{s['declaration_table_sizes']}",
                "basis": "the dump's own declaration table size differs from the "
                         f"core-only mode ({mode}); `install!` is not idempotent, "
                         "so a reused OS process would show exactly this",
                "evidence": {"sizes": s["declaration_table_sizes"], "mode": mode},
                "blocking": True, "note": None})

    # ---- aggregate: group by issue CODE, ranked by endpoints affected ----
    by_code = collections.defaultdict(list)
    for eid, s in recs.items():
        for i in s["issues"]:
            by_code[i["code"]].append(eid)
    ranked = sorted(by_code.items(), key=lambda kv: (-len(kv[1]), kv[0]))
    agg = []
    for code, eps in ranked:
        sample = next(i for i in recs[eps[0]]["issues"] if i["code"] == code)
        agg.append({"code": code, "endpoints_affected": len(eps),
                    "blocking": sample["blocking"], "basis": sample["basis"],
                    "sample_evidence": sample["evidence"],
                    "sample_endpoint": eps[0],
                    "endpoints": sorted(eps)})

    # ---- a flat, per-endpoint table (CSV) for reading and for diffing ----
    import csv
    with open(prefix + ".csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["endpoint", "entrypoint", "signed_in", "format",
                    "pipeline_verdict", "run_rc", "runs_executed",
                    "dumps_written", "dumps_accepted", "worklist_exhausted",
                    "path_conditions_max", "reach_best", "reach_union_n",
                    "atoms_normalized", "signatures", "policy_lines",
                    "sql_lines", "complete", "stop_type", "stop_missing_name",
                    "stop_receiver", "stop_frame", "issue_codes"])
        for eid in sorted(recs):
            s_ = recs[eid]
            st = s_["stages"]
            d = s_.get("dominant_stop") or {}
            w.writerow([
                eid, s_.get("entrypoint"), s_.get("signed_in"), s_.get("format"),
                s_.get("pipeline_verdict"), st["run"].get("rc"),
                st["run"].get("runs_executed"), st["run"].get("dumps_written"),
                st["dump_ir"].get("dumps_accepted"),
                st["run"].get("worklist_exhausted"),
                s_.get("path_conditions_max"), s_.get("reach_best"),
                len(s_.get("reach_union") or ()),
                st["build_policy"].get("atoms_normalized"),
                st["build_policy"].get("signatures"),
                st["build_policy"].get("policy_text_lines"),
                st["render_sql"].get("sql_lines"),
                st["run_complete"].get("complete"),
                d.get("type"), d.get("missing_name"), d.get("receiver_class"),
                d.get("raising_file_line"),
                " | ".join(i["code"] for i in s_["issues"]),
            ])
    json.dump(recs, open(prefix + ".json", "w"), indent=1, sort_keys=True)
    json.dump({"ranked_issues": agg,
               "endpoints": len(recs),
               "attempted": sum(1 for s in recs.values() if s["attempted"])},
              open(prefix + "_RANKED.json", "w"), indent=1)
    print(f"{len(recs)} endpoint records -> {prefix}.json (+ .csv)")
    print(f"{len(agg)} distinct issue codes -> {prefix}_RANKED.json")
    for a in agg[:40]:
        print(f"{a['endpoints_affected']:4d}  {'BLOCK' if a['blocking'] else '     '}  {a['code'][:110]}")


if __name__ == "__main__":
    main()
