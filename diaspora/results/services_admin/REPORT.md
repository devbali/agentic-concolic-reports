# services_admin — concolic re-run (batch-local targets)

Regenerated 2026-08-15. Runner `run_dse.rb`; batch-local overlay `targets.rb`
(new). `src/`, the shared `concolic_targets.rb`, and the app source are
untouched. 3003 executions, 51.7 s.

## BEFORE → AFTER

| entrypoint | dumps | PCs | nodes | missing | complete | genuine / vacuous | worklist |
|---|---|---|---|---|---|---|---|
| `services_invite` | 2 → **258** | 2 → **2946** | 1 → **264** | 0 → 0 | true | genuine → genuine | drained |
| `services_failure` | 1 → 1 | 0 → 0 | 0 → 0 | 0 → 0 | true* | VACUOUS → **VACUOUS** | drained |
| `admin_user_search` | 1 → **2** | 0 → **2** | 0 → **1** | 0 → 0 | true | **VACUOUS → genuine** | drained |
| `admin_dashboard` | 1 → **2** | 0 → **2** | 0 → **1** | 0 → 0 | true | **VACUOUS → genuine** | drained |
| `admin_stats` | 1 → **2** | 0 → **2** | 0 → **1** | 0 → 0 | true | **VACUOUS → genuine** | drained |
| `admin_close_account` | 2 → **3** | 2 → **5** | 1 → **2** | 0 → 0 | true | genuine → genuine | drained |
| `admin_lock_account` | 2 → **3** | 2 → **5** | 1 → **2** | 0 → 0 | true | genuine → genuine | drained |
| `admin_unlock_account` | 2 → **3** | 2 → **5** | 1 → **2** | 0 → 0 | true | genuine → genuine | drained |
| `admin_add_invites` | 2 → **3** | 2 → **5** | 1 → **2** | 0 → 0 | true | genuine → genuine | drained |
| **batch** | 14 → **277** | 10 → **2972** | 5 → **275** | **0** | — | 5/4 → **8 genuine / 1 vacuous** | all drained |

`*` complete only because the tree is empty.

Every entrypoint is a true fixpoint (no `MAX_RUNS`/`TIME_BUDGET` stop; caps were
40000 / 1200 s, largest drained at 2945 runs). `unflippable_pcs` empty,
`solver_lost = 0`, `dumps_unparseable = 0` everywhere. **No regressions.**
Framework-wall errors: 5 of 14 dumps → **0**.

## The headline: the admin gate now records, and both sides are reachable

Previously the gate was **both unrecordable and unenforced** — with the role
query answering false, all runs still executed admin-only action bodies, and the
`redirect_to stream_url` side was unreachable under any seeding.

`(SYM_RESULT_ActiveRecord__FinderMethods_exists__1_exists == True)`:

| entrypoint | taken=True | taken=False |
|---|---|---|
| admin_dashboard / admin_stats / admin_user_search | 1 | 1 |
| admin_close/lock/unlock_account, admin_add_invites | 2 | 1 |
| **batch** | **11** | **7** |

Both sides non-zero on all seven admin entrypoints. `gate=False` dumps stop at
`redirect_to` with the action body **not executed**; `gate=True` dumps run it.

## Raw vs distinct path conditions (no dedup performed anywhere)

2972 path conditions across 277 dumps, comprising **15 distinct expressions**
(12 of them in `services_invite`). Recording sites: `blank?` 1728,
`regex_predicate` 960, `finder_mock` 266, `recording_role_predicate` 18.

**This is combinatorial depth, not a loop.** `services_invite` has 12 branch vars
and 258 drained paths ≈ 11.4 PCs/path — the expected 2^k-ish product of
independent binary branches, from which the checker builds 264 distinct nodes.
The one expression with per-dump multiplicity above 1 is
`(assoc_profile_image_url == '')` (704 over 258 dumps ≈ 2.7×), because
`no_profile_image?` and `Profile#update_profile_with_omniauth` test the same
field at **three different call sites** in one request — genuinely three ordered
nodes at different prefixes, not iterations of one.

15 distinct expressions is the honest measure of *breadth*; 2972 is depth. The
raw number is not presented as coverage on its own. **No dedup exists in the
runtime, runner, dumps, or pre-checker path** — the ordered sequence is
load-bearing for the execution tree.

## What `targets.rb` does

1. **§1 admin gate (headline).** `Role.is_admin?/moderator?/moderator_only?/spotlight?`
   declared with lambdas that **re-issue the real query** (`Role.exists?` → the
   declared finder target, SQL note intact), record a PC on that query's own
   seedable var, and return a concrete truth value — the `col?` predicate-reader
   pattern. Not the old `admin?` stub: nothing is hidden, and `Role.is_admin?`'s
   body has no `if` to swallow. Two gotchas: `defined?(Role)` is useless under
   Rails 5.2 `const_missing` (silently declared nothing on the first attempt),
   and returning `false` gets re-wrapped into a truthy `SymbolicBool` by
   `to_symbolic` — so the mock returns `true`/`nil`.
2. **§1b/§1c halt enforcement.** Recording was not enough: the shared
   `redirect_to` marker never sets a response, so `performed?` stayed false and
   the before_action chain did not halt. Setting `@_response_body` fixes it. That
   exposed the same artifact for `render` — `ServicesController#redirect_to_origin`
   ends in `render(text:)` from the `abort_if_already_authorized` before_action,
   so `create` was running *after the app had responded*, manufacturing **16 of
   32 infeasible `services_invite` paths**.
3. **§3 STI-aware `symbolic_instance`** (runtime alias wrapper; shared file
   untouched). Base-of-hierarchy detection is the negation of
   `finder_needs_type_condition?`; allocates a concrete subclass and pins `type`.
   Fixes `provider.camelize`, and covers every producer at once (finders, W3
   `find_target`, the DESIGN #4 representative row, the runner's `current_user`).
   Caveat: default subclass is first-by-name = `Services::Tumblr` even when the
   payload says twitter; nothing branches on it.
4. **§2 `ConcolicArithInt < SymbolicInt`** — closes `#+` (`add_invites!`), `#-`
   (`percent_change`), `#to_i` (AR FK cast). Derived `sym_name` per op, mirroring
   `-@`. `zero?/positive?/negative?` record PCs. Caveats: `to_i` deliberately
   concretizes at the AR cast; Int→Float ops drop tracking (no symbolic Real);
   derived names are unregistered and would be unflippable (none occurred).
5. **§4 grouped `Calculations#count`** returns a one-entry `{key => symint}`
   (the Gate-1b "one representative" analogue), symbolic and seedable, never
   concretized. A plain Hash cannot be used — the interceptor turns Hash returns
   into `SymbolicDict`, which has no `#values`.
6. **§2b `ConcolicRegexString < SymbolicString`** — `match`/`match?`/`=~` mint a
   fresh seedable boolean, record it, and answer concretely. Clears the
   `SymbolicString#match` wall at `Profile#build_image_url` **without mocking the
   method whose body is the branch**. This is what took `services_invite` from 18
   to 258 paths. **The only soundness caveat in the batch:** the boolean is
   independent of the string's value; its default is the true concrete answer, so
   unflipped runs are exact, but a flipped run's dump records a witness string
   that does not satisfy the regex — the path is reachable, the witness is not a
   model of it.

## Refusals (kept)

- **`InvitationCode#add_invites!`** — still refused; its body calls
  `update_attributes`, a declared target. §2 fixed the *value's* arithmetic
  instead, and `ActiveRecord::Base.save` now fires visibly in the dump.
- **`AdminsController#percent_change → 0.0`** — dropped; with §2 the app's own
  arithmetic runs, so no mock is needed.
- **`Service#provider → "twitter"`** — dropped; §3 subsumes it more faithfully.
- **`redirect_unless_admin`** and **`Profile#build_image_url`** — never mocked;
  they *are* the branches.
- **`admins_controller.rb:37`** — the unguarded nil is preserved and still
  reproduces.

## Remaining errors (4 of 277 dumps — all real app outcomes)

| dump | error | classification |
|---|---|---|
| `admin_add_invites` v0_dse0003 | `NoMethodError: 'add_invites!' for nil` @ `admins_controller.rb:37` | **real app defect** — unknown invite token → 500, not 404 |
| `admin_close/lock/unlock_account` v0_dse0003 | `ActiveRecord::RecordNotFound` | real 404 path (no `rescue_from`) |

No framework wall, environment wall, or `src/` gap remains open. Cleared this
round: `camelize for nil`, `SymbolicInt#to_i`/`#-`/`#+`, `SymbolicString#match`,
grouped-count `NoMethodError: values`.

## `include Enumerable`

The batch's `GroupedCount` subclasses `Object`, not `SymbolicList`, so there was
nothing to shadow. Measured anyway: **2972 PCs both with and without** — not
exposed. Removed as a forward guard, with `map`/`count`/`to_a` named explicitly.

## Still unrecordable

`if current_user.services << service` (bare truthiness on an AR
`CollectionProxy` — no symbolic wrapper, no boundary to instrument), and branches
on concrete request params (`case params[:range]`,
`if params[:admins_controller_user_search]`), which were driven by concrete
variants instead and provably collapse to one signature each.

`services_failure` stays VACUOUS because the action genuinely has no branch and
`ServicesController` has no admin gate. `admin_stats` is genuine only via the
gate — with all its walls cleared it now runs 11 real queries to completion and
still records nothing of its own, which proves it is branch-free rather than
blocked.
