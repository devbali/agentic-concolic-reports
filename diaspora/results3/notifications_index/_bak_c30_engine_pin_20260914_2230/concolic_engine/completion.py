"""Completion checker — the concolic engine's "are the mocks complete?"
counterpart to CoverageChecker's "is exploration complete?" (Bali design,
2026-08-25). Its verdict is a SECTION of the engine's final JSON report
(coverage_summary.json: ``completion``), and the report's overall
``complete`` is coverage_complete AND completion complete.

Responsibility inversion: the ENGINE enumerates and demands; the agent
only supplies test bodies keyed by names the engine produced. Omission is
a red verdict (NO-TEST), never silence.

Zero coupling (CLAUDE.md): this module imports nothing from py_runtime /
ruby_runtime / queries_from_runs. Every runtime-specific step is a
configured subprocess command:

  config = {
    "batch_dir":    "<abs batch dir>",
    "workdir":      "<abs project root>",
    "extract_cmd":  "<runtime-specific shim extractor cmd> -> JSON list on stdout",
    "test_cmd":     "<runtime-specific shim test runner> {shims} {tests} {out}",
    "test_env":     {"JRUBY_OPTS": "--debug"},          # optional
    "shim_tests":   "<agent-provided test bodies file>",
    "concrete_run": "<concrete_run.json>",               # optional
    "note_check_cmd": "python3 .../mock_note_check.py {run} {batch} [--aliases ...]",  # optional
    "assumption_cfg": "<batch runner cfg json: batch_dir, runner, workdir, env_by_scenario>",
    "assumption_cmd": "python3 .../assumption_checker.py {cfg} --declared {declared} --json-out {out}"
  }

Pipeline: EXTRACT (authoritative shim list from the batch's own runner
code) -> TEST (agent-provided body per engine-enumerated shim: zero
target-function reach + 100% executable-line coverage of the real body,
or a reasoned waiver) -> NOTE CHECK (target-mock note fidelity from the
concrete run) -> ASSUMPTIONS (Bali, 2026-08-26: the assumption checker
is roped in too — every assumption the coverage checker USED must have a
manifest entry the driver VERIFIED at this evidence layer; unverified
declared assumptions block completion) -> SECTION.

  from concolic_engine.completion import run_completion
  section = run_completion(config)   # -> dict, JSON-serializable
  section["complete"]               # every shim PASS/WAIVED and notes green
"""
from __future__ import annotations

import json
import os
import subprocess
from typing import Any, Dict, List, Optional


def _run(cmd: str, cwd: str, env_extra: Optional[Dict[str, str]] = None,
         timeout: int = 1200) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env.update(env_extra or {})
    return subprocess.run(cmd, shell=True, cwd=cwd, env=env,
                          capture_output=True, text=True, timeout=timeout)


# The dump-side audits' cost scales with the batch DIRECTORY (they scan every
# dump_*.json in it), not with the pass's DUMP_LIST, so a corpus that grows
# between passes can push one past a fixed wall clock. 1800 s was hard-coded
# and a TimeoutExpired propagated out of `attach_to_summary`, destroying an
# hours-long coverage result that had already been computed
# (notifications_index, 2026-09-11: `cardinality_consistency_audit` killed at
# 30 min, `coverage_summary.json` never written). Two changes, both
# backward-compatible:
#   * the limit is configurable — per audit (`"timeout"` in its audit_cmds
#     entry), per invocation (`$COMPLETION_AUDIT_TIMEOUT`), or per batch
#     (`"audit_timeout"` in the completion config), in that order of
#     precedence: one audit's own limit beats an ad-hoc override, which beats
#     the batch's standing default. Unset everywhere = 1800 s, as before;
#   * a timeout is a RED AUDIT, not an exception. It blocks `complete` the way
#     any RED audit does, and the caller still gets its section back.
DEFAULT_AUDIT_TIMEOUT = 1800


def _audit_timeout(config: Dict[str, Any], audit: Dict[str, Any]) -> int:
    """Seconds allowed for one audit; most specific setting wins."""
    for raw in (audit.get("timeout"),
                os.environ.get("COMPLETION_AUDIT_TIMEOUT"),
                config.get("audit_timeout")):
        if raw is None or raw == "":
            continue
        try:
            val = int(raw)
        except (TypeError, ValueError):
            continue
        if val > 0:
            return val
    return DEFAULT_AUDIT_TIMEOUT


def extract_shims(config: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Step 1: the runtime-specific extractor derives the shim list."""
    r = _run(config["extract_cmd"], config.get("workdir", "."), config.get("env"))
    if r.returncode != 0:
        raise RuntimeError(f"shim extractor failed: {r.stderr[-400:]}")
    return json.loads(r.stdout)


def test_shims(config: Dict[str, Any], shims: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Step 2: the runtime-specific runner executes the agent-provided
    body per engine-enumerated shim and returns one verdict per shim."""
    batch = config["batch_dir"]
    shims_path = os.path.join(batch, "_shims_extracted.json")
    results_path = os.path.join(batch, "_shim_results.json")
    with open(shims_path, "w") as fh:
        json.dump(shims, fh, indent=2)
    if os.path.exists(results_path):
        os.remove(results_path)
    cmd = (config["test_cmd"].replace("{shims}", shims_path)
                             .replace("{tests}", config["shim_tests"])
                             .replace("{out}", results_path))
    r = _run(cmd, config.get("workdir", "."),
             {**(config.get("env") or {}), **(config.get("test_env") or {})})
    if not os.path.exists(results_path):
        raise RuntimeError(f"shim test runner produced no results: {(r.stdout + r.stderr)[-400:]}")
    with open(results_path) as fh:
        return json.load(fh)


def note_check(config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Step 3: deterministic target-mock note fidelity, if a concrete run
    and a note-check command are configured."""
    if not (config.get("concrete_run") and config.get("note_check_cmd")):
        return None
    cmd = (config["note_check_cmd"].replace("{run}", config["concrete_run"])
                                   .replace("{batch}", config["batch_dir"]))
    r = _run(cmd, config.get("workdir", "."), config.get("env"))
    return {"exit": r.returncode, "green": r.returncode == 0,
            "output": r.stdout[-3000:]}


def assumption_check(config: Dict[str, Any],
                     declared: Optional[List[Dict[str, Any]]] = None) -> Optional[Dict[str, Any]]:
    """Step 4: the assumption gate (Bali, 2026-08-26 — assumptions are
    already handed over by the coverage checker; the engine only has to
    RUN THE TESTS). Every declared assumption is tested by a test DERIVED
    from its type's claim (see assumption_checker.py --declared): 
      Independence(A,B): flip A, flip B, flip both — the both-flipped
        access trace must add no target-call shape absent from the
        others (the docstring's "practical test");
      UntrackedPath(e): flip e — access trace must be identical;
      OneSideUntracked(e): the untracked side adds no access shape.
    Needs config["assumption_cfg"]: batch runner config for replays
    (batch_dir, runner, workdir, env_by_scenario) and
    config["assumption_cmd"] with {cfg} {declared} {out} placeholders."""
    if not declared or not config.get("assumption_cmd"):
        return None
    batch = config["batch_dir"]
    acfg = config.get("assumption_cfg") or config.get("assumption_manifest")
    if not acfg:
        return None
    declared_path = os.path.join(batch, "_assumptions_declared.json")
    out_path = os.path.join(batch, "_assumption_results.json")
    with open(declared_path, "w") as fh:
        json.dump(declared, fh)
    if os.path.exists(out_path):
        os.remove(out_path)
    cmd = (config["assumption_cmd"].replace("{cfg}", acfg)
                                   .replace("{declared}", declared_path)
                                   .replace("{out}", out_path))
    r = _run(cmd, config.get("workdir", "."), config.get("env"), timeout=21600)
    results: List[Dict[str, Any]] = []
    if os.path.exists(out_path):
        with open(out_path) as fh:
            results = json.load(fh)
    counts: Dict[str, int] = {}
    for x in results:
        counts[x["verdict"]] = counts.get(x["verdict"], 0) + 1
    fails = [x for x in results if x["verdict"] == "FAIL"]
    # A driver that dies is a DIAGNOSABLE event or it is nothing: keeping only
    # a tail of stdout and discarding stderr entirely made a one-off death
    # (comments_index cycle 11, 2026-09-01 — exit 1, 0 of 5 315 tested, PASS
    # lines in the tail, no exception anywhere on disk) impossible to explain,
    # and it never reproduced. Persist the WHOLE of both streams next to the
    # batch whenever the driver fails, and name the file in the report.
    failure_log = None
    if r.returncode != 0 or fails:
        failure_log = os.path.join(config["batch_dir"], "_assumption_driver_failure.log")
        try:
            with open(failure_log, "w") as fh:
                fh.write(f"cmd: {cmd}\nexit: {r.returncode}\n"
                         f"declared: {len(declared)}  distinct_tested: {len(results)}\n"
                         f"==== STDOUT ====\n{r.stdout}\n==== STDERR ====\n{r.stderr}\n")
        except Exception as e:                       # never let logging mask the failure
            failure_log = f"<unwritable: {e}>"
    # Confinement (§16c, 2026-09-11): the declared list also carries the
    # INFERRED confined pairs (`CoverageResult.assumptions_to_dict`). A FAIL on
    # one is a withdrawal by replay evidence: it blocks `complete` below like
    # any FAIL, and the pairs are listed here so the next pass can feed them
    # back (`CoverageChecker(withdrawn_pairs=...)`) — the coverage numbers of
    # THIS pass were computed with those pairs licensed and are not to be quoted.
    # ... and an inferred pair the gate could not VERIFY (NOT-TESTABLE,
    # NOT-COMPARABLE, ERROR) is withdrawn just the same: a declared
    # assumption's NOT-TESTABLE is the batch's call, an inferred pair's is
    # not — the demand was reduced on it, so it must PASS on the gate's own
    # replays or it does not stand (owner, 2026-09-11).
    conf_rows = [x for x in results if x["type"] == "ConfinementAssumption"]
    conf_withdrawn = [[x["expr"], x.get("expr_b")] for x in conf_rows if x["verdict"] != "PASS"]
    conf_unverified = [x for x in conf_rows if x["verdict"] not in ("PASS", "FAIL")]
    n_conf = sum(1 for d in declared if d.get("type") == "ConfinementAssumption")
    return {"declared": len(declared),
            "distinct_tested": len(results),
            "verdict_counts": counts,
            "confinement_tested": n_conf,
            "confinement_withdrawn": conf_withdrawn,
            "confinement_unverified": [{"expr": x["expr"], "expr_b": x.get("expr_b"),
                                        "verdict": x["verdict"], "detail": x["detail"]}
                                       for x in conf_unverified],
            "failures": [{"type": x["type"], "expr": x["expr"], "expr_b": x.get("expr_b"),
                          "detail": x["detail"]} for x in fails],
            "driver_exit": r.returncode,
            "output_tail": r.stdout[-2000:],
            "stderr_tail": r.stderr[-2000:],
            "failure_log": failure_log,
            "green": (r.returncode == 0) and not fails and not conf_unverified}


def run_audits(config: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Step 0: the dump-side audits (Bali, 2026-08-26 — the engine runs
    them; the sub-agent experiment showed an agent can reach `complete`
    while skipping them). config["audit_cmds"] = [{"name": ..,
    "cmd": ".. {batch} .."}]; each must exit 0. The identity-symbolicity
    audit belongs here: a concrete principal id evades every other check."""
    out = []
    # Optional batch-supplied audits. The SQL-consumer audits
    # (src/queries_from_runs/audits/) are NOT run here — they are the parent
    # agent's manual phase between the engine's fixed checks and the
    # adversary (Bali, 2026-08-26).
    for a in list(config.get("audit_cmds") or []) + list(config.get("extra_audit_cmds") or []):
        cmd = a["cmd"].replace("{batch}", config["batch_dir"])
        tmo = _audit_timeout(config, a)
        try:
            r = _run(cmd, config.get("workdir", "."), config.get("env"), timeout=tmo)
        except subprocess.TimeoutExpired as exc:
            out.append({"name": a["name"], "exit": None, "green": False,
                        "timed_out": tmo,
                        "output_tail": _tail(exc.stdout),
                        "stderr_tail": (f"TIMEOUT after {tmo}s (raise it with "
                                        f"COMPLETION_AUDIT_TIMEOUT, the config's "
                                        f"audit_timeout, or this audit's own "
                                        f"timeout key)\n" + _tail(exc.stderr))})
            continue
        out.append({"name": a["name"], "exit": r.returncode, "green": r.returncode == 0,
                    "output_tail": r.stdout[-1500:],
                    # stderr is where an audit's traceback goes; a RED whose
                    # cause is only on stderr was previously unreadable.
                    "stderr_tail": r.stderr[-1500:] if r.returncode != 0 else ""})
    return out


def _tail(stream: Any, n: int = 1500) -> str:
    """Last n chars of a subprocess stream that may be str, bytes or None."""
    if stream is None:
        return ""
    if isinstance(stream, (bytes, bytearray)):
        stream = stream.decode("utf-8", "replace")
    return stream[-n:]


def run_completion(config: Dict[str, Any],
                   declared_assumptions: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
    """Run the full completion pipeline; return the report SECTION."""
    audits = run_audits(config)
    shims = extract_shims(config)
    verdicts = test_shims(config, shims)
    nc = note_check(config)
    ac = assumption_check(config, declared_assumptions)
    # No waivers (2026-08-27): a shim either runs in a test — with whatever
    # MINIMAL, justified mocks that test needs to make it runnable — and
    # passes, or it is blocking. Prose is not evidence. Methods that are not
    # mocks over application code at all (the symbolic runtime's own rep
    # plumbing) must be excluded by the EXTRACTOR, not waived here.
    # PASS = the shim ran and proved itself. PROTOCOL = it is not a shim over
    # application code at all (the runtime's own rep machinery, decided at
    # runtime from the real class — see shim_test_runner). Everything else,
    # waivers included, is blocking (DISCIPLINE Rule S).
    bad = [v for v in verdicts if v.get("verdict") not in ("PASS", "PROTOCOL")]
    blocking = [f"audit {a['name']}: RED"
                + (f" (TIMEOUT after {a['timed_out']}s)" if a.get("timed_out") else "")
                for a in audits if not a["green"]]
    if nc is None:
        blocking.append("note_check: NOT CONFIGURED (concrete_run + note_check_cmd are mandatory)")
    if ac is None:
        blocking.append("assumption gate: NOT CONFIGURED (assumption_cfg + assumption_cmd are mandatory)")
    blocking += [f"shim {v['key']}: {v['verdict']}" for v in bad]
    if nc is not None and not nc["green"]:
        blocking.append("note_check: RED")
    if ac is not None and not ac["green"]:
        blocking += [f"assumption FAIL ({f['type']}): {str(f['expr'])[:80]}" for f in ac["failures"]]
        blocking += [f"confinement NOT VERIFIED ({u['verdict']}): {str(u['expr'])[:60]} x "
                     f"{str(u['expr_b'])[:60]}" for u in ac.get("confinement_unverified") or []]
        if not ac["failures"] and not ac.get("confinement_unverified"):
            blocking.append("assumption driver: RED (see output_tail, stderr_tail, "
                            "and the full both-streams dump at "
                            + str(ac.get("failure_log")) + ")")
    section = {
        "audits": audits,
        "shims_extracted": len(shims),
        "shims": verdicts,
        "shim_verdict_counts": _counts(verdicts),
        "note_check": nc,
        "assumptions": ac,
        "complete": not blocking,
        "blocking": blocking,
    }
    return section


def _counts(verdicts: List[Dict[str, Any]]) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for v in verdicts:
        out[v.get("verdict", "?")] = out.get(v.get("verdict", "?"), 0) + 1
    return out


def gate_not_run(summary: Dict[str, Any], reason: str) -> None:
    """Mark a summary that was written WITHOUT the completion gate. A
    coverage-only pass (or a report killed before the gate) must never leave
    `complete: true` behind — that file gets read as a result."""
    summary["completion"] = {"complete": False, "blocking": [reason]}
    summary["complete"] = False


def attach_to_summary(summary: Dict[str, Any], config: Dict[str, Any]) -> Dict[str, Any]:
    """Add the ``completion`` section to a coverage summary and derive the
    overall ``complete`` flag (coverage_complete AND completion complete)."""
    declared = summary.get("assumptions")
    if isinstance(declared, dict):
        declared = declared.get("assumptions") or list(declared.values())
    section = run_completion(config, declared if isinstance(declared, list) else None)
    summary["completion"] = section
    summary["complete"] = bool(summary.get("coverage_complete")) and section["complete"]
    ac = section.get("assumptions") or {}
    if ac.get("confinement_withdrawn"):
        # the demand this pass was judged on licensed these pairs: say so
        # where the coverage numbers are read, not only in the gate section
        summary["confinement_withdrawn_by_gate"] = ac["confinement_withdrawn"]
        summary["coverage_numbers_stale"] = ("STALE: confined pair(s) FAILED the gate; "
                                             "missing/demand above were computed with them licensed")
    return summary


def main(argv: Optional[List[str]] = None) -> int:
    import sys
    argv = sys.argv[1:] if argv is None else argv
    if not argv:
        print("usage: python -m concolic_engine.completion <completion_config.json>")
        return 2
    with open(argv[0]) as fh:
        config = json.load(fh)
    section = run_completion(config)
    out = os.path.join(config["batch_dir"], "completion_report.json")
    with open(out, "w") as fh:
        json.dump(section, fh, indent=2)
    for a in section.get("audits", []):
        print(f"  AUDIT {'green' if a['green'] else 'RED  '}    {a['name']}")
    for v in section["shims"]:
        extra = v.get("detail") or (f"coverage {v.get('coverage_pct')}%" if "coverage_pct" in v else "")
        print(f"  {v['verdict']:<14} {v['key']:<52} {extra}")
    if section["note_check"] is not None:
        print(f"  NOTE-CHECK     {'green' if section['note_check']['green'] else 'RED'}")
    if section.get("assumptions") is not None:
        a = section["assumptions"]
        print(f"  ASSUMPTIONS    {'green' if a['green'] else 'RED'} "
              f"(declared {a['declared']}, distinct tested {a['distinct_tested']}, {a['verdict_counts']})")
        if a.get("confinement_tested"):
            print(f"  [confinement] inferred pairs gated: {a['confinement_tested']}, "
                  f"WITHDRAWN by the gate: {len(a.get('confinement_withdrawn') or [])}"
                  + "".join(f"\n      withdrawn: {x[0]} x {x[1]}"
                            for x in (a.get('confinement_withdrawn') or [])[:5]))
    print(f"completion: {'COMPLETE' if section['complete'] else 'NOT complete — ' + '; '.join(section['blocking'])}")
    print(f"report: {out}")
    return 0 if section["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
