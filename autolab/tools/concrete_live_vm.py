"""§6.3's concrete worker on its OWN box — now through `run_concrete`.

WHAT THIS FILE WAS
------------------
It ran the first `concrete` worker there has ever been (2026-09-29), and to do
it it had to work around two gaps, both of which are now closed in `src_new`:

GAP A — `ConcretePlan.worker_spec_for` could not describe a remote agent, so
every §8.2 backend refused the worker
(`Refusal(rule='§8.2', capability='argv')`) and this file bridged it in the
caller with `replace(ws, agent=remote_agent_spec(...))`. `worker_spec_for` now
takes `agent=` exactly as `BatchPlan.worker_spec_for` has since 2026-09-28, so
the bridge is gone. It is not needed anywhere else either: `run_concrete`
builds that spec itself.

GAP B — `run_concrete` refused a non-co-located backend, so this file drove
provision / stage_in / launch / poll / fetch by hand. It now branches on
`BackendCapabilities.colocated` like `run_batch`, so that half of this file is
gone too.

WHAT IS STILL THIS FILE'S: the campaign's composition — the domain NAME and
its brief path (§6.3 passes a name and §4 has no key for one), the credential,
the manifest that builds the box, the machine shape, and the unconditional
teardown with `ctl/` archived before it.

NOT RUN ON A REAL VM SINCE THE REWRITE: `run_concrete`'s remote path is proved
against `FakeVMBackend` in `sweep/tests/test_workers_remote_check.py` and
`tests/sweep_e2e/test_cloud_chain_composes.py`; what is unproved here is this
file's own argument assembly.
"""
from __future__ import annotations

import argparse, atexit, json, signal, sys, time
from pathlib import Path

sys.path.insert(0, "/home/dev/project/src_new")
sys.path.insert(0, "/home/dev/project")

from sweep.execution.base import KEEP_ARTIFACTS, KEEP_NOTHING
from sweep.execution.skypilot import SkyPilotBackend, RealSky
from sweep.spec import load_spec
from sweep.telemetry.usage import WorkerRows
from sweep.workers.base import BOX_ROOT
from sweep.workers.concrete import (
    REL_REVIEW_ITEMS, plan_concrete, run_concrete)
from sweep.box import REMOTE_SRC, agentd_argv, bundle_mount, setup_script_from_manifest

sys.path.insert(0, "/home/dev/project/reports/autolab/tools")
import run_real_sweep as rrs
from reports.autolab.tools import queue_context as qc

DOMAIN = "ruby_rails_sql"
BRIEF = "/home/dev/project/src_new/domains/ruby_rails_sql/briefs/concrete_agent.md"
STATE = {"backend": None, "box": None, "done": False, "archive": None}


def log(m: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {m}", flush=True)


def shutdown(reason: str) -> None:
    if STATE["done"]:
        return
    STATE["done"] = True
    # `STATE["box"]` stays None: `run_concrete` provisions and tears down the
    # box itself (including on a raise). What is left for this hook is the REAP,
    # which catches a cluster no teardown could stop.
    b, box = STATE["backend"], STATE["box"]
    log(f"TEARDOWN ({reason})")
    if b is not None and box is not None:
        try:
            log(f"  ctl/ archived -> {qc.archive_box(b, box, Path(STATE['archive']))}")
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
    p.add_argument("--packet", default="", help="local packet dir (optional)")
    p.add_argument("--batch-dir", default="", help="the corpus dir (optional)")
    p.add_argument("--policy", default="", help="the rendered policy (optional)")
    p.add_argument("--root", required=True)
    p.add_argument("--key-file", default="/home/dev/project/openrouter_api_key.txt")
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
    p.add_argument("--hello-timeout-s", type=float, default=1500.0)
    a = p.parse_args(argv)

    signal.signal(signal.SIGINT, _sig)
    signal.signal(signal.SIGTERM, _sig)
    atexit.register(shutdown, "atexit")

    root = Path(a.root); root.mkdir(parents=True, exist_ok=True)
    STATE["archive"] = str(root / "boxlogs")
    spec = load_spec(a.spec)
    ep = spec.endpoint(a.endpoint)
    aspec = spec.agent_for(a.endpoint, "batch")   # §4 has no `concrete` agent key
    key = Path(a.key_file).read_text().strip()
    import os
    os.environ[rrs.KEY_VAR] = key

    plan = plan_concrete(
        spec, a.endpoint, sweep=spec.sweep, worker_id=f"{a.endpoint}-concrete-1",
        domain=DOMAIN, brief=BRIEF, config=Path(ep.config), image="",
        execution_backend="skypilot", agent_backend=aspec.backend,
        model=aspec.model, effort=aspec.effort,
        packet=Path(a.packet) if a.packet else None,
        batch_dir=Path(a.batch_dir) if a.batch_dir else None,
        policy=Path(a.policy) if a.policy else None)
    log(f"plan_concrete OK domain={plan.domain!r} brief={len(plan.brief)} chars "
        f"mounts={[m.target for m in plan.mounts()]}")

    factory = rrs.agent_factory_for(
        dsh_home=rrs.BOX_DSH_HOME, dsh_bin=rrs.BOX_DSH_BIN, api_key=key,
        provider="openrouter", box_side=True)

    class Req:
        id = plan.identity.worker_id
        endpoint = a.endpoint
        kind = "concrete"
        attempt = 1

    agent = factory(Req(), aspec)

    backend = SkyPilotBackend(
        root / "boxes", infra="gcp/us-central1", idle_minutes_to_autostop=15,
        disk_tier="medium", use_spot=False,
        instance_type=(a.instance_type or None), keep_on_failure=False,
        # NPM IS NOT OVERRIDDEN — see `check_live_vm.py` and
        # `run_real_sweep.py` for the 18 minutes of silent boxes that bought
        # this comment.
        setup=setup_script_from_manifest(a.manifest),
        setup_mounts=bundle_mount(), remote_pythonpath=(REMOTE_SRC,),
        agentd_argv=agentd_argv(), secret_envs=(rrs.KEY_VAR,))
    STATE["backend"] = backend
    qc.install_ctl_preserver(backend, Path(STATE["archive"]))

    pf = backend.preflight()
    log(f"preflight ready={pf.ready} missing={list(pf.missing)}")
    if not pf.ready:
        return 2

    # THE SPEC, AS THE PLAN BUILDS IT — no `replace()`, no `remote_agent_spec`
    # call here. Logged before anything is provisioned because admission is the
    # cheap half and it used to be the half that failed.
    worker = plan.worker_spec_for(BOX_ROOT, agent)
    log(f"WorkerSpec: argv={worker.argv} "
        f"agent.buildable={getattr(worker.agent, 'buildable', None)}")
    refusals = backend.admits(plan.admission_spec_for(BOX_ROOT, agent), plan.box)
    if refusals:
        log(f"REFUSED: {[r.detail for r in refusals]}")
        return 2

    # THE WHOLE RUN, in one call — provision, stage, launch agentd on the box,
    # build the adapter THERE, poll, fetch `review_items.json` home, verify its
    # digest, write §11.1's row and §12.1's run record, tear the box down on
    # every path. `ctl/` is archived first by the teardown wrapper installed
    # above, on every one of those paths.
    log("run_concrete ... (this is the money)")
    rows = WorkerRows(root / "workers.jsonl")
    result = run_concrete(plan, backend, agent, rows, grace_s=120.0,
                          hello_timeout_s=a.hello_timeout_s,
                          keep=KEEP_ARTIFACTS)
    log(f"exit_reason={result.exit_reason} submitted={result.submitted} "
        f"wall_s={result.wall_s:.0f} turns={result.turns} "
        f"tool_calls={result.tool_calls} cost={result.cost}")
    log(f"remote: {json.dumps(result.remote)[:400]}")

    rel = REL_REVIEW_ITEMS.split("out/", 1)[-1]   # "review_items.json"
    rc = 1
    items = result.review_items.path
    if result.submitted and items is not None and Path(items).exists():
        (root / rel).write_text(Path(items).read_text())
        log(f"--- {rel} (digest {result.review_items.digest}) ---")
        log(Path(items).read_text()[:4000])
        rc = 0
    else:
        log(f"NO verified {rel}: {result.review_items.as_json()}")
    shutdown("normal")
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except BaseException:
        import traceback; traceback.print_exc()
        shutdown("exception")
        sys.exit(1)
