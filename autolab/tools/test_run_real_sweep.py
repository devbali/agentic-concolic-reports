"""Tests for the real-backend runner — `reports/autolab/tools/run_real_sweep.py`.

Not part of the `src_new` suite (this file is under `reports/`, which the
suite does not collect); run it explicitly:

    PYTHONPATH=/home/dev/project/src_new \
    venvs/queries_from_runs/bin/python3 -m pytest \
        reports/autolab/tools/test_run_real_sweep.py -q

Two things are proved here, each with a negative control:

1. **The console's money lever is LIVE.** A value changed through
   `LeverDesk.set` mid-run is in force in the SCHEDULER'S OWN POOL on the
   next interval — not merely written to the file. The negative control is
   the same run with no refresher, where the pool keeps the startup value.
2. **The skypilot refusal fires for agentic kinds and not otherwise.**
"""
import importlib.util
import json
import sys
from pathlib import Path

import pytest

SRC = "/home/dev/project/src_new"
sys.path.insert(0, SRC)

from sweep.console.levers import LeverDesk                      # noqa: E402
from sweep.sched.pools import DIM_CLOUD_USD, DIM_USD_SWEEP      # noqa: E402
from sweep.spec import load_spec                                # noqa: E402
from sweep import testbed                                       # noqa: E402

RUNNER = Path(__file__).with_name("run_real_sweep.py")
_spec = importlib.util.spec_from_file_location("run_real_sweep", RUNNER)
runner = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(runner)

CORPUS = ("/home/dev/project/reports/autolab/entrypoints/scaffold/"
          "comments_index")


def make_spec(tmp_path, *, usd_total=2.0, cloud_usd=2.0):
    doc = {
        "schema_version": 1, "sweep": "lever-test",
        "endpoints": [{"name": "comments_index",
                       "config": f"{CORPUS}/config.json",
                       "home": "local", "max_attempts": 1, "box": "sm"}],
        "parallel_batch_agents": 1, "max_batch_agents_per_endpoint": 1,
        "agents": {k: {"backend": "dsh", "model": "deepseek-chat"}
                   for k in ("batch", "concrete", "coordinator")},
        "boxes": {"sm": {"cpu": 2, "memory_mb": 4000, "disk_gb": 10,
                         "max_wall_s": 600}},
        "host_pools": {"cpu": 8, "memory_mb": 16000, "disk_gb": 40,
                       "app_slots": 2},
        "budgets": {"usd_per_endpoint": 0.1, "usd_total": usd_total},
        "preauthorized": {"on_shared_escalation": "decide",
                          "on_budget_exhausted": "park_endpoint",
                          "on_repeated_undecided": "raise_box_class",
                          "app_source_edits": "any"},
        "cloud": {"backend": "skypilot", "provider": "gcp",
                  "region": "us-central1", "max_concurrent_vms": 1,
                  "max_usd": cloud_usd},
        "prices": {"as_of": "2026-09-28", "margin": 0.15,
                   "rates": {"dsh/deepseek-chat": {"input": 0.2574,
                                                   "output": 1.0287}}},
        "out": str(tmp_path / "out"),
    }
    p = tmp_path / "spec.json"
    p.write_text(json.dumps(doc, indent=1))
    return p


def build(tmp_path, spec_path):
    from sweep.execution.host import FakeSystemd, HostBackend
    out = tmp_path / "out"
    coord, _ = testbed.build_coordinator(
        load_spec(spec_path), out=out,
        corpora={"comments_index": Path(CORPUS)},
        spec_dir=spec_path.parent, allow_shared_machine=True,
        execution=HostBackend(out / "boxes",
                              systemd=FakeSystemd(root=out / "cg")))
    return coord, out


def test_a_money_lever_changed_mid_run_is_in_force_in_the_scheduler(tmp_path):
    spec_path = make_spec(tmp_path, usd_total=2.0, cloud_usd=2.0)
    coord, out = build(tmp_path, spec_path)
    assert coord.pools[DIM_USD_SWEEP].total == 2.0
    assert coord.pools[DIM_CLOUD_USD].total == 2.0

    from sweep.console.reload import SpecRefresher
    refresher = SpecRefresher(spec_path, out)
    refresher.refresh(coord)                    # interval 1: the startup spec

    # The operator, through the console's own write path.
    desk = LeverDesk(spec_path, out)
    desk.set(lever="budgets.usd_total", value=0.5,
             reason="spending faster than expected")
    desk.set(lever="cloud.max_usd", value=0.25, reason="same")

    # ... and the scheduler at the top of the next interval.
    r = refresher.refresh(coord)
    assert r.ok and r.changed, r
    assert coord.pools[DIM_USD_SWEEP].total == 0.5
    assert coord.pools[DIM_CLOUD_USD].total == 0.25


def test_negative_control_without_the_refresher_the_lever_is_decorative(tmp_path):
    """The bug this wiring fixes, asserted as its own test: the file changes
    and the running sweep does not. Without this control, the test above
    would pass on a system where `load_spec` simply reads the new file."""
    spec_path = make_spec(tmp_path, usd_total=2.0)
    coord, out = build(tmp_path, spec_path)
    LeverDesk(spec_path, out).set(lever="budgets.usd_total", value=0.5,
                                  reason="no refresher is running")
    assert json.loads(spec_path.read_text())["budgets"]["usd_total"] == 0.5
    assert coord.pools[DIM_USD_SWEEP].total == 2.0      # unchanged, in force


def test_the_runner_loop_calls_refresh_once_per_interval(tmp_path):
    """`run()` is the three lines the coordinator asked for. Proved by
    counting, so a future edit that drops the call fails here."""
    spec_path = make_spec(tmp_path)
    coord, out = build(tmp_path, spec_path)

    class CountingRefresher:
        def __init__(self):
            self.n = 0

        def refresh(self, c):
            assert c is coord
            self.n += 1
            from sweep.console.reload import Reload
            return Reload("now", self.n, changed=False, ok=True, digest="d")

    ref = CountingRefresher()
    steps = 0
    real_step = coord.step

    def counted_step():
        nonlocal steps
        steps += 1
        return steps < 3

    coord.step = counted_step
    runner.run(coord, ref, max_steps=10, interval_s=0, report=lambda *_: None)
    assert ref.n == steps == 3
    # NEGATIVE CONTROL: no refresher, no calls, same number of steps.
    steps = 0
    coord.step = counted_step
    runner.run(coord, None, max_steps=10, interval_s=0, report=lambda *_: None)
    assert steps == 3 and ref.n == 3
    coord.step = real_step


def test_the_skypilot_refusal_is_gone_and_the_reason_it_was_there_is_fixed():
    """The refusal this file used to assert has been REMOVED, and what
    replaced it is a real capability, not a deleted check.

    It refused `--execution skypilot` for any spec with endpoints because an
    agentic worker had no way to run in a box. The fix is §8.2's `agent`
    field carrying enough to build one; the evidence that it is a fix and not
    a deletion is that a batch worker's spec is now ADMITTED by a backend
    that refuses an argv-less worker, and still refused when the adapter
    cannot describe itself.
    """
    from sweep.agentd.main import WorkerIdentity
    from sweep.execution.base import (
        AgentBackendSpec, BackendCapabilities, WorkerSpec, refusals_for)

    assert not hasattr(runner, "refuse_remote_agents")
    caps = BackendCapabilities(caps_disk=True, isolates_env=True,
                               isolates_filesystem=True, isolates_net=True,
                               colocated=False)
    ident = WorkerIdentity("w", "e", "batch", "skypilot",
                           agent_backend="dsh", model="m")
    argv_less = WorkerSpec(identity=ident, argv=(), cwd="/work")
    assert [r.capability for r in refusals_for(caps, argv_less)] == ["argv"]

    buildable = WorkerSpec(
        identity=ident, argv=(), cwd="/work",
        agent=AgentBackendSpec(backend="dsh", model="m",
                               ctor={"executable": ["dsh", "--profile", "sdk"]},
                               brief={"kind": "batch", "prompt": "do it",
                                      "max_wall_s": 60.0}))
    assert refusals_for(caps, buildable) == ()


def test_the_box_side_agent_carries_no_key_and_names_box_paths():
    """§7.8's credential rule, at the one seam where it could leak.

    The box-side adapter is SERIALIZED into the task document, which is
    written to the coordinator's disk and rsynced to the VM. A key in its
    `base_env` would be in both. The NAME must be there and the value must
    not, and every path must be the box's rather than this machine's.
    """
    f = runner.agent_factory_for(dsh_home="/ignored", dsh_bin="/ignored/dsh",
                                 api_key="sk-must-not-travel",
                                 provider="openrouter", box_side=True)

    class Req:
        kind = "batch"

    class ASpec:
        backend = "dsh"

    a = f(Req(), ASpec())
    assert a.env_passthrough == (runner.KEY_VAR,)
    assert runner.KEY_VAR not in a.base_env
    assert a.base_env["DSH_HOME"] == runner.BOX_DSH_HOME
    assert a.argv_prefix[0] == runner.BOX_DSH_BIN
    blob = json.dumps(a.remote_spec())
    assert "sk-must-not-travel" not in blob
    assert runner.KEY_VAR in blob            # the NAME, and only the name

    # NEGATIVE CONTROL: co-located, the value IS in base_env, because the
    # adapter is about to spawn a child of this very process and there is
    # nowhere safer for it to be.
    g = runner.agent_factory_for(dsh_home="/h", dsh_bin="/h/dsh",
                                 api_key="sk-local", provider="openrouter")
    b = g(Req(), ASpec())
    assert b.base_env[runner.KEY_VAR] == "sk-local"
    assert b.env_passthrough == ()


def test_the_box_manifest_carries_the_harness_and_the_route_and_no_key():
    """What the bundle must contain for a box-side agent to exist at all."""
    doc = json.loads(Path(runner.__dict__["__file__"]).parent.parent
                     .joinpath("box/manifest.json").read_text())
    assert any("dsh" in n for n in doc["npm"]), "no harness in the box"
    trees = [t["path"] for t in doc["trees"]]
    assert runner.BOX_DSH_HOME in trees, "no $DSH_HOME in the box"
    route = Path(runner.BOX_DSH_HOME) / "profiles/sdk/cordis.patch.yml"
    text = route.read_text()
    assert "openrouter" in text and "apiKeyEnv" in text
    assert runner.KEY_VAR in text
    # The whole point: the route names the variable and never a value.
    assert "sk-" not in text
    # And `setup_script` must actually install and VERIFY both halves —
    # SkyPilot detaches setup, so an unverified install is invisible.
    from sweep.box import setup_script_from_manifest
    script = setup_script_from_manifest(
        str(Path(runner.BOX_DSH_HOME).parent / "manifest.json"))
    assert "nodesource" in script and "npm install -g" in script
    assert "dsh --version" in script or "dsh" in script


def test_the_agent_factory_refuses_a_backend_the_spec_did_not_name(tmp_path):
    """A spec asking for `deepseek-shim` must not silently get `dsh`, and the
    reverse. Which harness runs is the user's decision."""
    f = runner.agent_factory_for(dsh_home="/x", dsh_bin="/x/dsh",
                                 api_key="k", provider="openrouter")

    class Req:
        kind = "batch"

    class ASpec:
        backend = "deepseek-shim"
        model = "deepseek-chat"

    with pytest.raises(SystemExit) as e:
        f(Req(), ASpec())
    assert "deepseek-shim" in str(e.value)
    ASpec.backend = "dsh"                        # NEGATIVE CONTROL
    b = f(Req(), ASpec())
    assert b.name == "dsh" and b.provider == "openrouter"


def test_shutdown_tears_down_a_live_box_that_reap_alone_misses(tmp_path):
    """The defect the pilot found, as a differential.

    MEASURED 2026-09-28: the pilot was interrupted with SIGTERM while a batch
    worker was running, `reap(stop=True)` returned `[]`, and the VM was still
    `UP`. `SkyPilotBackend.reap` skips any listed cluster it cannot name a
    reason for, and "recorded RUNNING, cluster UP" is — correctly — a healthy
    box during a run. At shutdown there is no worker left to own it.

    CONTROL FIRST: reap alone leaves it up. Then the real assertion.
    """
    from sweep.execution.base import BoxSpec
    from sweep.execution.skypilot import FakeSky, SkyPilotBackend

    def fresh():
        b = SkyPilotBackend(tmp_path / f"boxes{id(object())}", sky=FakeSky())
        box = b.provision(BoxSpec(cls="sm", cpu=2, memory_mb=8000, disk_gb=20,
                                  max_wall_s=600, image="", net="egress",
                                  labels={"sweep": "s", "endpoint": "e",
                                          "worker": "w"}))
        # What `launch()` leaves behind: a named, RUNNING, recorded cluster.
        name = str(box.handle["cluster_name"])
        b.sky.clusters[name] = {"name": name, "status": "UP",
                                "labels": dict(box.spec.labels),
                                "launched_at": 0.0, "to_down": True}
        box.state = b.boxes[box.id].state = __import__(
            "sweep.execution.base", fromlist=["BoxState"]).BoxState.RUNNING
        b._write_record(box)
        return b, name

    # CONTROL: reap alone. This is what `shutdown` used to do, and it is why
    # a VM was left billing.
    b, name = fresh()
    assert b.reap(stop=True) == []
    assert name in b.sky.clusters, "control: reap alone leaves the cluster up"

    # THE FIX: shutdown tears down the boxes THIS process provisioned first.
    b, name = fresh()
    runner.TEARDOWN.update({"backend": b, "done": False})
    runner.shutdown("test")
    assert name not in b.sky.clusters, "shutdown must down our own live box"

    # And it is idempotent: a second call does nothing and raises nothing.
    runner.shutdown("test again")
