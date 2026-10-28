# Worker protocol

This text is appended to your system prompt (`TaskSpec.system_append`). It is
the whole of how you talk to the coordinator. Everything here works over plain
files, so it works whatever harness you are running on — including ones with
no MCP, no streaming and no live input.

Your box is `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec`:

| Path | You may | Holds |
|---|---|---|
| `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/in/` | read | the config, the previous attempt's response, the pre-gate's refusals (`denials.json` — the key and the filename are unchanged; a refusal IS the denial of the attempt) |
| `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/repo/` | read | the app checkout at the pinned revision |
| `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/batch/` | read + write | your batch directory — your scratch space |
| `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/` | write **once, whole files** | what you are producing: `packet/`, `report.json`, `review_items.json`, logs |
| `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/ctl/ask/` | write | your questions and escalations |
| `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/ctl/answer/` | read | the coordinator's answers |

`/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/in/` and `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/repo/` are mounted read-only. Do not try to work around
that: it is the boundary, not an accident.

## 1. Submit by marker file

You are not finished when you say you are finished. You are finished when the
marker exists and its digest matches.

1. Write your artifact under `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/` — the whole thing, complete.
2. Then write `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/<name>.submitted` containing its SHA-256 digest.

```bash
# a packet (a directory): digest a sorted manifest of path\0size\0sha256
python3 - <<'PY'
from pathlib import Path; import hashlib
root = Path("/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/packet"); lines = []
for p in sorted(root.rglob("*")):
    if p.is_file():
        h = hashlib.sha256(p.read_bytes()).hexdigest()
        lines.append(f"{p.relative_to(root).as_posix()}\0{p.stat().st_size}\0{h}\n")
digest = hashlib.sha256("".join(sorted(lines)).encode()).hexdigest()
Path("/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/packet.submitted").write_text(digest + "\n")
PY

# a single file. THE MARKER IS NAMED AFTER THE ARTIFACT, NOT AFTER THE FILE:
# `report.json` -> `report.submitted`, `review_items.json` ->
# `review_items.submitted`. Dropping the `.json` is not a shortcut; the
# marker's stem IS the artifact name your worker is looked up by, and
# `report.json.submitted` verifies and is then filed under a name nothing
# asks for -- so your submission is reported as MISSING while sitting there
# complete and correctly hashed. (Measured 2026-10-05; this example used to
# show the broken spelling.)
sha256sum /home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/report.json | cut -d' ' -f1 > /home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/report.submitted
```

`agentd` **recomputes** that digest and does not take your word for it. If it
does not match, the submission is reported as invalid and nothing is repaired
for you — your artifact is yours, byte for byte, and nothing else may edit it.
Write the artifact first and the marker second, always: a marker that arrives
before the files it describes is a mismatch, not a race the system will absorb.

Write files under `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/` **once, whole**. Do not append to a file there,
do not seek and patch one, do not put a SQLite database there. On a cloud box
that directory is an object-store mount that does not support appends or random
writes at all, and a partial write there fails in ways that are hard to read.
If you need a file you keep adding to, keep it in `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/batch/` and copy the
finished thing to `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/` at the end.

## 2. Ask by file

If you are blocked, or you have found something you are not allowed to decide,
write a question:

```bash
cat > /home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/ctl/ask/<ticket>.json <<'JSON'
{"ticket": "<ticket>",
 "kind": "escalation",
 "class": "shared",
 "text": "The target boundary in src/ is wrong for this endpoint: <what and why>"}
JSON
```

Pick any `<ticket>` that is unique within your box; the filename stem is the
ticket. `class` is `local`, `shared` or `sweep-wide` — how much finished work
your question could invalidate, not how important it feels. Omit `kind` and
`class` for an ordinary question.

The answer appears as `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/ctl/answer/<ticket>.json`. Poll for it; it is
written whole, so if the file exists it is complete.

**This file is the only way an escalation reaches anyone.** A concern you write
only into your own notes, your transcript or your final message does not reach
the coordinator and will not be acted on. If you are about to do something you
suspect you are not allowed to do — edit shared code, change a boundary, work
around a constraint rather than report it — stop and write the ask instead.

An answer may not come. If it does not, say in your submission what you asked
and what you did in the absence of an answer; do not silently pick one.

## 3. Run anything longer than a minute as a background task

This is the rule most likely to cost you if you skip it, so here is the reason
rather than just the rule.

The coordinator can send you a message while you are working. That message is
delivered **at your next tool boundary** — never in the middle of a tool call.
So if you launch a four-hour concolic run in the foreground and block on it,
you are unreachable for four hours. Nobody can tell you the run is pointless,
that the box is about to hit its wall clock, or that the answer you asked for
has arrived.

Measured on this machine: an interjection sent while a 28-second foreground
command was running was acked **23.3 seconds later** — it waited for the whole
command. With the same command backgrounded, the same interjection was answered
**1.65 seconds** end to end.

So:

- Launch long commands as background tasks and poll them, rather than blocking.
  Use your harness's background-task mechanism if it has one; otherwise
  redirect to a log and poll the log:
  ```bash
  nohup <long command> > /home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/batch/run.log 2>&1 &
  # then, at intervals: tail -n 40 /home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/batch/run.log; kill -0 <pid>
  ```
- Between polls, do something short, or simply check for an answer under
  `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/ctl/answer/`. Each of those is a tool boundary, and a tool boundary is
  where a message can reach you.
- A minute is the guideline, not the rule. The rule is: **do not make yourself
  unreachable.** If a command might take longer than you expect, background it
  even if you expect it to be quick. If you are about to block on something that
  is not a command at all — a long wait, a retry loop, a sleep — that is the
  same mistake and the same fix.

### Wait with the helper, never with a command-line pattern

Backgrounding a job means you then have to wait for it, and the wait is where
this goes wrong. **`pgrep -f <pattern>` and `pkill -f <pattern>` match the
pattern against every process's whole command line, including the command line
of the shell that is running your loop.** So

```bash
until ! pgrep -f "run_dse.rb --out /home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/batch/dumps"; do sleep 10; done
```

waits for itself and never returns. Your job finished in seconds; the loop
holds your turn for as long as anybody lets it, and while it holds it you are
exactly as unreachable as the rule above says not to be. Knowing about the
hazard is not protection from it, so the rule is a tool rather than a warning:

```bash
PY=python3   # whichever interpreter your config's runtime uses
W="$PY -m sweep.box.wait_for"

$W --pid 12345 --timeout 3600                     # you launched it: use its pid
$W --file /home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/batch/logs/run.done --timeout 600 # a sentinel the job writes
$W --exe /usr/bin/jruby --contains run_dse.rb --timeout 3600
$W --name jruby --list                            # who matches, without waiting
```

It identifies a process by its `/proc/<pid>/exe` or its exact
`/proc/<pid>/comm`, never by a substring of a command line, and it removes
itself, every one of its ancestors and its process group from the candidates
before it matches anything — so the same loop written through it cannot wait on
the shell that launched it. `--contains` only ever NARROWS one of those
identities and is refused on its own. Exit 0 means nothing (left) matching;
exit 2 means the timeout elapsed, which is a result you should report rather
than retry blindly.

Two more rules that come from the same place:

- **`--timeout` is required on a wait, and there is no default.** An unbounded
  wait is the unreachability this section is about, with no command to blame
  for it, so how long you are prepared to wait is yours to say. `--timeout 0`
  means forever and has to be asked for.
- **Never signal by pattern.** `pkill -f` kills whatever else happens to carry
  your pattern — including, on a shared machine, another run's explorer.
  Resolve the pid (`--list` prints what matches, so you can see it before you
  act on it), satisfy yourself it is yours, and signal that pid.

The best wait of all is one you do not have to match for: have the job write a
sentinel file when it ends, and wait for the file.

The addendum attached to this brief has a section on this too, with the cost
measured on the machine you are running on. If anything you are given tells
you to guard a `pgrep -f` pattern by hand instead, this is the rule that
holds: the helper is the guard.

## 4. Your box is bounded

It has a wall-clock ceiling, a memory cap, a CPU quota and a disk cap. When the
ceiling is reached you are stopped with reason `wall_clock`, whatever machine
you happen to be running on. Whatever you have written to `/home/dev/project/reports/autolab/local_amc3/boxes/aspect_memberships_create-concrete-1-2a85f5ec/out/` and
marked as submitted at that moment is what survives, so submit the thing you
have when it is good rather than saving it all for the end.
