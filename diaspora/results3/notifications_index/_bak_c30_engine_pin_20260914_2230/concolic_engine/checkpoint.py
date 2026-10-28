"""Opt-in, crash-safe checkpointing for the engine's long phases.

Owner rule, 2026-09-12: *anything that runs longer than ~10 minutes must
checkpoint its progress and resume from it on a rerun, instead of restarting
from zero.* The checker's demand-set enumeration is hours of Z3 on a real
corpus and, before this module, wrote nothing until the very end — a kill at
2 h 30 threw away 2 h 30.

Design constraints this module is built to (``src/`` discipline):

- **Opt-in.** Nothing here runs unless a path is given, via the
  ``COVERAGE_CHECKPOINT`` environment variable or an explicit ``checkpoint=``
  argument. With it unset every existing invocation behaves exactly as before,
  byte for byte.
- **Keyed on the inputs.** The file's first line is a HEADER carrying a
  dict of key/digest pairs describing everything the checkpointed phase reads
  (engine source hash, checker parameters, corpus digest, assumption digest,
  the demand list, ...). On open, a file whose header does not match the
  current keys is NOT reused: it is rotated aside to ``<path>.stale`` and a
  fresh one is started, with a notice. A stale checkpoint can therefore never
  be silently consumed.
- **Atomic.** The header is written to a temp file in the same directory and
  ``os.replace``-d into place, so a half-written header cannot exist. Records
  are appended one complete line at a time and flushed; a process killed
  mid-append leaves at most a truncated LAST line, which the reader drops.
- **Flushed on SIGTERM/SIGINT.** The handlers fsync and close the log, then
  chain to whatever handler was installed before.
- **Simple format.** JSON Lines. Line 1 is the header; every later line is
  ``{"k": <record key>, "v": <record value>}``. A key written twice wins on
  its LAST occurrence (an append log, not a database).

Nothing in this module is specific to any experiment, endpoint or corpus.
"""

from __future__ import annotations

import atexit
import hashlib
import json
import os
import signal
import sys
import time
import typing as t

FORMAT = "concolic-engine-checkpoint"
FORMAT_VERSION = 1

#: Environment variable that enables checkpointing of the coverage checker's
#: demand-set enumeration. Unset (or empty) = today's behaviour.
ENV_VAR = "COVERAGE_CHECKPOINT"

#: How often the append log is fsync()ed, in seconds. Every record is
#: flush()ed immediately (which is what survives a process kill); the fsync
#: is the stronger guarantee that survives a machine crash, and is rate
#: limited because a demand-set record can be microseconds of work.
FSYNC_INTERVAL_S = 5.0


def _stderr(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def digest(*parts: t.Any) -> str:
    """A short, stable digest of any JSON-able values.

    ``default=str`` keeps it total: an exotic value degrades to its repr
    rather than raising, and two different exotic values with the same repr
    are the only way to collide beyond the 128-bit birthday bound.
    """
    h = hashlib.blake2b(digest_size=16)
    for p in parts:
        h.update(
            json.dumps(p, sort_keys=True, default=str, separators=(",", ":")).encode()
        )
        h.update(b"\x00")
    return h.hexdigest()


def source_hash(*modules: t.Any) -> str:
    """Digest of the SOURCE of the given modules — the "module version".

    Any edit to the checker invalidates every checkpoint it wrote, which is
    the point: a checkpoint records the output of one particular algorithm on
    one particular input, and the algorithm is as much an input as the corpus.
    Falls back to the module's ``__name__`` when the source cannot be read
    (a zipimport, a REPL); the fallback is weaker, never wrong-in-silence,
    because it is recorded in the header as such.
    """
    h = hashlib.blake2b(digest_size=16)
    for m in modules:
        path = getattr(m, "__file__", None)
        try:
            with open(path, "rb") as fh:  # type: ignore[arg-type]
                h.update(hashlib.blake2b(fh.read(), digest_size=16).digest())
        except Exception:  # noqa: BLE001 - see docstring
            h.update(b"?" + str(getattr(m, "__name__", m)).encode())
        h.update(b"\x00")
    return h.hexdigest()


class Checkpoint:
    """An append-only, header-keyed JSON-Lines record log.

    Usage::

        ck = Checkpoint(path, keys={...})          # None-safe: see `open`
        for unit in units:
            done = ck.get(unit_key)
            if done is not None:
                replay(done)
                continue
            done = expensive(unit)
            ck.put(unit_key, done)
        ck.close()
    """

    def __init__(
        self,
        path: str,
        keys: t.Mapping[str, t.Any],
        *,
        log: t.Optional[t.Callable[[str], None]] = None,
        fsync_interval_s: float = FSYNC_INTERVAL_S,
        install_signal_handlers: bool = True,
    ) -> None:
        self.path = path
        self.keys = dict(keys)
        self._log = log if log is not None else _stderr
        self._fsync_interval_s = fsync_interval_s
        self._records: t.Dict[str, t.Any] = {}
        self._fh: t.Optional[t.IO[str]] = None
        self._last_fsync = 0.0
        self._closed = False
        self._prev_handlers: t.Dict[int, t.Any] = {}
        #: how many records were read back from an existing, matching file
        self.resumed = 0
        #: why an existing file was discarded, if it was
        self.stale_reason = ""
        #: records written by THIS process
        self.written = 0

        reuse = self._read_existing()
        if reuse:
            self._fh = open(self.path, "a", encoding="utf-8")
            self.resumed = len(self._records)
            self._log(
                f"[checkpoint] resuming from {self.path}: "
                f"{self.resumed} completed unit(s) will be skipped"
            )
        else:
            self._start_fresh()

        if install_signal_handlers:
            self._install_signal_handlers()
        # so an exception escaping the checkpointed phase still fsyncs and
        # un-installs the handlers; `close` is idempotent.
        atexit.register(self.close)

    # -- file lifecycle ---------------------------------------------------

    def _read_existing(self) -> bool:
        """Load a matching checkpoint; rotate a non-matching one aside.

        Returns True iff the existing file's header matches ``self.keys`` and
        its records were loaded.
        """
        if not os.path.exists(self.path):
            return False
        header: t.Optional[t.Dict[str, t.Any]] = None
        records: t.Dict[str, t.Any] = {}
        truncated_tail = False
        try:
            with open(self.path, "r", encoding="utf-8") as fh:
                for lineno, line in enumerate(fh):
                    if not line.endswith("\n"):
                        # a kill mid-append: an incomplete last line, dropped
                        truncated_tail = True
                        break
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                    except ValueError:
                        truncated_tail = True
                        break
                    if lineno == 0:
                        header = obj
                        continue
                    if isinstance(obj, dict) and "k" in obj:
                        records[obj["k"]] = obj.get("v")
        except OSError as exc:
            self.stale_reason = f"unreadable ({exc})"
            self._rotate_aside()
            return False

        if not isinstance(header, dict):
            self.stale_reason = "no header"
        elif header.get("format") != FORMAT:
            self.stale_reason = f"foreign format {header.get('format')!r}"
        elif header.get("version") != FORMAT_VERSION:
            self.stale_reason = (
                f"format version {header.get('version')!r} != {FORMAT_VERSION}"
            )
        elif header.get("keys") != self.keys:
            old = header.get("keys") or {}
            changed = sorted(
                k for k in set(old) | set(self.keys) if old.get(k) != self.keys.get(k)
            )
            self.stale_reason = "input keys changed: " + ", ".join(changed)
        if self.stale_reason:
            self._log(
                f"[checkpoint] DISCARDING stale checkpoint {self.path} "
                f"({self.stale_reason}); starting from zero"
            )
            self._rotate_aside()
            return False

        self._records = records
        if truncated_tail:
            self._log(
                "[checkpoint] the previous run was killed mid-write: "
                "dropped an incomplete trailing record"
            )
            # Rewrite the log without the torn tail so appends stay parseable.
            self._rewrite_atomically(header)
        return True

    def _rotate_aside(self) -> None:
        try:
            os.replace(self.path, self.path + ".stale")
        except OSError:
            pass

    def _header(self) -> t.Dict[str, t.Any]:
        return {
            "format": FORMAT,
            "version": FORMAT_VERSION,
            "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "pid": os.getpid(),
            "keys": self.keys,
        }

    def _write_atomically(self, lines: t.Sequence[str]) -> None:
        d = os.path.dirname(os.path.abspath(self.path)) or "."
        os.makedirs(d, exist_ok=True)
        tmp = os.path.join(d, f".{os.path.basename(self.path)}.tmp-{os.getpid()}")
        with open(tmp, "w", encoding="utf-8") as fh:
            for line in lines:
                fh.write(line)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, self.path)

    def _start_fresh(self) -> None:
        self._records = {}
        self._write_atomically(
            [json.dumps(self._header(), sort_keys=True, default=str) + "\n"]
        )
        self._fh = open(self.path, "a", encoding="utf-8")

    def _rewrite_atomically(self, header: t.Mapping[str, t.Any]) -> None:
        """Rewrite the log without its torn tail. The caller (``__init__``)
        opens the append handle afterwards — opening one here too would leak
        a file object."""
        lines = [json.dumps(header, sort_keys=True, default=str) + "\n"]
        lines += [
            json.dumps({"k": k, "v": v}, default=str) + "\n"
            for k, v in self._records.items()
        ]
        self._write_atomically(lines)

    # -- records ----------------------------------------------------------

    def get(self, key: str) -> t.Any:
        """The recorded value for ``key``, or None if this unit is not done."""
        return self._records.get(key)

    def __contains__(self, key: str) -> bool:
        return key in self._records

    def items(self) -> t.Iterator[t.Tuple[str, t.Any]]:
        """Every recorded (key, value) IN FILE ORDER.

        For a phase whose records are not independent of each other -- one
        that carries a string table, say, whose ids only mean anything when
        the records are replayed in the order they were appended.
        """
        return iter(list(self._records.items()))

    def pop(self, key: str, default: t.Any = None) -> t.Any:
        """The recorded value for ``key``, FORGOTTEN in memory as it is read.

        The record stays in the log (this is an append log, and forgetting is
        not un-recording): only this process's copy is dropped. For a phase
        that consumes each record exactly once and whose records are big
        enough that holding the whole log alongside the structure it rebuilds
        is the memory wall -- the corpus index is 2.6 GB of rows.
        """
        return self._records.pop(key, default)

    def put(self, key: str, value: t.Any) -> None:
        """Record one completed unit. Appended and flushed immediately."""
        if self._closed or self._fh is None:
            return
        self._records[key] = value
        self._fh.write(json.dumps({"k": key, "v": value}, default=str) + "\n")
        self._fh.flush()
        self.written += 1
        now = time.monotonic()
        if now - self._last_fsync >= self._fsync_interval_s:
            self._sync()
            self._last_fsync = now

    def _sync(self) -> None:
        if self._fh is None:
            return
        try:
            self._fh.flush()
            os.fsync(self._fh.fileno())
        except (OSError, ValueError):
            pass

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        self._sync()
        self._restore_signal_handlers()
        try:
            atexit.unregister(self.close)
        except Exception:  # noqa: BLE001
            pass
        try:
            if self._fh is not None:
                self._fh.close()
        except OSError:
            pass
        self._fh = None

    def __enter__(self) -> "Checkpoint":
        return self

    def __exit__(self, *exc: t.Any) -> bool:
        self.close()
        return False

    # -- signals ----------------------------------------------------------

    def _install_signal_handlers(self) -> None:
        for sig in (signal.SIGTERM, signal.SIGINT):
            try:
                self._prev_handlers[sig] = signal.getsignal(sig)
                signal.signal(sig, self._on_signal)
            except (ValueError, OSError, RuntimeError):
                # not the main thread, or the platform disallows it: the
                # per-record flush still holds, only the fsync is skipped.
                self._prev_handlers.pop(sig, None)

    def _restore_signal_handlers(self) -> None:
        for sig, prev in list(self._prev_handlers.items()):
            try:
                signal.signal(sig, prev)
            except (ValueError, OSError, RuntimeError):
                pass
        self._prev_handlers.clear()

    def _on_signal(self, signum: int, frame: t.Any) -> None:
        prev = self._prev_handlers.get(signum, signal.SIG_DFL)
        self._log(
            f"[checkpoint] signal {signum}: flushed {len(self._records)} "
            f"completed unit(s) to {self.path}"
        )
        self._sync()
        try:
            if self._fh is not None:
                self._fh.close()
        except OSError:
            pass
        self._fh = None
        self._closed = True
        # chain to whatever was installed before us
        self._restore_signal_handlers()
        if callable(prev):
            prev(signum, frame)
        elif prev == signal.SIG_DFL:
            signal.signal(signum, signal.SIG_DFL)
            os.kill(os.getpid(), signum)
        # SIG_IGN: nothing to do


def open_checkpoint(
    path: t.Optional[str],
    keys: t.Mapping[str, t.Any],
    *,
    env_var: str = ENV_VAR,
    log: t.Optional[t.Callable[[str], None]] = None,
    install_signal_handlers: bool = True,
) -> t.Optional[Checkpoint]:
    """Open a checkpoint, or return None when checkpointing is not enabled.

    ``path`` None falls back to ``os.environ[env_var]``; empty or missing =
    disabled, which is the default for every existing invocation. A failure
    to open (unwritable directory, say) is NOT fatal: it is reported and the
    job runs uncheckpointed, exactly as it did before this module existed.
    """
    if path is None:
        path = os.environ.get(env_var) or None
    if not path:
        return None
    try:
        return Checkpoint(
            path, keys, log=log, install_signal_handlers=install_signal_handlers
        )
    except Exception as exc:  # noqa: BLE001 - never fail the job over a cache
        (log or _stderr)(
            f"[checkpoint] could not open {path}: {exc}; running without one"
        )
        return None
