#!/usr/bin/env python3
"""The FIVE-stage sweep chain for ONE endpoint, LOCALLY. Drive 6.

    batch  ->  pregate  ->  check  ->  policy  ->  realmode  ->  concrete

DERIVED FROM `local_cvd4/drive.py`, which is a completed drive's record and is
not edited. Everything below that is not listed here is drive 4's, verbatim and
for drive 4's reasons; read that file's docstring for them.

WHAT IS NEW ON DRIVE 6: the static half is finally given the one input it has
always asked for. Drive 4's gate blocked on
`statement-shape/no-real-mode-recording` — "compared nothing: no recording was
supplied (`real` is None)" — because no producer existed anywhere in the tree.
Drive 5 built the producer and ran it by hand, outside any box, and said so.
This drive runs it as a STAGE and mounts its output into the static half's box,
so §6.3's two halves run against the real artefacts THROUGH THE REAL SEAM.

Four concrete differences from drive 4, and they are the whole diff:

  realmode          A NEW STAGE. `RuntimeAdapter.drive_real_mode(cfg, plan,
                    out=...)` — the fourth adapter method — against the
                    endpoint's declared fixture world. Writes
                    `out/concrete_run.json`, THE RECORDING. It runs AFTER
                    `policy`, because the plan takes its target vocabulary
                    from this drive's own IR.
  recording=        §6.3's mount. `WorkerLayer.recording` ->
                    `concrete_mounts(recording=)` -> `in/real_mode.json`
                    (`sweep/workers/concrete.py::REL_RECORDING`). Drive 4
                    passed no such thing because there was nothing to pass
                    and no slot to pass it through.
  --real            in `STATIC_ARGV`, pointing at that mount. Drive 4
                    deliberately omitted it, with a correct reason at the
                    time: aiming it at the real-mode PLAN would have handed
                    `shape_check` a document of the wrong shape and got "the
                    recording is a dict", a sentence about a file that is not
                    a recording. With a recording to aim at, the flag is the
                    point.
  --app-config      also in `STATIC_ARGV`. `domains.load(name, app_config)`
                    forwards one as of 2026-10-07; before that every static
                    half built its domain with `app_config=None`.

THE APP CONFIG IS A MOUNT, NOT AN ABSOLUTE HOST PATH. The first draft of this
file passed `--app-config` as an absolute path and named that a gap: `--policy`
is relative because `concrete_mounts` mounts the policy IR, and
`concrete_mounts` had no slot for an app config, so there was no in-box path to
name. The slot exists now (`REL_APP_CONFIG`, `in/app_config.json`, threaded
through both plan functions and `WorkerLayer` on 2026-10-07), so the argv names
the MOUNT and the host path is passed as `app_config=` on the layer — the same
shape `policy` and `recording` already have. An absolute path would have named
this machine's copy rather than the box's, which is the defect `run_static`'s
co-location branch exists to prevent, and it would have stopped working on any
backend with real filesystem isolation.

WHY THE RECORDING IS A COORDINATOR STAGE AND NOT THE AGENT'S WORK. The fixture
world and the real-mode plan are GROUND TRUTH, so they are config this drive
owns and the batch agent may not supply (`sweep/briefs/batch.md` forbids it
producing a `concrete_run.json` at all, and `addendum_local.md` §8 repeats it).
An agent that writes its own ground truth has been handed the answer key. The
recording is derived from them by a deterministic stage, before any box that
would be checked against it exists.

Every stage goes through `sweep.binding.WorkerLayer.run(WorkRequest)` — the one
method `sweep/coordinator/driver.py`'s `Workers` protocol names — on the `host`
execution backend. Nothing here re-implements provision / stage / launch / poll
/ fetch / teardown, rebuilds a `WorkerSpec`, patches a plan, or names an
interpreter for a box.

WHAT IS NEW SINCE DRIVE 3 (`local_cvd3/drive.py`), AND IT IS THE POINT OF THIS
DRIVE: the fourth stage, and with it the first live occupant of §6.3's DOMAIN
GATE.

`a20ddd7` moved the mock-note check out of the generic engine's mandatory gate
(`concolic/checks/interactions.py::note_check`, reached by a `note_check_cmd`
config string) and into the domain that owns the claim
(`domains/ruby_rails_sql/checks.py::shape_check`, reached through
`Domain.check(policy, real)`), and made the domain tier able to BLOCK
(`WorkResult.domain_blocking` -> `Trigger.DOMAIN_GATE_FAILED`). It also said,
in its own message, that nothing reached it: no caller passed `domain=`,
`concrete_brief=` or `static_argv=`, so `WorkerLayer._static` was dead code in
every campaign and mock fidelity — the only check that compares the model to
REALITY rather than to itself — was enforced nowhere. This file is the live
caller. Four things it supplies that drive 3 did not:

  domain=           §6.3's pass-through NAME. §4 has no key for it (a named
                    gap), so it reaches a worker only as an argument.
  concrete_brief=   the path of `domain.agent_brief` — the agentic half's task.
  static_argv=      §6.3's STATIC half, as data. See `STATIC_ARGV` below for
                    what it is and why.
  policy=           §6.3's `in/policy.json`: the policy IR, built from the
                    APPROVED packet's corpus by `tools/build_policy_ir.py`.
                    Without it the static half has no right-hand side and
                    `shape_check` reports `statement-shape/no-policy` instead
                    of reading the corpus it is supposed to read.

`fixtures=` and `real_plan=` are read off the config and are both `null` on
this endpoint, which is exactly why the gate is expected to BLOCK: `real` is
`None`, so `shape_check` cannot compare the mocks' records against anything and
reports an UNMET OBLIGATION. That is the designed outcome, not a failure — what
must NOT happen is `shape_check` returning no items when `real` is absent.

WHY THIS FILE AND NOT `sweep/testbed.py`. `testbed.py` is the in-tree entry
point and takes `--static-argv`/`--policy` since 2026-10-05, so the gate can be
occupied there too — but its only agent backend is `ClaudeCodeBackend` pointed
at `sweep/tests/fake_claude.py` ("no real LLM call", its own docstring), and
§6.3's AGENTIC half is half the round. A proof that the gate runs under a real
closing round therefore cannot live there. The second reason is `policy=`:
the IR is built from the corpus the pre-gate just approved, and `sweep/` may
import `dumps_to_policy` no more than it may import `domains`, so producing it
is the caller's work and a campaign directory is where a caller's tools live.

THE CHECK WORKER IS NON-AGENTIC AND ON ITS OWN BOX (§6.1, and a standing owner
requirement: the same agent may not check its own work). That is structural —
`plan_check` takes no agent and `binding.py` constructs none for `kind="check"`
— but it is also ASSERTED here, on the box ids (`_assert_separate_boxes`),
because a shared box would make the requirement a matter of configuration.
Since this drive runs §6.3 as well, the assertion now covers FOUR boxes: the
batch agent's, the checker's, the closing agent's and the static half's.

CREDENTIALS. `ClaudeCodeBackend.session_store` points `CLAUDE_CONFIG_DIR`
INSIDE the box so two workers never share a session store; on `host` the box is
this machine, so the caller supplies a config directory it prepared.
`agent_config/` holds a symlink to the operator's `.credentials.json` (claude.ai
subscription login) and a `settings.json` whose allow/deny list is what makes
`--permission-prompts none` a working posture rather than a hang. No
`ANTHROPIC_*` variable is set anywhere, per `/home/dev/project/CLAUDE.md`.

STAGES, one per invocation, because each stage's answer is a thing a campaign
must be able to stop on and read.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = "/home/dev/project/src_new"
sys.path.insert(0, SRC)

from sweep import briefs                                          # noqa: E402
from sweep.agents.claude_code import ClaudeCodeBackend            # noqa: E402
from sweep.binding import WorkerLayer                             # noqa: E402
from sweep.coordinator.driver import WorkRequest                  # noqa: E402
from sweep.coordinator.pregate import (                           # noqa: E402
    PreGate, SubprocessValidationSource, verify_packet,
)
from sweep.decisions import DecisionLog, Evidence                 # noqa: E402
from sweep.execution.host import FakeSystemd, HostBackend         # noqa: E402
from sweep.spec import load_spec                                  # noqa: E402
from sweep.telemetry.usage import WorkerRows                      # noqa: E402

ENDPOINT = "tags_index"
ENTRYPOINT = "TagsController#index"
SPEC_PATH = HERE / "sweep_local.json"
SPEC_PATH_CHECK = HERE / "sweep_local_check.json"
CONFIG = HERE / "inputs" / f"{ENDPOINT}_config.json"
REPO = Path("/home/dev/project/ruby_examples/dse-apps/apps/diaspora")
STATE = HERE / "state"
CLAUDE = "/home/dev/.local/bin/claude"
AGENT_CONFIG = HERE / "agent_config"
AGENT_HOME = HERE / "agent_home"
IMAGE = ""          # `host` ignores it (`image_ignored` on the box record)
APP_REVISION = "diaspora@0760b6a22"

#: §5.2.1's PIN. Nothing in `src_new/` measures an application tree, so without
#: this the comparison reports NOT CONFIGURED on every attempt. `tools/
#: app_tree_digest.py` is the measurement and its docstring says exactly what it
#: covers; the batch agent runs the same script.
APP_TREE_PIN = "916d393795a47b99d2128464ba268defb51524555bc26c659560575051501954"

#: The caller's PATH for the agent's child. §7.8: constructed, never inherited.
AGENT_PATH = "/home/dev/.local/bin:/usr/local/bin:/usr/bin:/bin"

# ---------------------------------------------------------------------------
# §6.3's static half

#: §6.3's pass-through NAME. §4 has no key for it, so it is said here.
DOMAIN = "ruby_rails_sql"
#: §6.3: "a path this worker hands its agent as the task".
CONCRETE_BRIEF = Path(SRC) / "domains" / DOMAIN / "briefs" / "concrete_agent.md"

# ---------------------------------------------------------------------------
# the REAL-MODE stage (new on drive 6)

#: The probe, and the ONE place its path is written down. `real_mode_cmd` is a
#: config string the adapter substitutes `{plan}` and `{out}` into and does not
#: parse — the same contract `extract_cmd` / `test_cmd` have with their two
#: Ruby probes. Drive 5 established this value; it is unchanged.
#:
#: It goes through `scripts/diaspora-concolic` because that launcher is what
#: exports JAVA_HOME / GEM_HOME / RAILS_ENV=concolic and cd's into the app, and
#: `require "./config/environment"` only resolves from there. `unset
#: JAVA_TOOL_OPTIONS` is this machine's standing rule: the parent's value leaks
#: into every JVM and breaks it.
PROBE = Path(SRC) / "domains" / DOMAIN / "real_mode" / "real_mode_probe.rb"
REAL_MODE_CMD = (
    "unset JAVA_TOOL_OPTIONS; "
    f"/home/dev/project/scripts/diaspora-concolic {PROBE} {{plan}} {{out}}"
)

#: THE RECORDING. Produced by `--stage realmode`, mounted by `--stage
#: concrete` at `sweep/workers/concrete.py::REL_RECORDING`.
RECORDING = HERE / "out" / "concrete_run.json"

#: The domain's APP CONFIG. `domains.load(name, app_config)` forwards one as of
#: 2026-10-07 and `static_check.py --app-config` is how a caller supplies it.
#:
#: THIS CAMPAIGN HAS ONE, which was worth checking rather than assuming. It
#: carries NO `note_aliases` key, so the one thing the flag was named for in
#: `static_check.py`'s own docstring costs nothing here — and the config is
#: still worth passing for a different, measured reason: the SCHEMA. With it,
#: `render_views` on this endpoint's drive-4 IR dropped 7 condition predicates
#: instead of 17 and emitted one view with a predicate it otherwise could not
#: confirm was a column. Since `statement_differential` compares against that
#: render, the config changes what the differential's right-hand side IS.
#:
#: The frame alias this endpoint does need is applied one layer earlier, by the
#: real-mode plan's own `frame_aliases` block, at capture time — so the
#: recording arrives already attributed and `note_aliases` has nothing left to
#: repair. Two mechanisms, one of which is enough.
#:
#: THE HOST PATH. It reaches the box as `REL_APP_CONFIG` (`in/app_config.json`)
#: via `WorkerLayer.app_config`, and the argv names that mount, never this.
APP_CONFIG = Path("/home/dev/project/reports/autolab/blockaid/config/app.json")

#: The interpreter `domains` and `dumps_to_policy` need. `sqlglot` (statement
#: shapes) and `z3` (the policy IR) are both in this venv and in no other
#: interpreter on this machine, and `shape_check` degrades to a REGEX shape
#: comparison without sqlglot — which it says in its own evidence line
#: (`_sqlglot_note`), so a wrong interpreter would produce a WEAKER comparison
#: that still looked like a comparison. `HostBackend.box_python` answers
#: `sys.executable`, which is the interpreter driving THIS file; that is right
#: for §6.1's checker (`concolic` needs nothing extra) and wrong here, which is
#: why the argv names its interpreter instead of inheriting one.
VENV_PY = "/home/dev/project/venvs/queries_from_runs/bin/python3"

#: §6.3's STATIC HALF, AS DATA. `plan_static` takes an `argv` and refuses to
#: invent one ("§6.3 names no command line for `domain.check`, and this module
#: will not invent one. Pass the argv, exactly as §6.1's `CHECK_MODULE` is data
#: rather than a formatted string"), so this is that command line, and every
#: choice in it is a decision:
#:
#: * `domains/static_check.py` and nothing in `concolic/`. The check this
#:   replaces ran as the generic engine's `note_check` shelling out to
#:   `domains/ruby_rails_sql/mock_note_check.py` through a config string — the
#:   engine running the domain's code behind its back. `shape_check` is reached
#:   through `Domain.check` now, and only `domains/` may call that (`sweep/` may
#:   not import it: the dependency is one-way and tested), so the argv is a
#:   program this layer LAUNCHES rather than a function it calls.
#: * `--domain ruby_rails_sql`, by NAME, resolved inside the box by
#:   `domains.load` — which is where DESIGN_DOMAIN_LAYER says a domain is
#:   instantiated, "never in the sweep coordinator".
#: * `--policy in/policy.json`, RELATIVE, because `StaticPlan.brief_for` sets
#:   the child's cwd to the box root and `concrete_mounts` puts the policy IR
#:   at that relative path. An absolute path here would name this machine's
#:   copy rather than the box's mount, which is the defect `run_static`'s
#:   co-location branch exists to prevent.
#: * `--out out/review_items.json`, the artifact §6.3 names, which
#:   `read_submission` verifies by digest and this layer reads as CLAIMS.
#: * `--real in/real_mode.json`, RELATIVE, for `--policy`'s reason: it is a
#:   MOUNT (`sweep/workers/concrete.py::REL_RECORDING`), created from
#:   `WorkerLayer.recording`. DRIVE 4 OMITTED THIS FLAG AND WAS RIGHT TO:
#:   §6.3 mounted only `in/real_mode_plan.json`, which is the PLAN and not a
#:   recording, there was no mount for a recording and no producer for one, and
#:   aiming `--real` at the plan would have got "the recording is a dict" — a
#:   sentence about a file that is not a recording. Omitting it got "no
#:   recording was supplied", which was true. Both halves of that landed on
#:   2026-10-06/07, so the true thing to say now is the recording's path.
#: * `--app-config in/app_config.json`, RELATIVE, for the same reason: it is a
#:   MOUNT (`sweep/workers/concrete.py::REL_APP_CONFIG`), created from
#:   `WorkerLayer.app_config`. The flag takes a PATH and not a parsed document
#:   deliberately — `static_check.py` hands the path on because this domain's
#:   config contract resolves every relative path against the config file's own
#:   directory, which a parsed document has forgotten.
STATIC_ARGV = (
    VENV_PY,
    f"{SRC}/domains/static_check.py",
    "--domain", DOMAIN,
    "--policy", "in/policy.json",
    "--real", "in/real_mode.json",
    "--app-config", "in/app_config.json",
    "--out", "out/review_items.json",
)

#: §7.8: constructed, never inherited. `PYTHONPATH` is the same value
#: `HostBackend.box_python_env` would fill in, said explicitly because the
#: interpreter is NOT the box's. The locale keys are drive 3's `check_env`
#: belt for the same reason it needed one: `sqlglot` parses the UTF-8 SQL text
#: of every recorded note, and a child with no `LC_CTYPE` has been measured to
#: turn a parse into a traceback elsewhere in this chain.
STATIC_ENV = {
    "PATH": "/usr/local/bin:/usr/bin:/bin",
    "PYTHONPATH": SRC,
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8",
    # This machine's OOM history: the variable leaks in from the parent and
    # breaks anything that starts a JVM. Nothing here starts one, and it is
    # cleared anyway so the static half's environment is the one named here.
    "JAVA_TOOL_OPTIONS": "",
}


def _spec(kind: str = "batch"):
    return load_spec(SPEC_PATH_CHECK if kind == "check" else SPEC_PATH)


def _config() -> dict:
    return json.loads(CONFIG.read_text())


def _config_path(key: str) -> Path | None:
    """`fixtures` / `real_mode_plan` from the config, as §6.3's `ro` mounts.

    MEASURED RATHER THAN ASSUMED, and on this drive the measurement comes out
    the other way: drive 4 read `null` for both and its whole expected result
    turned on `real` being absent. Drive 6's config DECLARES both, so the
    mounts appear and the gate's answer changes by itself — which is exactly
    what reading the config rather than hard-coding `None` bought.
    """
    raw = _config().get(key)
    return None if raw in (None, "", False) else Path(str(raw))


def _brief() -> str:
    """§6.2's brief: the shipped app-agnostic one, plus two addenda.

    The addendum is the caller's by design (`sweep/briefs/batch.md`: everything
    specific to a campaign reaches the agent through its staged inputs and the
    caller's brief). `reports/autolab/docs/briefs_addendum.md` is the lab's
    standing one; `addendum_local.md` is this campaign's.
    """
    return "\n\n".join([
        briefs.batch_brief(),
        Path("/home/dev/project/reports/autolab/docs/briefs_addendum.md").read_text(),
        (HERE / "addendum_local.md").read_text(),
    ])


def _agent_factory(req, aspec):
    """§7.8's half of the seam: the adapter, constructed, with credentials."""
    return ClaudeCodeBackend(
        executable=CLAUDE,
        base_env={"PATH": AGENT_PATH, "HOME": str(AGENT_HOME), "TERM": "dumb"},
        config_dir=str(AGENT_CONFIG),
        setting_sources="user",
    )


def _layer(*, policy: Path | None = None, recording: Path | None = None):
    ex = HostBackend(HERE / "boxes", systemd=FakeSystemd(root=HERE / "cg"))
    return WorkerLayer(
        execution=ex,
        rows=WorkerRows(HERE / "out" / "workers.jsonl"),
        root=HERE / "layer",
        repo=REPO,
        batch_brief=_brief(),
        agent_factory=_agent_factory,
        # -- §6.3, all four of them new on this drive --------------------
        domain=DOMAIN,
        concrete_brief=CONCRETE_BRIEF,
        static_argv=STATIC_ARGV,
        static_env=STATIC_ENV,
        policy=policy,
        # §6.3's RECORDING mount, new on drive 6. `WorkerLayer.recording` ->
        # `concrete_mounts(recording=)` -> `in/real_mode.json`. Drive 4 could
        # not pass this: the field did not exist and neither did a producer.
        recording=recording,
        # §6.3's APP CONFIG mount, new on drive 6 (the slot landed 2026-10-07).
        # `WorkerLayer.app_config` -> `concrete_mounts(app_config=)` ->
        # `in/app_config.json`, which is what `STATIC_ARGV` names.
        app_config=APP_CONFIG,
        fixtures=_config_path("fixtures"),
        real_plan=_config_path("real_mode_plan"),
        # §6.1: the box names its own interpreter and its own PATH/PYTHONPATH.
        check_module=None,
        # BELT, NOT A FIX, AND MEASURED BOTH WAYS. §7.8 constructs a worker's
        # environment and `BOX_PYTHON_ENV_KEYS` is ("PATH", "PYTHONPATH"), so
        # nothing in the design gives the checker a LOCALE — and
        # `concolic/checks/proc.py::_run` hands `dict(os.environ)` to every
        # configured gate command. `shim_extractor.rb` reads two UTF-8 Ruby
        # files with `String#scan` and dies under US-ASCII. What actually
        # saves it is CPython: PEP 538 coercion puts `LC_CTYPE=C.UTF-8` into
        # `os.environ` of the checker process itself and `_run` passes that
        # on. With `PYTHONCOERCECLOCALE=0` the same pass exits 70 with
        # `outcome: UNDECIDED` and the Ruby traceback as its one blocking
        # line. These two keys make that independent of the interpreter.
        check_env={"LANG": "C.UTF-8", "LC_ALL": "C.UTF-8"},
        # §8.5: an agentic worker on a backend with no filesystem isolation is
        # refused unless the sweep says so out loud. This is that grant.
        allow_shared_machine=True,
        app_revision=APP_REVISION,
        hello_timeout_s=600.0,
        grace_s=120.0,
        max_usd=25.0,
    )


def _request(spec, kind: str, *, attempt: int, **kw) -> WorkRequest:
    base = HERE / "base"
    base.mkdir(parents=True, exist_ok=True)
    return WorkRequest(
        spec=spec, sweep=spec.sweep, endpoint=ENDPOINT, kind=kind,
        attempt=attempt, worker_id=f"{ENDPOINT}-{kind}-{attempt}",
        box_class=spec.box_for(ENDPOINT).name, home="local",
        execution_backend="host", config=CONFIG, base=base, image=IMAGE,
        app="diaspora", **kw)


def _save(name: str, doc) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / name).write_text(json.dumps(doc, indent=1, sort_keys=True,
                                         default=str))


def _load(name: str):
    return json.loads((STATE / name).read_text())


def _config_digest() -> str:
    return hashlib.sha256(CONFIG.read_bytes()).hexdigest()


def _box_of(path) -> str:
    """The box root an artefact path names. `<box>/out/<artefact>`, so
    `parents[1]`. READ OFF THE ARTEFACT, not off `WorkerRow` — the row carries
    no box identifier at all (measured on drive 3: `row.box_id` does not
    exist and `getattr(r, "box_id", "")` is the empty string for every kind,
    which made the first version of this check pass vacuously)."""
    return str(Path(path).parents[1]) if path else ""


def _assert_separate_boxes(attempt: int) -> None:
    """The standing requirement, checked rather than assumed.

    §6.1 gives the check worker no agent and no agent backend; this asserts the
    other half — that it did not run where any agent ran. On `host` a box IS a
    directory, so "a different box" is literally a different path.

    SINCE DRIVE 4 THIS COVERS FOUR BOXES, not two: §6.3 adds the closing
    agent's box and the static half's, and `WorkerLayer._concrete` provisions
    them separately (`plan_static` gets its own `worker_id`, `<id>/static`).
    A static half sharing the closing agent's box would let an agent write the
    document its own domain checks are read out of.
    """
    #: (label, state file, key). FOUR labels over THREE files, because §6.3's
    #: two halves answer one request and so land in one record.
    where = (("batch", f"batch-{attempt}.json", "box"),
             ("check", f"check-{attempt}.json", "box"),
             ("concrete/agent", f"concrete-{attempt}.json", "agent_box"),
             ("concrete/static", f"concrete-{attempt}.json", "static_box"))
    seen = {}
    for stage, fname, key in where:
        f = STATE / fname
        box = (_load(fname).get(key) if f.exists() else None)
        if not box:
            raise SystemExit(
                f"REFUSED: cannot name the {stage} box for attempt {attempt}; "
                "an unverifiable separation is not one")
        seen[stage] = box
    dupes = {b for b in seen.values() if list(seen.values()).count(b) > 1}
    if dupes:
        raise SystemExit(f"REFUSED: boxes shared: {sorted(dupes)} in {seen}")
    for stage, box in seen.items():
        print(f"[boxes] {stage}={box}")
    print(f"[boxes] {len(seen)} distinct: True")


# ---------------------------------------------------------------------------


def stage_batch(args) -> int:
    spec = _spec()
    layer = _layer()
    response = {}
    rpath = STATE / f"response-{args.attempt}.json"
    if rpath.exists():
        response = json.loads(rpath.read_text())
        print(f"[batch] carrying a response from attempt {args.attempt - 1}: "
              f"{len(response.get('denied') or [])} denial(s), "
              f"{len(response.get('blocking') or [])} blocking line(s)")
    t0 = time.time()
    result = layer.run(_request(spec, "batch", attempt=args.attempt,
                                response=response))
    r = layer.results[-1]
    print(f"[batch] submitted={result.submitted} detail={result.detail} "
          f"elapsed={time.time() - t0:.0f}s")
    print(f"[batch] packet={result.packet}")
    print(f"[batch] tokens={getattr(r, 'tokens', None)} "
          f"cost={getattr(r, 'cost', None)} "
          f"denials={getattr(r, 'permission_denials', None)}")
    _save(f"batch-{args.attempt}.json", {
        "submitted": result.submitted, "packet": str(result.packet or ""),
        "detail": result.detail, "box": _box_of(result.packet),
        "elapsed_s": round(time.time() - t0, 1)})
    if result.packet:
        _save("packet.json", {"path": str(result.packet),
                              "attempt": args.attempt})
    return 0 if result.submitted else 1


def stage_pregate(args) -> int:
    """§5.2's three MECHANICAL steps. No agent turn anywhere in here."""
    packet = Path(_load("packet.json")["path"])
    log = DecisionLog(HERE / "out" / "decisions.jsonl")

    # step 1 — the CALLER's, because its failure is a different transition.
    try:
        contents = verify_packet(packet, config_digest=_config_digest())
    except Exception as exc:                                   # noqa: BLE001
        print(f"[pregate] PACKET REJECTED (step 1): {exc}")
        _save(f"pregate-{args.attempt}.json",
              {"passed": False, "step": 1, "error": str(exc)})
        return 3
    print(f"[pregate] step 1: {contents.summary()}")

    gate = PreGate(spec=_spec(), log=log, source=SubprocessValidationSource(
        env={"PATH": "/usr/local/bin:/usr/bin:/bin", "PYTHONPATH": SRC},
        cwd=SRC))
    out = HERE / "out" / f"validate-{args.attempt}.json"
    outcome = gate.run(endpoint=ENDPOINT, packet=packet, out=out,
                       config_digest=contents.config_digest,
                       pinned_digest=APP_TREE_PIN, attempt=args.attempt,
                       raised_by=f"{ENDPOINT}-batch-{args.attempt}",
                       contents=contents,
                       evidence=Evidence(config=_config_digest(),
                                         app_revision=APP_REVISION))
    print(f"[pregate] step 2: {len(outcome.refusals)} declared refusal(s)")
    for r in outcome.refusals:
        print(f"[pregate]   REFUSED {r}")
    print(f"[pregate] step 3: {outcome.app_tree.detail()}")
    print(f"[pregate] passed={outcome.passed} decision={outcome.record.id}")
    print(f"[pregate] NOT ASKED: {outcome.not_asked_summary()}")
    _save(f"pregate-{args.attempt}.json", outcome.as_json())
    if not outcome.passed:
        _save(f"response-{args.attempt + 1}.json", outcome.response())
        print("[pregate] a refusal is a FAILED ATTEMPT: the endpoint returns to "
              "EXPLORING and the refusals go back as denials.json")
        return 1
    _save("approved.json", {"approved": outcome.record.id,
                            "attempt": args.attempt})
    return 0


def stage_check(args) -> int:
    spec = _spec("check")
    layer = _layer()
    packet = Path(_load("packet.json")["path"])
    approved = _load("approved.json")["approved"]
    t0 = time.time()
    result = layer.run(_request(spec, "check", attempt=args.attempt,
                                packet=packet, approved=approved))
    r = layer.results[-1]
    facts = result.facts
    print(f"[check] elapsed={time.time() - t0:.0f}s detail={result.detail}")
    print(f"[check] report={getattr(r, 'report_path', None)} "
          f"verified={getattr(r, 'report_verified', None)}")
    if facts is None:
        print("[check] NO FACTS — the checker wrote no report (UNDECIDED)")
        _save(f"check-{args.attempt}.json",
              {"outcome": None, "complete": None,
               "box": _box_of(getattr(r, "report_path", None)),
               "detail": result.detail,
               "elapsed_s": round(time.time() - t0, 1)})
        return 2
    print(f"[check] outcome={facts.outcome} complete={facts.complete}")
    for b in (facts.blocking or ()):
        print(f"[check] BLOCKING: {b}")
    _save(f"check-{args.attempt}.json", {
        "outcome": facts.outcome, "complete": facts.complete,
        "blocking": list(facts.blocking or ()),
        "unsettled": [dict(u) for u in (facts.unsettled or ())],
        "tree_missing": list(facts.tree_missing or ()),
        "closing_inadmissible_because": list(facts.closing_inadmissible_because()),
        "closing_admissible": facts.closing_admissible(),
        "report": str(getattr(r, "report_path", "") or ""),
        "box": _box_of(getattr(r, "report_path", None)),
        "elapsed_s": round(time.time() - t0, 1)})
    _write_next_response(args.attempt, facts)
    if not facts.closing_admissible():
        print("[check] the report is not a CLOSING one: §5's only path into "
              "CLOSED is (PROBING, NO_FINDINGS), and PROBING is entered on a "
              "closing COMPLETE. The concrete stage would be running §6.3 on "
              "an attempt the engine has not passed.")
    return 0 if facts.complete else 1


def stage_policy(args) -> int:
    """§6.3's `in/policy.json`, from the APPROVED packet's corpus.

    A stage of its own because it is the one §6.3 input with no producer
    anywhere in `src_new/`'s sweep layer, and because its numbers are evidence:
    how many notes the IR carries IS the right-hand side `shape_check` reads,
    so a policy that built with zero notes would make the gate's answer mean
    something different.
    """
    packet = Path(_load("packet.json")["path"])
    dumps = packet / "dumps"
    out = HERE / "out" / f"policy-{args.attempt}.json"
    cmd = [VENV_PY, str(HERE / "tools" / "build_policy_ir.py"),
           str(dumps), str(out), "--entrypoint", ENTRYPOINT,
           "--app", APP_REVISION]
    print("[policy] " + " ".join(cmd))
    proc = subprocess.run(cmd, capture_output=True, text=True,
                          env={"PATH": "/usr/local/bin:/usr/bin:/bin",
                               "PYTHONPATH": SRC, "LC_ALL": "C.UTF-8"})
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        _save(f"policy-{args.attempt}.json",
              {"built": False, "rc": proc.returncode,
               "stderr": proc.stderr[-2000:]})
        return proc.returncode
    doc = json.loads(out.read_text())
    _save(f"policy-{args.attempt}.json", {
        "built": True, "path": str(out),
        "summary": proc.stdout.strip(),
        "digest": hashlib.sha256(out.read_bytes()).hexdigest(),
        "form": doc.get("form") or doc.get("version")})
    return 0


def stage_realmode(args) -> int:
    """THE RECORDING — ground truth, captured before anything is checked
       against it. New on drive 6.

    `RuntimeAdapter.drive_real_mode(cfg, plan, out=...)` is DESIGN_ONE_STACK
    §9's fourth adapter method, and this is a caller of it rather than a
    re-implementation: the adapter knows only that a configured command takes
    a `{plan}` and writes an `{out}`, exactly as `extract_cmd` / `test_cmd`
    already do with their two Ruby probes. Everything that knows what a SQL
    statement IS lives in the domain, beside the checks that consume it.

    A STAGE OF ITS OWN, for `stage_policy`'s reason: its numbers are evidence.
    How many statements the real run issued, under which frames, IS the
    left-hand side of both C1 checks, so a recording that captured nothing
    would make the gate's answer mean something entirely different — and
    `real_mode.py` raises rather than returning a thin document precisely so
    that cannot pass quietly.

    AFTER `policy`, and that ordering is not cosmetic: the plan takes its
    TARGET VOCABULARY from this drive's own IR, so the two sides of the
    comparison cannot disagree about which target names exist.
    """
    plan = _config_path("real_mode_plan")
    world = _config_path("fixtures")
    if plan is None or world is None:
        raise SystemExit(
            "REFUSED: this endpoint's config declares "
            f"real_mode_plan={plan} fixtures={world}. Both are ground truth "
            "and both are the coordinator's to supply; a drive that invented "
            "either would be checking the mocks against an answer key it "
            "wrote itself")
    pol = _load(f"policy-{args.attempt}.json")
    if not pol.get("built"):
        raise SystemExit("REFUSED: run --stage policy first. The plan takes "
                         "its target vocabulary from this drive's own IR")

    sys.path.insert(0, SRC)
    from concolic.runtime import RubyAdapter

    cfg = {"real_mode_cmd": REAL_MODE_CMD,
           "workdir": "/home/dev/project",
           # This machine's standing rule, and the launcher unsets it too: a
           # leaked parent value breaks every JVM.
           "env": {"JAVA_TOOL_OPTIONS": ""},
           "real_mode_timeout": 900}
    RECORDING.parent.mkdir(parents=True, exist_ok=True)
    print(f"[realmode] plan={plan}")
    print(f"[realmode] world={world}")
    print(f"[realmode] out={RECORDING}")
    t0 = time.time()
    doc = RubyAdapter().drive_real_mode(cfg, str(plan), out=str(RECORDING))

    scen = doc.get("scenarios", []) if isinstance(doc, dict) else list(doc)
    n = sum(len(s.get("statements") or ()) for s in scen)
    print(f"[realmode] {len(scen)} scenario(s), {n} statement(s) captured "
          f"in {time.time() - t0:.0f}s")
    for s in scen:
        print(f"[realmode]   {s.get('name')}: "
              f"{len(s.get('statements') or ())} statement(s)"
              + (f"  ERROR: {s['error']}" if s.get("error") else ""))
    errs = [s.get("name") for s in scen if s.get("error")]
    if errs:
        # A scenario that raised still contributed the statements it issued
        # before raising, so the recording is usable — but a reader must not
        # have to find that out by reading the JSON.
        print(f"[realmode] WARNING: scenario(s) recorded an error: {errs}")
    _save(f"realmode-{args.attempt}.json", {
        "captured": True,
        "path": str(RECORDING),
        "digest": hashlib.sha256(RECORDING.read_bytes()).hexdigest(),
        "plan": str(plan), "plan_sha256": doc.get("plan_sha256"),
        "world": str(world),
        "scenarios": [{"name": s.get("name"),
                       "n_statements": len(s.get("statements") or ()),
                       "error": s.get("error"),
                       "world": s.get("world")} for s in scen],
        "n_statements": n,
        "frames": sorted({st.get("under") for s in scen
                          for st in (s.get("statements") or ())
                          if st.get("under")}),
        "elapsed_s": round(time.time() - t0, 1)})
    # An empty recording is not a pass. `real_mode.py` raises on a non-zero
    # exit, a missing file and unreadable JSON, so reaching here with zero
    # statements means the probe ran and the app issued nothing — which on
    # this endpoint cannot be true, and must stop the chain rather than feed
    # the gate a plausible wrong ground truth.
    if not n:
        print("[realmode] REFUSED: the recording carries no statements at "
              "all. The gate would read that as 'the application issued "
              "nothing under any target frame', which is a quiet wrong "
              "answer, not a missing input.")
        return 1
    return 0


def stage_concrete(args) -> int:
    """§6.3's closing round: the agentic half, then the STATIC half.

    ONE `WorkRequest`, two boxes, two halves — `WorkerLayer._concrete`'s
    policy, because the coordinator issues one `concrete` request at PROBING
    and §6.3 has two halves with no state between them.
    """
    spec = _spec()
    packet = Path(_load("packet.json")["path"])
    approved = _load("approved.json")["approved"]
    pol = _load(f"policy-{args.attempt}.json")
    if not pol.get("built"):
        raise SystemExit("REFUSED: run --stage policy first. Without "
                         "`in/policy.json` the static half has no right-hand "
                         "side and `shape_check` reports no-policy rather "
                         "than reading the corpus")
    rm = _load(f"realmode-{args.attempt}.json") if (
        STATE / f"realmode-{args.attempt}.json").exists() else {}
    if not rm.get("captured"):
        raise SystemExit(
            "REFUSED: run --stage realmode first. Without a recording the "
            "static half reports `statement-shape/no-real-mode-recording` and "
            "`statement-differential/no-real-mode-recording` — two UNMET "
            "OBLIGATIONS — and this drive exists to discharge them. That is "
            "drive 4's result, already recorded in local_cvd4/state/, and "
            "re-running it here would prove nothing new")
    if not Path(rm["path"]).exists():
        raise SystemExit(f"REFUSED: {rm['path']} is gone; re-run --stage "
                         "realmode rather than mounting a path that is not "
                         "there (a missing mount reads as 'no recording was "
                         "supplied', which would be a sentence about the "
                         "wrong world)")
    layer = _layer(policy=Path(pol["path"]), recording=Path(rm["path"]))
    # THE BOXES THIS ROUND CREATES, by difference. §6.3's two halves get two
    # boxes and the standing separation requirement is checked on their paths,
    # but an artefact path can only name a box whose artefact EXISTS -- and
    # measured on round 1 of this very drive, an agentic half that submitted
    # nothing left `review_items.path is None` and the separation claim
    # unverifiable for a box that had plainly been provisioned. On `host` a box
    # IS a directory, so the directories that appear during this call are the
    # boxes this call made, whatever the halves managed to write.
    before = {d.name for d in (HERE / "boxes").glob("*")}
    print(f"[concrete] domain={DOMAIN}")
    print(f"[concrete] brief={CONCRETE_BRIEF}")
    print(f"[concrete] static_argv={' '.join(STATIC_ARGV)}")
    print(f"[concrete] policy={pol['path']} ({pol['summary']})")
    print(f"[concrete] fixtures={_config_path('fixtures')} "
          f"real_plan={_config_path('real_mode_plan')}")
    print(f"[concrete] recording={rm['path']} "
          f"({rm['digest'][:12]}…, {rm['n_statements']} statement(s), "
          f"{len(rm['frames'])} frame(s)) -> in/real_mode.json")
    print(f"[concrete] app_config={APP_CONFIG}")
    t0 = time.time()
    result = layer.run(_request(spec, "concrete", attempt=args.attempt,
                                packet=packet, approved=approved))
    # `layer.results` holds BOTH halves, agentic first (see `_concrete`).
    halves = [r for r in layer.results if getattr(r, "half", None)]
    agentic = next((r for r in halves if r.half == "agent"), None)
    static = next((r for r in halves if r.half == "static"), None)

    print(f"[concrete] elapsed={time.time() - t0:.0f}s")
    print(f"[concrete] detail={result.detail}")
    print(f"[concrete] failed={result.failed} facts={result.facts}")
    print(f"[concrete] findings={len(result.findings)}")
    for f in result.findings:
        print(f"[concrete]   CLAIM {f.id} (raised_by={f.raised_by}, "
              f"catchable={f.catchable})")
    print(f"[concrete] DOMAIN GATE: {len(result.domain_blocking)} line(s)")
    for b in result.domain_blocking:
        print(f"[concrete] DOMAIN BLOCKING: {b}")
    if static is not None:
        print(f"[concrete] static exit_status={static.exit_status} "
              f"exit_reason={static.exit_reason} "
              f"items={static.review_items.path}")
        if static.stderr_tail:
            print("[concrete] static stderr tail:")
            for line in static.stderr_tail.strip().splitlines()[-20:]:
                print(f"[concrete]   | {line}")

    items = []
    if static is not None and static.review_items.path:
        try:
            items = json.loads(Path(static.review_items.path).read_text())
        except Exception as exc:                               # noqa: BLE001
            items = [{"identity": f"<unreadable: {exc}>"}]

    fresh = sorted(d for d in (HERE / "boxes").glob("*")
                   if d.name not in before)
    static_boxes = [str(d) for d in fresh if "_static" in d.name]
    agent_boxes = [str(d) for d in fresh if "_static" not in d.name]
    print(f"[concrete] boxes created this round: {[d.name for d in fresh]}")

    _save(f"concrete-{args.attempt}.json", {
        "detail": result.detail,
        "failed": result.failed,
        "facts_is_none": result.facts is None,
        "domain_blocking": list(result.domain_blocking),
        "findings": [{"id": f.id, "raised_by": f.raised_by,
                      "catchable": f.catchable, "consequence": f.consequence,
                      "text": f.text} for f in result.findings],
        # The artefact's box when there is an artefact, else the directory
        # this round provisioned. Both are read off the filesystem; neither is
        # `WorkerRow`, which carries no box identifier at all (measured on
        # drive 3: `getattr(r, "box_id", "")` is the empty string for every
        # kind, which made the first version of the separation check pass
        # vacuously).
        "agent_box": (_box_of(getattr(agentic, "review_items", None)
                              and agentic.review_items.path)
                      or (agent_boxes[-1] if agent_boxes else "")),
        "agent_box_source": ("artefact" if (
            getattr(agentic, "review_items", None)
            and agentic.review_items.path) else "provisioned directory"),
        "agent_exit_reason": str(getattr(agentic, "exit_reason", "")),
        "agent_exit_status": getattr(agentic, "exit_status", None),
        "static_box": (_box_of(static.review_items.path if static else None)
                       or (static_boxes[-1] if static_boxes else "")),
        "static_exit_reason": str(getattr(static, "exit_reason", "")),
        "static_exit_status": getattr(static, "exit_status", None),
        "static_submitted": getattr(static, "submitted", None),
        "static_stderr_tail": getattr(static, "stderr_tail", ""),
        "static_items": items,
        "policy": pol.get("path"),
        "recording": rm.get("path"),
        "recording_digest": rm.get("digest"),
        "app_config": str(APP_CONFIG),
        "elapsed_s": round(time.time() - t0, 1)})

    print()
    print("[certificate] " + _certificate(args.attempt, result))
    _assert_separate_boxes(args.attempt)
    # §6.3: a non-empty domain gate is `Trigger.DOMAIN_GATE_FAILED`, which is
    # (PROBING -> EXPLORING) with cause CONCRETE_REOPEN -- NOT a closed
    # endpoint and NOT a failed attempt.
    return 0 if not result.domain_blocking else 1


def _certificate(attempt: int, result) -> str:
    """ONE LINE, both tiers, and they are never merged.

    The requirement the two fields exist for: "the engine's conjunction
    passed, the domain's did not" must be distinguishable from "coverage is
    incomplete". The engine's reasons ride on `facts.blocking` of a CHECK
    result; the domain's on `domain_blocking` of a CONCRETE one. A concrete
    round carries no `facts` at all and a check round carries no
    `domain_blocking`, so this line reads them from the two different stages
    rather than from one merged list.
    """
    chk = _load(f"check-{attempt}.json")
    engine_ok = bool(chk.get("complete")) and bool(chk.get("closing_admissible"))
    dom_ok = not result.domain_blocking
    return (f"endpoint={ENDPOINT} attempt={attempt} "
            f"ENGINE={'COMPLETE' if engine_ok else 'INCOMPLETE'}"
            f"({len(chk.get('blocking') or [])} blocking) "
            f"DOMAIN={'PASSED' if dom_ok else 'BLOCKED'}"
            f"({len(result.domain_blocking)} blocking) "
            f"claims={len(result.findings)} "
            f"VERDICT={'CLOSEABLE' if (engine_ok and dom_ok) else 'NOT CLOSEABLE'}")


def _write_next_response(attempt: int, facts) -> None:
    """§14's response for attempt N+1, DERIVED from the report.

    The same document `sweep/coordinator/driver.py::_record_attempt_outcome`
    builds, with the same keys, because this harness is a CALLER of that seam
    and must not invent a second response shape. Never overwrites one already
    on disk, so an operator adding campaign provenance by hand still wins.
    """
    nxt = STATE / f"response-{attempt + 1}.json"
    if nxt.exists():
        print(f"[check] {nxt.name} already exists — left alone")
        return
    if facts.closing_admissible():
        print("[check] closing report — no next response to write")
        return
    doc = {
        "provenance": f"one-stack §14's previous response, derived from attempt "
                      f"{attempt}'s report by drive.py.",
        "outcome": facts.outcome,
        "complete": facts.complete,
        "blocking": list(facts.blocking or ()),
        "not_closeable_because": list(facts.closing_inadmissible_because()),
        "denied": [],
    }
    if facts.unsettled:
        doc["unsettled"] = [dict(u) for u in facts.unsettled]
        doc["what_an_unsettled_gate_row_means"] = (
            "A gate row whose verdict is NOT-TESTABLE / NOT-COMPARABLE / ERROR "
            "/ UNKNOWN settled NOTHING. It is treated as a NO: the assumption "
            "it guards is NOT verified and this endpoint cannot close while the "
            "row stands. It is also not a refutation, so the answer is to make "
            "the gate ABLE to run, not to argue the row away. Each row's "
            "`detail` says what the gate lacked; where it says no run records "
            "both members of a pair, the row is an EXPLORATION TARGET — produce "
            "a run that records BOTH decisions and the gate will have a base to "
            "replay. Do not drop, weaken or re-declare an assumption to make a "
            "row disappear: a withdrawn assumption restores the demand it was "
            "pruning, which is a bigger corpus obligation, not a smaller one.")
    if facts.tree_missing:
        doc["tree_missing"] = list(facts.tree_missing)
    _save(nxt.name, doc)
    print(f"[check] wrote {nxt.name}: {len(doc.get('unsettled') or [])} unsettled "
          f"row(s), {len(doc.get('tree_missing') or [])} unwalked prefix(es)")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", required=True,
                    choices=("batch", "pregate", "check", "policy",
                             "realmode", "concrete"))
    ap.add_argument("--attempt", type=int, default=1)
    args = ap.parse_args(argv)
    AGENT_HOME.mkdir(parents=True, exist_ok=True)
    (HERE / "out").mkdir(parents=True, exist_ok=True)
    return {"batch": stage_batch, "pregate": stage_pregate,
            "check": stage_check, "policy": stage_policy,
            "realmode": stage_realmode,
            "concrete": stage_concrete}[args.stage](args)


if __name__ == "__main__":
    raise SystemExit(main())
