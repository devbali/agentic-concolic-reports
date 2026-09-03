# PHASE_A_PATCH — note-fidelity reference for results3

Reusable reference for results3's "(a) Note fidelity" upgrade (see
`results3/README.md`). Originally implemented and validated against a live
smoke run in results2, then **reverted from results2** per Bali's
correction — results2 is a frozen record; all mock-file changes belong here.
Every results3 endpoint dir applies these patches to **its own copy** of
`concolic_targets.rb`/`targets.rb`; do not point back at results2.

Each patch below is a straight old-text → new-text replacement against the
results2-lineage `concolic_targets.rb` (the fixed collect_binds version —
see results2/README.md "Known fix to carry forward" — is assumed already
present; these patches are independent of it and apply the same either way).

---

## Patch 1 — `SingularAssociation#find_target` real SQL note

**Where:** the shared `concolic_targets.rb`, section `W3` (`# W3.
SingularAssociation#find_target -> symbolic instance.`).

**Problem:** the mock's note was the fixed junk string
`"SingularAssociation#{refl.name}"`, not the SQL it stands in for.

**Old text:**

```ruby
    if defined?(ActiveRecord::Associations::SingularAssociation)
      interceptor.declare_target(
        ActiveRecord::Associations::SingularAssociation, :find_target,
        returns: lambda do |receiver, _args, _name|
          begin
            refl = receiver.reflection
            klass = refl.klass
            if klass && klass.respond_to?(:allocate)
              symbolic_instance(klass, "assoc_#{refl.name}",
                                "SingularAssociation##{refl.name}")
            else
              nil
            end
          rescue StandardError
            nil
          end
        end
      )
    end
```

**New text:**

```ruby
    if defined?(ActiveRecord::Associations::SingularAssociation)
      interceptor.declare_target(
        ActiveRecord::Associations::SingularAssociation, :find_target,
        returns: lambda do |receiver, _args, _name|
          begin
            refl = receiver.reflection
            klass = refl.klass
            if klass && klass.respond_to?(:allocate)
              # Phase A (MOCK_FIDELITY): render the real SQL find_target stands
              # in for, derived from association.reflection (target table + FK +
              # owner key), instead of the junk "SingularAssociation#name" note.
              # belongs_to: FK column lives on the OWNER, target queried by its
              # own primary key. has_one: FK column lives on the TARGET table,
              # queried by the owner's primary key. Never let note-building
              # itself crash the mock (mirrors sql_for's own rescue-wraps-all
              # philosophy) -- fall back to the old junk note on any failure.
              sql = begin
                owner = receiver.owner
                table = klass.table_name
                if refl.belongs_to?
                  col = refl.association_primary_key(klass)
                  fk_raw = owner[refl.foreign_key]
                else
                  col = refl.foreign_key
                  fk_raw = owner[refl.active_record_primary_key]
                end
                %(SELECT "#{table}".* FROM "#{table}" WHERE "#{table}"."#{col}" = #{render_arg_value(fk_raw)})
              rescue StandardError
                "SingularAssociation##{refl.name}"
              end
              symbolic_instance(klass, "assoc_#{refl.name}", sql)
            else
              nil
            end
          rescue StandardError
            nil
          end
        end
      )
    end
```

**Why this derivation:** `refl.belongs_to?` / `refl.foreign_key` /
`refl.association_primary_key(klass)` / `refl.active_record_primary_key` are
all real `ActiveRecord::Reflection::AssociationReflection` methods
(activerecord-5.2.4.3 `lib/active_record/reflection.rb`). For `belongs_to`
the FK column lives on the *owner* and the target is queried by its own PK;
for `has_one` the FK column lives on the *target* table and is queried by
the owner's PK. `owner[...]` works whether `owner` is a `symbolic_instance`
(its `[]` reads the concolic attrs hash — this is the overwhelmingly common
case here, since the concolic SQLite DB's tables are empty) or a real AR
record.

### Patch 1b — polymorphic variant (`BelongsToPolymorphicAssociation#find_target`)

Apply **only** to endpoints that declare a batch-local override on
`ActiveRecord::Associations::BelongsToPolymorphicAssociation` (results2 had
this in `comments_index/targets.rb` only, for `Comment#commentable`). If
your endpoint's `targets.rb` doesn't touch `BelongsToPolymorphicAssociation`,
skip this sub-patch — Patch 1 alone (on the base `SingularAssociation`)
already covers ordinary (non-polymorphic) `belongs_to`/`has_one`.

**Old text** (in the batch-local `targets.rb`):

```ruby
      interceptor.declare_target(btpa, :find_target, returns: lambda do |receiver, _args, _name|
        nm = receiver.reflection.name
        ct.symbolic_instance(
          poly_klass(receiver), "assoc_#{nm}",
          "BelongsToPolymorphicAssociation##{nm} (polymorphic target load)"
        )
      end)
```

**New text:**

```ruby
      interceptor.declare_target(btpa, :find_target, returns: lambda do |receiver, _args, _name|
        nm = receiver.reflection.name
        klass = poly_klass(receiver)
        # Phase A (MOCK_FIDELITY item 1, polymorphic belongs_to variant):
        # render the real SQL this stands in for (FK column lives on the
        # OWNER for belongs_to; target queried by its own PK) instead of the
        # junk "BelongsToPolymorphicAssociation#name" note. Never let
        # note-building crash the mock.
        sql = begin
          table = klass.table_name
          pk = klass.primary_key
          fk_raw = receiver.owner[receiver.reflection.foreign_key]
          %(SELECT "#{table}".* FROM "#{table}" WHERE "#{table}"."#{pk}" = #{ct.render_arg_value(fk_raw)})
        rescue StandardError
          "BelongsToPolymorphicAssociation##{nm} (polymorphic target load)"
        end
        ct.symbolic_instance(klass, "assoc_#{nm}", sql)
      end)
```

(`ct` = `ConcolicTargets`, per that file's `install!` preamble; `poly_klass`
is the batch-local helper that resolves the polymorphic type string to a
`Class`, unchanged from results2.)

**Smoke-run proof (comments_index, 6-run exploration, 0 errors), quoted
verbatim from the dump events before revert:**

Base (non-polymorphic) `find_target`, `belongs_to :author`:

```
"note": "SELECT \"people\".* FROM \"people\" WHERE \"people\".\"id\" = $$(SYM_RESULT_ActiveRecord__Relation_records_1_row_author_id)"
```

`has_one :profile` (FK on the target table):

```
"note": "SELECT \"profiles\".* FROM \"profiles\" WHERE \"profiles\".\"person_id\" = $$(assoc_author_id)"
```

Both replaced the old junk notes (`"SingularAssociation#author"` /
`"SingularAssociation#profile"`) with real, bind-traceable SQL. Zero errors
across all 6 runs in the smoke exploration — the fix does not destabilize
anything downstream.

---

## Patch 2 — class-level dynamic finders (`sql_for`'s `(class-level finder)` fallback)

**Where:** the shared `concolic_targets.rb`, top of `sql_for`.

**Problem:** every class-level finder note (`Model.find_by(...)`,
`find_by_username`/friends via Rails' `DynamicMatchers#define`, which
compiles `find_by_username(x)` into a real method calling
`find_by(username: x)` — see activerecord
`lib/active_record/dynamic_matchers.rb`) rendered as `args=nil`. Verified
against **every** class-level-finder note across the entire results2 corpus
(44/44 occurrences) — 100% broken, zero information.

**Root cause (do not attempt to fix beyond this patch — it lives in
`src/ruby_runtime/call_interceptor.rb`, off-limits):**
`declare_target`'s param-binding loop matches captured call args by the
*original* method's `*rest` parameter NAME (e.g. `:args` for
`find_by(*args)`). A keyword-syntax call (`find_by(username: x)`) is bound by
Ruby into `**kwargs`, not `*splat_args` (verified empirically: `def m(*a,
**kw); end; m(username: "x")` binds `kw`, not `a`, on this Ruby). The binding
loop then does `kwargs[name]` i.e. `kwargs[:args]`, which is never present —
so `call_args["args"]` is always `nil` for this call style, which is this
app's exclusive style for `find_by`. Separately, `to_native()` in
`symbolic_func.rb` unwraps `SymbolicInt`/`String`/`Bool` to their concrete
`.value` before any mock ever sees them — so even where args ARE captured
(`Model.find(id)`, or a `find_by` call passing an explicit Hash
*positionally* — `find_by({...})`, which Ruby does NOT route through
`**kwargs`, and whose nested Hash values `to_native` does not touch) the
rendered bind is a concrete literal, never `$$(SYM)`. This patch renders real
SQL where data survives and an honest, clearly-labeled fallback where it
doesn't — it does not and cannot recover kwargs-style call data without a
`src/` change.

**Old text:**

```ruby
  def sql_for(receiver, args)
    if receiver.is_a?(Class)
      return "#{receiver.name} query (class-level finder), args=#{render_args(args)}"
    end
    render_relation_sql(receiver)
  rescue Exception => e # rubocop:disable Lint/RescueException
```

**New text:**

```ruby
  def sql_for(receiver, args)
    return class_finder_sql(receiver, args) if receiver.is_a?(Class)
    render_relation_sql(receiver)
  rescue Exception => e # rubocop:disable Lint/RescueException
```

**Then**, immediately after the existing `render_arg_value` method (so the
helpers are defined before any lambda that closes over `self` calls them),
insert two new methods. Old text to anchor on:

```ruby
  def render_arg_value(v)
    if v.respond_to?(:sym_name) && v.sym_name
      "$$(#{v.sym_name})"
    elsif v.respond_to?(:value)
      v.value.inspect
    else
      v.inspect
    end
  end
```

**New text** (keep the above `render_arg_value` body byte-identical, append
directly after its closing `end`):

```ruby
  def render_arg_value(v)
    if v.respond_to?(:sym_name) && v.sym_name
      "$$(#{v.sym_name})"
    elsif v.respond_to?(:value)
      v.value.inspect
    else
      v.inspect
    end
  end

  # Phase A (MOCK_FIDELITY): render REAL SQL for class-level finders
  # (Model.find(id), Model.find_by(...), and dynamic finders like
  # find_by_username -- Rails' DynamicMatchers#define compiles
  # `find_by_username(x)` into a real method that calls `find_by(username: x)`,
  # see activerecord .../dynamic_matchers.rb -- so one fix here covers all of
  # them). Previously this branch printed a useless "args=..." string for
  # every call.
  #
  # KNOWN, UNFIXABLE-HERE GAP (src/ruby_runtime/call_interceptor.rb, out of
  # scope -- raise to Bali, do not patch src/ from results3): declare_target's
  # param-binding loop matches captured call args by the ORIGINAL method's
  # *rest parameter NAME (e.g. `:args` for `find_by(*args)`). Ruby routes a
  # keyword-syntax call (`find_by(username: x)`) into **kwargs, not
  # *splat_args (verified empirically on this Ruby's arg-binding semantics --
  # `def m(*a, **kw); end; m(username: "x")` binds kw, not a). The binding loop
  # then does `kwargs[name]` i.e. `kwargs[:args]`, which is never present, so
  # `call_args["args"]` is always nil for this (the app's actual and apparently
  # exclusive) call style. Verified against every dump in results2 as of this
  # audit: 44/44 class-level find_by notes read "args=nil" -- 100% broken.
  # Separately, to_native() in symbolic_func.rb unwraps SymbolicInt/String/Bool
  # to their concrete .value before the mock ever sees them, so even where args
  # ARE captured (Model.find(id), or a find_by call passing an explicit Hash
  # POSITIONALLY -- `find_by({...})`, which Ruby does NOT route through
  # **kwargs and whose nested values to_native does not touch) the rendered
  # bind is a concrete literal, never a $$(SYM) -- matching sql_for's own
  # documented convention ("concrete literals otherwise") since the symbolic
  # identity of a top-level scalar arg is genuinely gone by the time it reaches
  # this mock. When no usable WHERE data survives at all, say so honestly
  # instead of printing a blank args=nil that looks like real information.
  def class_finder_sql(klass, args)
    table = klass.respond_to?(:table_name) ? klass.table_name : klass.name
    where_hash = extract_finder_where(klass, args)
    if where_hash && !where_hash.empty?
      conditions = where_hash.map { |k, v| %("#{table}"."#{k}" = #{render_arg_value(v)}) }.join(" AND ")
      %(SELECT "#{table}".* FROM "#{table}" WHERE #{conditions})
    else
      "#{klass.name} query (class-level finder; WHERE unavailable -- interceptor " \
      "drops kwargs for *rest-signature finder methods called with keyword " \
      "syntax, see call_interceptor.rb param binding), args=#{render_args(args)}"
    end
  end

  # Best-effort recovery of a {column => value} condition hash from whatever
  # declare_target's param-binding actually captured. Returns nil (never {})
  # when nothing usable was found, so the caller can render the honest
  # fallback rather than claiming an (empty) WHERE.
  def extract_finder_where(klass, args)
    return nil unless args.is_a?(Hash)
    args.each_value do |v|
      return v.map { |k, vv| [k.to_s, vv] }.to_h if v.is_a?(Hash) && !v.empty?
    end
    pk = klass.respond_to?(:primary_key) ? klass.primary_key : "id"
    args.each_value do |v|
      next if v.nil?
      return { pk => v }
    end
    nil
  end
```

**Expected observable effect:** any endpoint whose app code calls a
class-level `find_by`/`find_by!`/dynamic finder (`find_by_username`,
`find_by_diaspora_handle`, ...) will render a labeled, honest fallback note
(not fixed by this patch alone — needs the `src/` gap closed) *unless* app
code happens to call with a positional Hash or a bare `Model.find(id)`, in
which case real SQL renders. Do not expect `$$()` binds to appear for
class-level finders in practice given this app's call style — that is the
documented, honest limit, not a bug in this patch.

---

## Patch 3 — `User#blocks` real SQL note

**Where:** the shared `concolic_targets.rb`, Gate-1b section (`# user.blocks
-> SymbolicList of Block reps`).

**Old text:**

```ruby
    interceptor.declare_target(User, :blocks, returns: lambda do |receiver, args, name|
      rep = symbolic_instance(Block, "#{name}_block", "User#blocks")
      symlist(name, 1, representative: rep, note: "User#blocks")
    end)
```

**New text:**

```ruby
    interceptor.declare_target(User, :blocks, returns: lambda do |receiver, args, name|
      # Phase A (MOCK_FIDELITY): render the real SQL this stands in for
      # (Block belongs_to :user, default FK "user_id") instead of the junk
      # "User#blocks" note. Never let note-building crash the mock.
      sql = begin
        owner_id = receiver.respond_to?(:[]) ? receiver[:id] : receiver.id
        %(SELECT "blocks".* FROM "blocks" WHERE "blocks"."user_id" = #{render_arg_value(owner_id)})
      rescue StandardError
        "User#blocks"
      end
      rep = symbolic_instance(Block, "#{name}_block", sql)
      symlist(name, 1, representative: rep, note: sql)
    end)
```

**Note for results3:** `MOCK_AUDIT.md` also flags `Post.blocked_people`
(the mock immediately below `User#blocks` in the shared file) as a
VIOLATION — its real body (`app/models/post.rb:105`) calls `user.blocks`
directly, so the outer mock prevents this patch's fixed note from ever
firing along that path. Per `results3/README.md`'s "(b) No mock over SQL
potential," the correct results3 treatment is to **remove**
`Post.blocked_people`'s `declare_target` entirely (not just fix its note) so
it falls through to the real `.map` over the now-correctly-noted
`User#blocks` mock. That removal is a Phase B *descent*, not part of this
note-fidelity patch — do it as part of your endpoint's leaf-audit pass, not
by copying this patch alone.

---

## Patch 4 — Collection-association reads via `CollectionProxy`

**Where:** batch-local `targets.rb`, wherever the design-#4 collection
materialization mock (`%i[to_a to_ary records].each { declare_target(rel,
m, ...) }`) is declared.

**Problem:** `ActiveRecord::Associations::CollectionProxy` (a `Relation`
subclass) overrides `records` itself
(`activerecord-5.2.4.3/lib/active_record/associations/collection_proxy.rb:1003`,
`def records; load_target; end` → `@association.load_target`). A target
declared only on `ActiveRecord::Relation` therefore **never fires** for a
bare collection-association read (`post.comments`, `user.aspects`,
`person.posts`, ...) — it runs the real, unmocked load path against a
symbolic owner id (an eventual wall or silent bypass), and any
`.each`/`.map` on the result skips the query-note machinery entirely. This
was found and fixed in results2/posts_show's `targets.rb`; this patch ports
that fix's pattern.

**Generic form** — extract whatever your endpoint's existing
`%i[to_a to_ary records].each { interceptor.declare_target(rel, m, returns:
lambda do |receiver, args, name| ... end) }` block already does into a named
`rows_mock` lambda, then declare it a second time on `CollectionProxy`:

```ruby
    rel    = ActiveRecord::Relation
    cproxy = defined?(ActiveRecord::Associations::CollectionProxy) ? ActiveRecord::Associations::CollectionProxy : nil

    rows_mock = lambda do |receiver, args, name|
      # ... your endpoint's existing to_a/to_ary/records body, UNCHANGED ...
    end

    %i[to_a to_ary records].each do |m|
      interceptor.declare_target(rel, m, returns: rows_mock)
    end

    # Phase A (MOCK_FIDELITY item 2): collection-ASSOCIATION reads
    # (`post.comments`, `user.contacts`, ...) go through
    # `ActiveRecord::Associations::CollectionProxy`, which OVERRIDES
    # `Relation#records` with its OWN `records` (-> `load_target` ->
    # `@association.load_target`) — collection_proxy.rb:1003. A target
    # declared only on `ActiveRecord::Relation` therefore never fires for a
    # collection association load. Declaring the identical rows_mock on
    # CollectionProxy makes association reads a RECORDED symbolic query with
    # real rendered SQL, same as a plain Relation read.
    if cproxy
      %i[to_a to_ary records load_target].each do |m|
        next unless cproxy.method_defined?(m) || cproxy.private_method_defined?(m)
        interceptor.declare_target(cproxy, m, returns: rows_mock)
      end
    end
```

**Per-endpoint applicability — verified against real controller/model
source, do NOT apply blindly:**

| endpoint | needs this patch? | why |
|---|---|---|
| posts_show | already has it (origin of the pattern) | `PostInteractionPresenter#as_api` / association reads hit bare `CollectionProxy` |
| comments_index | **yes** | `CommentService#find_for_post` calls `post_service.find!(post_id).comments.for_a_stream` — `.comments` is a bare `CollectionProxy`; `for_a_stream`'s `including_author.merge(order(...))` chain preserves or downgrades it depending on path (both cases are safe: if it stays `CollectionProxy` this patch fires; if it downgrades to `Relation` the existing mock already covers it — confirmed inert-but-harmless via a comments_index smoke run: `for_a_stream` resolved to a plain `Relation` in the exercised path, so the `CollectionProxy` addition did not fire there but is safe to keep for other call sites) |
| people_show | **yes** | verified via `people_controller.rb`/model associations that a bare collection-association read is reachable |
| people_stream | **yes** | same — stream rendering reads person/post associations directly |
| notifications_index | **no** — do not add | verified in `notifications_controller.rb`: the only collection reads are `Notification.where(...)` (class-level `Relation`) and `current_user.unread_notifications` = `notifications.where(unread: true)`, which is an `AssociationRelation` (`activerecord/lib/active_record/association_relation.rb`) — confirmed this class does **not** override `records`, so the existing `Relation`-level mock already covers it |
| conversations_index | **no** — do not add | verified in `conversations_controller.rb#index`: `ConversationVisibility.includes(...)`/`Conversation.joins(...)` are class-level Relations, never a bare collection-association read on this entrypoint's own action |

Adding the `CollectionProxy` block when it's genuinely unneeded is harmless
(guarded by `defined?`/`respond_to?`, never fires) but adds untested surface
for no benefit — prefer verifying against your endpoint's actual call graph
first, per the table above, rather than porting reflexively.

---

## Order of application (independent, apply in any order)

Patches 1-3 touch disjoint regions of the shared `concolic_targets.rb` (W3
section, top of `sql_for`, right after `render_arg_value`, and the Gate-1b
`User#blocks` declaration) — apply all three to every results3 endpoint's
`concolic_targets.rb` copy. Patch 1b is comments_index-only (or any other
endpoint that separately mocks `BelongsToPolymorphicAssociation#find_target`
in its `targets.rb`). Patch 4 is per-endpoint per the applicability table —
verify against your endpoint's actual source before porting it.

After applying, `ruby -c` every touched file, and prefer validating with a
small `MAX_RUNS`/`TIME_BUDGET` exploration in a **scratch copy** (never the
live results3 corpus directory) before trusting the notes in a real run —
copy the endpoint dir to scratch, run there, inspect `dump_*.json` events for
`"note": "SELECT ..."` strings, then discard the scratch copy.
