# comments batch — concolic re-run (prefix-directed DSE + batch-local targets)

Regenerated 2026-08-15. Runner `run_dse.rb`; batch-local overlay `targets.rb`
(new), loaded after `ConcolicTargets.install!`. `src/`, the shared
`concolic_targets.rb`, and the app source are untouched.

## Overlay contents

| § | mock | why legal |
|---|---|---|
| 1 | `BelongsToPolymorphicAssociation#klass` → resolve type-column value to a Class, fallback `Post` | real body is `type.presence && type.constantize` — SQL-free, no app branch. Promoted out of `run_dse.rb` |
| 2 | `BelongsToPolymorphicAssociation#find_target` → `symbolic_instance(resolved_klass, "assoc_commentable", …)` | shadows shared W3 for polymorphic only; columns seedable → `owns?(parent)` becomes flippable. Promoted out of `run_dse.rb` |
| 3 | `IterableSymbolicList < SymbolicList` (`#each`/`#map` yield the representative once), returned from `Relation#records/to_a/to_ary`, plus a `NullRelation → []` guard | value fix, not a consumer mock |
| 4 | `Mentionable.people_from_string` → `Person.none` (shape-only override of shared X6f) | the Relation carries `ActsAsApi::Collection`; a bare `[]` became a SymbolicList with no `as_api_response` |
| 5 | `SuccIntValue < SymbolicInt` (`#next` → `(x + 1)`), wired by aliasing `ConcolicTargets.symbolic_instance` to re-wrap integer **columns** | closes `participation.count.next` |
| 6 | asset-path stub | AvatarPresenter / Sprockets environment wall |

## BEFORE vs AFTER (per entrypoint, never merged)

| entrypoint | dumps | PCs | nodes | missing | complete | genuine / vacuous | worklist | errors BEFORE → AFTER |
|---|---|---|---|---|---|---|---|---|
| `comments_create` | 10 | 36 | 9 | 0 | true | **genuine** | drained (31 execs) | `NotImplementedError`×3 → **0** |
| `comments_index` | 3 | 5 | 2 | 0 | true | **genuine** | drained (6 execs) | `NotImplementedError`×1 → **0** |
| `comments_new` | 1 | **0** | 0 | 0 | true* | **VACUOUS — not covered** | drained (1 exec) | 0 → 0 |
| `comments_destroy` | 4 | 9 | 3 | 0 | true | **genuine** | drained (10 execs) | 0 → 0 |

`*` complete only because the tree is empty.

**Coverage delta is exactly zero — the path sets are bit-identical**, verified by
comparing every `(expr, taken)` tuple before and after. That is the correct
outcome: both walls sat downstream of the last branch point on their paths. What
changed is that **all 18 dumps now have no `error` key at all**.
`create/dump_dse0002.json` went 15 → 21 events, ending at `render` after
`update!(count: (x+1))`; `index/dump_dse0002.json` now executes the real
`BasePresenter#as_collection` → real `CommentPresenter#as_json` → `render json:`.
No worklist hit `MAX_RUNS` or its budget; `unflippable_pcs = {}` everywhere.

## `SymbolicInt#next` — mock analysis re-confirmed, `src/` conclusion RETRACTED

The mock analysis stands: `User#update_or_create_participation!`
(`app/models/user/social_actions.rb:52`) issues SQL *and* holds
`if participation.present?` — illegal to mock on both rules. The smaller
alternative (mocking `Participation#count` → plain Integer) is rejected as
de-symbolization.

But the "therefore it needs a `src/` change" conclusion was **wrong and is
withdrawn**. The VALUE can carry `#next`: `SuccIntValue < SymbolicInt` returning
`SuccIntValue.new(value + 1, name: "(#{sym_name} + 1)")`, mirroring
`SymbolicInt#-@`. Still tracked, still flippable, nothing concretized. **No
`src/` change is required by this batch.**

Wiring note that differs from `photos`: their wall was `Calculations#count` on a
Relation; this one is an **integer column** on a `symbolic_instance` record. So
§5 aliases `ConcolicTargets.symbolic_instance` batch-locally and re-wraps integer
columns, reusing the same var name / seed / note and updating both the reader and
`concolic_attrs` (which backs `[]` / `read_attribute`).

## `BasePresenter.as_collection` — implemented, measured, DISCARDED

It is legal (body is `collection.map{…}` — no SQL, no `if`) and it did clear the
wall. Measured effect: 5 PCs → 5 PCs, and the wall simply relocated one frame
deeper to `NoMethodError: as_api_response`. Because it mocks the **consumer**, it
was replaced with the `IterableSymbolicList` value fix, which lets the app's own
`map` and `as_json` run for real. Negative result kept deliberately.

Also **not** mocked: `MentionsContainer#mentioned_people` — its body is
`if persisted?`, i.e. it *is* a branch.

## `include Enumerable` hazard — checked, not exposed, guarded anyway

`IterableSymbolicList` deliberately does **not** `include Enumerable`. A module
included into a `SymbolicList` subclass is inserted BEFORE the superclass in the
ancestor chain, so `Enumerable` would shadow `{any?, count, first, include?,
none?}` — and `SymbolicList#any?`/`#none?` are exactly what record the
`(len(X) != 0)` path condition (`src/ruby_runtime/list.rb:161-177`). Enumerable's
versions just iterate `each` and return a plain bool, silently dropping the PC on
a run that still looks green and error-free (`notifications_tags` measured
8 PCs → 4 from this alone). It would also silently re-enable `#include?` and
`#to_a`, which `SymbolicList` raises on BY DESIGN.

Measured for this batch, both ways, all four entrypoints re-run:

| | create | index | new | destroy | total |
|---|---|---|---|---|---|
| with `include Enumerable`    | 36 | 5 | 0 | 9 | **50** |
| without `include Enumerable` | 36 | 5 | 0 | 9 | **50** |

Per-expression identical, path sets still bit-identical, 0 errors. `comments` was
never exposed — every PC here is recorded by `block in finder_mock`,
`block in symbolic_instance`, `block in public?`, or `==`, none of which is in the
shadow set. The "coverage delta exactly zero, path sets bit-identical" headline
therefore stands unmodified. `include Enumerable` is removed regardless, as a
forward guard, with the hazard documented at the definition site.

## Remaining honest gaps

- `comments_new` is **vacuous by construction** — its body has no query and no
  branch; only Devise/Warden `before_action` code is branchable, and the
  controller-test rig does not run filters.
- Ruby truthiness gap: `if relayable.save!` on a `SymbolicBool` emits no PC and
  is always truthy → create's `status: 422` branch is unreachable and absent
  from the tree.
- `comments_index` explored anonymous-only
  (`before_action :authenticate_user!, except: :index`).
- Gate 1b: one representative row modeled for index's comment list.
- `src/` items reported, none blocking: the `CallInterceptor` `@all_calls` leak
  (worked around runner-locally), `SymbolicString#split` with a multi-char
  separator (worked around by §1), and singleton-class targets getting
  `SYM_RESULT_Anonymous_*` names (`call_interceptor.rb:100`).

**Stale docs:** README/STATUS still blame `Core::ClassMethods#find` for blocking
`comments_destroy`; it is declared at `concolic_targets.rb:422` and that
entrypoint is complete.
