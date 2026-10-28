"""§6.1's check worker on its OWN box — now through `run_check`, not around it.

WHAT THIS FILE WAS, AND WHY IT IS SHORT NOW
-------------------------------------------
Until 2026-09-29 `sweep/workers/check.py::run_check` REFUSED any backend that
was not co-located, so this file reimplemented the transport: provision,
stage_in, launch, poll the channel, fetch, read the report. About 150 lines of
it, beside 150 lines of the real thing.

That refusal is gone (`run_check` branches on `BackendCapabilities.colocated`
exactly as `run_batch` does), and with it the three things this file used to
have to say for itself:

* **the interpreter.** It passed `module=(remote_python(),) + CHECK_MODULE[1:]`
  because the shipped default was `("python", "-m", "concolic.check")` and no
  box this project builds has a `python`. The box now answers
  (`execution.base.box_python`, which `SkyPilotBackend` answers from its own
  `agentd_argv`), so nothing here names an interpreter.
* **the child environment.** It passed PATH and PYTHONPATH because
  `plan_check` defaulted `env={}` and a checker with no PYTHONPATH exits 1 in
  28 ms with no stderr anywhere. The box now answers that too
  (`box_python_env`), and agentd captures the child's stderr, so the 28-ms
  death is self-diagnosing.
* **the profile as a mount.** `run_check` declares it itself on a
  non-co-located backend, for the reason this file's old docstring recorded:
  a §8.4 backend syncs the declared mounts, the setup mounts and `ctl/`, and
  nothing else, so `in/profile.json` written into the mirror never arrives.

WHAT IS STILL THIS FILE'S: the campaign's own composition — which manifest
builds the box, which machine shape to pin, where the boxlogs go, and the
unconditional teardown with `ctl/` archived before it. That is caller
business and always was.

NOT RUN ON A REAL VM SINCE THE REWRITE. `run_check`'s remote path is proved
against `FakeVMBackend` (`sweep/tests/test_workers_remote_check.py` and
`tests/sweep_e2e/test_cloud_chain_composes.py`); what is unproved here is only
this file's own argument assembly.
"""
from __future__ import annotations

import argparse, atexit, json, os, signal, sys, time
from pathlib import Path

sys.path.insert(0, "/home/dev/project/src_new")
sys.path.insert(0, "/home/dev/project")

from sweep.execution.base import KEEP_ARTIFACTS, KEEP_NOTHING, box_python
from sweep.execution.skypilot import SkyPilotBackend, RealSky
from sweep.spec import load_spec
from sweep.telemetry.usage import WorkerRows
from sweep.workers.base import BOX_ROOT
from sweep.workers.check import plan_check, plan_for_box, run_check
from sweep.box import REMOTE_SRC, agentd_argv, bundle_mount, setup_script_from_manifest

from reports.autolab.tools import queue_context as qc

STATE = {"backend": None, "box": None, "done": False, "archive": None}


def log(m: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {m}", flush=True)


def shutdown(reason: str) -> None:
    if STATE["done"]:
        return
    STATE["done"] = True
    # `STATE["box"]` stays None: since the rewrite `run_check` provisions and
    # tears down the box itself, so this hook has no box of its own to stop.
    # What it still does is REAP — the one thing that catches a cluster
    # `run_check`'s own teardown could not stop (a `sky down` that failed, or a
    # SIGKILL between provision and teardown), which is why it is unconditional
    # and why it runs on SIGINT, SIGTERM and atexit alike.
    b, box = STATE["backend"], STATE["box"]
    log(f"TEARDOWN ({reason})")
    if b is not None and box is not None:
        # EVIDENCE FIRST, always. `teardown` rmtree's the mirror.
        try:
            d = qc.archive_box(b, box, Path(STATE["archive"]))
            log(f"  ctl/ archived -> {d}")
        except BaseException as exc:
            log(f"  archive RAISED: {type(exc).__name__}: {exc}")
        try:
            t = b.teardown(box, KEEP_NOTHING)
            log(f"  teardown: stopped={t.stopped} detail={t.detail!r}")
        except BaseException as exc:
            log(f"  teardown RAISED: {type(exc).__name__}: {exc}")
    if b is not None:
        try:
            log(f"  reap: {b.reap(stop=True)}")
        except BaseException as exc:
            log(f"  reap RAISED: {type(exc).__name__}: {exc}")
    try:
        log(f"  sky status now: {RealSky().status()}")
    except BaseException as exc:
        log(f"  status RAISED: {type(exc).__name__}: {exc}")


def _sig(signum, _f):
    shutdown(f"signal {signum}")
    sys.exit(130)


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--spec", required=True)
    p.add_argument("--endpoint", required=True)
    p.add_argument("--packet", required=True, help="local packet DIRECTORY")
    p.add_argument("--approved", required=True, help="sha256 of the review doc")
    p.add_argument("--root", required=True, help="where boxes/ and out/ go")
    # PIN THE MACHINE. Left to SkyPilot's optimizer this asks for
    # n4-standard-4, which MEASURED 2026-09-29 is exhausted across
    # us-central1-a/b/c. The batch box does not hit this because the queue
    # config pins n2-standard-4 per box class. Same shape, different family.
    p.add_argument("--instance-type", default="n2-standard-4")
    p.add_argument("--manifest",
                   default="/home/dev/project/reports/autolab/box/manifest.json")
    # `--wait-s` IS GONE (2026-09-29): the poll loop it bounded is gone
    # with it. The ceiling is now agentd's own (§8.1) plus the
    # coordinator-side backstop `run_*` derives from it, which is the one
    # clock that was always the real one.
    p.add_argument("--hello-timeout-s", type=float, default=1200.0)
    a = p.parse_args(argv)

    signal.signal(signal.SIGINT, _sig)
    signal.signal(signal.SIGTERM, _sig)
    atexit.register(shutdown, "atexit")

    root = Path(a.root); root.mkdir(parents=True, exist_ok=True)
    STATE["archive"] = str(root / "boxlogs")
    spec = load_spec(a.spec)
    ep = spec.endpoint(a.endpoint)
    base = root / "base"; base.mkdir(exist_ok=True)   # the checker's cache dir
    # 0777 FOR THE SAME REASON `stage_corpus` sets it: `check_mounts` declares
    # this mount `rw` and the checker WRITES its cache into it, but a
    # file_mount is an rsync that preserves the source's mode and lands
    # outside the box setup's `chown -R`. MEASURED 2026-09-29: the batch box's
    # `rw` batch/ mount arrived read-only and its agent was denied a `touch`.
    # A 0777 source is writable on the far side whoever ends up owning it.
    os.chmod(base, 0o777)

    plan = plan_check(
        spec, a.endpoint, sweep=spec.sweep, worker_id=f"{a.endpoint}-check-1",
        approved=a.approved, config=Path(ep.config), packet=Path(a.packet),
        base=base, image="", execution_backend="skypilot")
    # NOTHING IS PASSED FOR `module` OR `env`. Both are the BOX's and the box
    # says so — see the module docstring. Logged here because the two values
    # this file used to hand-write are exactly the two worth seeing in a log.
    log(f"profile (DERIVED by spec.profile_for, not ours): {plan.profile}")

    backend = SkyPilotBackend(
        root / "boxes", infra="gcp/us-central1", idle_minutes_to_autostop=15,
        disk_tier="medium", use_spot=False,
        instance_type=(a.instance_type or None), keep_on_failure=False,
        # NPM IS NOT OVERRIDDEN. `gate2_live_vm.py` passes `npm=()` and this
        # file copied it; MEASURED 2026-09-29 that is a box that never says
        # hello. `setup_script_from_manifest` takes `verify_cmds` from the SAME
        # manifest, and the manifest verifies `dsh --version` — so with npm
        # empty the setup installs no dsh and then checks for it, `set -e`
        # kills the script, SkyPilot 0.13 DETACHES setup so `launch()` still
        # reports success, and agentd is never started. Two boxes sat for 18
        # minutes with zero frames before this was found.
        setup=setup_script_from_manifest(a.manifest),
        setup_mounts=bundle_mount(), remote_pythonpath=(REMOTE_SRC,),
        agentd_argv=agentd_argv())
    STATE["backend"] = backend
    qc.install_ctl_preserver(backend, Path(STATE["archive"]))

    pf = backend.preflight()
    log(f"preflight ready={pf.ready} missing={list(pf.missing)}")
    if not pf.ready:
        return 2

    # What the box will actually run, before anything is provisioned. This is
    # the plan `run_check` builds for itself; it is resolved here only to log
    # it, and the resolution is idempotent.
    resolved = plan_for_box(plan, backend)
    log(f"box python: {box_python(backend)}")
    log(f"argv: {' '.join(resolved.command_for(BOX_ROOT).argv())}")
    log(f"child env: {sorted(resolved.env)}")
    for m in resolved.mounts():
        log(f"  mount {m.source} -> {m.target} ({m.mode})")

    # THE WHOLE RUN, in one call. `run_check` provisions, declares the profile
    # mount, launches agentd on the box, polls the channel, fetches
    # `report.json` home, reads it through `sweep.schemas`, writes §11.1's row
    # and §12.1's run record, and TEARS THE BOX DOWN on every path including a
    # raise (its own `except BaseException:` clause, `batch.run_batch`'s).
    #
    # `ctl/` is still archived first, and without this file knowing when the
    # teardown happens: `install_ctl_preserver` above shadows
    # `backend.teardown` with a wrapper that archives, so EVERY teardown path
    # — `run_check`'s normal one, its exception clause, and `shutdown()`'s —
    # archives before it stops the cluster.
    log("run_check ... (this is the money)")
    rows = WorkerRows(root / "workers.jsonl")
    result = run_check(plan, backend, rows, grace_s=120.0,
                       hello_timeout_s=a.hello_timeout_s,
                       keep=KEEP_ARTIFACTS)
    log(f"exit_reason={result.exit_reason} outcome={result.facts.outcome} "
        f"complete={result.facts.complete} wall_s={result.wall_s:.0f}")
    log(f"remote: {json.dumps(result.remote)[:400]}")
    if result.stderr_tail:
        log("--- the worker's stderr (tail, as agentd captured it) ---")
        log(result.stderr_tail[-2000:])
    if result.report_path is not None:
        (root / "report.json").write_text(Path(result.report_path).read_text())
        log("--- report.json ---")
        log(Path(result.report_path).read_text()[:4000])
    else:
        log("NO report.json came back")
    shutdown("normal")
    return 0 if result.report_path is not None else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except BaseException:
        import traceback; traceback.print_exc()
        shutdown("exception")
        sys.exit(1)
