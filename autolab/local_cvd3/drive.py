#!/usr/bin/env python3
"""The three-stage sweep chain for ONE endpoint, LOCALLY, after 87e08bf.

    batch  ->  pregate  ->  check

Every stage goes through `sweep.binding.WorkerLayer.run(WorkRequest)` — the one
method `sweep/coordinator/driver.py`'s `Workers` protocol names — on the `host`
execution backend. Nothing here re-implements provision / stage / launch / poll
/ fetch / teardown, rebuilds a `WorkerSpec`, patches a plan, or names an
interpreter for a box.

WHY THIS FILE EXISTS AND `sweep.testbed` DOES NOT DO. `testbed.py`'s only agent
backend is `ClaudeCodeBackend` pointed at `sweep/tests/fake_claude.py` ("no real
LLM call", its own docstring), and the fake harness copies already-recorded
dumps rather than exploring. The agent here is the REAL `claude` binary. The
rest — `concolic.validate`, `concolic.check` — is real in both.

WHAT IS DIFFERENT FROM `reports/autolab/local_cc/drive.py`, which is the same
file for the 2026-09-30 campaign on `posts_destroy`: that one has stages
`batch / review / approve / check` and imports `ReviewAnswer`,
`SubprocessReviewSource`, `approval_hash` and `verify_packet` from
`sweep.coordinator.review`. 87e08bf deleted the first three names and moved
`verify_packet` to `sweep.coordinator.pregate`, so **local_cc/drive.py no longer
imports**. The review stage is replaced here by ONE stage with no agent turn in
it: `verify_packet` (step 1), `python -m concolic.validate` (step 2) and the
app-tree digest (step 3), through `pregate.PreGate`. What licenses the check
worker is the pre-gate's DECISION RECORD ID, which is what `WorkRequest.
approved` now carries — `--approved` is gone from the checker's argv.

THE CHECK WORKER IS NON-AGENTIC AND ON ITS OWN BOX (§6.1, and a standing owner
requirement: the same agent may not check its own work). That is structural —
`plan_check` takes no agent and `binding.py` constructs none for `kind="check"`
— but it is also ASSERTED here, on the box ids, because a shared box would make
the requirement a matter of configuration (`_assert_separate_boxes`).

CREDENTIALS. `ClaudeCodeBackend.session_store` points `CLAUDE_CONFIG_DIR`
INSIDE the box so two workers never share a session store; on `host` the box is
this machine, so the caller supplies a config directory it prepared.
`agent_config/` holds a symlink to the operator's `.credentials.json` (claude.ai
subscription login) and a `settings.json` whose allow/deny list is what makes
`--permission-prompts none` a working posture rather than a hang. No
`ANTHROPIC_*` variable is set anywhere, per `/home/dev/project/CLAUDE.md`.

STAGES, one per invocation, because the pre-gate's answer is the thing a
campaign must be able to stop on and read.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
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

ENDPOINT = "conversation_visibilities_destroy"
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


def _spec(kind: str = "batch"):
    return load_spec(SPEC_PATH_CHECK if kind == "check" else SPEC_PATH)


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


def _layer():
    ex = HostBackend(HERE / "boxes", systemd=FakeSystemd(root=HERE / "cg"))
    return WorkerLayer(
        execution=ex,
        rows=WorkerRows(HERE / "out" / "workers.jsonl"),
        root=HERE / "layer",
        repo=REPO,
        batch_brief=_brief(),
        agent_factory=_agent_factory,
        # §6.1: the box names its own interpreter and its own PATH/PYTHONPATH.
        check_module=None,
        # BELT, NOT A FIX, AND MEASURED BOTH WAYS. §7.8 constructs a worker's
        # environment and `BOX_PYTHON_ENV_KEYS` is ("PATH", "PYTHONPATH"), so
        # nothing in the design gives the checker a LOCALE — and
        # `concolic/checks/proc.py::_run` hands `dict(os.environ)` to every
        # configured gate command. `shim_extractor.rb` reads two UTF-8 Ruby
        # files with `String#scan` and dies under US-ASCII ("invalid byte
        # sequence": `env -i PATH=... ruby shim_extractor.rb ...` exits 1).
        # What actually saves it is CPython: PEP 538 coercion puts
        # `LC_CTYPE=C.UTF-8` into `os.environ` of the checker process itself
        # (measured: `env -i PATH=... python3 -c 'print(dict(os.environ))'`
        # shows it), and `_run` passes that on. So the gate's locale comes from
        # the interpreter, not from anything constructed. With
        # `PYTHONCOERCECLOCALE=0` the same pass exits 70 with
        # `outcome: UNDECIDED`, `coverage: {}` and the Ruby traceback as its
        # one blocking line — the coverage verdict is lost to a locale. These
        # two keys make that independent of the interpreter's behaviour.
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


def _assert_separate_boxes(attempt: int) -> None:
    """The standing requirement, checked rather than assumed.

    §6.1 gives the check worker no agent and no agent backend; this asserts the
    other half — that it did not run where the batch agent ran. On `host` a box
    IS a directory, so "a different box" is literally a different path.

    READ OFF THE ARTEFACT PATHS, not off `WorkerRow`: the row carries no box
    identifier at all (measured — `row.box_id` does not exist and
    `getattr(r, "box_id", "")` is the empty string for both kinds, which made
    the first version of this check pass vacuously). `BatchResult.packet` is
    `<box>/out/packet` and `CheckResult.report_path` is `<box>/out/report.json`,
    so `parents[1]` is the box root in both cases.
    """
    b = _load(f"batch-{attempt}.json").get("box")
    c = _load(f"check-{attempt}.json").get("box")
    if not b or not c:
        raise SystemExit(f"REFUSED: cannot name both boxes (batch={b!r} "
                         f"check={c!r}); an unverifiable separation is not one")
    if b == c:
        raise SystemExit(f"REFUSED: batch and check shared box {b!r}")
    print(f"[boxes] batch={b}\n[boxes] check={c}\n[boxes] separate: True")


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
        "detail": result.detail,
        "box": str(Path(result.packet).parents[1]) if result.packet else "",
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
               "box": (str(Path(getattr(r, "report_path")).parents[1])
                       if getattr(r, "report_path", None) else ""),
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
        "report": str(getattr(r, "report_path", "") or ""),
        "box": (str(Path(getattr(r, "report_path")).parents[1])
                if getattr(r, "report_path", None) else ""),
        "elapsed_s": round(time.time() - t0, 1)})
    _assert_separate_boxes(args.attempt)
    _write_next_response(args.attempt, facts)
    return 0 if facts.complete else 1


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
                    choices=("batch", "pregate", "check"))
    ap.add_argument("--attempt", type=int, default=1)
    args = ap.parse_args(argv)
    AGENT_HOME.mkdir(parents=True, exist_ok=True)
    (HERE / "out").mkdir(parents=True, exist_ok=True)
    return {"batch": stage_batch, "pregate": stage_pregate,
            "check": stage_check}[args.stage](args)


if __name__ == "__main__":
    raise SystemExit(main())
