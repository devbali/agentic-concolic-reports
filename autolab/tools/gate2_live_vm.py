"""Gate 2 — one cheap VM, end to end, then gone.

Proves the seam `sweep/README.md` says has never been exercised: a real
`sky.launch`, a real `file_mounts` sync up, a real command run under agentd on
the far side, a real artifact rsynced down, and a real `sky down`.

Run with the sky venv, the only interpreter that can import the SDK:

    PATH=/home/dev/tools/google-cloud-sdk/bin:$PATH \
    PYTHONPATH=/home/dev/project/src_new \
    /home/dev/project/venvs/sky/bin/python3 \
        reports/autolab/tools/gate2_live_vm.py --stage trivial

Stages:
  trivial   tiny setup, tiny mount, one shell command, one artifact back
  box       the real bundle, then one diaspora endpoint inside the box

TEARDOWN IS UNCONDITIONAL. `finally`, SIGINT and SIGTERM all reach the same
`shutdown()`, which downs the cluster, reaps, and prints `sky status`.
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import atexit
import time
import traceback
from pathlib import Path

sys.path.insert(0, "/home/dev/project/src_new")

from sweep.agentd.main import WorkerIdentity
from sweep.execution.base import (
    KEEP_NOTHING, BoxSpec, Mount, WorkerSpec, build_child_env,
)
from sweep.execution.skypilot import SkyPilotBackend, RealSky
sys.path.insert(0, "/home/dev/project")
from reports.autolab.tools import queue_context as _qc  # noqa: E402
from sweep.box import (
    REMOTE_SRC, agentd_argv, bundle_mount, setup_script,
    setup_script_from_manifest,
)

LABELS = {"sweep": "gate2", "endpoint": "smoke", "worker": "w-1"}
#: where stage `trivial` puts the checkout (stage `box` gets it from the bundle)
REMOTE_TRIVIAL_SRC = "/opt/sweep_src"
STATE = {"backend": None, "box": None, "done": False, "archive": "/tmp"}


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def shutdown(reason: str) -> None:
    """Every exit path. Idempotent."""
    if STATE["done"]:
        return
    STATE["done"] = True
    b, box = STATE["backend"], STATE["box"]
    log(f"TEARDOWN ({reason})")
    if b is not None and box is not None:
        # EVIDENCE BEFORE TEARDOWN. `KEEP_NOTHING` rmtree's the whole box tree,
        # and that takes `ctl/events.ndjson` AND anything `fetch` just brought
        # down with it. MEASURED 2026-09-29: this stage fetched two real dumps
        # and an exploration_summary.json off a box, printed their sizes, and
        # then deleted all three eight seconds later. Archive first.
        try:
            print(f"  archived -> {_qc.archive_box(b, box, Path(STATE['archive']))}",
                  flush=True)
        except BaseException as exc:
            log(f"  archive RAISED: {type(exc).__name__}: {exc}")
        try:
            t = b.teardown(box, KEEP_NOTHING)
            log(f"  teardown: stopped={t.stopped} detail={t.detail!r}")
        except BaseException as exc:
            log(f"  teardown RAISED: {type(exc).__name__}: {exc}")
    if b is not None:
        try:
            r = b.reap(stop=True)
            log(f"  reap: {r}")
        except BaseException as exc:
            log(f"  reap RAISED: {type(exc).__name__}: {exc}")
    try:
        log(f"  sky status now: {RealSky().status()}")
    except BaseException as exc:
        log(f"  status RAISED: {type(exc).__name__}: {exc}")


def _sig(signum, _frame):
    shutdown(f"signal {signum}")
    sys.exit(130)


def trivial_worker(marker_text: str) -> WorkerSpec:
    """One shell command that proves all three legs at once: it READS the
    file that was synced up, WRITES an artifact, and writes the §8.1 marker
    whose digest agentd recomputes."""
    script = (
        "set -e; "
        "echo '--- box says hello ---'; "
        "uname -a; python3 -V; "
        "echo '--- what was synced up ---'; ls -la /work/in/ || true; "
        "cat /work/in/hello.txt; "
        "mkdir -p /work/out; "
        f"python3 -c \"import json,pathlib,platform,os;"
        f"pathlib.Path('/work/out/report.json').write_text(json.dumps("
        f"{{'marker':'{marker_text}',"
        f"'read_back':pathlib.Path('/work/in/hello.txt').read_text().strip(),"
        f"'uname':platform.platform(),'py':platform.python_version(),"
        f"'sweep_importable':__import__('importlib').util.find_spec('sweep') "
        f"is not None}}, indent=1))\"; "
        "sha256sum /work/out/report.json | cut -d' ' -f1 "
        "> /work/out/report.json.submitted; "
        "echo '--- done ---'; cat /work/out/report.json"
    )
    return WorkerSpec(
        identity=WorkerIdentity("w-1", "smoke", "check", "skypilot"),
        argv=("bash", "-lc", script),
        env=build_child_env({"PATH": "/usr/local/bin:/usr/bin:/bin"}),
        cwd="/work",
        artifacts=("report.json",),
    )


def endpoint_worker(endpoint: str) -> WorkerSpec:
    """Stage `box`: run one real diaspora endpoint INSIDE the box, out of the
    bundle, and bring its dumps home."""
    script = (
        "set -e; "
        "export PATH=/home/dev/tools/jdk-21.0.5/bin:"
        "/home/dev/tools/jruby-9.3.0.0/bin:$PATH; "
        "export JAVA_HOME=/home/dev/tools/jdk-21.0.5; "
        "export GEM_HOME=/home/dev/.gem/jruby/2.6.0; "
        "export RAILS_ENV=concolic; "
        "mkdir -p /work/out/dumps; "
        "cd /home/dev/project/ruby_examples/dse-apps/apps/diaspora; "
        "MAX_RUNS=2 TIME_BUDGET=300 DUMP_OUT=/work/out/dumps "
        "bundle exec jruby "
        "-I/home/dev/project/ruby_examples/dse-apps/apps/diaspora "
        f"/home/dev/project/reports/autolab/entrypoints/scaffold/{endpoint}"
        "/run_dse.rb 2>&1 | tail -40; "
        "ls -la /work/out/dumps; "
        "python3 - <<'EOF'\n"
        "import hashlib, pathlib\n"
        "root = pathlib.Path('/work/out/dumps'); lines = []\n"
        "for p in sorted(root.rglob('*')):\n"
        "    if p.is_file():\n"
        "        h = hashlib.sha256(p.read_bytes()).hexdigest()\n"
        "        lines.append(f'{p.relative_to(root).as_posix()}\\0{p.stat().st_size}\\0{h}\\n')\n"
        "d = hashlib.sha256(''.join(sorted(lines)).encode()).hexdigest()\n"
        "pathlib.Path('/work/out/dumps.submitted').write_text(d + '\\n')\n"
        "EOF\n"
    )
    return WorkerSpec(
        identity=WorkerIdentity("w-1", endpoint, "check", "skypilot"),
        argv=("bash", "-lc", script),
        env=build_child_env({"PATH": "/usr/local/bin:/usr/bin:/bin"}),
        cwd="/work",
        artifacts=("dumps",),
    )


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--stage", choices=("trivial", "box"), default="trivial")
    p.add_argument("--endpoint", default="comments_index")
    p.add_argument("--root", default="/tmp/claude-1000/-home-dev-project/"
                                     "4def6baa-dc40-472d-93be-f455baf9876b/"
                                     "scratchpad/gate2")
    p.add_argument("--wait-s", type=float, default=2400.0)
    p.add_argument("--hello-timeout-s", type=float, default=900.0,
                   help="tear down if agentd never says hello")
    p.add_argument("--cpu", type=int, default=2)
    p.add_argument("--mem-mb", type=int, default=8000)
    p.add_argument("--disk-gb", type=int, default=30)
    p.add_argument("--infra", default="gcp/us-central1")
    p.add_argument("--disk-tier", default="medium")
    p.add_argument("--manifest",
                   default="/home/dev/project/reports/autolab/box/manifest.json")
    p.add_argument("--keep", action="store_true",
                   help="DANGEROUS: leave the cluster up (costs money)")
    a = p.parse_args(argv)

    signal.signal(signal.SIGINT, _sig)
    signal.signal(signal.SIGTERM, _sig)
    atexit.register(shutdown, "atexit")

    root = Path(a.root)
    root.mkdir(parents=True, exist_ok=True)
    STATE["archive"] = str(root / "boxlogs")
    inbox = root / "stage"
    inbox.mkdir(exist_ok=True)
    hello = inbox / "hello.txt"
    token = f"gate2-{int(time.time())}"
    hello.write_text(f"{token}\n")

    if a.stage == "trivial":
        # The same generated setup as stage `box`, minus the bundle: the
        # interpreter install is NOT optional (see sweep.box.PYTHON_VERSION).
        setup = (
            "\n".join(
                l for l in setup_script(pip=(), npm=(), verify=False).splitlines()
                if "box-bundle" not in l and "tar -xzf" not in l
                and "chown -R \"$(id -u):$(id -g)\" /home/dev" not in l)
            + "\nsudo mkdir -p /work && sudo chown -R \"$(id -u):$(id -g)\" /work\n"
            + "python3.12 -VV\n"
            + "echo '[box] trivial setup complete'\n")
        # agentd is `python3 -m sweep.agentd` on the far side, so the sweep
        # package has to BE there. The image that was supposed to carry it
        # does not exist; until the bundle is in play (stage `box`) the
        # cheapest honest substitute is to sync the checkout up and name it
        # on PYTHONPATH. Measured 2026-09-28: without this the VM provisions,
        # setup succeeds, and the job dies as
        # `No module named 'sweep'` while the channel reports no frames.
        mounts = {REMOTE_TRIVIAL_SRC: "/home/dev/project/src_new"}
        worker = trivial_worker(token)
        want = ["report.json"]
        pypath = (REMOTE_TRIVIAL_SRC,)
    else:
        # npm NOT overridden (fixed 2026-09-29, W4). `setup_script_from_manifest`
        # takes `verify_cmds` from the same manifest and the manifest verifies
        # `dsh --version`, so `npm=()` builds a setup that checks for a harness
        # it did not install, `set -e` kills the script, SkyPilot 0.13 DETACHES
        # setup so `launch()` still reports success, and agentd never starts.
        # MEASURED on two real boxes that sat 18 minutes with zero frames.
        setup = setup_script_from_manifest(a.manifest)
        mounts = bundle_mount()
        worker = endpoint_worker(a.endpoint)
        want = ["dumps"]
        pypath = (REMOTE_SRC,)

    backend = SkyPilotBackend(
        root / "boxes",
        infra=a.infra,
        idle_minutes_to_autostop=15,   # backstop if this process dies hard
        disk_tier=(a.disk_tier or None),
        use_spot=False,
        keep_on_failure=bool(a.keep),
        setup=setup,
        setup_mounts=mounts,
        remote_pythonpath=pypath,
        # MEASURED: the image's own `python3` is 3.10 and `sweep` needs 3.11+.
        agentd_argv=agentd_argv(),
    )
    STATE["backend"] = backend

    pf = backend.preflight()
    log(f"preflight ready={pf.ready} missing={list(pf.missing)}")
    if not pf.ready:
        log("REFUSING to launch: preflight is not ready")
        return 2

    rc = 1
    try:
        box = backend.provision(BoxSpec(
            cls="sm", cpu=a.cpu, memory_mb=a.mem_mb, disk_gb=a.disk_gb,
            max_wall_s=3600,
            image="", net="none", labels=dict(LABELS)))
        STATE["box"] = box
        log(f"provisioned box id={box.id} cluster={box.handle['cluster_name']}")

        backend.stage_in(box, [Mount(source=str(hello), target="in/hello.txt",
                                     mode="ro")])
        log(f"staged in: {box.handle['stage_bytes']} bytes")

        plan = backend.task_plan(box, worker)
        log(f"plan: cpus={plan.cpus} mem={plan.memory} disk={plan.disk_size} "
            f"image={plan.image_id} setup={'yes' if plan.setup else 'NO'} "
            f"mounts={sorted(plan.file_mounts)}")

        t0 = time.time()
        log("sky.launch ... (this is the first money)")
        ch = backend.launch(box, worker)
        log(f"launched in {time.time() - t0:.0f}s; handle={json.dumps({k: v for k, v in box.handle.items() if k in ('cluster_name', 'request_id', 'job_id')})}")

        deadline = time.time() + a.wait_s
        # MEASURED 2026-09-28: SkyPilot 0.13 DETACHES setup, so `sky.launch`
        # returns success and `outcome.setup_failed` is False even when setup
        # exited 1. The cluster then sits UP and billing while the channel
        # reports nothing. A box whose agentd never said `hello` is a dead
        # box, and this is the only thing that notices.
        hello_by = time.time() + a.hello_timeout_s
        seen = 0
        terminal = None
        while time.time() < deadline:
            if not seen and time.time() > hello_by:
                log(f"NO `hello` IN {a.hello_timeout_s:.0f}s — agentd never "
                    "started. Setup probably failed (it is detached, so the "
                    "launch call could not tell us). Tearing down.")
                log(f"  read it with: sky logs {box.handle['cluster_name']} 1")
                break
            for f in ch.frames():
                seen += 1
                ch.after_seq = max(ch.after_seq, f.seq)
                log(f"  frame {f.seq} {f.type.value} {json.dumps(f.body)[:220]}")
                if f.type.value == "done":
                    terminal = f
            if terminal is not None:
                break
            time.sleep(5.0)
        log(f"frames seen={seen} terminal={'yes' if terminal else 'NO (timed out)'}")

        got = backend.fetch_detail(box, want)
        log(f"fetched: path={got.path} bytes={got.bytes_moved} copied={got.copied} missing={list(got.missing)}")
        for f in sorted(Path(got.path).rglob("*")):
            if f.is_file():
                log(f"   artifact {f.relative_to(got.path)} {f.stat().st_size}b")
        pulled = Path(got.path) / want[0]
        if pulled.is_file():
            log("  --- artifact content ---")
            log(pulled.read_text()[:1200])
            if a.stage == "trivial":
                doc = json.loads(pulled.read_text())
                assert doc["marker"] == token, doc
                assert doc["read_back"] == token, doc
                log("  ROUND TRIP VERIFIED: the token went up in a file mount "
                    "and came back down in an artifact")
        rc = 0 if (terminal is not None and not got.missing) else 1
    except BaseException:
        traceback.print_exc()
        rc = 1
    finally:
        if a.keep:
            log("--keep: NOT tearing down. THIS COSTS MONEY.")
            STATE["done"] = True
            try:
                log(f"  sky status: {RealSky().status()}")
            except BaseException:
                pass
        else:
            shutdown("normal exit" if rc == 0 else "failure")
    log(f"RESULT: {'PASS' if rc == 0 else 'FAIL'}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
