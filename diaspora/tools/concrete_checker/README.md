# Concrete checker

Ground-truth capture against a REAL database (sqlite via the bundled JDBC
adapter), real controller dispatch, real templates — no concolic mocks, no
symbolic values. This is the adversary's instrument (see
`reports/diaspora/docs/CONCRETE_CHECKER.md` for the brief given to the
adversarial sub-agent) and, more generally, any process that needs to know
what the real app actually does rather than what a mock claims it does.

Moved here 2026-09-20 from `src/ruby_runtime/completion_checker/` — read
that directory's own `README.md` ("Moved out" section) for the full
reasoning. Short version: unlike `shim_extractor.rb`/`shim_test_runner.rb`
(wired into every batch's `completion_config.json` as the automated
completion gate's `extract_cmd`/`test_cmd`), these three files back a
separate, currently-manual workflow — invoked per adversary round by
hand-written harnesses (`reports/diaspora/results3/<endpoint>/adversary*/
_common*.rb`, `run*.sh`), not through one configured entrypoint. They were
already generic/parameterized when they lived in `src/` (a schema path, a
manifest of scenarios/probes — nothing diaspora-specific baked in), so this
move is about where specialized single-app-workflow tooling belongs, not
about diaspora-specific content that had to leave `src/`.

## Files

| File | Role |
|---|---|
| `concrete_env.rb` | `CompletionChecker::ConcreteEnv` — real sqlite3-via-JDBC fixture-environment setup (`setup!`, `insert`, `quote`). Documents the JDBC boolean-quoting gotcha (comments_index adversary, 2026-08-28: raw-INSERT fixtures must quote booleans the same way the adapter reads them, or `WHERE public = 't'` silently returns nothing). |
| `concrete_run_probe.rb` | The capture side. Resolves the deterministic target list straight from a batch's own corpus (`targets_from_corpus`, no hand-authored list), drives a `CONCRETE_SCENARIOS` manifest for real, and records target calls + coverage + SQL statements to `concrete_run.json`. Requires `src/ruby_runtime/completion_checker/target_call_probe.rb` (still in `src/` — genuinely core, required by every probe). |
| `mock_checker.rb` | The per-mock verification driver (T1 + M2 + C1-shape). Runs a batch's `MOCK_PROBES` manifest against the clean app. Reduced role since `mock_note_check.py` subsumed target-note checking — still used for shim-mock probes and coverage top-ups. |

## Known gap, and the plan to close it (src/TODO.txt)

Right now each adversary round hand-writes its own manifest
(`concrete_manifest_r3.rb` through `r6.rb` for comments_index alone) and its
own fixture setup, rebuilt from scratch each time rather than reusing one
canonical, centrally-produced "concrete environment" per endpoint. See
`src/TODO.txt`'s "ONE STACK FOR ALL COMPLETION TESTS" item for the plan to
fix this: a fixed `concrete_env`/`concrete_run` artifact pair produced once
per endpoint by the coordinating agent, consumed identically by (a) any
agent driving the endpoint (to know what ground truth to match) and (b) the
adversarial agent (to have one trusted, consistent real environment to
attack), wired through `mock_note_check.py` as a single entrypoint instead
of the current ad-hoc per-round harnesses.
