# completion_checker — Ruby-runtime in-process probes

The runtime-coupled half of the check suite specified in
`reports/diaspora/docs/CHECKS.md`. These three probes must run
INSIDE the target app's process (JRuby), which is why they are Ruby.
Everything language-agnostic — the corpus/fold auditors (F1-F5) and the
C1 differ — lives in **`src/end_to_end_completion_checker/`** (Python;
the dump schema is shared by both runtimes, so those auditors serve
py_runtime corpora unchanged).

Zero coupling holds: nothing here requires any other `src/` module. No
reference policy is assumed anywhere.

## THE MOCK CHECKER (main driver)

```
JRUBY_OPTS=--debug scripts/diaspora-concolic \
  /abs/src/ruby_runtime/completion_checker/mock_checker.rb \
  /abs/<batch>/mock_manifest.rb
```
One manifest entry per mock in the batch's ledger: `kind: :shim`
(fixture block → zero target-function invocations + 100% executable-line
coverage of the real body) or `kind: :target_note` (real relation SQL vs
the mock's note, normalized shape equality). Writes
`mock_checker_report.json`; exit-code gated. Smoke: 2/2 on
notifications_index probes.

## The probes (require inside an app-boot script; mock_checker uses these)

```ruby
require_relative "path/to/completion_checker/target_call_probe" # T1 — the shim-mock contract
targets = [[ActiveRecord::FinderMethods, :find_by], ...]  # what the batch declare_target'ed
CompletionChecker::TargetCallProbe.assert_shim_mock!(targets: targets) { <real body, shim mock off> }
# capture form returns the hit list; raise_on_call: true fails fast when
# letting the target proceed would crash (e.g. no DB behind it)

require_relative "path/to/completion_checker/statement_log"   # C1 capture (+ T1's SQL-family belt)
real = CompletionChecker::StatementLog.capture { <run real code> }
CompletionChecker::StatementLog.capture_to("real_stmts.json") { ... }
# feed real_stmts.json to end_to_end_completion_checker/statement_diff.py

require_relative "path/to/completion_checker/coverage_probe"  # C2 capture (JRuby: run with --debug)
CompletionChecker::CoverageProbe.capture_to("real_cov.json", filter: %r{app/}) { ... }
```

T1 is about **target functions, not SQL**: a shim mock must reach zero
target functions — targets are where the runtime mints evidence, so a
shim mock over a target-reaching body swallows evidence by construction.
A **target mock** (the mock OF a target function) has the opposite
obligation: it must produce evidence matching the real target function
(C1-shape / T1b — checked by end_to_end_completion_checker's
`statement_diff.py`). `StatementLog.capture { probe }.empty?` is T1's
supplementary belt for the SQL target family where a DB is wired.
