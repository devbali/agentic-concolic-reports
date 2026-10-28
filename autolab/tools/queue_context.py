"""The `--context` factory for `python -m sweep.queue`, wired for THIS lab.

`sweep/queue/` holds no app anything: no repo path, no credential, no
provider route (`tests/test_self_contained.py`). So `advance` imports a
zero-argument factory by name and the factory is here, where the app lives.

    export SWEEP_QUEUE_CONFIG=/path/to/queue.json
    python -m sweep.queue advance --out <queue-dir> \
        --context reports.autolab.tools.queue_context:make

`SWEEP_QUEUE_CONFIG` names a JSON file with the same fields
`run_real_sweep.py` takes as flags, so the two agree by construction:

```json
{
  "spec": ".../sweep_openrouter.json",
  "out": ".../sweep_out_or",
  "repo": ".../ruby_examples/dse-apps/apps/diaspora",
  "corpus_root": ".../reports/autolab/e2e/runs",   # must hold dump_*.json
  "execution": "skypilot",
  "region": "us-central1",
  "instance_type": "n2-standard-2",
  "manifest": ".../reports/autolab/box/manifest.json",
  "provider": "openrouter",
  "key_file": ".../openrouter_api_key.txt",
  "app_revision": "real",
  "max_launch": 0
}
```

WHY A FILE AND NOT FLAGS: the CLI's contract is a zero-argument callable, so
that `advance` can be invoked identically by a person, by a cron line and by
an agent's tool call. Everything variable is therefore data, and the same
file drives every invocation of a run — which is also what makes two
invocations of `advance` agree about what they are advancing.

THE CREDENTIAL never enters the queue's files. It is read here, put into this
process's environment under the name the box's task document carries, and
`RealSky.to_task` moves it into SkyPilot's `envs` at launch (§7.8).
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve()
SRC = HERE.parents[3] / "src_new"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from sweep.queue.admission import PoolAdmission              # noqa: E402
from sweep.queue.cli import QueueContext                    # noqa: E402
from sweep.queue.store import Entry                         # noqa: E402
from sweep.queue.workers_runner import BatchRunner          # noqa: E402
from sweep.spec import load_spec                            # noqa: E402
from sweep.telemetry.usage import WorkerRows                # noqa: E402
from sweep.workers.batch import plan_batch                  # noqa: E402
from sweep import briefs                                    # noqa: E402

sys.path.insert(0, str(HERE.parent))
import run_real_sweep as rrs                                # noqa: E402

ENV_CONFIG = "SWEEP_QUEUE_CONFIG"

#: A batch worker's corpus. §6.2 mounts `batch_dir` into the box as
#: `<box>/batch`, and the brief tells the agent that is "where the corpus of
#: `dump_*.json` lives" — so on the CLOUD path the dumps have to be put there
#: before the plan is built or the agent arrives to an empty room.
#:
#: MEASURED 2026-09-29, the 161-endpoint wave: they were not. `plan_for`
#: created `batch_dir` and nothing ever filled it, and 51 boxes spent their
#: full `max_wall_s` re-listing directories looking for a corpus that was on
#: the dev box all along. The local path never showed it, because there
#: `batch_dir` IS the working directory and the corpus never has to travel.
#: The cloud path is the only place it does.
CORPUS_GLOB = "dump_*.json"


def corpus_for(corpus_root: Path, endpoint: str) -> list[Path]:
    """The dumps for one endpoint, or [] — the caller decides how loud that is."""
    return sorted((corpus_root / endpoint).glob(CORPUS_GLOB))


def check_every_endpoint_has_a_corpus(spec: Any, corpus_root: Path) -> None:
    """Refuse the WHOLE run before it launches anything, as `run_real_sweep`
    does ("an endpoint with no corpus cannot start").

    This guard is worth more than the staging it guards. The queue path had
    no equivalent, which is why a missing corpus ran at width 51 instead of
    failing at endpoint one: every box provisioned, billed for its wall
    clock, and reported a perfectly ordinary `exit_reason: stopped`.
    """
    missing = [e.name for e in spec.endpoints
               if not corpus_for(corpus_root, e.name)]
    if missing:
        raise SystemExit(
            f"corpus_root {corpus_root}: no {CORPUS_GLOB} for {len(missing)} "
            f"of {len(spec.endpoints)} endpoint(s), e.g. {missing[:5]}. An "
            "endpoint with no corpus cannot start, and on the cloud path it "
            "fails SILENTLY — the box provisions, the agent finds an empty "
            "batch/ and burns its whole wall clock. Point corpus_root at a "
            "tree that holds them (reports/autolab/e2e/runs has all 840).")


#: The mount that carries the staged corpus to the box. §6.2 stages
#: `batch_dir` as `<box root>/batch`, and the brief's table names it.
BATCH_MOUNT = "batch"


def check_config_points_at_the_corpus(config: Path, endpoint: str) -> None:
    """The config must send the agent to the directory the corpus is in.

    THIS IS THE GUARD THAT CATCHES BOTH BUGS, and it is the reason it exists
    rather than the staging fix beside it. `check_every_endpoint_has_a_corpus`
    only asks whether dumps exist here; it passes happily while the document
    the agent actually reads sends it somewhere else.

    MEASURED 2026-09-29, the one-box proof: the corpus was staged and visible
    at `<box>/batch` (14 dumps, confirmed by ssh), and the agent still never
    opened one — because `config.paths.batch_dir` was a dev-box absolute path
    into `scaffold/<endpoint>/`, the bundle reproduces that tree ON the box,
    and the copy there is empty. Two real directories, one full and one
    empty, and the config named the empty one. 186 tool calls, 20 of them
    listing `batch/`, zero dumps opened.

    So: every path in the block must be relative — an absolute path into this
    machine is wrong on a box by construction — and `batch_dir` must resolve
    inside the mount that carries the corpus.
    """
    try:
        doc = json.loads(Path(config).read_text())
    except Exception as exc:                                # noqa: BLE001
        raise RuntimeError(f"{endpoint}: unreadable config {config}: {exc}") from exc
    paths = doc.get("paths") or {}
    absolute = sorted(k for k, v in paths.items()
                      if isinstance(v, str) and os.path.isabs(v))
    if absolute:
        raise RuntimeError(
            f"{endpoint}: config {config} has absolute path(s) {absolute} in "
            "its `paths` block. The config travels to a machine with a "
            "different filesystem, so a path into this one is wrong there by "
            "construction — and the box bundle reproduces parts of this tree "
            "at their absolute paths, so it will RESOLVE on the box and be "
            "empty. Use box-relative values ('.', 'batch', 'out').")
    batch_dir = paths.get("batch_dir")
    if batch_dir is None:
        return
    first = Path(str(batch_dir)).parts[:1]
    if first != (BATCH_MOUNT,):
        raise RuntimeError(
            f"{endpoint}: config {config} says batch_dir={batch_dir!r}, which "
            f"does not resolve inside {BATCH_MOUNT!r} — the only directory the "
            "corpus is staged into. The agent would be sent somewhere the "
            "dumps are not.")


def stage_corpus(corpus_root: Path, endpoint: str, batch_dir: Path) -> int:
    """Copy one endpoint's dumps into the directory that is mounted to the box.

    Copied rather than symlinked: rsync stages `batch_dir` itself, and a
    symlink into a tree the box does not have is a dangling link on the far
    side — which is exactly what one agent reported seeing ("a config with a
    symlink that seems broken"). Idempotent, so re-advancing an entry after a
    transient failure re-stages nothing.
    """
    dumps = corpus_for(corpus_root, endpoint)
    if not dumps:
        raise RuntimeError(
            f"{endpoint}: no {CORPUS_GLOB} under {corpus_root / endpoint}. "
            "Refusing to launch a box whose brief promises it a corpus.")
    for f in dumps:
        dst = batch_dir / f.name
        if not dst.exists() or dst.stat().st_mtime < f.stat().st_mtime:
            shutil.copy2(f, dst)
    staged = sorted(batch_dir.glob(CORPUS_GLOB))
    if len(staged) < len(dumps):
        raise RuntimeError(
            f"{endpoint}: staged {len(staged)} of {len(dumps)} dumps into "
            f"{batch_dir}; refusing to launch a box with a partial corpus")
    # MAKE `rw` TRUE. `batch_mounts` declares this mount `rw` and the brief's
    # own table promises the agent "your batch directory" is read-write — and
    # MEASURED 2026-09-29 on a real box it is not: the batch agent ran
    # `touch /work/batch/test_write`, was denied, and said so ("the batch
    # directory is read-only ... which is inconsistent with the brief").
    #
    # The cause is the transport, not the declaration. A `file_mount` is an
    # rsync that PRESERVES THE SOURCE'S MODE, and it lands outside the one
    # `chown -R` the box's setup performs (that covers the unpacked bundle
    # under the manifest's `writable` prefixes, and a file_mount is not part
    # of the bundle). So whatever this directory's mode is here is what the
    # agent faces there, under whatever uid the far side happens to use.
    #
    # Setting the mode explicitly is therefore the only place the promise can
    # be made true without touching `src_new`: 0777 on the directory and 0666
    # on its files survive the copy and are writable whoever owns them.
    try:
        os.chmod(batch_dir, 0o777)
        for f in batch_dir.iterdir():
            if f.is_file():
                os.chmod(f, 0o666)
    except OSError:                                         # noqa: BLE001
        pass    # a mode we could not set is not a reason to refuse a launch
    return len(staged)


#: WHERE A TORN-DOWN BOX'S EVIDENCE GOES. `SkyPilotBackend.teardown` ends with
#: `shutil.rmtree(tree.root)` unless the keep policy says otherwise, and
#: `ctl/events.ndjson` — the ONLY per-box diagnostic record there is — goes with
#: it. Both diagnoses in `sweep_out_w3/RESULT.md` exist purely because someone
#: read that stream before stopping; the seven `md` boxes of the same wave are
#: recorded `tool_calls: 0` because nobody did, and that zero is an artefact of
#: the teardown rather than a measurement.
#:
#: So the copy is made HERE, automatically, on the way into every teardown,
#: rather than by an operator remembering. It lands beside the queue's own
#: records (`entries/`, `responses/`, `log.jsonl`) because those are the files
#: that already outlive every box and every invocation.
ARCHIVE_SUBDIR = "boxlogs"

#: What is copied out. `repo/` and `batch/` are deliberately NOT here: they are
#: mirrors of trees that still exist on this machine (the app checkout and
#: `corpus_root`), so copying them would multiply hundreds of megabytes per box
#: to preserve nothing that is not already preserved. Everything that is the
#: BOX'S OWN — what it was told, what it did, what it produced — is in these.
ARCHIVE_DIRS = ("ctl", "in", "out")


def _final_ctl_sync(backend: Any, box: Any, tree: Any) -> str:
    """Best effort: pull the live `ctl/` down once more before the VM dies.

    The event log is mirrored by polling, so the local copy is only as fresh
    as the last `advance`. The last frames written — which are exactly the
    ones that say how the box ENDED — are the likeliest to be missing. This
    is a courtesy, never a precondition: any failure is recorded and ignored,
    because refusing to tear a billing VM down over a failed diagnostic copy
    would be a far more expensive mistake than an incomplete log.
    """
    sky = getattr(backend, "sky", None)
    cluster = ""
    try:
        cluster = str(box.handle.get("cluster_name") or "")
    except Exception:                                       # noqa: BLE001
        pass
    if sky is None or not cluster:
        return "skipped (no live cluster)"
    try:
        remote_ctl = getattr(backend, "remote_ctl", None) or "/work/ctl"
        sky.rsync_down(cluster, str(remote_ctl), Path(tree.ctl))
        return "ok"
    except BaseException as exc:                            # noqa: BLE001
        return f"{type(exc).__name__}: {exc}"


def archive_box(backend: Any, box: Any, archive_root: Path) -> Path | None:
    """Copy one box's own files out of the mirror, before anything deletes it.

    Idempotent and total: it never raises. A teardown that did not happen
    because the archiver threw would leave a VM billing, which is the one
    outcome worse than a lost log.
    """
    try:
        tree = backend.tree_of(box)
    except BaseException:                                   # noqa: BLE001
        return None
    root = Path(getattr(tree, "root", "") or "")
    if not root.exists():
        return None
    dest = Path(archive_root) / str(getattr(box, "id", "") or "box")
    try:
        dest.mkdir(parents=True, exist_ok=True)
        note = {"box_id": getattr(box, "id", None),
                "archived_at": _dt.datetime.now(_dt.timezone.utc).isoformat(),
                "mirror_root": str(root),
                "final_ctl_sync": _final_ctl_sync(backend, box, tree),
                "copied": []}
        for name in ARCHIVE_DIRS:
            src = root / name
            if not src.exists():
                continue
            shutil.copytree(src, dest / name, dirs_exist_ok=True,
                            symlinks=True, ignore_dangling_symlinks=True)
            note["copied"].append(name)
        try:
            note["box"] = box.as_json()
        except BaseException:                               # noqa: BLE001
            pass
        (dest / "archived.json").write_text(json.dumps(note, indent=1) + "\n")
        return dest
    except BaseException as exc:                            # noqa: BLE001
        try:
            (dest / "archive_error.txt").write_text(f"{type(exc).__name__}: {exc}\n")
        except BaseException:                               # noqa: BLE001
            pass
        return dest


def install_ctl_preserver(backend: Any, archive_root: Path) -> Any:
    """Make `backend.teardown` archive first, always.

    An INSTANCE attribute shadowing the bound method, so nothing in `src_new`
    changes and the behaviour is confined to this lab's context factory. Every
    teardown path in `sweep/queue/advance.py` (collect, stop, reap-on-stop)
    goes through `backend.teardown`, so one wrapper covers all of them.
    """
    Path(archive_root).mkdir(parents=True, exist_ok=True)
    original = backend.teardown
    if getattr(original, "_preserves_ctl", False):
        return backend

    def teardown(box: Any, keep: Any) -> Any:
        archive_box(backend, box, Path(archive_root))
        return original(box, keep)

    teardown._preserves_ctl = True                          # type: ignore[attr-defined]
    backend.teardown = teardown                             # type: ignore[method-assign]
    return backend


def archive_all_live_mirrors(backend: Any, archive_root: Path,
                             store: Any) -> list[Path]:
    """Belt and braces: archive every open entry's box NOW, teardown or not.

    The wrapper above covers an orderly teardown. This covers the other way a
    mirror disappears — an operator `rm`, a crashed invocation, a box torn
    down by a path that never reached `teardown`. Cheap enough to call from a
    monitor loop.
    """
    from sweep.execution.base import Box                    # noqa: PLC0415
    out: list[Path] = []
    for entry in store.all():
        if not entry.box:
            continue
        try:
            box = Box.from_json(entry.box)
        except BaseException:                               # noqa: BLE001
            continue
        got = archive_box(backend, box, Path(archive_root))
        if got is not None:
            out.append(got)
    return out


def _config() -> dict[str, Any]:
    p = os.environ.get(ENV_CONFIG)
    if not p:
        raise SystemExit(
            f"{ENV_CONFIG} is not set. It names the JSON file this factory "
            "reads; see this module's docstring for its fields")
    doc = json.loads(Path(p).read_text())
    if not isinstance(doc, dict):
        raise SystemExit(f"{p}: expected a JSON object")
    return doc


def make() -> QueueContext:
    cfg = _config()
    out = Path(cfg["out"])
    out.mkdir(parents=True, exist_ok=True)
    spec = load_spec(cfg["spec"])

    # §7.8: the value is read once, here, and put in this process's
    # environment under the NAME the task document carries. It never reaches
    # the plan, the box record, the queue's files or the task document.
    key = Path(cfg["key_file"]).read_text().strip()
    if not key:
        raise SystemExit(f"{cfg['key_file']} is empty; there is no credential")
    os.environ[rrs.KEY_VAR] = key

    execution_kind = cfg.get("execution", "skypilot")
    backend = rrs.execution_for(
        execution_kind, out=out, manifest=cfg["manifest"],
        region=cfg.get("region", "us-central1"),
        real_systemd=bool(cfg.get("real_systemd", False)),
        instance_type=rrs._instance_types(cfg.get("instance_type") or ""))

    box_side = execution_kind != "host"
    dsh_home = rrs.BOX_DSH_HOME if box_side else str(
        Path(cfg["dsh_root"]) / "dshhome")
    dsh_bin = rrs.BOX_DSH_BIN if box_side else str(
        Path(cfg["dsh_root"]) / "node_modules" / ".bin" / "dsh")
    agent_factory = rrs.agent_factory_for(
        dsh_home=dsh_home, dsh_bin=dsh_bin, api_key=key,
        provider=cfg.get("provider", "openrouter"), box_side=box_side)

    repo = Path(cfg["repo"])
    corpus_root = Path(cfg["corpus_root"])
    # BEFORE anything can provision. See check_every_endpoint_has_a_corpus.
    check_every_endpoint_has_a_corpus(spec, corpus_root)
    for _e in spec.endpoints:
        check_config_points_at_the_corpus(Path(_e.config), _e.name)
    # THE BRIEF IS THE CALLER'S (`binding.py`: "the caller's, always"), so a
    # campaign-specific addendum belongs HERE and not in `src_new/sweep/briefs`
    # — that file is app-agnostic by design and names no application. The
    # addendum is optional: absent, the shipped brief is handed over unchanged.
    brief = briefs.batch_brief()
    addendum = Path(cfg.get("brief_addendum") or "")
    if str(addendum) and addendum.exists():
        brief = brief.rstrip() + "\n\n" + addendum.read_text().strip() + "\n"
    rows = WorkerRows(out / "workers.jsonl")
    batch_dirs = out / "batch"

    def plan_for(entry: Entry):
        ep = spec.endpoint(entry.endpoint)
        d = batch_dirs / entry.endpoint
        d.mkdir(parents=True, exist_ok=True)
        check_config_points_at_the_corpus(Path(ep.config), entry.endpoint)
        stage_corpus(corpus_root, entry.endpoint, d)
        return plan_batch(
            spec, entry.endpoint, sweep=spec.sweep, worker_id=entry.id,
            brief=brief, config=Path(ep.config), repo=repo, batch_dir=d,
            image=cfg.get("image", ""), execution_backend=backend.name,
            agent_backend=spec.agent_for(entry.endpoint, "batch").backend,
            model=spec.agent_for(entry.endpoint, "batch").model,
            effort=spec.agent_for(entry.endpoint, "batch").effort,
            attempt=entry.attempt, prices=spec.prices,
            max_usd=spec.budgets.usd_per_endpoint)

    class _Agents:
        """One adapter per entry. `agent_factory` wants a request-shaped
        object; the entry is the only request the queue has."""

        def __call__(self, entry: Entry) -> Any:
            aspec = spec.agent_for(entry.endpoint, "batch")
            return agent_factory(entry, aspec)

    runner = BatchRunner(backend=backend, plan_for=plan_for,
                         agent_for=_Agents(), rows=rows)

    # THE CEILING. Without this, 161 `put`s launch 161 VMs against a
    # `cloud.max_concurrent_vms` of 50 and the spec's number is a comment.
    # `PoolAdmission` builds §9's pools from the spec and charges every entry
    # that is already PROVISIONED or RUNNING — read off disk, because the
    # process that launched those boxes has exited.
    from sweep.queue.store import QueueStore
    queue_dir = Path(cfg.get("queue") or (out / "queue"))
    store = QueueStore(queue_dir)
    admit = PoolAdmission(spec=spec, all_entries=store.all,
                          local_backend=execution_kind)

    # EVIDENCE BEFORE TEARDOWN. See ARCHIVE_SUBDIR. This is installed on the
    # backend the QueueContext hands back, so it is in force for every
    # teardown `advance` performs — including the ones a `stop` triggers,
    # which is the path that erased seven boxes' event streams on 2026-09-29.
    install_ctl_preserver(backend, queue_dir / ARCHIVE_SUBDIR)

    return QueueContext(backend=backend, runner=runner, admit=admit,
                        max_launch=int(cfg.get("max_launch", 0)))
