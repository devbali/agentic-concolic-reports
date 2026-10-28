# The disagreement inventory

Every place where the sources behind this library disagree about the **same
target** — two declarations that differ, or one source declaring what another
deliberately does not — and what this lab ruled in each case. The machine-readable form is
[`inventory/conflicts.json`](inventory/conflicts.json); this file is the
argument.

Nothing here is resolved silently. Where this lab took a side, the ruling and
its evidence are written down; where it did not, the row says so and names what
is blocking. That discipline is the whole point of the file: the single
app-wide targets file this library replaced
(`reports/diaspora/concolic_targets.rb`) was retired on 2026-09-25 because
per-endpoint ownership had won — different endpoints legitimately mock the same
method differently, and one flat file could not hold both answers. A merge that
silently picked a winner per target would recreate that failure exactly.

## The layers, and the sources they came from

Everything below is a disagreement between two of these. The short labels are
used throughout; the paths are citations you may follow, not reading you need
to have done.

| label | what it is | where it lives |
|---|---|---|
| **the core** | the shared declarations every endpoint installs first: 87 by the probe's maximal count, 86 in a booted app (one guarded site is dormant — see the README), from 59 `declare_target` sites | `targets/core.rb` — copied verbatim from `reports/diaspora/results4/aspect_memberships_create/concolic_targets.rb`, byte-identical to the `comments_index` copy |
| **an endpoint layer** | one endpoint's own declarations, installed after the core and winning ties. Two exist, `aspect_memberships_create` and `comments_index`; both are closed, with dumps recorded against exactly these declarations. (The hand-run experiment that produced them calls such a layer a *batch*, and quotations below use that word.) | `targets/endpoints/<endpoint>.rb` — from `reports/diaspora/results4/<endpoint>/targets.rb` |
| **the prior corpus** | six older endpoint configurations — `comments_index`, `conversations_index`, `notifications_index`, `people_show`, `people_stream`, `posts_show` — carrying 670 declarations between them, **not one of which states a `kind:` or a `type:`**. Mined here for target names only; nothing from it is shipped as a declaration | `reports/diaspora/results3/*/` |
| **the retired master** | the single app-wide targets file described above, and its `_RETIRED.md` | `_trash/diaspora_shared_concolic_targets_20260925/` |

The app under test is diaspora, and every mock in this library is a mock of
diaspora's code; that is what the library currently contains, not what this
document is about.

**How the numbers were obtained.** Every count below was measured by running
the real `install!` against the real `CallInterceptor` from `src_new`
(`tools/declaration_probe.rb`) and reading back what the interceptor holds —
not by parsing source. That distinction is load-bearing: 29 of the 142
`declare_target` sites in the four source files (the core, counted once in each
of the two endpoint directories it was copied from, plus each endpoint's own
file) sit inside a loop over a variable method list
(`%i[find take! first!].each { |m| declare_target(fm, m, ...) }`), so neither
the receiver nor the method is resolvable from the call site. A manifest built
by parsing omits every declaration those 29 sites expand into. The core's 59
sites make **87** declarations — the probe's maximal count. A booted app installs **86**; the one difference is named in the README under *Two counts*, and every count in this file is the maximal one.

| class | what it is | count |
|---|---|---|
| **C1** contract disagreement | two declarations give one target a different `kind:` or `type:` | 2 |
| **C2** body override | an endpoint layer redeclares a core target with the *same* contract and a different body | 27 |
| **C3** parallel invention | both endpoint layers invented the same target independently | 1 |
| **C4** deliberately removed from the core | the shared core of the prior corpus declared it and the core here does not; six of the seven removals have their rationale written into the core file itself | 7 |
| **C5** named by a lower-trust source, not adopted | only the prior corpus declares it — with no `kind:`, no `type:` and no run behind it — and this library declares it nowhere | 34 |

The corresponding keys in `conflicts.json` are `C1_contract`,
`C2_body_override`, `C3_parallel_invention`, `C4_demoted_from_shared_core` and
`C5_unmigrated`.

---

## C1 — contract disagreements (2)

The only two places in this library where one target carries two different
`(kind, type)` pairs. **Both turned out to be correct on both sides.**

### `ActiveRecord::FinderMethods#exists?` — `bool` vs `bool?`

| source | kind | type | at |
|---|---|---|---|
| core (`ConcolicTargets`) | `target_function` | `bool` | `targets/core.rb:1504` |
| comments_index (`CommentsTargets`) | `target_function` | `bool` | `targets/endpoints/comments_index.rb:1505` |
| aspect_memberships_create (`AspectMembershipsTargets`) | `target_function` | **`bool?`** | `targets/endpoints/aspect_memberships_create.rb:288` |

**Ruling: both stand. Nothing is promoted and nothing is corrected.**

`type:` states what **the mock** returns, not what Rails returns. The runtime
enforces exactly that: `CallInterceptor.observation_fits?` counts "a null where
the declaration is not nullable" as a defect and raises `TypeMismatch`
(`src_new/runtimes/ruby_runtime/call_interceptor.rb:1007`).

* comments_index's body ends `ex == true` — a bare Ruby `true`/`false`, never
  `nil`. `bool` is exactly right.
* aspect_memberships_create's body ends `(ex == true) ? true : nil`. It **must**
  be `bool?`; declaring `bool` there would raise `TypeMismatch` on the first
  negative arm.

It returns `nil` rather than `false` for a measured reason, written up in that
endpoint's own file at
`targets/endpoints/aspect_memberships_create.rb:264`: `to_symbolic(false)`
is `SymbolicBool.new(false)` (`symbolic_func.rb:815-817`) — a Ruby **object**,
therefore **truthy** — so

```ruby
return if blocks.where(person_id: person.id).exists?   # connecting.rb:14
```

returned unconditionally. Measured, not inferred: that endpoint's
`dump_auth_json_dse0001.json` reached the 409 arm on every run, with no
`contacts` SELECT and no write. `to_symbolic(nil)` is the one native that passes
through unchanged, so `nil` is the only falsy value a mock can hand back.

> **A separate finding, and explicitly not a ruling, because I did not verify
> it.** comments_index's mock returns a bare `false` on its negative arm, and by
> the same runtime rule that `false` is re-wrapped into a truthy
> `SymbolicBool`. Whether it bites depends on whether any comments_index call
> site tests `exists?` with bare truthiness rather than an explicit compare. **I
> did not check its call sites.** If one does, comments_index has the defect
> aspect_memberships_create measured and fixed.

An earlier reading of this conflict — *"Rails' `exists?` never returns nil, so
`bool?` is the sloppy one"* — treats `type:` as a fact about Rails. It is a fact
about the mock.

### `User#blocks` — `target_function` vs `shim`

| source | kind | type | at |
|---|---|---|---|
| core | **`target_function`** | `[?]` | `targets/core.rb:1740` |
| aspect_memberships_create | **`shim`** | `[?]` | `targets/endpoints/aspect_memberships_create.rb:319` |

**Ruling: both stand.** The `kind` difference is a *consequence* of a body
difference, not a disagreement about the method.

* The core mock **returns** a `SymbolicList` standing in for the blocks query.
  Its call **is** the access → `TARGET_FUNCTION`.
* aspect_memberships_create restores the **real** association reader
  (`receiver.association(:blocks).reader`), because `share_with` chains
  `blocks.where(person_id:).exists?` and `SymbolicList#where` is a
  `NoMethodError` that kills the run before the write. The real relation then
  issues its SELECT downstream at the `exists?` target, so this call is no longer
  an access — and per DESIGN_IR §4.1.1f change 9, a call that is not itself an
  access is a `SHIM`.

That is strictly **more** evidence, not less: the endpoint gets a genuine
`SELECT 1 AS one FROM "blocks" … LIMIT 1` instead of the core's hand-rolled
`SELECT "blocks".*` note.

This is the one place in the library where a `kind:` flips between layers, and
it is the clearest demonstration available that **kind is a property of the
mock, not of the method**.

---

## C2 — body overrides (27: 18 in aspect_memberships_create, 9 in comments_index)

An endpoint layer redeclares a core target with the **same** `kind` and `type`
and a different mock body. Every one is a **note-shape** refinement: the layer
renders the SQL statement its endpoint's evidence needs — a faithful single-row
finder statement, a DML statement instead of a description — while agreeing with
the core about the contract.

| endpoint layer | targets |
|---|---|
| aspect_memberships_create | the 7 `FinderMethods` finders, the 8 `ActiveRecord::Base` persistence methods, `Relation#update_all`, `Relation#delete_all`, `Querying#find_by_sql` |
| comments_index | `Relation#to_a`/`#to_ary`/`#records`, 4 `FinderMethods` finders, `FinderMethods#exists?`, `SingularAssociation#find_target` |

**Ruling: the core keeps its declaration and the endpoint layer keeps its body.
Not promoted.** The library says why in its own words, at
`targets/endpoints/aspect_memberships_create.rb:61` — the note helpers were

> "Kept batch-local rather than pushed into the shared config: the shared copy is
> app-wide (Rule T) and a note-shape change there restarts every endpoint."

Two endpoints are closed against the current shapes.

### This is where the ruling and Rule T pull against each other

All 27 of these are **target functions**, so the kind-axis ruling says *core*.
Rule T — the rule quoted just above, that a shared file is app-wide, so changing
it restarts every endpoint already closed against it — says a shared note-shape
change costs two completed endpoints a re-run. **This lab did not resolve that**
— it is not a judgement a targets library can make on its own. It needs a
decision and, if the answer is "promote", a re-run budget attached.

It matters mechanically too, not just politically, because of **D5**:

> A second `declare_target` on the same `(class, method)` does not replace the
> first — `declare_target` installs via `define_method`, so it **wraps** it, and
> then reads `klass.instance_method(method).parameters` off the *first* mock's
> wrapper, whose signature is `|*splat_args, **kwargs, &block|`. Every named
> argument the second mock wanted comes back `nil`.

Measured on a bare runtime and written up at
`targets/endpoints/aspect_memberships_create.rb:946`; the companion warning
that a **prepend** is the right tool for a second layer is at
`targets/core.rb:2053`. So these 27 rows are not free: each is a wrapped
declaration, and the one that needed real argument values
(`Querying#find_by_sql`) had to restore the original signature with
`define_method` first to work around D5.

Every double declaration is listed in `inventory/conflicts.json`, and
`Autolab::Targets.install!` reports them per run, so a sweep sees them rather
than meeting them in a dump.

---

## C3 — parallel invention (1)

`ActiveRecord::FinderMethods#devise_user_first` — an alias of `#first` that both
endpoint layers invented independently, routed from the one `.first` inside
`OrmAdapter::ActiveRecord#get`, so the Devise session lookup gets its own
symbolic variable name.

Both declare it `target_function` / `obj<?>`. **The contract agrees; the bodies
do not**: aspect_memberships_create returns a bare `"concolicsalt"` String from
the salt leaf, comments_index wraps the same string in `ConcreteSymbolicString`,
and each calls its own layer's `finder_note`.

**Ruling: not promoted, rated `core-eligible`.** Promoting means choosing one
body and changing the other endpoint's dumps. Two independently built endpoints
arriving at the same declaration without coordinating is the strongest evidence
of app-wideness available here, so this is the top of the promotion backlog —
but the body is the open question, not the contract.

---

## C4 — deliberately removed from the core (7)

The core's predecessor — the shared core of the prior corpus — declared these,
and the core shipped here does not. **Six of the seven have a written rationale
in the core file itself, and all six are the same argument**: the mock was
standing in front of the evidence.

| target | declared in the prior corpus by | status here | rationale |
|---|---|---|---|
| `ActionDispatch::Journey::Router::Utils.escape_segment` | people_show, people_stream, posts_show | now a plain prepend, not a target | `targets/core.rb:2683` — pure URL escaping, no data access; declaring it minted a junk note on **every** route generation |
| `ActsAsApi::Collection#as_api_response` | people_show, people_stream, posts_show | removed | `targets/core.rb:2241` — mocking the collection walk hid every **item**'s own `as_api_response`, which fetches declared targets |
| `Diaspora::Mentionable.people_from_string` | people_show, people_stream | removed | `targets/core.rb:2411` — its body reaches a real `find_by`, itself a declared target |
| `Diaspora::MessageRenderer::Processor.process` | people_show, posts_show | removed | `targets/core.rb:2527` — `diaspora_links` can reach `Post.exists?(guid:)`; mocking it is defect D1, "a mock may replace execution, never evidence" (`targets/core.rb:2459`) |
| `Person.name_from_attrs` | people_show | removed | `targets/core.rb:2434` — `Person#name` reads `self.profile`, a declared target, before reaching it |
| `Post.blocked_people` | notifications_index | removed | `targets/core.rb:1755` — its body calls `user.blocks` directly, so the outer mock prevented `User#blocks` from ever firing |
| `ActiveRecord::Associations::BelongsToPolymorphicAssociation#find_target` | notifications_index | **declared, but in the comments_index endpoint layer, not the core** | **none recorded, in either file** |

**The last row is the one open question in C4.** The prior corpus declared it in
a **shared** core; here it is carried only by
`targets/endpoints/comments_index.rb`. Nothing explains the move.
`partition.json` rates it `core-eligible` for exactly that reason.

---

## C5 — named by a lower-trust source, not adopted (34)

Target names the prior corpus declares and this library does not declare at all.
Full list in [`inventory/candidates.json`](inventory/candidates.json); by
family:

| family | n | declared in the prior corpus by | examples |
|---|---|---|---|
| per-call-site naming aliases | 12 | posts_show | `Relation#evilq_act_vis`, `Relation#findpublic_like` |
| per-call-site naming alias | 1 | conversations_index | `Relation#convidx_conv_lookup` |
| the C4 six, above | 6 | the shared core carried by one to three prior-corpus endpoints | `escape_segment`, `as_api_response`, … |
| display / attribute leaves | 9 | people_show, people_stream | `Person#first_name`, `Person#last_name`, `Person#name`, `Person#remote?`, `PersonPresenter#description`, `Service#nickname`, `Service#provider`, `ActsAsTaggableOn::Tag#name`, `PeopleController#diaspora_id?` |
| ActiveRecord surface no endpoint here ever needed | 4 | conversations_index, notifications_index, people_show, people_stream, posts_show | `Base#to_param`, `Base#update_column`, `Base#update_columns`, `CollectionProxy#size` |
| other | 2 | notifications_index, conversations_index | `Person#fix_profile`, `DiasporaFederation::Discovery::Discovery.new` |

The 13 naming aliases are structurally local (see `partition.json`'s
`call_site_naming_aliases`) and would never be promoted. The 9 display leaves
are the same family the core removed on purpose in C4 — `Person#name` in
particular is named there as an "audited, carried-over VIOLATION" that the core
then fixed by removal. The 4 ActiveRecord methods are the only rows here with a
plausible path into a future core.

**These are names, not declarations, and they are deliberately not shipped.**
The probe settles how much trust the prior corpus deserves: **670 of its 670
declarations carry neither `kind:` nor `type:`** — measured by running all six
of its endpoint configurations in lenient mode. There is no contract to inherit.
Adopting one means writing the declaration, defending its kind and type, and
putting it behind a real run.

Inventing a kind and a type for a mock nobody has run is precisely how the
retired master became unloadable without anyone noticing.
