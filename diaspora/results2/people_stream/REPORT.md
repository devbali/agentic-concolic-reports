# people_stream — results2 rerun (symbolic entrypoint args)

(Report authored by the batch agent; saved by the coordinating session.)

Ported from `results/people/` restricted to `PeopleController#stream`;
`concolic_targets.rb` is the fixed private copy (bind-order fix verified,
byte-identical to `results2/conversations_index/`'s).

## Scenarios (one directory, distinct label prefixes)

| scenario | format | signed_in | source |
|---|---|---|---|
| `anon_all` | html | no | source batch's canonical DSE scenario |
| `anon_json` | json | no | pre-DSE `run_concolic.rb` scenario (person_id "1", username "bob@example.org") |
| `auth_json` | json | yes | new: signed-in, symbolic user, pins removed |

`person_id` and `username` symbolic in every scenario.

## Results

54 runs → 20 dumps (8+6+6), 60 PCs, 9 tree nodes, 0 missing.
`coverage_complete: true`, genuine (every dump ≥1 PC), all 3 worklists
DRAINED, 0 unflippable PCs, 0 dump errors, 0 assumptions.

## Acceptance test

Every finder-reaching dump:
```
SELECT "people".* FROM "people" WHERE "people"."diaspora_handle" = $$(SYM_PARAM_username)
```
Signed-in stream query (`dump_auth_json0001.json`):
```
SELECT "posts".* FROM "posts" WHERE "posts"."author_id" = $$(SYM_RESULT_ActiveRecord__FinderMethods_first_1_id) AND "posts"."created_at" < ...
```

`$$(SYM_PARAM_person_id)` appears in NO dump — a structural finding, not an
oversight (below).

## Central finding — mock decisions can't drive bare-truthiness branches

`find_person`'s `if diaspora_id?(username)`: the real predicate is
uncallable on a symbolic string (`lstrip`, `=~` both UNSUPPORTED — verified
against the gem source), so it was mocked as a boundary decision (targets.rb
§7). But `declare_target`'s `returns:` auto-wrap (`call_interceptor.rb`
~168-176 → `to_symbolic`) re-wraps concrete `false` into a truthy
`SymbolicBool` object, and `if <object>` is bare Ruby truthiness — so the
branch NEVER actually flips (verified: a `False` PC dump issues the same
diaspora_handle SQL as `True` runs). The `diaspora_id?` node is "covered"
per the checker but behaviorally identical on both sides;
`find_from_guid_or_username` (the person_id/guid path) is unreachable.
**Raise to Bali**: this is the documented truthiness/auto-wrap gap
(src/TODO.txt; the clean fix is letting explicit `false` mock returns pass
unwrapped). No discipline-legal mock closes it (`find_person` itself fires
other targets on both branches).

## Secondary finding — viewer identity never reaches SQL on this action

`Stream::Person#posts` checks only `user.present?`; `posts_from` uses the
VIEWED person's id. The one viewer-id query (`Like.where(author_id:
user.person_id, ...)`) sits inside the shared `attach_user_likes` Gate-1b
mock's skipped body. `SYM_USER_PS_*`/`SYM_PERSON_PS_*` appear in zero
auth_json dumps — a genuine property of people#stream, reported honestly.

## What worked

- `SYM_PARAM_username` reaches SQL as a bind in every scenario.
- The pre-DSE runner's json-format wall (`stream_posts.map` crash) is closed
  (`IterableSymbolicList` §5b + shared Gate-1b splits): all 12 json dumps
  error-free; 0 crashes in all 20.
- All identity pins removed (user.id, person.id, person_id, guid,
  diaspora_handle — guid/handle now via the real `delegate` to person);
  left symbolic and simply unreached, not re-pinned.
- Associations rescoped to real FKs (`contacts`/`blocks`/`aspects`/
  `posts_from`); `posts_from` fires with a genuine bind.
- Pre-existing, already-documented gap kept as-is: `Person#posts` (§1)
  remains unscoped `Post.all` (association readers on `klass.allocate`
  instances have no association state) — visible in anon_json posts queries.

## Technique notes

- `ctrl.dispatch(action, req, res)` instead of `ctrl.send(action)`:
  `@person` is set by the `find_person` before_action, so the callback chain
  must run; dispatch keeps rescue handling real while params are injected
  directly.
- Per-instance identity overrides on the username value
  (`downcase`/`lstrip` → self) mirror the runtime's own `to_s` identity
  trick; sound because finder outcomes are boundary-decided via `seed_for`,
  independent of the string bytes.

## Errors

Zero `error` keys in all 20 dumps; closed_account/not_found paths end in the
app's real redirect/render tails through `ActionController::Rescue`.

---

## ADDENDUM (2026-08-18): completed under combination-coverage semantics

The coverage sections above predate the engine rewrite (combination
semantics) and are superseded. Current authoritative state
(`coverage_summary.json`, reproduced by a fresh checker run):
`coverage_complete: true, truncated: false, solver_lost: 0,
unevaluable_exprs: [], assumptions_used: 6`.

All 14 blocking missing combos were closed by six source-cited assumptions
in `coverage_assumptions.py` (no new runs needed): five expr-keyed
IndependenceAssumptions for guard truncation (people_controller.rb:140
raises RecordNotFound before the closed_account check; :141 raises
AccountClosed before the redirect body reads guid), and one
OneSideUntrackedPathAssumption whose untracked side is proven unreachable
from actionpack's formatter.rb:40-41 (the only path evaluating the guid
inequality forces it False). The diaspora_id? truthiness inertness remains
a real framework finding but did not block completeness — its decision var
is freely seedable and all its cross-combos were already observed.

---

## ADDENDUM 2 (2026-08-18): dispatch inertness FIXED, re-explored, complete on the enlarged universe

Supersedes both the "Central finding" (inert diaspora_id?) and Addendum 1.

- **Steering fix** (targets.rb §7): the declare_target mock now returns
  `true`/`nil` (nil is the only falsey passthrough; a returned false gets
  re-wrapped truthy by to_symbolic). Verified in dumps: 17 dispatch=False
  runs issue the ALTERNATE finder family (find_from_guid_or_username /
  User.find_by_username) and never the diaspora_handle query.
- **Universe grew 5 → 12 exprs**; 27 fresh dumps, all three scenario
  worklists DRAINED, 0 errors. The username sub-branch required a
  deliberate probe root (person_id="" + dispatch=False seeded together) —
  `params[:id].present?` is a concrete, unrecorded decision the flip-based
  worklist can never discover; documented in run_dse.rb.
- **Ordinal caveat, documented not hidden**: Person.find_by(guid:) and
  User.find_by_username share the find_by_1 not_found expr name; argued
  equivalent for the True side (identical 2-PC abstract trace, raise at
  people_controller.rb:140) with downstream vars fully distinguishing the
  False sides. people_show-style §8 wall mocks + the len()→SYM_LEN rename
  ported.
- **66 argued assumptions** (63 independence: per-arm guard sequences,
  arm-vs-arm exclusivity, dispatch-tier full cross — the last extended
  mid-pass when the checker's pairwise demands exposed the initial
  guard-tier-only mirror of people_show as insufficient, corrected and
  documented in-file; 3 OneSide with the formatter.rb unreachability
  proof per arm).
- Final (fresh checker run reproduces): coverage_complete=true,
  truncated=false, solver_lost=0, unevaluable_exprs=[], tree_nodes=12,
  total_runs=27, assumptions_used=66. Verified by the coordinating
  session including the SQL steering property.
