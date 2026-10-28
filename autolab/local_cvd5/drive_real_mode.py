#!/usr/bin/env python3
"""The REAL-MODE stage for conversation_visibilities_destroy, end to end.

    RubyAdapter.drive_real_mode  ->  the Rails probe  ->  concrete_run.json
                                 ->  domains/static_check.py --real
                                 ->  out/gate/review_items.json

This is the "capture ground truth, then compare" pair as ONE step a caller
sequences, which is what `concolic/DESIGN.md` §9's fourth adapter method was
for. Before 2026-10-06 the compare half existed with no producer and said so
in an item of its own (`statement-shape/no-real-mode-recording`); this file is
the producer being called through the seam rather than by hand.

WHY A CAMPAIGN FILE AND NOT `sweep/`
------------------------------------
`drive.py` in `local_cvd4` is the live caller of §6.3's domain gate and reads
`fixtures` / `real_mode_plan` off the endpoint config, where both are `null`.
Setting them is not enough to make the sweep drive a recording, and this file
does NOT pretend otherwise -- see "WHAT IS STILL NOT WIRED" below. What it
does is run the two halves in the order the gate will run them, against the
real artefacts, so that the mechanism is demonstrated rather than asserted.

WHAT IS STILL NOT WIRED, measured 2026-10-06
--------------------------------------------
1. `sweep/workers/concrete.py` mounts `in/real_mode_plan.json` (the PLAN) and
   has NO slot for the RECORDING. `concrete_mounts` would need one before a
   static half running inside a box could be pointed at a recording produced
   outside it.
2. `local_cvd4/drive.py`'s `STATIC_ARGV` deliberately omits `--real`, with a
   correct reason at the time (pointing it at the plan would hand
   `shape_check` a document of the wrong shape). With a recording to point at
   it needs `--real <path-inside-the-box>`.
3. `domains.load(name)` takes no arguments, so the `Domain` the static half
   builds has `app_config=None` and `shape_check`'s `note_aliases` is always
   empty. That costs nothing on THIS endpoint (no frame here needs an alias)
   and would matter on one where a mock records under another target's name.

None of the three is this file's to fix and each is named so it is not
mistaken for something this drive proved.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = Path("/home/dev/project/src_new")
VENV_PY = "/home/dev/project/venvs/queries_from_runs/bin/python3"

DOMAIN = "ruby_rails_sql"
ENDPOINT = "conversation_visibilities_destroy"

#: The probe, and the ONE place its path is written down. `real_mode_cmd` is a
#: config string the adapter substitutes `{plan}` and `{out}` into and does
#: not parse -- the same contract `extract_cmd` / `test_cmd` have.
#:
#: It goes through `scripts/diaspora-concolic` because that launcher is what
#: exports JAVA_HOME / GEM_HOME / RAILS_ENV=concolic and cd's into the app, and
#: `require "./config/environment"` only resolves from there. `unset
#: JAVA_TOOL_OPTIONS` is this machine's standing rule: the parent's value leaks
#: into every JVM and breaks it.
PROBE = SRC / "domains" / DOMAIN / "real_mode" / "real_mode_probe.rb"
REAL_MODE_CMD = (
    "unset JAVA_TOOL_OPTIONS; "
    f"/home/dev/project/scripts/diaspora-concolic {PROBE} {{plan}} {{out}}"
)

#: The policy IR is NOT rebuilt here. It is the one produced from the approved
#: packet's corpus by drive 4 (`local_cvd4/tools/build_policy_ir.py`), and
#: re-deriving it would mean this drive compared against a corpus side nobody
#: approved.
POLICY = Path("/home/dev/project/reports/autolab/local_cvd4/out/policy-1.json")

PLAN = HERE / "plan" / "real_mode_plan.json"
RECORDING = HERE / "out" / "concrete_run.json"
REVIEW_ITEMS = HERE / "out" / "gate" / "review_items.json"


def cfg() -> dict:
    """The batch `cfg` the adapter takes. Its schema is documented once, in
    `concolic/checks/__init__.py`; these are the three keys a real-mode drive
    reads, plus the timeout, which is named rather than inherited because a
    drive's cost grows with the PLAN."""
    return {
        "real_mode_cmd": REAL_MODE_CMD,
        "workdir": "/home/dev/project",
        "env": {"JAVA_TOOL_OPTIONS": ""},
        "real_mode_timeout": 900,
    }


def capture() -> dict:
    """Stage 1 -- THROUGH THE ADAPTER, not by shelling out to the probe.

    Calling the probe directly would demonstrate the Ruby and leave the seam
    untested, and the seam is half of what was missing: `drive_real_mode` did
    not exist, so nothing could sequence a capture at all.
    """
    sys.path.insert(0, str(SRC))
    from concolic.runtime import RubyAdapter

    RECORDING.parent.mkdir(parents=True, exist_ok=True)
    doc = RubyAdapter().drive_real_mode(cfg(), str(PLAN), out=str(RECORDING))
    scen = doc.get("scenarios", []) if isinstance(doc, dict) else doc
    n = sum(len(s.get("statements") or ()) for s in scen)
    print(f"[real-mode] {len(scen)} scenario(s), {n} statement(s) captured")
    for s in scen:
        print(f"[real-mode]   {s.get('name')}: "
              f"{len(s.get('statements') or ())} statement(s)"
              + (f"  ERROR: {s['error']}" if s.get("error") else ""))
    errs = [s.get("name") for s in scen if s.get("error")]
    if errs:
        # A scenario that raised still contributed the statements it issued
        # before raising, so the recording is usable -- but a reader must not
        # have to find that out by reading the JSON.
        print(f"[real-mode] WARNING: scenario(s) recorded an error: {errs}")
    return doc


def compare() -> int:
    """Stage 2 -- `domains/static_check.py`, unmodified, with `--real`.

    The same program §6.3's static half runs inside a box, with the same
    `--domain` / `--policy` / `--out`, and the one flag the campaign's
    `STATIC_ARGV` could not supply because there was nothing to point it at.
    Its exit code is the gate's: 0 = no items, 1 = items (which is NOT "the
    check failed"), 2 = it could not run.
    """
    REVIEW_ITEMS.parent.mkdir(parents=True, exist_ok=True)
    argv = [VENV_PY, str(SRC / "domains" / "static_check.py"),
            "--domain", DOMAIN,
            "--policy", str(POLICY),
            "--real", str(RECORDING),
            "--out", str(REVIEW_ITEMS)]
    env = dict(os.environ, PYTHONPATH=str(SRC))
    return subprocess.run(argv, cwd=str(HERE), env=env).returncode


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("stage", choices=["capture", "compare", "all"],
                    nargs="?", default="all")
    args = ap.parse_args()
    if args.stage in ("capture", "all"):
        capture()
    if args.stage in ("compare", "all"):
        rc = compare()
        print(f"[static] exit {rc} "
              f"({'no items' if rc == 0 else 'items' if rc == 1 else 'DID NOT RUN'})")
        if REVIEW_ITEMS.exists():
            items = json.loads(REVIEW_ITEMS.read_text())
            for it in items:
                print(f"[static]   {it['identity']}")
        return 0 if rc in (0, 1) else rc
    return 0


if __name__ == "__main__":
    sys.exit(main())
