#!/usr/bin/env python3
"""The four-stage chain for ONE endpoint, LOCALLY, through the normal path.

    batch  ->  review  ->  check          (concrete is a stage-2 gap; see below)

Every stage goes through `sweep.binding.WorkerLayer.run(WorkRequest)` — the one
method `coordinator.driver.Workers` names — on the `host` execution backend.
Nothing here re-implements provision / stage / launch / poll / fetch / teardown,
rebuilds a `WorkerSpec`, patches a plan, or names an interpreter for a box. That
is the whole point: `tests/sweep_e2e/test_cloud_chain_composes.py`'s co-located
control asserts this composition holds on `host`, and this file is that control
with the fakes removed:

  * the agent is the REAL `ClaudeCodeBackend` over the REAL `claude` binary
    (`/home/dev/.local/bin/claude`), not `sweep/tests/fake_claude.py`;
  * `concolic.check` is the REAL checker on this tree's `PYTHONPATH`, not
    `tests/sweep_e2e/fake_concolic`;
  * `review()` is `python -m concolic.review` in a subprocess, as it already was.

WHY THE CALLER IS A FILE AT ALL. `WorkerLayer` is the seam, and four things a
worker needs are not on it (the module docstring of `sweep/binding.py` lists
them): the brief, the repo and batch directory, the domain, and a CONSTRUCTED
agent backend. §7.8 makes constructing the adapter the caller's because it
needs credentials `sweep/` does not hold. This file is that caller, and it is
the only thing here that is campaign-specific.

CREDENTIALS, and why `config_dir=` is set. `ClaudeCodeBackend.session_store`
points `CLAUDE_CONFIG_DIR` INSIDE the box so two workers never share a session
store — which on a fresh box also means no claude.ai login and no settings. On
`host` the box is this machine, so the caller supplies a config directory it
prepared: `agent_config/` holds a copy of the operator's `.credentials.json`
(the claude.ai subscription login — CLAUDE.md's rule is that no
ANTHROPIC_* override may be set, and none is) and a `settings.json` whose
allow-list is what makes `--permission-prompts none` a working posture rather
than a hang. `setting_sources="user"` is what makes that file read at all.

SCOPE ON A SHARED MACHINE. `HostBackend.capabilities.isolates_filesystem` is
False and the brief's `ro` mounts are symlinks and a convention (§8.5), so the
agent can reach the whole machine. The settings file DENIES Write/Edit outside
the box, the addendum says it in words, and the box tree lives under
`reports/autolab/local_cc/boxes/`.

STAGES. `--stage` runs one; state that has to cross a stage boundary (the
packet path, the approval hash) is written to `state/`, because each stage is a
separate process here so a long batch box cannot be lost to a driver crash.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import replace as dc_replace
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = "/home/dev/project/src_new"
sys.path.insert(0, SRC)

from sweep import briefs                                          # noqa: E402
from sweep.agents.claude_code import ClaudeCodeBackend            # noqa: E402
from sweep.binding import WorkerLayer                             # noqa: E402
from sweep.coordinator.driver import WorkRequest                  # noqa: E402
from sweep.coordinator.review import (                            # noqa: E402
    ReviewAnswer, SubprocessReviewSource, approval_hash, verify_packet,
)
from sweep.execution.host import FakeSystemd, HostBackend         # noqa: E402
from sweep.spec import load_spec                                  # noqa: E402
from sweep.telemetry.usage import WorkerRows                      # noqa: E402

#: Two spec files, differing in ONE number: `boxes.md.max_wall_s`. The batch
#: box gets 5400 s, because a batch agent that ends its turn without submitting
#: has nothing left to do and every further second is idle billing (measured
#: attempt 1). The check box gets 14400 s, because §6.1's deadline GATES the
#: completion step and this endpoint's config configures two heavy gates whose
#: own timeouts sum to 7800 s; at 5400 the pass would report "the deadline was
#: reached before the completion gate ran" and set `wall_clock_terminated`,
#: which §12.1 treats as a disqualified closing run. The endpoint's config —
#: the thing the packet's digest binds — is identical for both. `parse_spec`
#: is a closed schema, so the reasoning lives in SPEC_NOTES.md, not in a
#: comment key.
SPEC_PATH = HERE / "sweep_local.json"
SPEC_PATH_CHECK = HERE / "sweep_local_check.json"
ENDPOINT = "posts_destroy"
CONFIG = HERE / "inputs" / f"{ENDPOINT}_config.json"
REPO = Path("/home/dev/project/ruby_examples/dse-apps/apps/diaspora")
STATE = HERE / "state"
CLAUDE = "/home/dev/.local/bin/claude"
AGENT_CONFIG = HERE / "agent_config"
AGENT_HOME = HERE / "agent_home"
IMAGE = ""          # `host` ignores it (`image_ignored` on the box record)
APP_REVISION = "diaspora@local-worktree"

#: The caller's PATH for the agent's child. §7.8: constructed, never inherited.
AGENT_PATH = "/home/dev/.local/bin:/usr/local/bin:/usr/bin:/bin"


def _spec(kind: str = "batch"):
    return load_spec(SPEC_PATH_CHECK if kind == "check" else SPEC_PATH)


def _brief() -> str:
    """§6.2's brief: the shipped app-agnostic one, plus the campaign addendum.

    The addendum is the caller's by design (`sweep/briefs/batch.md`: everything
    specific to a campaign reaches the agent through its staged inputs and the
    caller's brief). `reports/autolab/docs/briefs_addendum.md` is the one this
    campaign already had — measured against three boxes that burned a turn
    re-listing directories — and `addendum_local.md` is this run's two extra
    facts: the box is a directory on a shared machine, and the corpus has to be
    WIDENED rather than merely produced.
    """
    parts = [briefs.batch_brief(),
             Path("/home/dev/project/reports/autolab/docs/briefs_addendum.md").read_text(),
             (HERE / "addendum_local.md").read_text()]
    return "\n\n".join(parts)


def _agent_factory(req, aspec):
    """§7.8's half of the seam: the adapter, constructed, with credentials."""
    return ClaudeCodeBackend(
        executable=CLAUDE,
        base_env={"PATH": AGENT_PATH,
                  "HOME": str(AGENT_HOME),
                  "TERM": "dumb"},
        config_dir=str(AGENT_CONFIG),
        setting_sources="user",
    )


def _layer(execution=None):
    ex = execution if execution is not None else HostBackend(
        HERE / "boxes", systemd=FakeSystemd(root=HERE / "cg"))
    return WorkerLayer(
        execution=ex,
        rows=WorkerRows(HERE / "out" / "workers.jsonl"),
        root=HERE / "layer",
        repo=REPO,
        batch_brief=_brief(),
        agent_factory=_agent_factory,
        # §6.1: the box names its own interpreter and its own PATH/PYTHONPATH.
        # `check_module=None` is what asks it; `check_env` adds nothing, because
        # `HostBackend.box_python_env()` already puts this tree on PYTHONPATH.
        check_module=None,
        check_env={},
        # §8.5: an agentic worker on a backend with no filesystem isolation is
        # refused unless the sweep says so out loud. This is that grant.
        allow_shared_machine=True,
        app_revision=APP_REVISION,
        # A batch box that never says `hello` still costs wall clock; generous
        # because a cold `claude` start plus a JRuby/Rails boot is minutes.
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
    print(f"[batch] submitted={result.submitted} exit={result.detail} "
          f"elapsed={time.time() - t0:.0f}s")
    print(f"[batch] packet={result.packet}")
    print(f"[batch] tokens={getattr(r, 'tokens', None)} "
          f"cost={getattr(r, 'cost', None)} "
          f"denials={getattr(r, 'permission_denials', None)}")
    _save(f"batch-{args.attempt}.json", {
        "submitted": result.submitted, "packet": str(result.packet or ""),
        "detail": result.detail, "box": str(getattr(r, "box_id", "")),
        "elapsed_s": round(time.time() - t0, 1),
    })
    if result.packet:
        _save("packet.json", {"path": str(result.packet),
                              "attempt": args.attempt})
    return 0 if result.submitted else 1


def _gate_artefact_guard(packet: Path) -> list[str]:
    """Reviewer diligence on the two gate artefacts, BEFORE a check box runs.

    MEASURED 2026-09-30 against the previous attempt's packet: its
    `shim_tests.rb` defined 36 plain `test_*` methods instead of the constant
    `SHIM_TESTS`, the runner aborted, and because it wrote no results file
    `concolic.checks.shims.test_shims` raised `RuntimeError` — out of
    `attach_to_summary`, out of `check()`, with no report written at all. A
    malformed artefact therefore does not cost a red gate, it costs the WHOLE
    pass including an already-computed coverage verdict.

    §5.2 step 1 (`verify_packet`) checks that each named artefact EXISTS. This
    checks that the two the config's gates will actually consume are loadable.
    It is a reviewer's own reading of the packet — it changes no gate, relaxes
    nothing, and its findings are reported, never repaired. `shim_tests` and
    `assumption_manifest` are both optional keys the brief allows an agent to
    omit, so "absent" is not a finding here; "present and unusable" is.
    """
    import subprocess
    findings: list[str] = []
    doc = json.loads((packet / "packet.json").read_text())

    name = doc.get("shim_tests")
    if name:
        f = packet / name
        chk = subprocess.run(["ruby", "-c", str(f)], capture_output=True, text=True)
        if chk.returncode != 0:
            findings.append(f"shim_tests {name}: ruby -c failed: "
                            f"{(chk.stderr or chk.stdout).strip()[:300]}")
        else:
            probe = subprocess.run(
                ["ruby", "-e",
                 f'load {str(f)!r}; exit(defined?(SHIM_TESTS) ? 0 : 3)'],
                capture_output=True, text=True)
            if probe.returncode == 3:
                findings.append(
                    f"shim_tests {name}: parses but does not define SHIM_TESTS. "
                    "shim_test_runner.rb aborts on this and writes no results, "
                    "which raises out of the whole check pass")
            elif probe.returncode != 0:
                findings.append(f"shim_tests {name}: loading it raised: "
                                f"{(probe.stderr or '').strip()[:300]}")

    name = doc.get("assumption_manifest")
    if name:
        f = packet / name
        try:
            m = json.loads(f.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            findings.append(f"assumption_manifest {name}: not readable JSON ({exc})")
        else:
            for key in ("batch_dir", "runner"):
                if not m.get(key):
                    findings.append(
                        f"assumption_manifest {name}: no {key!r}. The assumption "
                        "gate reads it unguarded")
    return findings


def stage_review(args) -> int:
    """§5.2 step 1 (mechanical) then the REAL `python -m concolic.review`."""
    import hashlib
    packet = Path(_load("packet.json")["path"])
    digest = hashlib.sha256(CONFIG.read_bytes()).hexdigest()
    contents = verify_packet(packet, config_digest=digest)
    print(f"[review] step 1: config_digest ok, carries={sorted(contents.carries)}")

    guard = _gate_artefact_guard(packet)
    _save("gate_guard.json", {"findings": guard})
    for g in guard:
        print(f"[review] GATE ARTEFACT FINDING: {g}")
    if guard:
        print("[review] STOPPING before the check box: the artefacts above would "
              "abort the check pass rather than fail their gate. Nothing is "
              "repaired here (§12.2 rule 2) — this is a denial to carry back to "
              "the batch agent as denials.json on the next attempt.")
        return 3

    source = SubprocessReviewSource(
        env={"PATH": "/usr/local/bin:/usr/bin:/bin", "PYTHONPATH": SRC},
        cwd=SRC)
    out = HERE / "review" / f"attempt-{args.attempt}.json"
    doc = source.review(endpoint=ENDPOINT, config=CONFIG, packet=packet, out=out)
    print(f"[review] {len(doc.items)} item(s), doc_hash={doc.hash}")
    _save(f"review_items-{args.attempt}.json", {
        "doc": str(out), "doc_hash": doc.hash,
        "config_digest": doc.config_digest, "app_revision": doc.app_revision,
        "items": [{"id": i.id, "text": i.text, "consequence": i.consequence}
                  for i in doc.items]})
    for i in doc.items:
        print(f"\n  == {i.id}\n     {i.text}")
    print(f"\n[review] STOP. §5.2 step 4 wants an answer per item, each with its "
          f"own reason and the consequence it would let through. Write "
          f"{STATE / f'answers-{args.attempt}.json'} — a JSON object mapping "
          f"item id -> {{answer, reason, consequence}} — and run --stage approve. "
          f"Nothing here answers them for you: a blanket accept over "
          f"{len(doc.items)} substantive items is a rubber stamp, and the "
          f"approval hash is what licenses the check worker.")
    return 0


def stage_approve(args) -> int:
    """§5.2 steps 4-5: bind the answers to the document, as `approval_hash`."""
    meta = _load(f"review_items-{args.attempt}.json")
    answers_doc = _load(f"answers-{args.attempt}.json")
    ids = [i["id"] for i in meta["items"]]
    missing = [i for i in ids if i not in answers_doc]
    if missing:
        print(f"[approve] REFUSED: {len(missing)} item(s) unanswered: {missing}")
        return 3
    answers = [ReviewAnswer(item_id=i, answer=answers_doc[i]["answer"],
                            reason=answers_doc[i]["reason"],
                            consequence=answers_doc[i]["consequence"])
               for i in ids]
    denied = [a.item_id for a in answers if not a.accepted]
    approved = approval_hash(meta["doc_hash"], answers)
    _save("approved.json", {"approved": approved, "doc_hash": meta["doc_hash"],
                            "items": len(answers), "denied": denied})
    print(f"[approve] {len(answers)} answered, {len(denied)} denied: {denied}")
    print(f"[approve] approved={approved}")
    if denied:
        print("[approve] §5.2 step 6: a denied item goes back to the batch agent "
              "as denials.json; it does not license a check worker.")
        return 1
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
    print(f"[check] elapsed={time.time() - t0:.0f}s exit={result.detail}")
    print(f"[check] report={getattr(r, 'report_path', None)} "
          f"verified={getattr(r, 'report_verified', None)}")
    if facts is None:
        print("[check] NO FACTS — the checker wrote no report (UNDECIDED)")
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
        "report": str(getattr(r, "report_path", "")),
        "elapsed_s": round(time.time() - t0, 1)})
    _write_next_response(args.attempt, facts)
    return 0 if facts.complete else 1


def _write_next_response(attempt: int, facts) -> None:
    """§14's response for attempt N+1, DERIVED from the report.

    WHY THIS EXISTS. `stage_batch` reads `state/response-{attempt}.json` and
    nothing used to write it: attempts 1 and 2 of the 2026-09-30 campaign were
    handed responses an operator had composed BY HAND, pulling the witnesses
    out of the report themselves because `ReportFacts` did not carry them. So
    when attempt 2's check came back with 11 confinement pairs NOT-TESTABLE,
    the campaign stopped — not because an attempt counter ran out and not
    because an agent gave up, but because no response-3 existed and nothing
    would have written one. The loop was never exercised past the point where
    the hand-written responses ran out.

    This is the same document `sweep/coordinator/driver.py::
    _record_attempt_outcome` builds, with the same keys, because the local
    harness is a CALLER of that seam and must not invent a second response
    shape. A response written here is a starting point for the operator to add
    campaign-specific provenance to, not a replacement for their judgment —
    which is why it never overwrites one that is already on disk.
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
          f"row(s), {len(doc.get('tree_missing') or []) } unwalked prefix(es)")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", required=True,
                    choices=("batch", "review", "approve", "check"))
    ap.add_argument("--attempt", type=int, default=1)
    args = ap.parse_args(argv)
    AGENT_HOME.mkdir(parents=True, exist_ok=True)
    # No `all`: §5.2 step 4 is a judgment between review and check, and a
    # driver that ran straight through would have to answer the items itself.
    return {"batch": stage_batch, "review": stage_review,
            "approve": stage_approve, "check": stage_check}[args.stage](args)


if __name__ == "__main__":
    raise SystemExit(main())
