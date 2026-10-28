#!/usr/bin/env python3
"""THE FULL ENGINE SECTION, run on a summary the coverage pass already wrote.

`coverage_report.py` runs the completion gate IN-PROCESS, at the end of a pass
that takes hours — so a gate that is cgroup-killed takes every coverage number
with it (the pass prints nothing until the very end). Splitting it costs
nothing in fidelity: `concolic_engine.completion.attach_to_summary` is the SAME
call the pass makes, on the SAME summary dict, and it derives `complete` the
same way (coverage_complete AND completion complete). src/ is untouched.

  SUMMARY_IN=<the pass's SUMMARY_OUT>  [SUMMARY_OUT=coverage_summary.json]
"""
import hashlib, json, os, shlex, sys
_ENV0 = dict(os.environ)      # env as RECEIVED, before our setdefault()s
sys.path.insert(0, "/home/dev/project/src")
HERE = os.path.dirname(os.path.abspath(__file__))
from concolic_engine.completion import attach_to_summary  # noqa: E402

sin = os.environ.get("SUMMARY_IN", os.path.join(HERE, "_cov_RESTORE_20260913.json"))
sout = os.environ.get("SUMMARY_OUT", os.path.join(HERE, "coverage_summary.json"))
S = json.load(open(sin))
print(f"summary in : {sin}  coverage_complete={S.get('coverage_complete')} "
      f"missing={S.get('missing_branches')} demand_sets={S.get('demand_sets')} "
      f"assumptions_used={S.get('assumptions_used')}")
cfgpath = os.path.join(HERE, "completion_config.json")
cfg = json.load(open(cfgpath))

# CHECKPOINT (owner rule, 2026-09-12). This stage is dominated by the
# assumption gate — ~29 min for posts_show's 184 probes, ~112 min for
# notifications' 5 075 — and it was all-or-nothing: a kill anywhere in
# `attach_to_summary` left SUMMARY_OUT untouched and the whole gate was
# re-run. ENGINE_CHECKPOINT=1 does two things, both opt-in and both inert
# when it is unset:
#   1. WHOLE-STAGE skip. A sidecar `<SUMMARY_OUT>.checkpoint_key` records the
#      digest of EVERY input this stage's verdict depends on (key v2,
#      2026-09-13 -- `_key_inputs()` and `_KEY_NOTE` below enumerate them;
#      v1 digested only SUMMARY_IN + completion_config and was blind to a
#      `shim_tests.rb` edit). If SUMMARY_OUT
#      exists with a completion section and the sidecar matches, the stage is
#      already done for these inputs and is not repeated. Any change to
#      ANY of them changes the digest, so a stale section is never kept.
#   2. PROBE-LEVEL resume INSIDE the gate. `ACHK_CHECKPOINT` is exported
#      (unless the caller already set it) so assumption_checker.py's
#      ProbeCache persists each JRuby replay as it lands; a killed gate then
#      resumes at the probe it died on instead of relaunching all of them.
#   3. CORPUS-INDEX resume (2026-09-12). Before a single probe is derived the
#      gate parses EVERY dump in the batch (`corpus_index`) -- ~50 min on
#      posts_show's 194 262 -- and it did that again on every relaunch.
#      `ACHK_INDEX_CHECKPOINT` records one row per dump, keyed on the corpus,
#      the declared set, the canonicalization and the engine's source, so the
#      second run replays the index instead of re-reading 36 GB of JSON, and
#      `ACHK_DERIVE_CHECKPOINT` records one row per confined DECISION (its
#      profile representatives and their flipped seeds) so the derivation
#      that follows the index resumes too.
#      `ACHK_HEARTBEAT_S` makes each pre-probe phase report itself (phase,
#      done/total, elapsed, RSS); the lines reach `_c1/_gate_engine.log`
#      through the gate wrapper's `tee`, since completion.py CAPTURES the
#      driver's stdout rather than streaming it.
CKPT = bool(os.environ.get("ENGINE_CHECKPOINT"))
_side = sout + ".checkpoint_key"


# ---------------------------------------------------------------- key, v2
# CHECKPOINT KEY v2 (2026-09-13). v1 digested only (SUMMARY_IN bytes,
# completion_config.json bytes). That is NOT every input this stage's verdict
# depends on: comments_index 2026-09-13 (§3 of `_RESTORED_20260913.md`) ported
# two shim tests into `shim_tests.rb`, a file v1's key cannot see, so the stage
# would have SKIPPED and replayed the stale `OVERALL_COMPLETE=False` section.
# RUNBOOK §4's rule is that a checkpoint is keyed on ALL of its inputs, so a
# stale checkpoint is never reused silently. v2 digests, in this order:
#   * SUMMARY_IN and completion_config.json (v1's two);
#   * every file the config NAMES: `shim_tests`, `concrete_run`,
#     `assumption_cfg` / `assumption_manifest`, plus the shim stage's own
#     `_shims_extracted.json`;
#   * every existing file NAMED by any command string in the config (each
#     command is shell-tokenized; a token is resolved against `workdir` when it
#     is relative, and kept when it is a regular file) — `extract_cmd` (shim_extractor.rb + this batch's
#     targets.rb and concolic_targets.rb), `test_cmd` (shim_test_runner.rb, the
#     slot wrapper), `note_check_cmd` (mock_note_check.py, concrete_aliases.json),
#     `assumption_cmd` (this batch's gate wrapper / _c11_gate_reuse.py), and each
#     `audit_cmds` / `extra_audit_cmds` entry, i.e. every AUDIT SCRIPT'S SOURCE;
#   * the assumption gate's batch-local side inputs, absent-tolerant:
#     `coverage_assumptions.py`, `_confinement_withdrawn.json`,
#     `_prior_footprints.json`;
#   * the ENGINE SOURCES that decide the verdict: `concolic_engine/completion.py`
#     and `end_to_end_completion_checker/assumption/assumption_checker.py`;
#   * the ENV KNOBS a caller changes the verdict with — `ACHK_*`, `CONCOLIC_*`,
#     `COMPLETION_*` (so `COMPLETION_AUDIT_TIMEOUT`) and `QFR_APP_CONFIG` — as
#     this process RECEIVED them (`_ENV0`, snapshotted before our setdefaults),
#     minus `_KEY_ENV_IGNORE`.
# A missing optional file digests as the literal "ABSENT": an optional input's
# ABSENCE is an input, not an error. The key is computed ONCE, BEFORE the stage
# runs, and that same key is written afterwards — an input touched mid-run
# therefore leaves a key that no longer matches and the next run redoes the
# stage rather than replaying a section computed from something else.
_KEY_ENV_PREFIXES = ("ACHK_", "CONCOLIC_", "COMPLETION_")
_KEY_ENV_EXTRA = ("QFR_APP_CONFIG",)
# NOT keyed: destinations and cadences. They move where a log or a resume cache
# is written, or how often a heartbeat prints; they cannot change a verdict, and
# keying them would invalidate the checkpoint every time a wrapper renames a log.
_KEY_ENV_IGNORE = {"ACHK_CHECKPOINT", "ACHK_INDEX_CHECKPOINT",
                   "ACHK_DERIVE_CHECKPOINT", "ACHK_RESULTS_JSONL",
                   "ACHK_HEARTBEAT_S", "ACHK_LABEL_TOKEN"}
_ENGINE_SRC = ("/home/dev/project/src/concolic_engine/completion.py",
               "/home/dev/project/src/end_to_end_completion_checker/assumption/"
               "assumption_checker.py")
_GATE_SIDE_INPUTS = ("coverage_assumptions.py", "_confinement_withdrawn.json",
                     "_prior_footprints.json")
_KEY_NOTE = (
    "# SIDECAR FORMAT v2 (2026-09-13) — the whole-stage checkpoint key of\n"
    "# _engine_section.py.\n"
    "# LINE 1 IS THE KEY and is the ONLY line read back: blake2b-128 over the\n"
    "# 'label\\0detail\\0digest' rows listed below, in exactly this order.\n"
    "# Every other line begins with '#' and is a human-readable RECORD of what\n"
    "# was digested; nothing below line 1 is ever re-parsed.\n"
    "#   file rows : digest = blake2b-128 of the bytes, or ABSENT if the file is\n"
    "#               not there (an optional input's absence IS an input).\n"
    "#   env rows  : the VALUE as this process received it.\n"
    "# The key is computed BEFORE the stage runs and written unchanged after, so\n"
    "# an input touched mid-run leaves a non-matching key and the next run redoes\n"
    "# the stage. Not keyed (destinations/cadence only): "
    + ", ".join(sorted(_KEY_ENV_IGNORE)) + ".\n")


def _cmd_tokens(cmd):
    """Every token of a shell command that could NAME a file: the token itself
    and, for `VAR=value` / `--flag=value`, the part after the first `=` (so
    `PYTHONPATH=…` and `--aliases=…` are seen). `{batch}` / `{shims}` / `{tests}`
    / `{out}` placeholders are skipped — the engine fills those in itself."""
    if not cmd:
        return []
    try:
        toks = shlex.split(cmd)
    except ValueError:                      # unbalanced quoting: fall back
        toks = cmd.split()
    out = []
    for t in toks:
        if "{" in t or "}" in t:
            continue
        out.append(t)
        if "=" in t:
            out.append(t.split("=", 1)[1])
    return out


def _fdigest(path):
    """blake2b-128 of a file's bytes (streamed), or "ABSENT" if it is missing."""
    try:
        h = hashlib.blake2b(digest_size=16)
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return "ABSENT"


def _key_inputs():
    """[(label, detail, digest)] — every input this stage's verdict depends on."""
    items = [("summary_in", sin, _fdigest(sin)),
             ("completion_config", cfgpath, _fdigest(cfgpath))]
    for k in ("shim_tests", "concrete_run", "assumption_cfg", "assumption_manifest"):
        p = cfg.get(k)
        if p:
            items.append((k, p, _fdigest(p)))
    shims = os.path.join(HERE, "_shims_extracted.json")
    items.append(("shims_extracted", shims, _fdigest(shims)))
    cmds = [cfg.get("extract_cmd"), cfg.get("test_cmd"),
            cfg.get("note_check_cmd"), cfg.get("assumption_cmd")]
    cmds += [a.get("cmd") for a in (list(cfg.get("audit_cmds") or [])
                                    + list(cfg.get("extra_audit_cmds") or []))]
    workdir = cfg.get("workdir") or "."
    seen = {p for _, p, _ in items}
    for c in cmds:
        for tok in _cmd_tokens(c):
            p = os.path.normpath(tok if os.path.isabs(tok)
                                 else os.path.join(workdir, tok))
            if p in seen or not os.path.isfile(p):
                continue
            seen.add(p)
            items.append(("cmd_file", p, _fdigest(p)))
    for name in _GATE_SIDE_INPUTS:                      # absent-tolerant
        p = os.path.join(HERE, name)
        items.append((name, p, _fdigest(p)))
    for p in _ENGINE_SRC:
        items.append(("engine_src", p, _fdigest(p)))
    for name in sorted(_ENV0):
        if name in _KEY_ENV_IGNORE:
            continue
        if name.startswith(_KEY_ENV_PREFIXES) or name in _KEY_ENV_EXTRA:
            items.append(("env", name, _ENV0[name]))
    return items


def _inputs_key(items=None):
    items = _key_inputs() if items is None else items
    h = hashlib.blake2b(digest_size=16)
    for label, detail, dig in items:
        h.update(f"{label}\0{detail}\0{dig}\n".encode())
    return h.hexdigest()


if CKPT:
    key_items = _key_inputs()
    key = _inputs_key(key_items)
    print("[checkpoint] key inputs: " + " ".join(
        f"{lb}:{os.path.basename(dt) or dt}="
        f"{dg if lb == 'env' else dg[:8]}" for lb, dt, dg in key_items)
        + f"  ({len(key_items)} inputs) -> key {key}", flush=True)
    os.environ.setdefault("ACHK_CHECKPOINT",
                          os.path.join(HERE, "_achk_probe_checkpoint.jsonl"))
    os.environ.setdefault("ACHK_INDEX_CHECKPOINT",
                          os.path.join(HERE, "_achk_index.ckpt.jsonl"))
    os.environ.setdefault("ACHK_DERIVE_CHECKPOINT",
                          os.path.join(HERE, "_achk_derive.ckpt.jsonl"))
    os.environ.setdefault("ACHK_HEARTBEAT_S", "60")
    print(f"[checkpoint] index log {os.environ['ACHK_INDEX_CHECKPOINT']}, "
          f"derive log {os.environ['ACHK_DERIVE_CHECKPOINT']}, "
          f"heartbeat {os.environ['ACHK_HEARTBEAT_S']}s", flush=True)
    print(f"[checkpoint] ON: inputs {key[:12]}, probe log "
          f"{os.environ['ACHK_CHECKPOINT']}", flush=True)
    done = False
    try:
        done = (os.path.exists(_side)
                and open(_side).read().split("\n", 1)[0].strip() == key
                and json.load(open(sout)).get("completion") is not None)
    except Exception as exc:  # noqa: BLE001 - a bad sidecar just means redo
        print(f"[checkpoint] sidecar unusable ({exc}); re-running the stage")
    if done:
        S = json.load(open(sout))
        print("[checkpoint] this stage is already done for these inputs "
              "(SUMMARY_OUT + matching key); replaying its section")
        attach_to_summary = None            # nothing to run

if attach_to_summary is not None:
    attach_to_summary(S, cfg)
    json.dump(S, open(sout, "w"), indent=2)
    if CKPT:
        tmp = _side + ".tmp"
        with open(tmp, "w") as fh:
            fh.write(key + "\n")          # the key computed BEFORE the stage ran
            fh.write(_KEY_NOTE)
            for _lb, _dt, _dg in key_items:
                fh.write(f"#   {_lb} {_dt} {_dg}\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, _side)
sec = S["completion"]
print(f"OVERALL_COMPLETE={S['complete']};COMPLETION={sec['complete']}")
for a in sec.get("audits", []) or []:
    print(f"  AUDIT {'green' if a['green'] else 'RED  '}    {a['name']}")
for v in sec.get("shims", []) or []:
    extra = v.get("detail") or (f"coverage {v.get('coverage_pct')}%" if "coverage_pct" in v else "")
    print(f"  {v['verdict']:<14} {v['key']:<52} {extra}")
if sec.get("note_check") is not None:
    print(f"  NOTE-CHECK     {'green' if sec['note_check']['green'] else 'RED'}")
if sec.get("assumptions") is not None:
    a = sec["assumptions"]
    print(f"  ASSUMPTIONS    {'green' if a['green'] else 'RED'}  {a}"[:400])
for b in sec.get("blocking", []) or []:
    print(f"  BLOCKING  {b}")
if S.get("confinement_withdrawn_by_gate"):
    print(f"  CONFINEMENT WITHDRAWN BY THE GATE: "
          f"{len(S['confinement_withdrawn_by_gate'])} pair(s) — the coverage "
          f"numbers above are STALE and a re-census is owed")
print("ENGINE SECTION DONE")
