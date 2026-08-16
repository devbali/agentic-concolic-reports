# users_sessions batch — concolic re-run (prefix-directed DSE + batch-local targets)

Batch 10: the `users` / `sessions` / `registrations` / `invitations`
controllers, driven through Rails' own `ActionController::TestCase` rig against
the real app. Regenerated 2026-08-15 with `run_dse.rb` + `targets.rb`;
`registrations_create` re-run 2026-08-16 (see below).

- Runner: `run_dse.rb` (prefix-directed DSE, seed inheritance + single-branch flip)
- Overlay: `targets.rb` (`UsersSessionsTargets.install!` + `.decorate_user!`),
  loaded AFTER `ConcolicTargets.install!`
- `src/` untouched, shared `concolic_targets.rb` untouched, app source untouched
- 63 dumps / 249 executions for the whole batch; every dump parses
  (7.8 s for the 19 in-process entrypoints, plus one 23 s isolated boot for
  `registrations_create`)

> **Provenance and status.** This batch's agent was **killed mid-flight** at
> 01:12 on 2026-08-15 by the coordinator session's provider failure (the pinned
> `~deepseek/deepseek-v4-flash-latest` gateway went away), so it never wrote
> this report. It is reconstructed from the artefacts it did leave — a fully
> documented `targets.rb`/`run_dse.rb` and complete per-entrypoint summaries —
> plus a fresh re-measurement of every dump
> (`reports/diaspora/batch_stats.py users_sessions`).
>
> **Update 2026-08-15 (later):** `registrations_create` — the one entrypoint
> this report originally recorded as unfinished — has since been **diagnosed and
> closed**. It now drains with 0 missing branches. The batch is **20/20
> complete**. See "registrations_create — CLOSED" below; the original
> capped-and-contained account is kept there because the diagnosis came out of
> it.

## Results

| entrypoint | dumps | PCs | nodes | missing | complete | genuine | **both sides seen** | clean | runs | drained |
|---|---|---|---|---|---|---|---|---|---|---|
| `users_getting_started` | 16 | 104 | 24 | 0 | true | genuine | 4 / 5 | 16 / 16 | 38 | yes |
| `sessions_create` | 5 | 14 | 4 | 0 | true | genuine | 4 / 4 | 5 / 5 | 15 | yes |
| `users_auth_token` | 4 | 9 | 3 | 0 | true | genuine | 3 / 3 | 4 / 4 | 10 | yes |
| `users_public` | 3 | 6 | 3 | 0 | true | genuine | 2 / 3 | 3 / 3 | 6 | yes |
| `sessions_destroy` | 3 | 5 | 2 | 0 | true | genuine | 2 / 2 | 3 / 3 | 6 | yes |
| `users_confirm_email` | 3 | 5 | 2 | 0 | true | genuine | 2 / 2 | 3 / 3 | 6 | yes |
| `users_update` | 2 | 2 | 1 | 0 | true | genuine | 1 / 1 | 2 / 2 | 3 | yes |
| `users_update_privacy_settings` | 2 | 2 | 1 | 0 | true | genuine | 1 / 1 | 2 / 2 | 3 | yes |
| `users_destroy` | 2 | 2 | 1 | 0 | true | genuine | 1 / 1 | 2 / 2 | 3 | yes |
| `invitations_new` | 2 | 2 | 1 | 0 | true | genuine | 1 / 1 | 2 / 2 | 3 | yes |
| **`registrations_create`** | **12** | **47** | **11** | **0** | **true** | genuine | **4 / 4** | 3 / 12 | **147** | **yes** |
| `invitations_create` | 1 | 0 | 0 | 0 | true* | VACUOUS | — | 1 / 1 | 1 | yes |
| `registrations_new` | 1 | 0 | 0 | 0 | true* | VACUOUS | — | 1 / 1 | 1 | yes |
| `sessions_new` | 1 | 0 | 0 | 0 | true* | VACUOUS | — | 1 / 1 | 1 | yes |
| `users_edit` | 1 | 0 | 0 | 0 | true* | VACUOUS | — | 1 / 1 | 1 | yes |
| `users_privacy_settings` | 1 | 0 | 0 | 0 | true* | VACUOUS | — | 1 / 1 | 1 | yes |
| `users_export` | 1 | 0 | 0 | 0 | true* | VACUOUS | — | 1 / 1 | 1 | yes |
| `users_export_photos` | 1 | 0 | 0 | 0 | true* | VACUOUS | — | 1 / 1 | 1 | yes |
| `users_download_profile` | 1 | 0 | 0 | 0 | true* | VACUOUS | — | 1 / 1 | 1 | yes |
| `users_getting_started_completed` | 1 | 0 | 0 | 0 | true* | VACUOUS | — | 1 / 1 | 1 | yes |
| **total** | **63** | **198** | **53** | **0** | **20 / 20** | **11 genuine, 9 vacuous** | **26 / 28** | **54 / 63** | **249** | **20 / 20** |

`*` complete only because the tree is empty.

**Headline: 14 of 20 entrypoints were VACUOUS before this round; 9 are now.**
Five entrypoints acquired their first recorded branch, and `users_getting_started`
went from a handful of PCs to 104 across 16 distinct paths.

### `complete=true` is the weakest number in that table

Per `COMPLETENESS_AUDIT.md`, `missing=0` is returned identically whether the
other side was *proved unreachable* or the solver *could not parse the
constraint*. Use the conjunction instead: **worklist drained for all 20**,
`unflippable_pcs` empty for all 20, and both sides observed for **26 of 28**
branch expressions. The two that are not are provably unreachable, not gaps —
enumerated at the end.

## The central technique: boundary-decided booleans

14 of 20 entrypoints were vacuous, and the dominant cause was **not a wall** but
the Ruby truthiness gap (`src/TODO.txt`):

```ruby
if current_user.confirm_email(params[:token])
if current_user.update_attributes(...)
if @user.sign_up
```

Every one of these mocks returned a value that is **truthy in Ruby no matter
what it wraps** — either a literal `true` (`concolic_targets.rb:508`, `:1191`)
or a `SymbolicBool`, which is a non-nil object and therefore truthy even when it
wraps `false`. So the app always took the success branch and recorded no path
condition. **Making the value merely seedable is not enough**: DSE emits the
flip, the mock honours it, and the app still goes left.

`to_symbolic` (`symbolic_func.rb:149-155`) documents the way out, and the shared
file already uses it for boolean column readers (`concolic_targets.rb:237-241`,
`post.public?`):

> "nil means 'absent' — pass through unchanged. Absence must be decided (and
> PC-recorded) AT THE MOCK BOUNDARY, never silently converted into a symbolic
> value."

So `flag` (`targets.rb:59`) records the path condition on a seedable
`SymbolicBool` inside the mock and then returns a value whose **Ruby
truthiness** matches the decision: `true` (re-wrapped by the interceptor into a
truthy SymbolicBool) or `nil` (passed through unchanged, falsy). The branch is
recorded once, at the boundary, and the app then really diverges.
`src/TODO.txt` sanctions exactly this.

**The honesty rule that constrains it:** `flag` is used ONLY on methods whose
callers in this batch actually branch on the result. A `flag` on a method whose
return value is discarded would **manufacture a phantom branch** — two paths
through code that has no `if`. That is why `save` is deliberately not converted
(§7).

## `targets.rb` — section by section

| § | target | shape | why legal / why refused |
|---|---|---|---|
| 0 | per-instance fixes for the symbolic `current_user` | `module_function` the runner calls | `symbolic_instance` installs **singleton** column readers (`concolic_targets.rb:229`) which beat any `define_method` or prepend — a `declare_target` on `User#language` could never fire |
| 1 | `User#valid_password?` | boundary-decided `flag` | caller branches on it (`sessions#create`) |
| 2 | `ActiveRecord::Base#update_attributes` | boundary-decided `flag` | caller branches on it |
| 3 | `User#confirm_email` | boundary-decided `flag` | caller branches on it |
| 4 | `User#sign_up` | boundary-decided `flag` | the `registrations#create` fork |
| 5 | schema gap: `unconfirmed_email` / `confirm_email_token` | column stubs | columns absent from the concolic SQLite schema |
| 6 | `User.authentication_token` (class method) | hard integer bound | **the JVM-OOM guard** — see below |
| 7 | `ActiveRecord::Base#save` | **deliberately NOT converted** | its result is discarded at every call site a flag would touch — see below |
| 8 | `DeviseController#devise_mapping` | the REAL Devise mapping | plumbing, records nothing |
| 9 | `User#blocks` | real `Relation` | was runner-local, moved here |
| 10 | NullRelation short-circuit | adopted verbatim from `photos` §4 | `.none` issues no SQL and has no target beneath it |
| 11 | asset-path stub | adopted verbatim from `photos` §5 | Sprockets environment wall |
| 12 | `TolerantSymbolicString < SymbolicString` | batch-local subclass | `check_string_operand!` (`string.rb:384`) raises on a non-String `==`/`!=` operand, which i18n's `enforce_available_locales!` triggers |
| 13 | `ConcolicDate` | batch-local subclass (`photos` §6a) | date/datetime typed-column gap |
| 14 | crypto leaf stubs for `registrations#create` | **NOT ADDED** — built, measured, removed | see below; the leaf they were guessing at was the wrong one |
| 15 | `DiasporaFederation::Discovery::Discovery#fetch_and_save` → `nil` | ported verbatim from `search_links_reports_profiles` §2 | **closes the JVM abort.** Body is `validate_diaspora_id` + a callback trigger — no SQL, no other declared target beneath it — and `find_or_fetch_by_identifier` re-runs the real `find_by(diaspora_handle:)` afterwards, so the branch survives |

### §6 — the bug that killed a whole batch process

`user/authentication_token.rb:20-24`:

```ruby
loop do
  token = Devise.friendly_token(30)
  break token unless User.exists?(authentication_token: token)
end
```

`FinderMethods#exists?` is a declared target returning a `SymbolicBool`, which
is **always truthy**, so `break … unless` never fires and the loop spins
forever allocating tokens until the JVM dies. Measured: 343 s, then
`java.lang.OutOfMemoryError`.

The guard is a **hard integer bound** (`max_probes = 2`), not a symbolic one —
termination does not depend on any symbolic value, so it cannot regress. The
probe stays **real**: `User.exists?` still runs through the declared target, so
the uniqueness SELECT is still issued and recorded, and its result is
boundary-decided so the retry branch is flippable. The previous runner-local
guard no-op'd `reset_authentication_token!` wholesale, which hid that SELECT
entirely; guarding the *generator* instead lets `reset_authentication_token!`
run for real, and `ensure_authentication_token!` is untouched — that is where
`users#auth_token`'s flippable `authentication_token.blank?` PC comes from.

**Honest under-approximation:** the real loop retries unboundedly. Seeding
"token collides" twice returns the colliding token instead of looping, so the
>2-collision path is not modelled. Forced by the truthiness gap.

### §7 — why `save` is refused

Converting `save` to a `flag` would be the single biggest raw-PC win available.
It is refused on purpose: in this batch `save`'s result is **discarded at every
call site** a flag would touch —

| site | call | result |
|---|---|---|
| `users#getting_started_completed` | `user.save` | ignored |
| `users#export` / `#export_photos` | `queue_export` → `update` | ignored |
| `reset_authentication_token!` | `save(validate: false)` | ignored |

Recording a PC there manufactures a phantom branch: two "paths" through code
containing no `if`, inflating PCs and nodes while covering nothing. The one real
`save` branch in this batch (`users#change_email`'s `if @user.save`) is
unreachable with this entrypoint's params — `user_data[:language]` wins the
`update_user` elsif chain first.

**Consequence reported instead of hidden:** `users_getting_started_completed`
and the discarded-`save` sites stay at 0 PCs, and they are 0-PC **because the
action has no conditional**, not because a wall blocks them.

## `registrations_create` — CLOSED

**Final state: 12 dumps, 47 PCs, 11 nodes, 0 missing, `complete=true`, 4/4
branch expressions two-sided, worklist drained in 147 executions across a single
process with zero crashes.** Was: 1 dump, 3 PCs, 5 blocking missing, capped at
one execution.

Three things got it there, in order.

### 1. Crash-isolated DSE moved the worklist out of the process

The abort is a native SIGSEGV, so `rescue Exception` cannot catch it and the
in-process worklist dies with the JVM — which is why the entrypoint had to be
capped. `run_registrations_isolated.rb` keeps the entire DSE state (stack,
seen-seeds, seen-paths, counters) in `state.json` and **fsyncs it after every
single execution**, writing the seed about to run to `current_seed.json` first.
`drive_registrations.py` supervises: when the child dies it reads
`current_seed.json`, marks **that one seed** poisoned with its exit signal and
log, and restarts. The search continues past a crash instead of stopping at it.

Rails boots in **11.5 s**, so a restart is cheap; a clean batch costs one boot,
not one per execution.

Run against the un-mocked app it drained in **5 boots / 13 executions**, and
produced the diagnosis the previous round could not get: **all four poisoned
seed sets share exactly one assignment**

```
SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found = true
```

### 2. That pointed straight at a wall another batch had already closed

`find_by_1` is `Person.by_account_identifier` (`person.rb:331`,
`find_by(diaspora_handle:)`), reached from `User#send_welcome_message` →
`share_with`. Its caller is `Person.find_or_fetch_by_identifier`, whose
not-found arm is `person.rb:325`:

```ruby
DiasporaFederation::Discovery::Discovery.new(diaspora_id).fetch_and_save
by_account_identifier(diaspora_id)
```

— a **real webfinger over HttpClient → libcurl → JRuby FFI**. That is the same
native path `search_links_reports_profiles` hit on `links#resolve`, with the
same signature: SIGSEGV outside the JVM, jffi frames,
`munmap_chunk(): invalid pointer`; the crash report here carries
`org.jruby.ext.ffi.AutoPointer` locals and `RIP=0x32`.

**It was never a crypto leaf** — which is exactly why §14's two crypto mocks
(`OpenSSL::PKey::RSA.generate`, `Devise::Encryptor.digest`) measured no effect,
and why "a real query reaching the FFI sqlite driver" was the wrong suspect.

§15 ports that batch's proven §2 mock verbatim: `Discovery#fetch_and_save → nil`.
Legality is unchanged from theirs — the body is `validate_diaspora_id` plus a
`save_person_after_webfinger` callback trigger, no SQL of its own and no other
declared target beneath it — and, decisively, `find_or_fetch_by_identifier`
calls `by_account_identifier` **again** afterwards, so the real
`find_by(diaspora_handle:)` query and its seedable `_not_found` var **survive
the mock**. The branch is preserved; only the network is removed.

With §15 in place: **one boot, 63 executions, 5 distinct paths, 0 poisoned
seeds, worklist drained.** Exploration also got deeper — a new decision
(`find_by_2`) appeared that the crash had been hiding.

### 3. Going deeper exposed the batch's last framework wall

Reaching that new code hit `NotImplementedError: SymbolicString#=~` — ActiveModel's
format validator (`validations/format.rb:9`) doing `value.to_s !~ regexp` on
`unconfirmed_email` (§5). Worth noting in its own right: **closing one wall
exposes the next**, and a wall count going up mid-fix is progress, not
regression.

There is no app method to mock here — the caller is framework code, so the
README's "smallest SQL-free enclosing unit" rule has nothing to bite on. Fixed
by **§12b**, which adds regex predicates to `TolerantSymbolicString`, ported from
`services_admin/targets.rb` §2b (the same port photos took as its §6d). A regex
match is not expressible in the `(VAR op LITERAL)` PC grammar, so the predicate
becomes a fresh seedable boolean recorded at the predicate boundary — the
sanctioned boundary-decided pattern — with the soundness caveat stated in the
code: the boolean is independent of the string's value, its default is the true
concrete answer, so an unflipped run is exact and a flipped one explores a path
some string could take though that dump's witness does not satisfy the regex.

**Result: 5 → 12 distinct paths, 14 → 47 PCs, 4 → 11 nodes, still drained in one
boot with zero crashes, and zero framework walls left in the batch.**

The 3 remaining error dumps are real app outcomes (`Module::DelegationError`),
not walls.

### The original account (kept — the diagnosis came out of it)

It was capped by design rather than by accident.

Once §12's `downcase`/`strip` tolerance let `registrations#create` past its
`SymbolicString#downcase` wall, its **second** DSE path started **aborting the
whole JVM**:

```
SIGSEGV ... The crash happened outside the Java Virtual Machine in native code
  com.kenai.jffi.Foreign.getZeroTerminatedByteArray
  org.jruby.ext.ffi.jffi.FFIUtil.getString(Ruby, long)
```

— an FFI binding reading a C string back from a native pointer. Because it is
outside the JVM it cannot be rescued.

Two candidate leaves were mocked and **measured**, and neither prevented the
abort, so both were removed rather than left in as decoration:

- `OpenSSL::PKey::RSA.generate` (`User#setup` → `generate_keys`, 4096-bit)
- `Devise::Encryptor.digest` (bcrypt is FFI-based on JRuby)

The remaining suspect is a real query reaching the FFI SQLite driver with a
`SymbolicString` bind value, which no batch-local mock can fix without
suppressing the query itself.

> **That suspect was wrong.** It is `Discovery#fetch_and_save` webfingering over
> libcurl, not the SQLite driver — see "CLOSED" above. Guessing at the leaf was
> the mistake; isolating the crash and letting it name its own seed was what
> settled it.

**Contained instead:** `run_dse.rb` sets `RUNS_CAP = {"registrations_create" => 1}`
and explores it **last**, so its first path (clean, 3 genuine PCs) is kept and
the batch process survives. The consequence is reported, never hidden:

```
worklist_exhausted: false        stop_reason: "max_runs"
coverage_complete: false         missing_branches: 5 (all blocking)
```

Its 5 missing branches, with Z3's suggested seeds:

| node constraint | missing side | suggested values |
|---|---|---|
| `(SYM_USER_unconfirmed_email == '')` | not_taken | `unconfirmed_email = "A"` |
| `(SYM_RESULT_User_sign_up_1_ok == True)` | not_taken | `sign_up_ok = false` |
| `(SYM_RESULT_User_sign_up_1_ok == True)` | taken | `unconfirmed_email = "A"` |
| `(..._find_by_1_not_found == True)` | taken | `sign_up_ok = true`, `not_found = true` |
| `(..._find_by_1_not_found == True)` | taken | `sign_up_ok = false`, `not_found = true` |

The one dump on disk carries a `Module::DelegationError` — the batch's only
error dump. Note `targets.rb` §14's prose says "3 missing branches"; the
checker's own summary says **5** (`blocking_missing_branches: 5`). The measured
figure is 5; the comment predates the final run.

~~**To finish it**, the FFI SIGSEGV has to be diagnosed at the driver boundary —
that is infrastructure work (a non-FFI SQLite driver, or a MySQL/Postgres-backed
`concolic` database), not something `targets.rb` can reach.~~ **Wrong on both
counts:** it was diagnosable without touching infrastructure, and `targets.rb`
§15 is exactly what reached it.

## One-sided branch expressions (solver-independent)

Down to **2**, and both are provably unreachable rather than gaps — the three
`registrations_create` entries are gone.

| entrypoint | expression | site | reading |
|---|---|---|---|
| `users_getting_started` | `(assoc_person_id == assoc_person_id)` | `active_record/core.rb:425` | a **tautology** — AR comparing an id to itself; the false side is UNSAT by construction |
| `users_public` | `(assoc_person_guid != StringVal(''))` | `journey/formatter.rb:41` | route-generation guard recorded only under a `guid == ''` prefix — UNSAT by construction, same shape as `people_stream` in `COMPLETENESS_AUDIT.md` |

## Three README entrypoints do not exist in this app revision

`results/users_sessions/` has empty directories for these; they are **absent
routes**, not failures:

| entrypoint | why |
|---|---|
| `users_token` | No `users#token` action and no `/users/token` route (`config/routes.rb`, `app/controllers/users_controller.rb`) |
| `users_remove_avatar` | No `users#remove_avatar` action and no matching route (`grep -rn remove_avatar app/ config/` = 0 hits) |
| `invitations_edit` | `InvitationsController` defines only `#new` and `#create`; there is no `/users/invitation/accept` route (routes.rb has `users/invitations` GET→new, POST→create). `invitations_new` is covered instead |

So the batch is **20 entrypoints, not the 22 named in the README table** (which
lists routes this revision does not have). The README's batch-10 row should be
corrected.

## `src/` gaps to raise to Bali (worked around batch-locally, NOT patched)

1. **Ruby truthiness gap** (`src/TODO.txt`) — the single largest cause of
   vacuous entrypoints experiment-wide, and the reason boundary-decided
   booleans have to exist at all.
2. Literal-`true` persistence mocks (`concolic_targets.rb:508`, `:1191`) with no
   `seed_for` — unflippable by construction.
3. `symbolic_instance`'s `define_singleton_method` column readers cannot be
   overridden by any `declare_target` or prepend.
4. `SymbolicString#check_string_operand!` (`string.rb:384`) raises on any
   non-String `==`/`!=` operand, which ordinary framework code (i18n) triggers.
5. `SymbolicString` has no `#downcase`/`#strip` and no date semantics.
6. `FinderMethods#exists?` returning an always-truthy `SymbolicBool` can turn an
   app retry loop into an infinite one (§6) — a liveness hazard, not just a
   coverage one.
7. Engine: `len(X)` constraints unparseable; `coverage.py` treats them as UNSAT
   while leaving `solver_lost` at 0.

## Files

```
results/users_sessions/
├── targets.rb                      BATCH-LOCAL overlay (UsersSessionsTargets)
├── run_dse.rb                      runner (RUNS_CAP, ABSENT, flip machinery)
├── run_registrations_isolated.rb   crash-isolated DSE: durable on-disk worklist,
│                                   one execution at a time (loads run_dse.rb's
│                                   helper prefix verbatim — cannot drift)
├── drive_registrations.py          supervisor: restarts after each abort and
│                                   attributes it to the in-flight seed set
├── coverage_report.py              per-entrypoint checker
├── run_concolic.rb                 previous-round runner, kept as input
├── batch_exploration_summary.json  batch-level roll-up
├── batch_coverage_summary.json     batch-level roll-up
├── elapsed_seconds.txt
└── <entrypoint>/
    ├── dump_*.json                 one per DISTINCT path
    ├── exploration_summary.json
    └── coverage_summary.json       this entrypoint's runs ONLY
```

Reproduce:

```
# the 19 in-process entrypoints
scripts/diaspora-concolic /home/dev/project/reports/diaspora/results/users_sessions/run_dse.rb

# registrations_create — crash-isolated, one execution at a time
cd /home/dev/project && OUT_DIR=reports/diaspora/results/users_sessions/registrations_create \
    python3 reports/diaspora/results/users_sessions/drive_registrations.py --fresh

cd /home/dev/project && PYTHONPATH=src python3 \
    reports/diaspora/results/users_sessions/coverage_report.py
PYTHONPATH=src python3 reports/diaspora/batch_stats.py users_sessions
```

`registrations_create` is **not** driven by `run_dse.rb` any more (its
`RUNS_CAP` entry is now inert — the driver above supersedes it). To reproduce
the original crash and the seed attribution, run the driver with §15 disabled by
commenting it out in `targets.rb`: it drains in 5 boots / 13 executions with 4
poisoned seeds, all sharing `find_by_1_not_found = true`.
