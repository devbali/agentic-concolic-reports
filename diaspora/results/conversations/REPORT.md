# conversations batch — concolic re-run (prefix-directed DSE + batch-local targets)

Regenerated 2026-08-15. Runner `run_dse.rb`; batch-local overlay `targets.rb`
(new). `src/`, the shared `concolic_targets.rb`, and the app source are
untouched. 1492 executions, 19.8 s, all six worklists drained, no env vars
needed.

## BEFORE vs AFTER (engine-verified, per entrypoint, own runs only)

| entrypoint | dumps | PCs | nodes | missing | complete | genuine? |
|---|---|---|---|---|---|---|
| `conversations_index` | 7 → **32** | 18 → **164** | 5 → **30** | 0 → 0 | true → true | genuine (truncated) → **genuine, runs to completion** |
| `conversations_create` | 3 → **5** | **0 → 4** | 0 → **1** | 0 → 0 | true → true | **VACUOUS → genuine** |
| `conversations_show` | 12 → **14** | 36 → **46** | 5 → **6** | 0 → 0 | true → true | genuine → genuine |
| `conversations_raw` | 6 → **7** | 18 → **23** | 5 → **6** | 0 → 0 | true → true | genuine → genuine |
| `messages_create` | 2 → 2 | 2 → 2 | 1 → 1 | 0 → 0 | true → true | genuine → genuine |
| `conversation_visibilities_destroy` | 3 → 3 | 5 → 5 | 2 → 2 | 0 → 0 | true → true | genuine → genuine |
| **total** | 33 → **63** | 79 → **244** | 18 → **46** | **0** | **6/6** | **5 genuine + 1 vacuous → 6/6 genuine** |

Error dumps **13 of 33 → 4 of 63**, and **zero `NotImplementedError` remain**.
No regressions: no entrypoint lost a PC, a node, or its genuine status.

## The headline fix: `Calculations#pluck` — the prediction held

Applied as proposed: length-only symlist with a seeded representative,
`note: sql_for(...)`. The justification stands — `pluck` **is** the query
boundary (it fires the SELECT), the same role `records`/`to_a` play, so this is
§C's existing collection-materialization shape applied to the method that
materializes, not a new hole in the "contents ops raise" policy. Representatives
are per-column typed (`columns_hash`, `_id`-suffix fallback) and every scalar
goes through `seed_for` so DSE can flip it.

**`create` is genuine, exactly as predicted.** `person_ids.present?` →
`Object#blank?` → `SymbolicList#empty?` → `(len(…_pluck_1_plucked) != 0)`,
recorded **on both sides** (build vs. the 422 "no recipient" render).

**`index` reaches `respond_with` — but the stated reason was wrong.** It now runs
to completion with zero errors (previously all 7 dumps died in `pluck`), 4 → 7
branch points, 5 → 30 nodes. However the predicted
`no_contacts: current_user.contacts.mutual.empty?` PC **does not exist**: the
block does run (`Relation.empty?` at `conversations_controller.rb:29`), but the
shared mock returns a `SymbolicBool` *directly* — not a `SymbolicList` whose
`empty?` records — and the value is only stuffed into `locals:`, never compared.
The branch that would consume it lives in the Haml template, which never renders
because `ActionController::Rendering#render` is itself a body-skipped target.
Index's real new depth comes from `contacts_data`'s display-name projection:
three genuine `SymbolicString#empty?` branch points on plucked profile columns
via `Person.name_from_attrs`.

## `SymbolicList#[] only supports index 0` — a legal fix exists

`SampledList < SymbolicList` honours **index −1 only**, which is sound rather
than a relaxation:

- `list.rb:120` already models `#last` as "return the representative". `x[-1]`
  and `x.last` denote the same element, so −1 grants no capability the runtime
  does not already grant under another name. The case the guard protects — a
  block needing the SECOND row, |i| > 1 — still raises.
- It is the **only** index the frontier ever demands: the sole PC on that value
  is `((- unread) == 0)`, whose one flip assigns `unread = 1`, i.e. index −1.
  Nothing generates −2. So −1 is fixpoint-complete, and a general-index version
  would be strictly less honest for zero extra coverage.
- The `(idx == 0)` compare is kept first and unchanged so the existing
  `((- VAR) == 0)` PC still records; the −1 test reads the concrete `.value` and
  deliberately records nothing.

**Verified:** the `((- unread) == 0) = False` paths — which in production are the
*only* reachable ones, since the visibility comes from `.where('unread > 0').first`
so `unread ≥ 1` always — used to die at the wall. They now continue into
`Conversation#set_read` and explore both sides of `find_by_1_not_found`.

## Other subclass fixes (surfaced *by* the pluck fix)

| wall | where | fix | effect |
|---|---|---|---|
| `SymbolicList#map`/`#to_a` | `contacts_data`'s `.map{}`; index-json `@visibilities.map(&:conversation)`; `[*person_ids]` | `SampledList` iterates the one rep, `concrete_length.zero? ? 0 : 1` times | index runs clean |
| `SymbolicString#strip`/`#scrub` | `Person.name_from_attrs`; `ERB::Util.h` | `SampledString` computes the native result, returns **self** when it equals the concrete value (always here) | 1148 error dumps → 0 |
| `SymbolicInt#to_i` | AR `ids_writer` type-cast in `build_conversation` | `CastableInt` adds `to_i` (never `to_int`) | **zero PCs gained** |

No branch is swallowed: `strip`/`scrub` results are never compared, and the
`blank?` PCs preceding them are branches this fix *exposes*, not hides.

**Honest limits introduced:** iteration count is concretized to 0-or-1 (no branch
here needs two distinct rows; `empty?`/`any?`/`length` stay symbolic);
`strip(X) ≈ X`; and **`CastableInt#to_i` is a real concretization that bought
nothing** — 5 paths / 4 PCs with or without it. It only moved create's crash from
`NotImplementedError: SymbolicInt#to_i` to `RecordNotFound`. Kept because
`build_conversation` now actually assembles the recipient list, but it is not a
coverage win.

**JRuby trap worth recording:** JRuby runs Ruby 2.6 semantics where
`String#strip` on a subclass returns an instance of the *receiver's* class via
allocate+copy — it came back as a `SampledString` with `@value` still `nil` and
blew up as `TypeError: no implicit conversion of nil into String` (1148 dumps).
Rebinding native `String#to_s` flattens it first.

## Every remaining error, classified

| error | dumps | classification |
|---|---|---|
| `ActiveRecord::RecordNotFound` (create) | 2 | **harness artifact, NOT a 404.** `[*person_ids] \| [person_id]` fails to dedupe (SymbolicInt doesn't `eql?` plain `1`), both cast to `1`, and the concolic DB has no Person rows — AR wants 2, finds 0. Costs no coverage: the only branch left in `create` is `if @conversation.save`, the truthiness gap. |
| `ActionController::UnknownFormat` (show) | 1 | **real app outcome** — json + not-found does `redirect_to` with no json responder; the identical html run completes via the redirect. |
| `ActiveRecord::RecordNotFound` (messages_create) | 1 | **real app outcome** — the 404 path. |

## Branches the runtime still cannot record

Ruby truthiness gap (`src/TODO.txt`): `if @conversation.save` (create 422),
`if message.save`, `if @vis.destroy`. `if @conversation` is *not* lost — the
finder mock records `*_not_found` at the query boundary. View-level branches are
out of scope by construction (`render` is body-skipped). `(- VAR) == 0` is
emitted by `SymbolicList#[]`'s own index check, not by diaspora source.

## New `src/` finding — reported, not patched: lossy arg capture for splat methods

`CallInterceptor` builds `call_args` by zipping the *original* method's
`parameters` against the actual args (`call_interceptor.rb:115-125`). For
`pluck(*column_names)` that keeps only the **first** column — and once a target
is declared, the "original" is the interceptor's own
`|*splat_args, **kwargs, &block|` wrapper, so a 4-column pluck is dumped as
`{"splat_args": "contacts.id", "kwargs": "profiles.first_name", "block": "profiles.last_name"}`
— not merely lossy but **mislabelled**. Any consumer reading `args` off a
splat-method dump is reading garbage. Since pluck's return *shape* depends on its
arity, the overlay recovers the real list via a `PluckArgs` module prepended to
`ActiveRecord::Relation` that stashes columns in a thread-local and immediately
`super`s into the intercepted mock — nothing bypassed, no query hidden. Fixing
the interceptor is a Bali call.

Still true and still worked around runner-locally: unbounded `@all_calls`
retention (`call_interceptor.rb:69`).

## Method / fidelity

Prefix-directed DSE with seed inheritance + single-branch flip; MD5-digest
path-signature dedup; **0 unflippable PCs** across all six entrypoints. Variants
are request shapes the real route accepts, not different app logic.
Carried-over caveats: `current_user.id`/`person_id` concrete (=1), and
association readers are runner-supplied `.all` relations so rendered SQL is the
unscoped relation, not the real `has_many through:` join — branch structure is
real, the rendered join is not.

**Stale doc note (unchanged):** the README still lists `messages_create` as
blocked by an undeclared `Core::ClassMethods#find` → `SymbolicList#first`; that
target exists (`concolic_targets.rb` §A2, ~line 422) and the entrypoint is
genuinely covered.
