# tags_index — batch-1 (local_tags1), first drive of this endpoint

## Summary

The corpus covers every branch, but it says almost nothing about what the endpoint does.
`TagsController#index` has exactly one recorded path condition,
`(Length(SYM_PARAM_q) > 1)` at `app/controllers/tags_controller.rb:18`, and
both sides of it are in the corpus:

| dump | seeds | side | outcome |
|---|---|---|---|
| `dump_anon_json_dse0001.json` | (default, `q="alice"`) | taken | terminal `NotImplementedError: SymbolicString#gsub! is not supported in the concolic runtime` raised at `src_new/runtimes/ruby_runtime/string.rb:391`, reached from `tags_controller.rb:19` |
| `dump_anon_json_dse0002.json` | `SYM_PARAM_q="g"` | not taken | `head :unprocessable_entity`; target calls `ActionController::Rendering#_set_rendered_content_type` and `ActionController::Head#head` (both declared shims, neither an access). No SQL. |

The explorer ran in this box at `MAX_RUNS=24 TIME_BUDGET=300`, through
`reports/autolab/entrypoints/scaffold/tags_index/launch.sh` with
`DUMP_OUT=<box>/batch/explore1`, inside a 10G `systemd-run` scope. It ran once.
`runs executed 3`, `distinct paths 2` (run 3 repeated a path, so no dump was written), `worklist empty true`,
`stack_remaining 0`, `unflippable 0`, `run errors {}`, and
`terminals {"NotImplementedError"=>2}`. The runner printed `no target override for tags_index
(tier=candidate) — running on core targets only`.

## The wall: the interesting side of the branch cannot run

The true side contains the whole endpoint: the tag query, the limit
arithmetic and the JSON render. It stops on the very next line at a
declared runtime non-goal. Four more declared non-goals stand behind it, so
lifting `gsub!` alone would only move the wall:

| line | expression | refused by |
|---|---|---|
| controller:19 | `params[:q].gsub!("#","")` | `SymbolicString#gsub!` (mutation; `SymbolicString::UNSUPPORTED`) |
| controller:20 | `params[:limit].to_i` | `SymbolicString#to_i` (numeric coercion) |
| controller:21 | `params[:limit] - 1` | `SymbolicInt` arithmetic |
| `acts_as_taggable_on-tag.rb:12` | `name.downcase` in `Tag.autocomplete` | `SymbolicString#downcase` |
| controller:70 | `"#" + tag.name`, `@tags << …`, `@tags.uniq!` | `SymbolicString#+` (concat); list mutation |

I did not try to get past the wall. In particular I did not make `q` concrete, did not seed
`q` to skip the branch, and edited nothing in `src_new/` or the app. The terminal is
recorded in the corpus as an outcome. It is not a coverage assumption, so it is not
declared as one.

## Empty note set

The real endpoint issues one statement,
`SELECT tags.* FROM tags WHERE (name LIKE ?) ORDER BY name ASC LIMIT ?`.
The corpus records **no note for it**. `statement_note_lint` sees 2 dumps and
reports the only 2 target calls as JUNK, with the exit status
"no red-level note findings". This follows directly from the wall. I did not invent
a note, and I did not produce a `concrete_run.json`: the fixtures and real-mode plan
are owned by the coordinator. I expect the domain's static-half `shape_check` to find
this gap, and it is a real finding.

## Audits (run in this box over `batch/`, the config's six)

All six exited 0. `statement_note_lint` reported 0 clean notes and 2 JUNK target
calls (the shims above). `noteless_call_audit` passed: both note-less calls are declared shims.
`exception_note_audit` passed, with 0 notes capturing an exception.
`empty_relation_emission_audit` passed, with 0 empty-list states.
`identity_symbolicity_audit` passed. `cardinality_consistency_audit` passed
**VACUOUSLY**. In its own words: "Absence of the subject is not evidence
about it; do not count this as a check that passed."

## Coverage and assumptions

The coordinator measured the engine's coverage layer on this endpoint's default corpus
(`coverage_complete true`, `tree_complete true`, `missing_branches 0`,
`solver_lost 0`), and this box reproduced that corpus (same 2 paths, worklist
exhausted). I did not re-run the full `python -m concolic.check` here. Because the tree is complete
and the worklist is exhausted, there is nothing to be licensed not to explore, so
`assumptions.json` is `[]` (the validator printed `ok`).

The coordinator also recorded this line:
`Failed to eval var decl 'Length(SYM_PARAM_q) = Int('Length(SYM_PARAM_q)')'`.
The only symbolic variable is a derived length variable whose name contains
parentheses, so the generated Python declaration does not parse. That was not fatal here, because
coverage resolves by path signature with no solver query lost. I recorded it and did not repair it.

## assumption_manifest.json

`batch_dir` is `in/packet/dumps`, relative to the check box root. `runner` is the
absolute `launch.sh` for this endpoint, which exists at the same path on every box built from
this image. The manifest has **no `workdir` key**, as the config's `_note_no_workdir` requires.
`env` sets `DUMP_OUT=/tmp` so a replay never writes into the shared scaffold
directory, and clears `JAVA_TOOL_OPTIONS`. `assumptions` is `[]`; in derived mode that key is not read.

## shim_tests.rb

The file is carried over with its bodies unchanged from
`local_cvd4/boxes/conversation_visibilities_destroy-batch-1-bb942577/out/packet/shim_tests.rb`
(which was itself carried from `posts_destroy`), and only the provenance header was rewritten. I
re-extracted the key set in this box. The extractor printed 22 keys, the same 22 as the earlier packets.
11 of them are `rep_plumbing` keys that the runner classes as PROTOCOL, so they have no entry, as
documented in the file header. The other 11 have bodies. Running the extractor needed
`LANG=C.UTF-8` in my shell: under a US-ASCII locale, `shim_extractor.rb:35`
raises `invalid byte sequence in US-ASCII`. The gate's environment may need the
same setting. The verdicts from running the tests in this box are below.

**Shim verdicts in this box** (run twice, `shim_test_runner.rb` through
`scripts/diaspora-concolic` with `JRUBY_OPTS=--debug`, the second run on the
exact file in this packet): **10 PASS, 12 PROTOCOL, 0 FAIL/ERROR/NO-TEST**.
PROTOCOL covers the 11 rep-plumbing keys plus `obj.post_location`: its entry
names `real_class: "Post"`, and `Post` defines no `post_location`. That is
documented in the file at lines 246-254.

## Escalations

None filed. I hit no boundary I needed to cross: the wall is the finding.
