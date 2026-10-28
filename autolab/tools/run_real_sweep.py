"""The real-backend entry point — `testbed.py`'s assembly, with the two fakes
replaced by the real things.

`sweep/testbed.py` says it outright: "No real LLM call, ever... There is no
flag that swaps in a real backend." This program is that flag, and it lives
OUTSIDE `sweep/` for two reasons:

1. §18.4 — the console "is a dependency of nothing", enforced by
   `tests/test_console_read.py` AST-scanning every module outside
   `sweep/console/` for an import of it. The scheduling loop is where
   `SpecRefresher.refresh()` has to be called, so the loop cannot live in
   `sweep/`. **The runner is what holds both.**
2. Nothing in `sweep/` may name an application tree
   (`tests/test_self_contained.py`), and a real run names one in every
   argument it takes.

Two execution backends, chosen with `--execution`:

  host      the boxes are this machine (§8.5). The agent runs in THIS
            process, against the box's own tree, because the tree is the box.
  skypilot  the boxes are GCP VMs built from `sweep/box/`. The agent runs ON
            THE VM: `run_batch` calls `backend.launch()`, `agentd` is PID 1
            there and builds the adapter itself from §8.2's `agent` block,
            and this process reads frames and pulls the packet home. **No
            model process runs on the dev box.**

The agent backend is always real: `agents/deepseek.py` driving the real
`dsh --profile sdk`, routed at OpenRouter through a pi-ai provider route.

WHERE THE SAME TWO BACKENDS DIFFER HERE, and it is only in paths. The `dsh`
adapter is configured with the paths of the machine it will RUN on, which is
this one for `host` and the box for `skypilot` — a different binary location,
a different `$DSH_HOME`, and a credential that travels as a NAME rather than
a value. `agent_factory_for(box_side=...)` is that difference and nothing
else; everything downstream is the same object.
"""
from __future__ import annotations

import argparse
import atexit
import json
import os
import signal
import sys
import time
import traceback
from pathlib import Path
from typing import Any, Sequence

SRC = "/home/dev/project/src_new"
sys.path.insert(0, SRC)

from sweep import engine_digest, testbed                         # noqa: E402
from sweep.agents.deepseek import DeepSeekBackend                # noqa: E402
from sweep.box import REMOTE_SRC, agentd_argv, bundle_mount, setup_script_from_manifest  # noqa: E402
from sweep.console.reload import SpecRefresher                   # noqa: E402
from sweep.execution.base import KEEP_ARTIFACTS                  # noqa: E402
from sweep.execution.host import HostBackend, SystemdUser, FakeSystemd  # noqa: E402
from sweep.execution.skypilot import SkyPilotBackend             # noqa: E402
from sweep.spec import load_spec                                 # noqa: E402

DEFAULT_KEY_FILE = "/home/dev/project/openrouter_api_key.txt"
DEFAULT_DSH = ("/tmp/claude-1000/-home-dev-project/"
               "4def6baa-dc40-472d-93be-f455baf9876b/scratchpad/dshinstall")

TEARDOWN: dict[str, Any] = {"backend": None, "done": False}


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def shutdown(reason: str) -> None:
    """Money discipline: every exit path tears its own boxes down, THEN reaps.

    **The explicit teardown is not belt-and-braces; `reap(stop=True)` alone
    misses the live case.** MEASURED 2026-09-28: the pilot was interrupted
    with SIGTERM while a batch worker was running, `reap(stop=True)` returned
    `[]`, and the VM was still `UP` a minute later.

    `SkyPilotBackend.reap` builds a reason (`why`) for each listed cluster and
    skips any cluster it cannot name a reason for. Its four reasons are: a
    failed previous teardown, a deliberate `keep_on_failure`, a cluster stuck
    in INIT past the grace period, and **a record that says GONE while the
    cluster is UP**. A box whose record says RUNNING and whose cluster is UP
    is, correctly, a healthy box — during a run. At shutdown there is no
    worker left to own it, and that is exactly the state a Ctrl-C leaves
    behind, which is the most common way a sweep ends.

    So this reaps for the cases reap is for (orphans from earlier attempts,
    other processes, stale records) and tears down the boxes THIS process
    provisioned by identity, which it holds in `backend.boxes`. Idempotent.

    The underlying `reap()` gap is written up in `reports/autolab/
    docs/LAUNCH_SWEEP.md` §8 as a src/ defect with a test to write; it is not
    patched from here, because changing what reaping means is a decision
    about somebody else's VMs (§8.5's "recorded identity" rule).
    """
    if TEARDOWN["done"]:
        return
    TEARDOWN["done"] = True
    b = TEARDOWN["backend"]
    if b is None or not hasattr(b, "reap"):
        return
    log(f"TEARDOWN ({reason})")
    # 1. The boxes we provisioned, by recorded identity, whatever state their
    #    worker is in. This is the one that catches an interrupted run.
    for box in list(getattr(b, "boxes", {}).values()):
        if str(getattr(box, "state", "")) == "gone":
            continue
        try:
            t = b.teardown(box, KEEP_ARTIFACTS)
            log(f"  teardown {box.id}: stopped={t.stopped} detail={t.detail!r}")
        except BaseException as exc:                              # noqa: BLE001
            log(f"  teardown {box.id} RAISED: {type(exc).__name__}: {exc}")
    # 2. Everything else that looks like ours and should not be up.
    try:
        log(f"  reap: {b.reap(stop=True)}")
    except BaseException as exc:                                  # noqa: BLE001
        log(f"  reap RAISED: {type(exc).__name__}: {exc}")
    if getattr(b, "name", "") != "skypilot":
        return                       # nothing in the cloud to verify
    try:
        from sweep.execution.skypilot import RealSky
        log(f"  sky status now: {RealSky().status()}")
    except BaseException as exc:                                  # noqa: BLE001
        log(f"  status RAISED: {type(exc).__name__}: {exc}")


def _sig(signum, _frame):
    shutdown(f"signal {signum}")
    sys.exit(130)


# ---------------------------------------------------------------- the agent


#: What the bundle unpacks `$DSH_HOME` to on a box. The profile is DATA under
#: `reports/`, carries the OpenRouter route, and carries no credential —
#: `reports/autolab/box/dshhome/README.md` says why that is safe.
BOX_DSH_HOME = "/home/dev/project/reports/autolab/box/dshhome"
#: `npm install -g` puts it on PATH; `sweep.box.setup_script` does the install.
BOX_DSH_BIN = "dsh"
#: The one variable that must reach the VM and must not reach a file.
KEY_VAR = "OPENROUTER_API_KEY"


def agent_factory_for(*, dsh_home: str, dsh_bin: str, api_key: str,
                      provider: str, request_timeout_s: float = 120.0,
                      box_side: bool = False):
    """The REAL `dsh` adapter, one per worker request.

    `provider` is a constructor argument on the adapter and has no spec key
    (`spec._AGENT_KEYS` is `{backend, model, effort, env, cost_reporting}`), so
    it is named here rather than in the spec. That is a real gap, written down
    rather than worked around: a spec cannot today say WHICH provider route a
    `dsh` worker uses, and a sweep that mixed two would need it to.

    `box_side` is the §8.4 configuration: the adapter is built HERE but
    started THERE, so every path in it is the box's and the key is declared
    rather than carried.

    **The key.** Co-located, the value goes in `base_env` because the adapter
    is about to spawn a child of this process and there is nowhere safer for
    it to be. Box-side, the value must not be in the adapter at all: the
    adapter is SERIALIZED into the task document (`remote_spec()`), which is
    written to the coordinator's disk and rsynced to the VM. So the box-side
    adapter declares `env_passthrough=("OPENROUTER_API_KEY",)`, which makes
    `remote_spec()` report the NAME and drop the value, and `agentd` resolves
    it from its own environment on the box. The value's only route to the VM
    is SkyPilot's `envs`, via `SkyPilotBackend(secret_envs=...)`, which reads
    it from THIS process's environment at launch.
    """
    if box_side:
        base_env = {
            # `dsh`, `node` and `python3.12` all land on the standard prefixes
            # via apt/npm; nothing here points at the dev box.
            "PATH": "/usr/local/bin:/usr/bin:/bin",
            "HOME": "/home/dev",
            "DSH_HOME": BOX_DSH_HOME,
            # NO KEY. See the docstring.
        }
    else:
        base_env = {
            "PATH": "/usr/local/bin:/usr/bin:/bin:" + os.path.dirname(sys.executable),
            "HOME": os.environ.get("HOME", "/home/dev"),
            "DSH_HOME": dsh_home,
            KEY_VAR: api_key,
        }

    def factory(req: Any, aspec: Any) -> DeepSeekBackend:
        if aspec.backend != "dsh":
            raise SystemExit(
                f"{req.kind} worker asks for backend {aspec.backend!r}; this "
                "runner builds `dsh` only. Point the spec at `dsh`, or add the "
                "adapter here deliberately — do not let a spec silently get a "
                "different harness than it named")
        return DeepSeekBackend(
            # Box-side, the paths are the BOX's and the caller's are ignored:
            # one place decides them, so a runner that forgot to swap them
            # cannot produce an adapter that points at the dev box.
            executable=[BOX_DSH_BIN if box_side else dsh_bin,
                        "--profile", "sdk"],
            provider=provider,
            base_env=dict(base_env),
            request_timeout_s=request_timeout_s,
            env_passthrough=(KEY_VAR,) if box_side else (),
        )

    return factory


# ------------------------------------------------------------ the execution


def _instance_types(raw: str):
    """`--instance-type` as one shape or as a per-box-class map.

    "n2-standard-4"                     -> every box
    "sm=n2-standard-2,md=n2-standard-4" -> per §4 box class
    ""                                  -> SkyPilot's own optimizer

    A sweep with more than one box class needs the second form: a shape big
    enough for `md` over-provisions every `sm` box, and one sized for `sm`
    cannot run `md` at all. `sweep_openrouter.json` has 77 `sm` and 84 `md`.
    """
    raw = (raw or "").strip()
    if not raw:
        return None
    if "=" not in raw:
        return raw
    out = {}
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        cls, _, shape = part.partition("=")
        if not cls.strip() or not shape.strip():
            raise SystemExit(
                f"--instance-type {raw!r}: expected `class=shape` pairs, e.g. "
                "`sm=n2-standard-2,md=n2-standard-4`")
        out[cls.strip()] = shape.strip()
    return out


def execution_for(kind: str, *, out: Path, manifest: str, region: str,
                  real_systemd: bool, instance_type: str | None = None):
    if kind == "host":
        systemd = SystemdUser() if real_systemd else FakeSystemd(root=out / "cg")
        return HostBackend(out / "boxes", systemd=systemd)
    if kind == "skypilot":
        return SkyPilotBackend(
            out / "boxes",
            infra=f"gcp/{region}" if region else "gcp",
            # A backstop ONLY: this process tears its own boxes down. It
            # exists for the case where this process dies hard, which is
            # exactly when a VM is left billing.
            idle_minutes_to_autostop=15,
            # `npm` is NOT overridden any more. It used to be forced empty
            # here, which meant the box got python, JRuby and the app and no
            # HARNESS — fine for a `check` worker and fatal for an agentic
            # one. The manifest names `@deepseek-ai/dsh` and
            # `setup_script` installs node and it, and VERIFIES both, because
            # SkyPilot 0.13 detaches setup and a missing harness is otherwise
            # discovered only as a box that says nothing.
            setup=setup_script_from_manifest(manifest),
            setup_mounts=bundle_mount(),
            remote_pythonpath=(REMOTE_SRC,),
            agentd_argv=agentd_argv(),
            # §7.8's credential path. NAMES only: the value is read from this
            # process's environment inside `RealSky.to_task` and is never in
            # the plan, the box record or the task document. See
            # `TaskPlan.secret_envs`.
            secret_envs=(KEY_VAR,),
            # MEASURED 2026-09-28, and the reason this is not left to the
            # optimizer: with only cpus/memory given, SkyPilot's GCP catalog
            # picked `n4-standard-2`, and n4 had NO CAPACITY in any
            # us-central1 zone — a/b/c/f all answered
            # `ResourcesUnavailableError`, which costs four zone attempts per
            # box and then fails the launch. §8.4 also wants it pinned for a
            # second reason: n4 supports only `hyperdisk-balanced`, so a
            # sweep whose boxes land in two families splits its disk across
            # two GCP quota buckets.
            instance_type=instance_type,
        )
    raise SystemExit(f"unknown --execution {kind!r}")


AGENTIC_KINDS = ("batch", "concrete")

# HISTORY, kept because the reason it is gone matters more than the fact.
#
# This runner used to refuse `--execution skypilot` for any spec with
# endpoints, quoting `workers/base.py::agent_supervisor_for`'s own note: an
# agentic worker's `WorkerSpec.argv` was `()`, `execution.base.refusals_for`
# refused an empty argv under §8.2, so `run_batch` never called
# `backend.launch()` at all — it provisioned the box, staged in, took
# `backend.tree_of(box)` and supervised the adapter IN THIS PROCESS. On
# `host` that is correct; on `skypilot` the tree is a local mirror, so the
# agent would have run here, read an empty directory, and the VM would have
# idled and billed for the whole attempt.
#
# The note named two routes and said the choice belonged to whoever built
# §8.3/§8.4. That build (2026-09-28) took the second: **an agent-building
# branch in agentd's entrypoint**, because §8.1 gives agentd "the agent
# process (via an `AgentBackend`, §7.2)" and §7.2 opens "`AgentBackend` runs
# *inside* the box, driven by `agentd`". §8.2's `agent` field became
# `execution.base.AgentBackendSpec`, which carries what agentd needs to
# construct the adapter; `refusals_for` now accepts argv OR a buildable
# agent; and `run_batch` branches on `BackendCapabilities.colocated`, never
# on a backend name.
#
# `sweep/tests/test_workers_remote_agent.py` holds both halves, including the
# negative control that `host` still never calls `launch()`.


# ------------------------------------------------------------------- driving


def run(coord, refresher: SpecRefresher | None, *, max_steps: int,
        interval_s: float, report=log) -> dict[str, Any]:
    """`testbed.run`'s loop, with the console's one call at the top.

    `refresher.refresh(coord)` goes BEFORE `coord.step()`, once per interval,
    exactly as `sweep/console/reload.py` documents. Nothing in `sweep/`
    imports `console/`; this program imports both, which is the dependency
    direction §18.4 asks for.
    """
    steps = 0
    while steps < max_steps:
        if refresher is not None:
            r = refresher.refresh(coord)
            if r.changed:
                report(f"SPEC RELOAD #{r.interval}: {r.resized}")
            elif not r.ok:
                report(f"SPEC RELOAD #{r.interval} REFUSED: {r.error}")
        moved = coord.step()
        steps += 1
        for line in coord.drain_progress() if hasattr(coord, "drain_progress") else ():
            report(line)
        if not moved:
            break
        if interval_s:
            time.sleep(interval_s)
    return {"steps": steps}


def main(argv: Sequence[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--spec", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--corpus", action="append", default=[],
                   metavar="ENDPOINT=DIR")
    p.add_argument("--corpus-root", default=None, metavar="DIR",
                   help="<DIR>/<endpoint>/ holds that endpoint's dump_*.json. "
                        "`build_coordinator` REFUSES an endpoint with no "
                        "corpus (every endpoint starts in EXPLORING, which is "
                        "a batch worker over one), so a 161-endpoint spec "
                        "needs 161 of these; this is the one flag that "
                        "supplies them. An explicit --corpus wins.")
    p.add_argument("--execution", choices=("host", "skypilot"), default="host")
    p.add_argument("--region", default="us-central1")
    p.add_argument("--instance-type", default="n2-standard-2",
                   help="EXPLICIT GCP shape. The default is not cosmetic: "
                        "left to the optimizer, SkyPilot picked n4-standard-2 "
                        "and n4 had no capacity in ANY us-central1 zone on "
                        "2026-09-28. Pass '' to let the optimizer choose — "
                        "and expect to watch it walk the zones. It must be at "
                        "least as large as the spec's box class, because it "
                        "REPLACES the cpu/memory search rather than "
                        "constraining it. Per-class form: "
                        "`sm=n2-standard-2,md=n2-standard-4`.")
    p.add_argument("--manifest",
                   default="/home/dev/project/reports/autolab/box/manifest.json")
    p.add_argument("--repo", default=None)
    p.add_argument("--domain", default="")
    p.add_argument("--app-revision", default="real")
    p.add_argument("--app-tree-digest", default="", metavar="DIGEST",
                   help="the pre-gate's app-tree PIN. Measure it with this "
                        "campaign's tools/app_tree_digest.py. Left out, the "
                        "comparison reports NOT CONFIGURED on every attempt "
                        "and says so — it never reports a match.")
    p.add_argument("--engine-digest", default="", metavar="DIGEST|now",
                   help="the pre-gate's ENGINE pin: `python3 -m "
                        "sweep.engine_digest`'s output, or the word `now` to "
                        "pin whatever is on disk as this process starts. "
                        "`now` agrees with itself by construction, so it "
                        "cannot catch a campaign launched against the wrong "
                        "tree — it does catch a tree that MOVES while the "
                        "campaign runs, which is the failure a revision name "
                        "cannot see. A digest written out catches both. Left "
                        "out, the comparison reports NOT CONFIGURED.")
    p.add_argument("--max-steps", type=int, default=400)
    p.add_argument("--interval-s", type=float, default=2.0)
    p.add_argument("--provider", default="openrouter")
    p.add_argument("--key-file", default=DEFAULT_KEY_FILE)
    p.add_argument("--dsh-root", default=DEFAULT_DSH)
    p.add_argument("--real-systemd", action="store_true")
    p.add_argument("--no-refresh", action="store_true",
                   help="do NOT re-read the spec each interval (the console's "
                        "money levers then do nothing)")
    p.add_argument("--allow-shared-machine", action="store_true")
    p.add_argument("--dry", action="store_true",
                   help="build everything and print it; call no model")
    a = p.parse_args(argv)

    signal.signal(signal.SIGINT, _sig)
    signal.signal(signal.SIGTERM, _sig)
    atexit.register(shutdown, "atexit")

    spec = load_spec(a.spec)
    box_side = a.execution != "host"

    key = Path(a.key_file).read_text().strip()
    if not key:
        raise SystemExit(f"{a.key_file} is empty; there is no credential to use")
    # THE ONE PLACE THE VALUE GOES. `RealSky.to_task` reads it from here at
    # launch and puts it in SkyPilot's `envs`; nothing else in the process
    # ever writes it anywhere. It is set even on `host`, harmlessly, so the
    # two paths differ in one flag rather than in two code paths.
    os.environ[KEY_VAR] = key

    if box_side:
        # The adapter will be built on the BOX, so the local install is not
        # what gets checked — the bundle's is. Both halves are verified here
        # rather than on the VM, because a VM that fails setup costs money
        # and SkyPilot 0.13 does not even tell us it failed (it detaches
        # setup), while this check is free.
        manifest_doc = json.loads(Path(a.manifest).read_text())
        if not any("dsh" in n for n in manifest_doc.get("npm", ())):
            raise SystemExit(
                f"{a.manifest} lists no `dsh` in `npm`: the box would come up "
                "with python, the app and NO HARNESS, and the only symptom "
                "would be a batch worker whose agentd says hello and then "
                "nothing")
        route = Path(BOX_DSH_HOME) / "profiles" / "sdk" / "cordis.patch.yml"
        trees = [t["path"] for t in manifest_doc.get("trees", ())]
        if not any(str(route).startswith(t.rstrip("/") + "/") or t == BOX_DSH_HOME
                   for t in trees):
            raise SystemExit(
                f"{a.manifest} does not carry {BOX_DSH_HOME} as a tree, so the "
                "box would have `dsh` and no provider route")
        dsh_home, dsh_bin = BOX_DSH_HOME, BOX_DSH_BIN
    else:
        dsh_bin = str(Path(a.dsh_root) / "node_modules" / ".bin" / "dsh")
        if not Path(dsh_bin).is_file():
            raise SystemExit(
                f"no dsh at {dsh_bin}. Install it: "
                f"`npm install @deepseek-ai/dsh@latest` in {a.dsh_root}")
        dsh_home = str(Path(a.dsh_root) / "dshhome")
        route = Path(dsh_home) / "profiles" / "sdk" / "cordis.patch.yml"
    if "openrouter" not in route.read_text():
        raise SystemExit(
            f"{route} carries no `openrouter` provider route. `dsh`'s "
            "`initialize` takes {cwd, provider, model, ...} and no base URL "
            "or key, so the route is configuration, not an argument")
    if KEY_VAR not in route.read_text():
        raise SystemExit(
            f"{route} does not name {KEY_VAR} as its `apiKeyEnv`. The whole "
            "credential design rests on dsh reading the key from the "
            "environment: a route with an inline key would put it in the "
            "bundle")

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    execution = execution_for(a.execution, out=out, manifest=a.manifest,
                              region=a.region, real_systemd=a.real_systemd,
                              instance_type=_instance_types(a.instance_type))
    TEARDOWN["backend"] = execution

    corpora = {}
    if a.corpus_root:
        root = Path(a.corpus_root)
        for e in spec.endpoints:
            d = root / e.name
            if any(d.glob("dump_*.json")):
                corpora[e.name] = d
        missing = [e.name for e in spec.endpoints if e.name not in corpora]
        if missing:
            raise SystemExit(
                f"--corpus-root {root}: no dump_*.json for "
                f"{len(missing)} endpoint(s), e.g. {missing[:5]}. Name them "
                "with --corpus, or point --corpus-root somewhere that has "
                "them: an endpoint with no corpus cannot start")
    corpora.update(testbed._parse_corpus(a.corpus))

    # The ENGINE pin. `now` measures the tree this process is about to run,
    # which is a weaker claim than a digest written out — stated where it is
    # made, not only in the flag's help.
    engine_pin = a.engine_digest
    if engine_pin == "now":
        engine_pin = engine_digest.digest()
        rev, dirty = engine_digest.revision()
        log(f"engine pin MEASURED AT LAUNCH: {engine_pin} "
            f"(HEAD {rev or '(no repository)'}"
            f"{'+dirty — the history does not show what is running' if dirty else ''}). "
            "This catches a tree that moves under the campaign; it cannot "
            "catch a campaign launched against the wrong tree")
    elif engine_pin:
        here = engine_digest.digest()
        log(f"engine pin: {engine_pin}; this tree measures {here}"
            + ("" if here == engine_pin else
               " — THEY DIFFER, so every attempt will be refused until the "
               "pin or the tree is put right"))
    else:
        log("no engine pin: the pre-gate's engine comparison reports NOT "
            "CONFIGURED on every attempt. A mid-flight move is still caught, "
            "because that needs no pin")
    rc = 1
    try:
        coord, layer = testbed.build_coordinator(
            spec, out=out, corpora=corpora,
            spec_dir=Path(a.spec).resolve().parent,
            repo=Path(a.repo) if a.repo else None,
            domain=a.domain, app_revision=a.app_revision,
            app_tree_digest=a.app_tree_digest,
            engine_digest=engine_pin,
            allow_shared_machine=a.allow_shared_machine,
            execution=execution,
            agent_factory=agent_factory_for(
                dsh_home=dsh_home, dsh_bin=dsh_bin, api_key=key,
                provider=a.provider, box_side=box_side),
            execution_backend=a.execution,
        )
        refresher = None if a.no_refresh else SpecRefresher(a.spec, out)
        log(f"spec={a.spec} endpoints={[e.name for e in spec.endpoints]}")
        log(f"execution={a.execution} agent=dsh/{a.provider} "
            f"refresher={'ON' if refresher else 'OFF'}")
        log(f"agent runs {'ON THE BOX' if box_side else 'in THIS process'}; "
            f"dsh={dsh_bin} DSH_HOME={dsh_home}; "
            f"{KEY_VAR} reaches it "
            f"{'as a NAME in the task document + a VALUE in SkyPilot envs'
               if box_side else 'in the adapter base_env (same machine)'}")
        log(f"budgets: usd_total={spec.budgets.usd_total} "
            f"usd_per_endpoint={spec.budgets.usd_per_endpoint}")
        if spec.prices:
            log(f"prices as_of={spec.prices.as_of} margin={spec.prices.margin} "
                f"rates={json.dumps(spec.prices.rates)}")
        if a.dry:
            log("--dry: built, calling no model")
            return 0
        res = run(coord, refresher, max_steps=a.max_steps,
                  interval_s=a.interval_s)
        log(f"finished: {res}")
        rc = 0
    except BaseException:
        traceback.print_exc()
    finally:
        shutdown("normal exit" if rc == 0 else "failure")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
