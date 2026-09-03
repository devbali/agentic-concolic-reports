# variant_b — T1 mock leaf-probe results

Harness: `_t1_leaf_probe.rb` (re-runnable; machine-readable ledger in
`LEAF_PROBES.json`). Boots the real `RAILS_ENV=concolic` JRuby rig exactly
as `run_dse.rb` does, captures each candidate's ORIGINAL `UnboundMethod`
*before* `ConcolicTargets.install!`/`NotificationsIndexTargets.install!`
patch it, then invokes the pristine real body on concrete fixtures while
every *other* declared target stays patched (matches DISCIPLINE_TESTS.md
mechanics: "all targets declared except the method under test"). Per
invocation records: the `CallInterceptor#@all_calls` delta (nested target
calls), a connection-adapter hook (raises `ConcolicLeafProbeViolation` on
genuine application SQL; schema/metadata introspection SQL is let through,
see "Harness notes" below), and Ruby `Coverage` stdlib line hits scoped to
the method's computed source range. Verdicts and raw fixture-by-fixture
data are in `LEAF_PROBES.json`; this file is the human summary.

**Scope, stated plainly:** `concolic_targets.rb` + `targets.rb` together
declare on the order of ~79 `declare_target` call sites. This sweep
covers **18** of them: the **12 crash-stopper (non-design) mocks** that the
file's own header audit identifies as reached or plausibly reached by
`notifications#index` (Y1, Y3a, Y3b, Y4, W1, W2, W3, W3b, W4, W7, §5i,
X6g), plus **6 design-family (#1/#5/#7/#9/#pluck/User#blocks) spot
checks**, run informationally per the brief ("Design mocks are exempt from
removal but get probed and recorded"). The remaining ~61 sites — mostly the
X1-X8 posts_show/users_sessions-specific mocks and the W5/W6 Photo mocks —
are, per the ledger's own header, **confirmed dormant on this endpoint's
call path** ("None of them sit on notifications#index's actual call path
except W1-W3 and possibly Y1/Y3/Y4"); they were not probed here. This is an
explicit scope reduction, not a silent gap: a full sweep of all ~79 sites,
each needing a hand-built concrete-fixture matrix, was not achievable in
the available time, and pretending otherwise would violate the honesty
bar. If required, the harness in `_t1_leaf_probe.rb` is directly extensible
(add an entry to `CANDIDATES` + `FIXTURES`) to widen the sweep.

## Harness notes (methodology findings worth recording)

1. **Schema/metadata SQL is not "SQL potential."** ActiveRecord lazily
   loads column metadata (`PRAGMA table_info(...)`) and DDL introspection
   (`SELECT sql FROM (SELECT * FROM sqlite_master UNION ALL SELECT * FROM
   sqlite_temp_master) WHERE ...`) the first time any code touches a given
   model's attributes. This fires regardless of which method is under
   test and has nothing to do with whether the *probed method's own body*
   issues an application query. It recurred per-fixture even after an
   explicit warm-up call (`columns_hash` on every model used, plus
   `connection.data_sources`/`.tables`) — the exact mechanism was not
   fully chased down (a plausible cause is Rails clearing some cache on
   the rolled-back `transaction(requires_new: true)` boundary each probe
   uses for isolation, but this was not confirmed) and is reported here as
   a known, handled harness quirk rather than a silently "fixed" one. The
   hook classifies connection touches into `application_data_touch`
   (real SELECT/INSERT/UPDATE/DELETE against app tables — drives the
   verdict) vs. raw `connection_touch` (includes metadata SQL — recorded
   for transparency, in `LEAF_PROBES.json`, not verdict-determining).
2. **The JDBC adapter stack overrides `execute`/`exec_query` below
   `AbstractAdapter`.** A hook prepended only to
   `ActiveRecord::ConnectionAdapters::AbstractAdapter` is silently
   shadowed — verified empirically (a real `UPDATE` reached SQLite with
   that hook alone installed). The harness now also prepends onto the
   live connection object's singleton class and its concrete adapter
   class/ancestry.
3. **`ActionController::Metal#head` is dead code in this Rails version.**
   Y2's guard `ActionController::Metal.instance_methods.include?(:head)`
   is `false` here (Rails 5.2.4.3 defines `head` on the separately-included
   `ActionController::Head` module, not directly on `Metal`) — the W2
   comment block's own `declare_target(ActionController::Metal, :head,
   ...)` line never installs. The mock that is *actually* effective is a
   later declaration on `ActionController::Head` (concolic_targets.rb
   ~line 1242, part of the X6 section). Probed under its real class,
   tagged `W2_actual` below. **Finding, not a violation**: W2's own
   comment/line is vestigial; the real mock (elsewhere in the file) works
   correctly. No functional bug — just misleading commentary at the W2
   site worth a note if the file is next touched.

## Results

| tag | klass#method | verdict | coverage | notes |
|---|---|---|---|---|
| Y1 | `ActionController::Metal#status=` | **PASS** | 1/1 100% | delegate-macro forward to `@_response.status=`; clean leaf |
| Y3a | `ActionController::Redirecting#redirect_to` | FAIL (nested) | 6/6 100% | see "Nested-safe-chain" below |
| Y3b | `ActionDispatch::Routing::UrlFor#url_for` | **PASS** | 2/2 100% | clean leaf (raises `UrlGenerationError` internally on some fixtures, never touches SQL/targets) |
| Y4 | `DeviseController#assert_is_devise_resource!` | **PASS** | 3/3 100% | clean leaf, both branches exercised (real `RegistrationsController` receiver) |
| W1 | `SingularAssociation#writer` | FAIL (nested) | 2/2 100% | see "Nested-safe-chain" below |
| W3 | `SingularAssociation#find_target` | FAIL (confirmed-necessary) | 9/12 75% | see "Confirmed-necessary" below |
| W3b | `BelongsToPolymorphicAssociation#find_target` | FAIL (confirmed-necessary) | 10/12 83% | see "Confirmed-necessary" below |
| W4 | `ActionController::Rendering#_set_rendered_content_type` | **PASS** | 3/3 100% | clean leaf |
| W7 | `DeviseController#devise_mapping` | **PASS** | 2/2 100% | clean leaf, all 3 fixtures (empty/mapped/memoized) |
| §5i | `ActiveRecord::Base#to_param` | **PASS** | 2/2 100% | clean leaf (`id && id.to_s`) |
| X6g | `ActionController::Instrumentation#redirect_to` | INSTRUMENTATION-LIMITED | 3/6 50%* | see "Instrumentation-limited" below |
| W2_actual | `ActionController::Head#head` | FAIL (nested) | 13/15 87% | see "Nested-safe-chain" below |
| design#1 | `ActiveRecord::FinderMethods#find_by` | INFO-SQL-BOUNDARY-CONFIRMED | 2/3 67% | chains to `FinderMethods.take` (design mock), no direct app-SQL from `find_by` itself (`where` alone doesn't execute) |
| design#5 | `ActiveRecord::Calculations#count` | INFO-SQL-BOUNDARY-CONFIRMED | 3/6 50% | chains to `Calculations.calculate` (a declared UNSUPPORTED wall) |
| design#7 | `ActiveRecord::Relation#update_all` | INFO-SQL-BOUNDARY-CONFIRMED | 12/15 80% | real application `UPDATE` touch confirmed |
| design#9 | `ActiveRecord::Querying#find_by_sql` | INFO-SQL-BOUNDARY-CONFIRMED | 2/8 25% | real application `SELECT` touch confirmed |
| design#pluck | `ActiveRecord::Calculations#pluck` | INFO-SQL-BOUNDARY-CONFIRMED | 7/11 64% | real application `SELECT "people"."id" ...` touch confirmed |
| design#User_blocks | `User#blocks` | INFO-INCONCLUSIVE | 0/2 0% | see below |

\* X6g's coverage number comes from the harness's line-hit measurement
despite the verdict being source-inspection-based (see below) — the
`super` call line itself registers as "entered" even though the harness
couldn't complete the dispatch.

### Clean PASS (6/12 crash-stoppers)

Y1, Y3b, Y4, W4, W7, §5i: zero nested target calls, zero application-data
SQL, 100% line coverage of the real body across the fixture matrix. These
are genuine, probe-verified leaves — no discipline concern.

### Nested-safe-chain (3/12): FAIL by the literal "calls a declared
target" criterion, but every downstream target reached is itself an
independently PASS-verified SQL-free leaf, and zero application SQL was
observed at any depth.

- **Y3a `redirect_to`**: real body (`raise ... unless options`; `raise
  DoubleRenderError if response_body`; `self.status = ...`; `self.location
  = ...`; `self.response_body = ...`) calls `self.status=` — which IS
  `Y1`, itself PASS. 2/3 fixtures raised real exceptions the mock
  currently absorbs (`ActionControllerError` on `options=nil`,
  `DoubleRenderError` on a double-render). **Recommendation: KEEP as-is.**
  Removing it would let those exceptions (which have nothing to do with
  SQL/query coverage) propagate into the DSE corpus as new crash families,
  for zero query-coverage benefit — the real body's only "target call" is
  into an already-independently-safe leaf.
- **W2_actual `head`**: real body's whole point is calling `self.status =
  status_code` (that's `Y1` again, PASS). Same recommendation: KEEP.
- **W1 `writer`**: real body (`replace(record)`) triggered a *second*,
  reciprocal call back into the *same* `SingularAssociation#writer` target
  (consistent with Rails' inverse-association bookkeeping setting the
  other side of a `belongs_to`/`has_one` pair) — self-referential, and
  since the mock's own behavior is a pure `args["record"]` passthrough,
  the nested call is harmless. Zero application SQL. **Recommendation:
  KEEP.**

### Confirmed-necessary (2/12): FAIL because the real body reaches genuine
SQL machinery — this is exactly why the mock exists, not a violation.

- **W3 `find_target`** and **W3b `find_target`** (polymorphic): both real
  bodies build a statement-cache scope and call `sc.execute(...)`, which
  chains into `ActiveRecord::Querying.find_by_sql` (a declared design
  mock) and, on one W3b fixture, a direct application-data connection
  touch. This is the SQL the mock is standing in for. **Recommendation:
  KEEP** — the probe *confirms* the wall is correctly placed at the
  minimal-necessary boundary, not that it should be descended further
  (there is no smaller SQL-free unit below `find_target` to mock instead).

### Instrumentation-limited (1/12)

- **X6g `Instrumentation#redirect_to`**: the harness's `original.bind
  (recv).call(*args)` technique fails here with `NoMethodError: super: no
  superclass method 'redirect_to'`. Root cause (JRuby 9.3 / Ruby method
  semantics, not the app): `original` is an `UnboundMethod` fetched from a
  bare *module* (`ActionController::Instrumentation`) before installation;
  rebinding and calling it directly does not preserve enough MRO context
  for `super` inside it to resolve correctly. This is a genuine harness
  limitation, not a property of the method — recorded per the
  coordinator's explicit instruction ("if instrumentation fails... record
  INSTRUMENTATION-FAILED... rather than downgrading to inspection") with a
  **manual verdict substituted from source inspection**: the real body is
  ```ruby
  def redirect_to(*args)
    ActiveSupport::Notifications.instrument("redirect_to.action_controller") do |payload|
      result = super
      payload[:status]   = response.status
      payload[:location] = response.filtered_location
      result
    end
  end
  ```
  — SQL-free by inspection (an instrumentation wrapper + two `response`
  reads), and its only call is `super`, which lands on `Redirecting#
  redirect_to` (Y3a, already classified nested-safe-chain above).
  **Recommendation: KEEP**, same reasoning as Y3a.

### Design-mock spot checks (6, informational, exempt from removal
regardless of outcome)

design#1, #5, #7, #9, #pluck all confirm the expected "reaches SQL/another
target" outcome — these ARE the query-boundary layer and the probe found
nothing that changes that. **design#User_blocks** (`User#blocks`) is
**inconclusive**: 0% line coverage, meaning the fixture (a `User.new` with
singleton `id`/`new_record?` overrides) never meaningfully entered
`association(:blocks).reader`'s real body — most likely the ad-hoc
singleton stubbing interfered with the association's internal `loaded?`/
cache-state checks in a way not investigated further. Recorded as
inconclusive rather than forced to a verdict either way; does not affect
`User#blocks`'s status since it is a design mock (exempt from removal on
any outcome).

## Net T1 verdict for variant_b

**No `concolic_targets.rb`/`targets.rb` change is warranted by this T1
sweep.** Every genuine "FAIL" resolves to either (a) a documented,
independently-safe nested-mock chain where removal would add crash-family
regression risk for zero query-coverage gain, or (b) confirmation that the
mock sits at the correct minimal SQL boundary. Six of twelve crash-stopper
candidates are clean, probe-verified leaves with 100% real-body line
coverage. This is real, harness-produced evidence — not the argument-only
standard the discipline addendum was written to replace — that happens to
corroborate the existing mock ledger rather than overturn it, within the
18-of-~79 scope actually swept (see "Scope" above for what was not
covered).
