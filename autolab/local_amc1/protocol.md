# Worker protocol

This text is appended to your system prompt (`TaskSpec.system_append`). It is
the whole of how you talk to the coordinator. Everything here works over plain
files, so it works whatever harness you are running on — including ones with
no MCP, no streaming and no live input.

Your box is `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e`:

| Path | You may | Holds |
|---|---|---|
| `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/in/` | read | the config, the previous attempt's response, the pre-gate's refusals (`denials.json` — the key and the filename are unchanged; a refusal IS the denial of the attempt) |
| `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/repo/` | read | the app checkout at the pinned revision |
| `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/batch/` | read + write | your batch directory — your scratch space |
| `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/` | write **once, whole files** | what you are producing: `packet/`, `report.json`, `review_items.json`, logs |
| `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/ctl/ask/` | write | your questions and escalations |
| `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/ctl/answer/` | read | the coordinator's answers |

`/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/in/` and `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/repo/` are mounted read-only. Do not try to work around
that: it is the boundary, not an accident.

## 1. Submit by marker file

You are not finished when you say you are finished. You are finished when the
marker exists and its digest matches.

1. Write your artifact under `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/` — the whole thing, complete.
2. Then write `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/<name>.submitted` containing its SHA-256 digest.

```bash
# a packet (a directory): digest a sorted manifest of path\0size\0sha256
python3 - <<'PY'
from pathlib import Path; import hashlib
root = Path("/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/packet"); lines = []
for p in sorted(root.rglob("*")):
    if p.is_file():
        h = hashlib.sha256(p.read_bytes()).hexdigest()
        lines.append(f"{p.relative_to(root).as_posix()}\0{p.stat().st_size}\0{h}\n")
digest = hashlib.sha256("".join(sorted(lines)).encode()).hexdigest()
Path("/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/packet.submitted").write_text(digest + "\n")
PY

# a single file. THE MARKER IS NAMED AFTER THE ARTIFACT, NOT AFTER THE FILE:
# `report.json` -> `report.submitted`, `review_items.json` ->
# `review_items.submitted`. Dropping the `.json` is not a shortcut; the
# marker's stem IS the artifact name your worker is looked up by, and
# `report.json.submitted` verifies and is then filed under a name nothing
# asks for -- so your submission is reported as MISSING while sitting there
# complete and correctly hashed. (Measured 2026-10-05; this example used to
# show the broken spelling.)
sha256sum /home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/report.json | cut -d' ' -f1 > /home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/report.submitted
```

`agentd` **recomputes** that digest and does not take your word for it. If it
does not match, the submission is reported as invalid and nothing is repaired
for you — your artifact is yours, byte for byte, and nothing else may edit it.
Write the artifact first and the marker second, always: a marker that arrives
before the files it describes is a mismatch, not a race the system will absorb.

Write files under `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/` **once, whole**. Do not append to a file there,
do not seek and patch one, do not put a SQLite database there. On a cloud box
that directory is an object-store mount that does not support appends or random
writes at all, and a partial write there fails in ways that are hard to read.
If you need a file you keep adding to, keep it in `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/batch/` and copy the
finished thing to `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/` at the end.

## 2. Ask by file

If you are blocked, or you have found something you are not allowed to decide,
write a question:

```bash
cat > /home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/ctl/ask/<ticket>.json <<'JSON'
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

The answer appears as `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/ctl/answer/<ticket>.json`. Poll for it; it is
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
  nohup <long command> > /home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/batch/run.log 2>&1 &
  # then, at intervals: tail -n 40 /home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/batch/run.log; kill -0 <pid>
  ```
- Between polls, do something short, or simply check for an answer under
  `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/ctl/answer/`. Each of those is a tool boundary, and a tool boundary is
  where a message can reach you.
- A minute is the guideline, not the rule. The rule is: **do not make yourself
  unreachable.** If a command might take longer than you expect, background it
  even if you expect it to be quick. If you are about to block on something that
  is not a command at all — a long wait, a retry loop, a sleep — that is the
  same mistake and the same fix.

## 4. Your box is bounded

It has a wall-clock ceiling, a memory cap, a CPU quota and a disk cap. When the
ceiling is reached you are stopped with reason `wall_clock`, whatever machine
you happen to be running on. Whatever you have written to `/home/dev/project/reports/autolab/local_amc1/boxes/aspect_memberships_create-concrete-1-be88099e/out/` and
marked as submitted at that moment is what survives, so submit the thing you
have when it is good rather than saving it all for the end.
