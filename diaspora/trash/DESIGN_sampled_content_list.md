# DESIGN — Sampled-content SymbolicList (Gate 1b)

**Date:** 2026-08-09
**Status:** PROPOSAL — needs Bali sign-off on the representative-element
semantics before implementation (changes the documented SymbolicList contract
in §5 of `PLAN_symbolic_query_ops.md`, and touches **both** runtimes).
**Motivation:** Bali's Gate 0 = B decision (run through views) plus the
app-logic iteration we already see require `SymbolicList` to yield *elements*,
which today it deliberately cannot (§5) — every element op raises.

### OVERRIDING PRINCIPLE (Bali, 2026-08-09): NO STUBBING — CALL THE ENTRY POINT STRAIGHT

Affirmed after the initial proposal: there is **no stubbing anywhere** — not of
views, not of render, not of anything. The render-boundary stub (from the
option-A era) is **fully removed**; templates, render, helpers all execute for
real. We invoke the entry point directly and let the real app run. The only
intervention is the interceptor supplying symbolic values at AR/query/
association boundaries, which hand symbolic VALUES to real code — it never
canned app-logic results.

### REFINED VIEW MODEL (Bali, 2026-08-09, FINAL): just wrap the `each`

Simplify the earlier "symbolic view" idea to its essence: **wrap the `each`**.
The iteration is intercepted so it never executes against a `SymbolicList`
(no crash); the iterated/derived collection result is supplied symbolically.
And within that wrap there are **NO SQL calls** — the wrapped `each` region
must not issue real DB queries (no association loads, no `to_sql`, no query
ops). The data it iterates is already present symbolically. Keep it that
small — no whole-view-symbolic-mock mechanism needed.

---

## 1. The problem, precisely

Current `SymbolicList` (both runtimes) is a wrapper around a **symbolic
length ONLY** (`PLAN_symbolic_query_ops.md` §5). ALL element access raises:

- `list[i]`, `list.first`, `list.last`, `list.each`, `list.map`,
  `list.reject`, `list.select`, `list.find`, `list.include?`, …

Crash budget (2026-08-09 dumps): **32 `#each`** + **11 `#first`**
(43 total), plus the downstream nil-derefs those cause.

**Root-cause finding (not just views):** the tracebacks show these fire in
**app/model logic that runs BEFORE render**, e.g. `StreamsController` →
`stream_posts` → `Post.excluding_blocks` → `user.blocks.map { |b| b.person_id }`
(`post.rb:90`). So sampled contents are needed for controller/model iteration
under *any* completness philosophy — Bali's B choice makes them mandatory for
views too, but they are not hostage to B.

---

## 2. The design: keep the length, add ONE representative element

The contract becomes:

> A `SymbolicList` models the **"how many rows"** dimension symbolically
> (unchanged) **plus** holds a single **representative element** —
> typically a `SymbolicObject` (the §4 redesign: an instance of the real model
> class with symbolic attributes). Element access and iteration return/yield
> that one representative row.

### Constructor (back-compatible)
```ruby
def initialize(length = 0, name: nil, note: nil, representative: nil)
  # ...existing symbolic-length setup unchanged...
  @representative = representative
end
```
- **Default `representative: nil`** ⇒ behaviour is IDENTICAL to today: element
  ops still raise. Zero blast radius on existing runs that never set one.
- When a harness/association supplies `representative:`, element ops engage.

### Semantics per op (when representative is present)

| Op | Behaviour | PC recorded |
|---|---|---|
| `first` / `last` | return `@representative` | — (absence decided at mock boundary, see §3) |
| `[0]` | return `@representative` | — |
| `[i]` (i>0) | raise (only 1 rep is modeled — see honesty §5) | — |
| `each` / `map` / `reject` / `select` / block-`any?` / `find` | **NOT implemented on the list.** Iteration is bypassed by wrapping the CALLER (see §2a) | handled by caller wrap |
| `length` / `size` / `count`(0-arg) | symbolic length (unchanged) | on compare |
| `empty?` / `any?` (no block) / `none?` / `!` | symbolic length (unchanged) | `(len != 0)` |
| `include?(x)` | concrete `@representative-attr match`? | comparison PC |
| everything else | still raises `NotImplementedError` | — |

All **length/emptiness** branches stay **symbolic** — the "0 vs ≥1 row"
dimension is preserved and branchable exactly as today. Only *which* element
is concretized (to the single rep).

## 2a. Iteration: wrap the caller, don't fabricate it

`each`/`map`/`reject`/`select` stay **unimplemented** on `SymbolicList` —
iterating once over a rep would be a lie about iteration semantics. Instead,
for each call site we **wrap the method that CALLS the iteration** at the
mocked boundary, so the derived/iterated result is supplied symbolically
without ever executing `each` on a SymbolicList. This matches the model case:

```ruby
# user.blocks.map { |b| b.person_id }
# → wrap the ASSOCIATION READER user.blocks (runner-local, approved pattern)
#   so .map on it yields a symbolic set of person_id values; no each runs.
```

The wrap target is the **collection/association producer** (legit mock layer),
NOT hand-replicated app methods (SOUCE_DISCIPLINE). [open: exact per-call-site
target — see §7 D5]

Generalized rule (Bali, 2026-08-09, FINAL): **mock the SMALLEST enclosure that
contains the `each`** — NOT `each` itself. You cannot intercept `each` because
the enclosing method does real per-element work in the block; intercepting
`each` would skip that logic. Instead mock the smallest method that wraps the
loop (e.g. `user.blocks` association reader, or the model/view method that
iterates), and ensure the **real body of that mocked method contains NO SQL**
— it should only be laying out/presenting already-loaded data (e.g. "show
these in a table"), never querying (no association loads, no `to_sql`, no
query ops).

---

## 3. Absence / nil semantics — decided at the mock boundary (NOT in the list)

The list itself does **not** model "empty vs has-a-row" by returning nil for
`first`. Following the established §4 null-handling rule ("no null flag on the
object; absence decided at the mock boundary"), the *finder mock* already
records the `any?`/`empty?` PC and raises `RecordNotFound` (for `find`) or
returns concrete `nil` (for `find_by`/`take`/`first`) when the not-found
branch is explored. The sampled list's `first` is reached only on the
"has-a-row" branch, so it can safely return the rep. This keeps the list's job
orthogonal: **length/emptiness = symbolic; row content = one rep.**

---

## 4. The representative element

- Supplied via the **harness / `concolic_targets.rb` / association reader**,
  not synthesized by the runtime. The runtime stays generic (source-discipline):
  it just stores and yields whatever `representative:` it's given.
- Typically a `SymbolicObject` per §4: `receiver.klass.allocate` with symbolic
  singleton attribute readers. Its attributes are individually symbolic, so a
  view/model block doing `rep.author.name`, `rep.public?`, `rep.person_id`
  branches on real symbolic attrs → genuine PCs.
- **Association flavor (important for `user.blocks.map{b|b.person_id}`):** the
  block reads `person_id` off each row. With a single rep, `map` runs once and
  reads the rep's symbolic `person_id` — a real PC from model logic.

---

## 5. Honest limits (state these in reports — do NOT over-claim)

1. **One representative row, not N distinct rows.** We model "0 rows vs ≥1
   row" and let ONE row's values flow through the app. We do NOT model
   *different* rows having *different* values (`row1.public? ≠ row2.public?`).
   Distinct-row branching is out of scope — same as §5's original stance, just
   now shifted to "contents = one rep, not many."
2. **`each` runs once.** Blocks that genuinely iterate many rows will run their
   body once against the rep. Fine for branch coverage of the block's logic;
   NOT a faithful N-row simulation.
3. **Indexing beyond the rep raises** (`list[1]`, `list[3]`) — we only have one.
   A block that needs the *second* row will crash loudly (better than silently
   wrong).

---

## 6. Cross-runtime parity (mandatory)

Both runtimes must change together or the path-signature mirror breaks:

- **Ruby** `src/ruby_runtime/list.rb`: add `representative:` to ctor; implement
  the element ops above when rep present, else keep raising.
- **Python** `src/py_runtime/list_.py`: same — `_representative` attr; map
  `__getitem__/__iter__/__contains__` and the `_LIST_STUBS` that become
  single-item ops. (Python has no `first`/`map`; those are framework-level —
  the runtime only implements `__iter__`/`__getitem__` and the app's `.map{...}`
  is lowercased/explicit in the py mirror tests.)

---

## 7. What I need from you (Gate 1b sign-off)

- **D1 — Representative-element semantics:** OK that `SymbolicList` gains a
  single `representative:` whose ACCESS ops (`first`/`last`/`[0]`, `include?`)
  return/use it, with the honest limits above? (This is the contract change to
  §5.) NOTE: `each`/`map`/`reject`/`select` are NOT implemented on the list —
  they stay non-implemented and are handled by caller-wrapping (§2a), per Bali.
- **D2 — Absence/nil at mock boundary:** OK to keep nil/RecordNotFound handled
  by the finder mock (list itself doesn't model empty-row nil)?
- **D3 — Default back-compat:** OK that `representative: nil` means element ops
  keep raising (no behavioural change for existing runs)?
- **D4 — Scope of iterable ops:** `each`/`map`/`reject`/`select` left
  UNIMPLEMENTED on the list, handled by caller-wrapping; `first`/`last`/`[0]`/
  `include?` via the rep.
- **D5 — VIEW `each` — RESOLVED (Bali, 2026-08-09, FINAL):** mock the SMALLEST
  enclosure that contains the `each` (NOT `each` itself — it does real
  per-element work). REASON: intercepting `each` would skip the per-element
  logic. The mocked method's real body must contain **NO SQL** — it only lays
  out/ presents already-loaded data (e.g. render rows in a table), never
  queries (no association loads, no `to_sql`).
- **D6 — SCALE: mock TOP-LEVEL AR framework modules, not per-model (Bali,
  2026-08-09):** no mock per model. Targets are declared once on shared AR
  framework modules (FinderMethods, Relation, Core::ClassMethods, Calculations,
  Batches, Persistence, Querying) — every model inherits them, so each is
  covered by a single declaration. The per-entrypoint work is choosing WHICH
  already-mocked association/query producer is the "smallest SQL-free
  enclosure" for a given `each`, and wiring that call-site to carry a symbolic
  representative. New work is per CALL-SITE (a countable list pulled from the
  dumps), not per AR-kind.
- **D7 — APPROVED PLAN (Bali, 2026-08-09):** mock specific call-sites that call
  `.each`; for each, verify the REAL implementation of that mocked method does
  NO SQL queries (it just lays out/ presents already-loaded data, e.g. render
  rows in a table). If the real body would query, pick a different (outer)
  enclosure or supply the data symbolically.
- **D8 — MOCK MECHANISM = regular `declare_target`, free (Bali, 2026-08-09):**
  the `.each` call-site mocks are declared through the STANDARD
  `interceptor.declare_target` symbolic-target mechanism — the same regular
  layer as the finder/query/render mocks — NOT ad-hoc runner monkey-patching.
  For a given call-site, declare_target on the smallest SQL-free enclosure
  method so it returns a symbolic representative/collection like any other
  target function.

On your nod I'll implement in both runtimes, add mirror tests, then wire
representatives into the harness/associations for the entrypoints that need
them (streams, contacts, notifications, people, likes, photos).

---

## 8. IMPLEMENTATION GUIDE & RUNBOOK (for a fresh agent)

This section turns the design into a step-by-step, self-contained guide. Follow
it top to bottom. Everything in this section is the live plan for Gate 1b.

> **Canonical running instructions live in `reports/diaspora/README.md`**
> (Workflow / Usage / Coverage loop / Output structure). This runbook is the
> Gate-1b-specific overlay — it points at the README for launch mechanics and
> adds only what the design changes introduce. Read the README first.

### 8.0 Environment / prerequisites

- App: `/home/dev/project/ruby_examples/dse-apps/apps/diaspora` (Rails 5.2.4.3,
  JRuby 9.3, Java 21).
- Java/JRuby tools: `/home/dev/tools/`
- Ruby runtime (to edit): `/home/dev/project/src/ruby_runtime/`
- Python mirror runtime (to keep in parity): `/home/dev/project/src/py_runtime/`
- Target declarations (to extend): `reports/diaspora/concolic_targets.rb`
- Launch script: `/home/dev/project/scripts/diaspora-concolic <runner.rb>`
  (runs from the app dir with `RAILS_ENV=concolic`, minimal gems, sqlite DB at
  `db/concolic.sqlite3` — has the tables needed for `columns_hash`).
- Reference: this design doc + `README.md` + `STEP0_query_targets.md` +
  `RAILS_CONCOLIC_MOCKING.md`.

### 8.1 Phase 1 — runtime: give `SymbolicList` a representative (both runtimes)

Goal: `SymbolicList` can carry ONE representative element so element-ACCESS ops
(`first`/`last`/`[0]`/`include?`) return it, while `each`/`map`/`reject`/`select`
STAY unimplemented (handled by caller-wrapping, §2a/8.4). Back-compat: a list
with `representative: nil` behaves EXACTLY as today (element ops raise).

**Ruby — `src/ruby_runtime/list.rb`:**
1. Add `representative: nil` to `initialize`; store `@representative`.
2. Define an accessor `attr_reader :representative`.
3. In `first`, `last`, `[]` (index 0), `include?`: if `@representative` is set,
   return/use it; else raise as today. `[i]` for i>0 still raises (only 1 rep).
4. Leave `each`/`map`/`reject`/`select`/`find` in the `LIST_STUBS` (still raise).
5. Keep `length`/`size`/`empty?`/`any?`/`none?`/`!` exactly as-is (symbolic).

**Python mirror — `src/py_runtime/list_.py`:**
1. Add `_representative` in `__init__`; expose a property.
2. Map `__getitem__`(0), `__contains__` to the rep when set.
3. Keep `__iter__` and the iteration/`map` stubs raising (parity with Ruby).
4. Keep `__bool__`/`length` symbolic (unchanged).

**Verify parity & back-compat (run from `.openclaw/workspace` or `project`):**
```bash
# Ruby smoke
ruby -I src/ruby_runtime -e '
  require "list"; require "object"
  l = symlist("x", 3, representative: symint("r", 7))
  abort unless l.first.value == 7
  abort unless l[0].value == 7
  abort "no-sql: each must still raise" if l.respond_to?(:each) rescue raise
  empty = symlist("y", 0)                       # no rep -> back-compat
  begin; empty.first; raise "should raise"; rescue NotImplementedError; end
  puts "ruby list rep OK"'   # expect: ruby list rep OK … (each raises)
```
Keep a Python-side check that `__getitem__`/`__contains__` behave the same.
Add both to `src/*/test_*.{rb,py}` as regression tests.

### 8.2 Phase 2 — audit contract + honest limits (no code)

Re-read §5 hard limits and re-confirm the source-discipline rule (runtime must
stay generic: it only stores & yields the given rep; it must NOT embed any
Rails/SQL-specific behavior). The rep is supplied by the harness, never
synthesized inside the runtime.

### 8.3 Phase 3 — the `.each` call-sites (counted, from 2026-08-09 dumps)

The iteration crashes are NOT in views; they are in model/controller transform
methods that `map` over a collection. For each, the mock target is the
smallest SQL-free enclosure — almost always the ASSOCIATION/RELATION PRODUCER
that returns the collection (a `SymbolicList` carrying a rep). Verified on the
real source:

| # | Batch / entrypoint | Crash method (caller of each/map) | Real body | SQL in body? | Mock target (declare_target) | Returns |
|---|---|---|---|---|---|---|
| 1 | streams · streams_commented | `Post.excluding_blocks` (post.rb:90) | `user.blocks.map{b\|b.person_id}` then `.where(...)` | `.where` DOES query → not SQL-free | `user.blocks` (association reader) | SymbolicList of symbolic person_ids |
| 2 | streams · streams_liked | same `excluding_blocks` | same | same | `user.blocks` | SymbolicList of person_ids |
| 3 | streams · streams_activity | same `excluding_blocks` | same | same | `user.blocks` | SymbolicList of person_ids |
| 4 | streams · streams_aspects | `Stream::Aspect#aspect_ids` (aspect.rb:95) | `aspects.map(&:id)` | no — pure transform | `aspects` | SymbolicList of symbolic ids |
| 5 | streams/aspects · aspects | `Stream::Aspect#aspect_ids` | `aspects.map(&:id)` | no | `aspects` | SymbolicList of ids |
| 6 | streams · streams_followed_tags | `Stream::FollowedTag#tag_ids` (followed_tag.rb:29) | `tags.map{x\|x.id}` | no — but `tags`→`user.followed_tags` | `tags` / `followed_tags` | SymbolicList of ids |
| 7 | streams · streams_multi | `Stream::Multi#publisher_prefill` (multi.rb:43) | `followed_tags.map{...}` + `invited_by.try(:person)` | `.try(:person)` may load assoc | `followed_tags` + `invited_by` | String (prefill) |
| 8 | streams · streams_multi | same `publisher_prefill` | same | same | `followed_tags` + `invited_by` | String |
| 9 | streams · streams_public | `stream_responder` json (streams_controller.rb:70) | `stream_posts.map{Presenter.new(p)}` | decorator may query | `stream_posts` | SymbolicList |
| 10 | people · people_stream | `people#stream` json (people_controller.rb:97) | `stream_posts.map{...Decorator}` | decorator queries | `stream_posts` | SymbolicList |
| 11 | people · people_index | `hashes_for_people` (people_controller.rb:151) | `people.map{...}` + `contact_for(person)` | `contact_for` DOES query | `contact_for` | SymbolicList of hashes |
| 12 | notifications_tags · tags_index | `prep_tags_for_javascript` (tags_controller.rb:69) | `@tags.map{...}; uniq!` | no — pure transform | `@tags` | SymbolicList |
| 13 | notifications_tags · tags_index | same `prep_tags_for_javascript` | same | no | `@tags` | SymbolicList |
| 14 | likes · likes_index | `acts_as_api` collection (gem) | gem iterates collection | gem wrapper | the relation `records`/`to_a` | SymbolicList |

**Selection rule (per D7):** if the enclosing method's real body would issue SQL
(rows 1–3, 10, 11), mock the INNER association that provides the data
(`user.blocks`, `contact_for`, `stream_posts`). If the body is a pure transform
(rows 4–6, 12–13), mock the collection producer (`aspects`, `tags`, `@tags`).
This keeps every mock SQL-free (D7) and on a producer that returns a `SymbolicList`
carrying a rep (D8).

### 8.4 Phase 4 — declare the call-site mocks (all via `interceptor.declare_target`)

In `reports/diaspora/concolic_targets.rb` (the legit target layer — D8), add a
target for each producer from 8.3. They should look EXACTLY like the existing
finder/association targets — regular symbolic returns, no monkey-patching.

Pattern (association readers returning a SymbolicList with a rep):
```ruby
# user.blocks -> SymbolicList of symbolic person_ids (a Block object rep)
interceptor.declare_target(User, :blocks, returns: lambda do |_r, _a, name|
  rep = symbolic_instance(Block, person_id: symint("#{name}_person", 1))
  symlist(name, 1, representative: rep).tap { |l| register_list_of(l, rep) }
end)
```
Pattern (plain transform helper, mock the method that returns the derived ids):
```ruby
# aspects.map(&:id) -> supplied symbolically; no each runs
interceptor.declare_target(Stream::Aspect, :aspect_ids, returns: lambda do |_r, _a, name|
  symlist(name, 1)   # ids are just a length; per-element access via rep if needed
end)
```
Adjust per row of 8.3. When in doubt, mock the collection/association producer
(most reusable, clearly SQL-free). Wire `representative:` wherever a caller
reads attributes off the rep (`person_id`, `id`, `name`).

### 8.5 Phase 5 — run each affected batch and close the coverage loop

The canonical how-to-launch instructions already live in
**`reports/diaspora/README.md`** — see its **Workflow**, **Usage (verified
working ...)**, **Coverage loop (verified)**, and **Output structure (per
batch)** sections, plus `scripts/diaspora-concolic <runner.rb>` for the exact
launch command. Follow those for the mechanics. This section only adds what
is Gate-1b-specific:
1. Update `results/{batch}/run_concolic.rb` per the README pattern (load app +
   runtime + `ConcolicTargets.install!`; map each entrypoint to
   `CallInterceptor.instance.run(...)`; write `dump_{label}.json`; close the
   coverage loop via `ConcolicTargets.seed_overrides` ← CoverageChecker
   suggestions; write `coverage_summary.json`).
2. Wire the new producer targets from 8.3/8.4 into the runner (or rely on
   `ConcolicTargets.install!` if they're declared there in 8.4).
3. Launch: `/home/dev/project/scripts/diaspora-concolic results/{batch}/run_concolic.rb`
4. Verify each dump: `symbolic_call` events (query interceptions with real SQL
   in `note`) and `path_condition` events for entrypoints that branch. A dump
   with an `error` key means the run crashed (report it honestly — do NOT
   drop, per README).
5. Re-run until complete (or no new CoverageChecker suggestions). Purge stale
   append-only round dumps so each entrypoint reflects only its newest runs
   (see STATUS.md hygiene note).

Affected batches from 8.3: `streams`, `people`, `notifications_tags`, `likes`.

### 8.6 Phase 6 — verify & report

- Run the engine coverage check per the README's **Coverage loop (verified)**
  snippet (the `CoverageChecker` on the parsed dumps). Don't re-copy it here.
- For each affected entrypoint record honestly: PCs covered, remaining crashes,
  and the §5 limits (one rep row; `each` runs once; distinct-row branching not
  modeled). Update `STATUS.md` with the new numbers.
- Confirm the audience rule: entrypoints are "controller-action-level"; reports
  must state the honest limits, never over-claim N-row coverage.

### 8.7 Definition of done

The 4 affected batches' entrypoints move off the `each`/`first` crash wall:
- No `SymbolicList#each`/`#first` crash in those dumps.
- Each call-site from 8.3 has a `declare_target` on its SQL-free producer.
- `each`/`map`/`reject`/`select` still raise on the list (unchanged contract).
- Both runtimes in parity; mirror tests pass.
- STATUS.md + reports updated with honest numbers & limits.

### 8.8 Open items / gates still to close (for the continuing agent)

- **Gate 2 (coercion):** policy for `to_i`/`to_s`/`-@`/`+` (§3.5) — still open.
- **Gate 3 (engine):** `len()` var-decl + vacuous flag (§3.7/3.11).
- **Gate 4 (env):** reports/roles tables + Redis (§3.10).
- **AUDIT (hash-membership):** after call-site mocks land, verify no set/hash
  membership branch of a symbolic value goes unrecorded (see `src/TODO.txt`).
