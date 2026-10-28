# RC-1 replacement design — the lazy-column fetch as a *branch-dependent access*, not a synthesis-time constant

**Date:** 2026-09-25
**Status:** DESIGN ONLY. No production code written, no mock changed, nothing
under `src/` or `src_new/` touched, nothing committed.
**Supersedes (as a proposal, not yet as a decision):** the `default_projection(klass)`
half of `results3/queries_from_runs/_RAILS_ENV_MOD_FIX_20260919.md` §4, and its
§8.5 recommendation for notifications_index.
**Prompted by:** the user's proposal to make the lazy-column disclosure a
SYMBOLIC DECISION rather than a synthesis-time constant.

---

## 0. How to read this document

Every factual claim below is tagged:

- **[V]** — verified by me, this session, by reading the cited file at the cited
  lines, or by running a measurement whose command is shown.
- **[V-ref]** — verified by re-reading a prior write-up's citation and confirming
  it against the primary source.
- **[P]** — proposed; a design statement, not an observation.
- **[?]** — open question I could not close by reading, named deliberately.

Line numbers were re-derived this session, not copied. Where a previously
circulated citation was off, I say so.

**The one-paragraph summary.** The literal proposal — mint a fresh free
`SymbolicBool` for "does the lazy fetch fire" — is the wrong primitive, and I
argue that in §3: it would add decisions that are in truth *functions of state
the corpus already branches on*, producing infeasible gate combinations and an
over-permissive policy, while forfeiting the cheap branching-safety proof. The
user's underlying goal — the disclosure must be *derived and branch-dependent*
rather than a constant chosen at synthesis time — is achievable, and more
faithfully, by making Q2 a **derived** access whose gate is the application's
*already-symbolic* `show_profile_info` decision. That design is uniform across
all six endpoints, emits Q2 as its own statement with its own note and binds,
adds **zero** path conditions, and is therefore verifiable by exactly the
seed-exact replay the `default_projection` fix used. §4 is that design; §6 is
its soundness argument, including the one place it genuinely cannot lean on
replay.

---

## 1. The mechanism, re-verified from primary sources

### 1.1 The gem

`~/.gem/jruby/2.6.0/gems/lazy_columns-0.5.9/lib/lazy_columns/acts_as_lazy_column_loader.rb`
**[V]** (whole file is 39 lines; read in full):

```ruby
def exclude_columns_from_default_scope(columns)          # line 17
  default_scope { select((column_names - columns).map { |c| "#{table_name}.#{c}" }) }
end

def define_lazy_accessor_for(column)                     # line 24
  define_method column do
    unless has_attribute?(column)
      changes_before_reload = self.changes.clone
      self.reload
      changes_before_reload.each{|attribute_name, values| self.send("#{attribute_name}=", values[1])}
    end
    read_attribute column
  end
end
```

Four consequences that the design hangs on, all read straight off that code:

1. **Q1 narrowing is a `default_scope`** — it applies to every relation-derived
   read of the model. **[V]**
2. **Q2 is `ActiveRecord::Base#reload`**, i.e. `unscoped { find(id) }` — it
   bypasses the default scope and reads **all** columns. **[V]** (the `unscoped`
   fact is not in the gem; it is AR's own `reload`, and is already documented
   and relied on at `results3/notifications_index/targets.rb:1237-1240`
   **[V-ref]**).
3. **Q2 fires at most once per instance per request**: the guard is
   `unless has_attribute?(column)`, and one `reload` brings in *all* absent
   columns, so the second and subsequent lazy reads on the same instance issue
   nothing. **[V]** This is the mechanism's own answer to the
   per-column-vs-per-representative question (§4, D5).
4. **`lazy_load` is installed on the class, via `define_method`** (line 22/25),
   not on the instance. **[V]** That is what makes it losable to a singleton
   reader (§1.4).

### 1.2 The application's gate

`ruby_examples/dse-apps/apps/diaspora/app/models/profile.rb:7-10` **[V]**:

```ruby
class Profile < ApplicationRecord
  if Rails.env.include?("mod") || Rails.env == "test"
    lazy_load :bio, :gender, :birthday, :location
  end
```

The only in-scope reader of those four columns is
`ProfilePresenter#private_hash` (`app/presenters/profile_presenter.rb:27-33`)
**[V]**, which reads all four:

```ruby
def private_hash
  public_hash.merge(
    bio:      bio_message.plain_text_for_json,   # :29
    birthday: formatted_birthday,                # :30  -> birthday
    gender:   gender,                            # :31
    location: location_message.plain_text_for_json  # :32
  )
end
```

`public_hash` (`profile_presenter.rb:13-18`) and `for_hovercard`
(`:20-25`) read **none** of them. **[V]**

`private_hash` is reached from exactly one place:
`PersonPresenter#full_hash_with_profile`
(`app/presenters/person_presenter.rb:78-86`) **[V]**:

```ruby
def full_hash_with_profile
  attrs = full_hash
  if attrs[:show_profile_info]
    attrs.merge!(profile: ProfilePresenter.new(profile).private_hash)
  else
    attrs.merge!(profile: ProfilePresenter.new(profile).public_hash)
  end
  attrs
end
```

and the gate itself is `person_presenter.rb:18` **[V]**:

```ruby
show_profile_info: public_details? || own_profile? || person_is_following_current_user
```

with `own_profile?` at `:51` (`current_user.try(:person) == @presentable`) and
`person_is_following_current_user` at `:66` (`contact && contact.sharing?`)
**[V]**. `public_details?` is delegated `Person -> profile`
(`app/models/person.rb:27-29`) **[V]** — that same `delegate` line also carries
`:bio, :location, :gender, :birthday`, which is how `Person#bio` reaches the
lazy accessor at all.

**A second, distinct reader surface exists**, and prior write-ups did not treat
it as one: `PersonPresenter#description` (`person_presenter.rb:124-126`) **[V]**

```ruby
def description
  public_details? ? bio : ""
end
```

It is reached from `metas_attributes` (`person_presenter.rb:31-43`) **[V]** and
is gated on `public_details?` **alone** — a strictly weaker gate than
`show_profile_info`. Any design that only hooks `private_hash` will
under-model this surface. §4, D7.

### 1.3 The chain on notifications_index — citations re-checked

`_RAILS_ENV_MOD_FIX_20260919.md` §8.2's chain is correct; two of its line
numbers are slightly off and are corrected here.

| claim | write-up said | actually **[V]** |
|---|---|---|
| StartedSharing branch + `gon_load_contact` | `_notification.haml:6-9` | `app/views/notifications/_notification.haml:5-7` (branch at 5, `note.target.present?` at 6, `gon_load_contact(note.contact)` at 7) |
| JSON suppresses it | `notification_serializer.rb:14` | correct — `:14`, `locals: {note: object, no_aspect_dropdown: true}` |
| `gon_load_contact` | `gon_helper.rb:4-9` | correct |
| `full_hash_with_person` → `person_without_contact` | `contact_presenter.rb:16-24` | `:16` and `:22-24` — correct |
| `full_hash_with_profile` / gate | `person_presenter.rb:78-88` / `:18` | `:78-86` / `:18` |
| `private_hash` | `profile_presenter.rb:27-34` | `:27-33` |

I also confirmed `_notification.mobile.haml` never calls `gon_load_contact`
(`grep -rn 'gon_load_contact' app/` returns only `gon_helper.rb:4` and
`_notification.haml:7`) **[V]** — so on notifications_index, Q2 is
HTML-desktop-only, as §8.2 said.

### 1.4 Why the escape hatch is dead today

`results3/notifications_index/concolic_targets.rb:632` `def symbolic_instance`
**[V]** (the user's cite of 632-652 is right; the builder body runs to ~659)
iterates `klass.columns_hash` — *all* physical columns, with no awareness of
`default_scope` — and at `:645` does

```ruby
obj.define_singleton_method(col) { attrs[col] }
```

A singleton method always beats a class-level `define_method` in Ruby's MRO, so
`lazy_columns`' generated `bio`/`gender`/`birthday`/`location` readers are
**shadowed and never invoked**, and `self.reload` inside them never runs.
**[V]** — and this is not merely inferred: `results3/people_show/_probe_lazyfetch.rb`
is a purpose-built probe that asserts exactly this
(`p.singleton_methods.include?(:bio)` → "singleton SHADOWS the lazy accessor")
**[V]**.

This is the single structural fact that made people_show's RC-1 escape hatch
unreachable, and any design that does not address it fails there. §4, D4.

### 1.5 What `default_projection` actually switches on

`results3/people_show/concolic_targets.rb:236-246` **[V]**:

```ruby
def default_projection(klass)
  tbl = klass.respond_to?(:table_name) ? klass.table_name : nil
  star = tbl ? %("#{tbl}".*) : "*"
  return star unless klass.respond_to?(:all)
  sel = klass.all.select_values
  return star if sel.nil? || sel.empty?
  sel.map(&:to_s).join(", ")
rescue Exception
  tbl ? %("#{tbl}".*) : "*"
end
```

It reads `select_values`, which is non-empty **only** when the `default_scope`
exists, i.e. only under a `"mod"` env. So "implemented but not activated" on
people_show is precise and literal: the helper is wired at two sites
(`concolic_targets.rb:253` and `:1339` **[V]**) and returns the bare star
because people_show drives under `RAILS_ENV=concolic`
(`scripts/diaspora-concolic:17` `export RAILS_ENV=concolic`, still the default
**[V]**). **The env is the activation switch.** This matters for §6.3.

Applied sites today **[V]**: conversations_index
(`concolic_targets.rb:333`, `:1205`; `targets.rb:717`, `:729`, `:1794`, `:1840`),
people_stream (`concolic_targets.rb:237`, `:1283`), comments_index (per the
write-up; its sites are the same shape), people_show (2, inert),
notifications_index (**none**), posts_show (**none**).

---

## 2. A shape census of the reference — measured this session

The write-up's §8.1 numbers were derived for notifications_index only. I ran the
same census over all six answer keys, so the design can be judged endpoint by
endpoint. Command (statement = `;`-delimited; "projecting" = the SELECT list
mentions a `profiles` column; "wide" = the SELECT list contains any of
`bio|gender|birthday|location`):

```
cd /home/dev/project/policy-extraction-bench/data/answers/diaspora
python3 -c '<split on ";", regex the select list>'
```

| reference | distinct narrow `profiles` shapes | distinct wide shapes | total statements |
|---|---:|---:|---:|
| notifications-index | 17 | **2** | 71 |
| people-show | 2 | **3** | 30 |
| posts-show | 15 | 0 | 93 |
| people-stream | 42 | 0 | 168 |
| comments-index | 6 | 0 | 23 |
| conversations-index | 4 | 0 | 16 |

**[V]** (the answer keys at `policy-extraction-bench/data/answers/diaspora/` are
world-readable and are the graded artifact; the *other* reference,
`ruby_examples/dse-apps/policies/`, remains quarantined — I confirmed it is
still `Permission denied` and did not attempt to read it).

Two findings here are new, and both bear directly on the brief.

**(a) The wide shapes are literally the three disjuncts of `show_profile_info`.**
The gating WHERE clauses, printed verbatim **[V]**:

*people-show*, three wide shapes:
```
WHERE people.owner_id = _MY_UID  AND profiles.person_id = people.id AND people.closed_account = FALSE
WHERE profiles.public_details = TRUE AND profiles.person_id = people.id AND people.closed_account = FALSE
WHERE contacts.sharing = TRUE AND profiles.person_id = people.id AND contacts.user_id = _MY_UID
      AND contacts.person_id = people.id AND people.closed_account = FALSE
```
i.e. `own_profile?` / `public_details?` / `person_is_following_current_user` —
one wide statement per disjunct.

*notifications-index*, two wide shapes:
```
WHERE notifications.type = 'Notifications::StartedSharing'
  AND (contacts.sharing = TRUE AND profiles.person_id = notifications.target_id) AND (...)
WHERE notifications.type = 'Notifications::StartedSharing'
  AND (profiles.public_details = TRUE AND ...) AND (... AND contacts.sharing = FALSE)
```
i.e. the same disjunction, path-split (note the `contacts.sharing = FALSE`
conjunct in the `public_details` arm — that is the *else* edge of the first
disjunct, which is what a per-path PC fold of a short-circuiting `||` produces).
`own_profile?` is absent, which is exactly right: you do not receive a
StartedSharing notification about yourself.

This is strong evidence that the reference's wide statements are **not** a
projection width to be chosen, but a *second access recorded on the true side of
an existing decision*. A design that reproduces them by construction is
reproducing the application; a design that hand-builds them is guessing.

**(b) people_show's reference is 2 narrow + 3 wide, not uniformly wide.**
The standing record (README's people_show row; `_RAILS_ENV_MOD_FIX_20260919.md`
§8.5) describes people_show as the endpoint where narrowing is "a pure recall
loss" because "798/800 dumps read all four lazy columns". That statement is
about **our corpus**, and it is a correct reason to reject the
*narrowing-only* fix. It is **not** a statement that people_show's reference is
uniformly wide — it is not: it wants both shapes, and today we emit only the
wide one, so people_show is losing precision on its 2 narrow shapes right now,
by the same argument §8.4 makes for notifications_index (a set union over
`(table,column)` pairs saturates and hides it). **[V]** — I assert this from the
census above, not from the write-up.

Consequence: **people_show is not an exemption from this design. It is its
second beneficiary.**

**(c) The narrow-only endpoints are narrow-only because the gate is
unreachable, not because of a projection policy.** posts_show and comments_index
render people through `Person.as_api_response(:backbone)`
(`app/presenters/post_presenter.rb:63`, `app/presenters/comment_presenter.rb:13`)
**[V]**, whose accessible attribute list is `id, guid, name, diaspora_handle,
avatar` (`app/models/person.rb:12-24`) **[V]** — no lazy column, no
`PersonPresenter#full_hash_with_profile`. people_stream's own targets file says
it plainly: "`PersonPresenter` isn't reached by the `stream` action"
(`results3/people_stream/targets.rb:57`) **[V]**. Their references' zero wide
shapes are the *prediction* of the same mechanism, not a different policy.

That is the uniformity result, and I did not have to assume it: **one mechanism,
six endpoints, and the endpoints that should not emit Q2 do not emit it because
their control flow never reaches the gate.**

---

## 3. Why a *free* symbolic decision is the wrong primitive

The literal reading of the proposal is: at the point where a lazy column is
read, mint `symbool("#{base}_lazy_fetch", ...)`, and on the true side emit the
wide Q2. I recommend against it, for four reasons, in descending order of
seriousness.

**3.1 It is a decision over a state the application forbids.** Whether the lazy
fetch fires is *not* free. It is `(private_hash was reached) ∧ (first lazy read
on this instance)`, and `private_hash was reached` is `show_profile_info`, which
is a function of `profiles.public_details`, `contacts.sharing` and person
identity — state this corpus **already branches on**. §1.2 and the §2(a) census
both say so. A free bool lets the engine explore `lazy_fetch = true ∧
show_profile_info = false`, which no execution can produce. This is the same
error class as the pins the project has already had to retract: "a decision over
a state the application forbids, inflating the universe with fiction"
(`results4/comments_index/concolic_targets.rb`, the D4 guid pin comment) **[V]**.

**3.2 The resulting policy is over-permissive, which is the bug we are fixing.**
The extraction's PC fold prunes a predicate that appears on both sides of a
shape (`src/queries_from_runs/transform.py:1796-1821`, the
`irrelevant_predicates` / `irrelevant_predicates_reliable` path) **[V]**. If Q2
is gated on a *free* variable, then across the corpus Q2 will be observed with
`public_details = TRUE` **and** with `public_details = FALSE`, so the fold will
prune the real gate and ship a wide `profiles` read with **no** disclosure
condition at all. That is strictly worse than today's uniform width: today the
wide read is at least attached to the base find's conditions. Under a derived
gate (§4) the opposite happens — Q2 occurs *only* on the true side, the
predicate never appears both ways, and the fold **keeps** it. The reference's
shape split falls out.

**3.3 It forfeits the cheap proof and buys a very expensive one.** Adding a PC
per lazy-reading representative multiplies the tree along a new axis. A
seed-exact replay cannot establish branching safety for a change that, by
construction, changes branching. §6.1 prices the alternative.

**3.4 It answers a question the corpus can already answer.** `show_profile_info`
is not walled on notifications_index (`_RAILS_ENV_MOD_FIX_20260919.md` §8.2
asserts this by grep; I re-ran the grep over
`results3/notifications_index/{targets,concolic_targets}.rb` and found no
`declare_target` on `PersonPresenter`, `ProfilePresenter`, `full_hash*`,
`private_hash`, `public_details?` or `own_profile?` **[V]**), and its two
symbolic disjuncts already record PCs through `symbolic_instance`'s boolean
predicate reader (`concolic_targets.rb:651-656`, which calls
`sym.send(:record!, "(#{sym.sym_name} == True)", "#{col}?", taken: val)`)
**[V]**. The decision exists. Minting a second one for the same fact is the
"one fact, one variable" violation the project already paid for once — see the
CYCLE 6 / D1 comment at `results3/notifications_index/targets.rb:1061-1075`
**[V]**, which describes exactly this failure (a second representative for the
same row, and "the whole cross-rep clique the checker then demanded between
them").

**Where a free decision *would* be right.** If a gate were genuinely
unobservable — walled behind a mock whose body we cannot run — then minting a
decision is the honest move, because the alternative is silently foreclosing a
branch. There is exactly one such site (§4 D7, people_show's `description` mock),
and there the right repair is to make the *existing* mock emit, not to add a
variable: the mock already computes `receiver.public_details?` and so already
records the gate PC.

---

## 4. The design — Q2 as a derived, branch-dependent access

**[P] throughout this section unless tagged otherwise.**

The shape of the change: `symbolic_instance` stops shadowing the lazy accessors
with plain hash readers and instead installs a *lazy-aware* reader that
faithfully re-implements the gem's own body, emitting the reload statement as
its own SQL note. Nothing else changes. Q1 narrowing continues to come from
`default_projection`, which becomes universal.

### D1 — Derive the lazy column set from the model, never from a literal

```
lazy_columns(klass) =
  klass.column_names - klass.all.select_values.map { |s| s.to_s.split(".").last }
```

This is the exact inverse of the gem's own `column_names - columns`
(`acts_as_lazy_column_loader.rb:17`) **[V]**, so it is correct by construction
for any model using the gem, and it is **empty for every model with no narrowing
default scope** — which, in this app, is every model but `Profile`
(`grep -rn "lazy_load\|default_scope" app/ lib/` finds only
`app/models/profile.rb:8`; the RC-1 write-up §4 makes the same claim and I
re-ran the grep **[V]**).

Two properties this buys:

- **No diaspora-specific constant anywhere.** No `%w[bio gender birthday
  location]` literal, no `if klass == Profile`. The mechanism is a statement
  about `default_scope`, not about diaspora. (This matters: the standing rule is
  that nothing app-specific may live in `src/`, and the same hygiene is what
  keeps the shared boundary shareable.)
- **The same activation semantics as `default_projection`**: under
  `RAILS_ENV=concolic` the set is empty and the whole mechanism is a provable
  no-op; under `concolic_mod` it is the four columns. One switch, not two.

### D2 — The decision is *not minted*; it is inherited. Naming and stability.

There is **no new symbolic variable**. The branch that decides whether Q2 is
emitted is the application's own, and is already in the tree:

- `profiles.public_details` → recorded by `symbolic_instance`'s boolean
  predicate reader as `(<base>_public_details == True)`
  (`concolic_targets.rb:651-656`) **[V]**;
- `contacts.sharing` → same reader on the `Contact` representative;
- `own_profile?` → a Ruby object-identity comparison
  (`person_presenter.rb:51`) **[V]**, concrete in our harness — see §7 Q3.

**On the prefix-relative naming hazard.** This is the design's quiet advantage.
The known defect is that `CallInterceptor` names results
`SYM_RESULT_<func>_<idx>` with a per-run call ordinal
(`src/ruby_runtime/call_interceptor.rb:171-173`) **[V]**, and
`SymbolicFunc.next_call_idx` is a per-`func_name` counter
(`src/ruby_runtime/symbolic_func.rb:91-97`) **[V]** — so a representative's
`base_name`, and therefore every `<base>_<col>` variable, shifts when an earlier
decision changes the call sequence. The corpus's mitigation is suffix seeding
(`concolic_targets.rb:205-220`, `SEED_SUFFIXES`) **[V]**, and the comment there
records the measured failure it was built for: "11 runs seeded
`find_by_1_profile_disp_has_dlink = true`, 0 of them evaluated that variable".

A design that mints `<base>_lazy_fetch` inherits that hazard in full and needs a
`SEED_SUFFIXES` entry to be steerable at all. **A design that mints nothing does
not.** The gate variables it reuses (`<base>_public_details`,
`<contact base>_sharing`) are pre-existing column variables that the corpus is
already seeding and already suffix-steering. Stability across runs is therefore
not a new problem, and the seeds that already reach the wide branch keep
reaching it.

### D3 — Q2 is emitted as its own access, with its own note and binds

Not as a widening of Q1. The emission vehicle already exists and is already the
project's idiom for "a statement with no returned value": a declared no-op
target whose sole job is to mint a `symbolic_call` **event** carrying SQL in its
`note` (`results3/notifications_index/targets.rb:1040-1054`, the
`ConcolicThroughLoadProbe` construction and its `declare_target`) **[V]**. The
extraction reads queries off events, not off return values
(the comment at `targets.rb:1040-1042` cites `transform.py:225` for this).

A dump's `symbolic_call` event carries `target`, `args`, `result_name`,
`result_value`, `result_sort`, `file`, `lineno`, `function`, `note` — I
confirmed the shape against a real dump
(`results3/notifications_index/_archive_c6a_dumps/dump_html_plain_dse0001.json`)
**[V]**. "Refs" are the `$$(...)` bind tokens inside `note`; the same dump shows
`"note": "SELECT \"users\".* ... WHERE \"users\".\"id\" = $$(SYM_USER_NI_id) ..."`
**[V]**.

So Q2's note is:

```
SELECT "profiles".* FROM "profiles" WHERE "profiles"."id" = $$(<base>_id) LIMIT 1
```

built with the same `render_arg_value` used everywhere else
(`concolic_targets.rb:302-313`) **[V]** — which I checked is PC-free: it reads
`sym_name`/`value` and performs no comparison, so emitting a note cannot itself
add a path condition.

Three deliberate choices:

- **`"profiles".*`, not the narrow list.** `reload` is `unscoped`, so Q2 really
  is all 18 columns. I verified the reference agrees exactly: line 93 of
  `notifications-index.sql` projects 18 distinct `profiles` columns, and they
  are `db/schema.rb:442-459`'s column list in schema order **[V]**. The existing
  `reload` target is correspondingly and correctly left starred
  (`targets.rb:1263`, `SELECT "#{table}".* ... WHERE ... = ... LIMIT 1`) **[V]**.
- **Bound to the receiver's own id variable**, never a literal — the same
  discipline the `reload` target already states in its header comment
  (`targets.rb:1241-1243`) **[V]**. The resolver then inlines the producing
  query and recurses on its binds (README "Loadability" §1), which is what turns
  our single-table Q2 note into the reference's joined, `_MY_UID`-bearing shape.
- **A dedicated probe module, not `ConcolicThroughLoadProbe`.** Because
  `next_call_idx` is per-`func_name` **[V]**, routing Q2 through the existing
  probe would renumber every *existing* through-load probe variable in any run
  where a Q2 fires first. Those variables carry no PC (their return is discarded
  at every call site I checked: `targets.rb:687, 734, 771, 1129, 1264, 1358`
  **[V]**), so the tree would not move — but their *names* appear in
  `symbolic_vars` and in the footprints the confinement census measures, and
  there is no reason to accept that churn. A separate
  `ConcolicLazyFetchProbe.load_lazy` gets its own counter and renumbers nothing.

### D4 — Resolving the singleton-reader shadowing

This is the part that makes the mechanism reachable at all, and the specific
thing whose absence killed the escape hatch on people_show (§1.4).

The naive fix — "don't define a singleton reader for lazy columns, let the
gem's accessor run" — will not work, and I want to be explicit about why rather
than let an implementer discover it: the gem's body calls `has_attribute?`,
`self.changes.clone`, `self.reload`, and a writer per changed attribute. On a
`klass.allocate`d instance `@attributes` is nil, which is precisely the family
of crashes `symbolic_instance` already had to paper over — see its own
"nil-`@attributes` family (wall-fixing discipline)" block, which overrides
`attributes`, `write_attribute`, `_write_attribute` and `[]=` for exactly this
reason (`concolic_targets.rb:668-677`) **[V]**. `changes` (ActiveModel::Dirty,
via `@mutations_from_database`) is not in that list and would be the next crash.

So: **re-implement the gem's body, do not invoke it.** For each column in
`lazy_columns(klass)`, install a singleton reader of the form

```
obj.define_singleton_method(col) do
  unless <per-instance fetched flag>
    <set flag>
    ConcolicLazyFetchProbe.load_lazy(<Q2 note built from this row's id>)
  end
  attrs[col]
end
```

This is legitimate under the project's own discipline as I read it: it is a mock
that *renders its real SQL*, at a leaf, standing in for a body whose only
observable effects are (i) the statement and (ii) returning the column. It is
strictly *more* faithful than the reader it replaces, which silently swallowed a
real statement. Non-lazy columns keep the existing plain reader verbatim.

**The returned value is the pre-existing `attrs[col]` variable — no new
representative, no new variable.** In the real app the reload overwrites the
row's attributes, so one could argue for fresh variables; that would be the "one
fact, two variables" mistake documented at `targets.rb:1061-1075` **[V]** and
would summon a cross-rep clique for no gain. Same row, same column, same fact,
same variable.

### D5 — Granularity: one decision, one emission, **per representative**

The brief asks whether the fetch is per representative, per column, or per
display surface. Three independent lines of evidence give the same answer:

1. **The gem.** `unless has_attribute?(column)` plus a full-row `reload` means
   the second lazy read on the same instance issues nothing
   (`acts_as_lazy_column_loader.rb:26-32`) **[V]**. Per instance — i.e. per
   representative — is not a modelling choice, it is the mechanism.
2. **The precedent the brief points at.** `results3/notifications_index/targets.rb`
   mints one `<base>_disp_has_dlink` decision for `bio`+`location` together, on
   the stated ground that "they are one display surface, and a second
   independent guid would only duplicate the same statement". The user's cite of
   1627-1655 is very close: the reasoning comment begins at **1627**, `disp_cols`
   is computed at **1639**, and the block ends at **1656** **[V]**. That
   precedent is per representative, and it covers two of our four columns.
3. **The reference.** notifications-index's two wide shapes differ by *gate*, not
   by column — both project all 18 **[V]**. If the model were per column we
   would expect up to four wide shapes per gate; we see one.

So: one flag per representative, cleared never (a request is one run), and the
emission carries all four columns because the statement does.

**Per display surface is what the *shapes* are, and it is emergent.** The two
surfaces (§1.2) have different gates, so whichever fires first stamps Q2 with a
different PC context, and the fold separates them into different statements.
Nothing needs to enumerate surfaces.

### D6 — Q1 narrowing becomes universal

`default_projection` is applied at *every* class-finder / association /
preload note site in **all six** batches, including notifications_index and
posts_show, which have none today **[V]**. The two exceptions the RC-1 write-up
already identified stay starred and are now *load-bearing* rather than
incidental: `ActiveRecord::Base#reload` (because `unscoped`) and the
through-reflection intermediate (`isql`, whose table is the join table).

Under this design the earlier objection to narrowing notifications_index
evaporates: narrowing no longer destroys the two wide shapes, because those
shapes are no longer produced by Q1's width at all. They are produced by Q2.
That is the whole point of separating them.

### D7 — The one site that needs a local repair: `PersonPresenter#description`

`results3/people_show/targets.rb:588-596` declares a target on
`PersonPresenter#description` that returns a `ConcreteSymbolicString` and never
touches `bio` **[V]**:

```ruby
interceptor.declare_target(PersonPresenter, :description, returns: lambda do |receiver, _args, name|
  pub = receiver.public_details?
  ConcreteSymbolicString.build(pub ? "Concolic bio" : "", name: name,
                               note: "PersonPresenter#description (untracked bio HTML-escape leaf)")
end)
```

The mock exists for a real reason (a downstream HTML-escape wall on a tracked
`SymbolicString`), and its header comment argues "no SQL is skipped by mocking
`description`" (`targets.rb:566-587`, the DESCENT block) **[V]**. **Under `concolic_mod` that
argument becomes false**: `bio` is exactly the read that issues Q2. This is a
latent boundary-note defect that the env change would activate, and it is worth
recording as such independently of whether this design is adopted.

The repair is one line inside the existing mock, not a new mechanism: the mock
already computes `pub`, so on the true side it reads `receiver.bio` (through the
lazy-aware reader, which emits Q2 and returns the tracked var) and *then* wraps
a render-safe concrete string. The gate PC is already recorded by
`public_details?`; nothing new is minted. See §7 Q4 for the residual question.

I want to be straight about this: D7 **is** a per-endpoint touch, and the brief
asked for none. My defence is that it is a repair to a people_show-*local* wall,
not a per-endpoint variant of the mechanism — the mechanism (D1-D6) is
byte-identical everywhere. If that distinction is not accepted, then the honest
answer to "is it uniform?" is "uniform except here, and here is a wall, not a
policy."

---

## 5. Uniformity, endpoint by endpoint

One mechanism. What differs is only whether control flow reaches
`private_hash` / `description`.

| endpoint | reaches the gate? | evidence | Q2 emitted | reference wants wide |
|---|---|---|---|---|
| notifications_index | yes, HTML-desktop StartedSharing only | `_notification.haml:5-7`; serializer `:14` suppresses for JSON **[V]** | sometimes | 2 shapes ✔ |
| people_show | yes, both surfaces | `people_controller.rb:71,78,89` → `@presenter.as_json` **[V]** | often | 3 shapes ✔ |
| people_stream | no | `results3/people_stream/targets.rb:57` **[V]** | never | 0 ✔ |
| comments_index | no | `comment_presenter.rb:13` → `as_api_response(:backbone)` **[V]** | never | 0 ✔ |
| posts_show | no | `post_presenter.rb:63` → same **[V]** | never | 0 ✔ |
| conversations_index | no (by the same census) | reference has 0 wide **[V]**; I did **not** trace its render path | never | 0 ✔ |

Every prediction matches the reference. That is six for six, and it was not
fitted — the mechanism was derived from the gem and the presenters before the
census was run.

The one row I have not earned is conversations_index: I inferred "never" from
the reference's zero wide shapes and from its 4 narrow `profiles` statements,
without tracing the conversation render path to a presenter. **[?]** It is
cheap to close and should be closed before implementation.

---

## 6. Soundness — the hard part

### 6.1 What branching-safety argument is needed, and whether replay suffices

**For the design as specified in §4: yes, seed-exact replay is sufficient, and
for the same reason it was sufficient for `default_projection`.**

The argument has three legs, and each is checkable rather than asserted:

1. **No new symbolic variable is minted** (D2, D4) — so no new
   `path_condition` event can be produced by the mechanism. The reader's only
   added work is a flag test, a note construction and a probe call.
2. **Note construction is PC-free.** `render_arg_value`
   (`concolic_targets.rb:302-313`) reads `sym_name`/`value` and performs no
   comparison **[V]**. The flag test is on a plain Ruby boolean.
3. **The probe's return is discarded**, so its `symint` can never be branched on
   — the same property every existing `load_intermediate` call site relies on
   **[V]**.

The verification is then exactly the protocol
`_RAILS_ENV_MOD_FIX_20260919.md` §5 already ran and documented: replay the
corpus's own recorded `concolic_seeds` 1:1 under the new code and assert **0
per-seed PC-signature mismatches**, identical PC-count multiset, identical error
profile, 0 missing/duplicate seeds. That run reported 0/26,528 on comments_index
**[V-ref]**. Under this design I would additionally require two assertions the
earlier replay did not need:

- **A1 (no-op where predicted):** on people_stream, comments_index,
  conversations_index and posts_show, **zero** `ConcolicLazyFetchProbe` events
  across the whole replayed corpus. This is the mechanised form of §5's
  prediction, and if it fails, §5 is wrong and the design stops.
- **A2 (emission where predicted, and only there):** on notifications_index and
  people_show, every dump containing a Q2 event also contains the gate PC taken
  true, and no dump contains a Q2 event without it. This is the property §3.2
  depends on for the fold to keep the gate; it is a per-dump check, not a
  statistical one.

**Why this is not a dodge.** The reason a "change that adds decisions cannot be
replay-verified" is true — and the brief is right to suspect it — is that replay
compares PC signatures, and a design that adds PCs changes them by construction.
The escape is not that we verify an adding change cheaply; it is that **this
design does not add any**. If review concludes that some PC is unavoidably
added, the cheap proof is void and §6.2 applies.

### 6.2 What the expensive proof would cost, if a free decision is adopted anyway

If the free-bool variant (§3) is adopted — or if D4 turns out to require a real
comparison somewhere — then replay establishes nothing and each affected
endpoint needs a fresh completion-gate proof on a **re-explored** corpus:

- notifications_index: 313,977 dumps, the largest of the six, and its last full
  gate run already reports 96 missing branches (92 blocking, `truncated=True`)
  on the full corpus per the README row. A new decision axis multiplies the leaf
  count the enumeration cap is already truncating — the realistic outcome is not
  "a longer run", it is "a cap that now truncates harder, and a floor that is
  less informative".
- people_show: its completion gate did not exist until 2026-09-19 and is still
  being built; it additionally **cannot be seed-replayed at all** —
  `_RAILS_ENV_MOD_FIX_20260919.md` §7.2 records that it writes no
  `concolic_seeds` and its runner deletes the corpus on startup **[V-ref]**. So
  for people_show even the *cheap* proof needs infrastructure work first (§7 Q5).
- the three closed endpoints: a from-scratch re-exploration plus all three
  checks plus an adversary round, per Rule T's T2 procedure
  (`docs/DISCIPLINE.md:272-288`) **[V]**.

That is the price, and it is why I recommend the derived gate.

### 6.3 Runtime gate vs deployment constant — and no, `concolic_mod` does not go away

The brief's distinction is the right one and the design observes it strictly.

- **Symbolised (correctly):** whether the lazy fetch fires on a given row in a
  given request. Under this design it is not even "symbolised" — it is
  *derived* from `show_profile_info`, which is already symbolic. Both sides are
  explored, and the policy carries a narrow Q1 plus a conditionally-gated Q2.
- **NOT symbolised:** `Rails.env.include?("mod")` (`profile.rb:8`) **[V]**.
  Symbolising it would union two deployments into one policy — a weaker and
  genuinely different claim ("in *some* deployment this row may be read wide"),
  and it would also make the lazy column *set* itself symbolic, which is
  incoherent: under the non-mod deployment there is no Q1/Q2 split to model,
  because every read is already wide.

**Does `concolic_mod` become unnecessary?** **No — it becomes more load-bearing,
not less.** Three things break if it is removed:

1. **Q1 stops narrowing.** `default_projection` reads `klass.all.select_values`
   (`concolic_targets.rb:236-246`) **[V]**, which is empty without the
   `default_scope`. Every `profiles` read reverts to 18 columns — RC-1 restored
   in full on all six endpoints.
2. **D1 stops deriving.** `lazy_columns(klass)` is `column_names -
   select_values`; with no default scope it is empty, so no lazy reader is
   installed and Q2 is never emitted. The mechanism becomes a no-op everywhere.
3. **The only way back is a hard-coded list**, i.e. `%w[bio gender birthday
   location]` written into the target layer — a diaspora-specific constant in
   the shared boundary, and worse, a *fabricated* projection: we would be
   emitting a narrow statement the application, as configured, never emits.
   That is a mock-fabrication defect of exactly the kind the precision audits
   hunt for.

The correct framing: `concolic_mod` is **the deployment the claim is about**.
It should be stated as such in each policy's `POLICY_HEADER` — the policy
describes a pod whose `Rails.env` matches `"mod"` (equivalently, the reference's
own configuration), and makes no claim about a non-mod pod. The
`_RAILS_ENV_MOD_FIX_20260919.md` §3 env-name safety audit — that
`"concolic_mod"` trips no other `Rails.env` check in the app — was re-derived
this session: `grep -rn 'Rails.env' app/ config/ lib/` shows the only
name-sensitive checks are `include? "checked"`, `.test?`, `== "production"`,
`.start_with?("production")` and `.development?` **[V]**.

Follow-up item 1 of that write-up (flip `scripts/diaspora-concolic`'s default,
currently `RAILS_ENV=concolic` at line 17 **[V]**) becomes a prerequisite of
this design rather than a deferred cleanup.

### 6.4 Rule T — this is a boundary change, and it needs a ruling before code

`symbolic_instance` is the boundary's row-representative constructor; changing
what its readers do is a target-boundary change. `docs/DISCIPLINE.md:272-288`
(T2) says a boundary **defect** voids every endpoint's `complete: true` and
forces every corpus to be regenerated from scratch, with all three checks and an
adversary round re-run per endpoint **[V]**. T3 (`:301-308`) says batch agents
may not edit the boundary at all — only the coordinator, and doing so triggers
T2 **[V]**.

Two honest observations:

- **RC-1 is already a T2-shaped defect** ("a note that misstates what the real
  call does", "a missing target" — both listed in T2's opening sentence), and it
  was nonetheless repaired on three endpoints via seed-exact replay rather than
  regeneration, on the argument that a provably branching-identical, note-only
  change does not need the full cycle. That precedent is real and, I think,
  correct — but it is a *de facto* relaxation of T2 that has never been written
  down. This design relies on it.
- **The shared file T1 names does not exist.** `docs/DISCIPLINE.md:256`
  points at `shared/target_boundary.rb`; `results3/shared/` is not present on
  disk **[V]**, and each batch still carries its own `concolic_targets.rb` copy
  (I diffed `results4/comments_index`'s `symbolic_instance` against
  `results3/notifications_index`'s: same skeleton, local divergences for guid
  pinning and `default_int`'s arity **[V]**). So "land it once in the shared
  file" is not currently an available action; in practice this means **six
  copies of D1-D6**, kept byte-identical by discipline. That is a real risk and
  the same one T1 was written to kill.

**The ruling I need from Bali, stated as a yes/no:** *may a target-boundary
change that is verified branching-identical by seed-exact replay (0 PC-signature
mismatches, plus assertions A1/A2) be adopted without triggering T2's
from-scratch regeneration?* If yes, this design is executable. If no, it costs a
full six-endpoint regeneration and should be scheduled as such, not slipped in.

### 6.5 Per-endpoint impact

| endpoint | precision | recall | closure claim |
|---|---|---|---|
| **notifications_index** | **improves** — its 17 narrow shapes stop being emitted 18-wide; this is the defect §8.5 identified and declined to fix | **preserved** — the 2 wide shapes are now produced by Q2 rather than by an unconditionally wide Q1 | **no closure to reopen.** The README row already records that the full-corpus gate is *not* complete (96 missing, 92 blocking, truncated); the 2026-09-15 `CLOSED + SHIPPED` claim is scoped to a pruned 138,912-dump snapshot. A corpus change does not make that worse, but it does mean the snapshot claim can never be re-established without a re-run. |
| **people_show** | **improves** — recovers its 2 narrow reference shapes, currently lost (§2b) | **improves** — the 3 wide shapes become *gated* rather than accidental, and D7 recovers the `description` surface that is walled today | REOPENED already (2026-09-19); its completion gate is still being built. No certification is destroyed. |
| **people_stream** | unchanged | unchanged | **at risk, and I want to be loud about it.** The mechanism is a predicted no-op here (A1), but it still means touching this batch's `concolic_targets.rb` and re-replaying 13,677 dumps. Its coverage layer was verified byte-identical to the 2026-09-11 certification as recently as 2026-09-20, and its gate currently reports `OVERALL_COMPLETE=False` with 5 blocking items. Re-touching it while those are open is a scheduling hazard, not a correctness one. |
| **comments_index** | unchanged (already 1.0000) | unchanged | closure is `CLOSED 2026-09-01` + a round-3 gate run in flight per the README. A1 makes the change a provable no-op, but it is still a boundary touch → §6.4's ruling governs. |
| **conversations_index** | unchanged | unchanged | same as comments_index; its gate re-run is checkpointed and pending a quiet window. |
| **posts_show** | **improves** — gains `default_projection` (D6), which it has never had, against a reference with 15 narrow and 0 wide `profiles` shapes | unchanged (Q2 never fires) | not closed. Still blocked on the standing user decision to unpin `concolic_targets.rb` from `627bac2c1199`. |

Net: two endpoints gain precision, one of those also gains recall, one gains
precision from the narrowing half alone, and three are predicted no-ops whose
only exposure is the cost of re-verification. **No endpoint's certification is
invalidated by the design's semantics**; three endpoints' certifications are
exposed only through §6.4's procedural question.

---

## 7. Open questions I could not close

- **Q1 — does the PC fold actually keep the gate conjunct?** §3.2's argument
  rests on `transform.py`'s pruning rule dropping only predicates seen both ways
  for a shape (`transform.py:1796-1821`) **[V]** — but I read the entry point,
  not the full `pcs.irrelevant_predicates` implementation, and I did not check
  how `reliable_witness` interacts when Q2's witness count is small (2 shapes out
  of 71 on notifications). If the fold prunes too aggressively at low witness
  counts, Q2 ships ungated and the design produces an over-permissive policy —
  the exact failure §3.2 accuses the free-bool variant of. **This is the single
  most important thing to check before writing code**, and it is checkable
  offline against the existing corpus by synthesising a Q2 event stream.
- **Q2 — does the shape of our Q2 note fold into the reference's joined
  shape?** Ours is a single-table `WHERE id = $$(...)`; the reference's is a
  three-table join with aliases (`profiles.id AS id1`). The resolver is supposed
  to inline the producing query and recurse (README "Loadability" §1), and that
  is how other joined shapes arise today — but I did not verify it end-to-end for
  a `reload`-shaped bind specifically.
- **Q3 — `own_profile?` is a concrete object-identity comparison**
  (`person_presenter.rb:51`) **[V]**, so people-show's first wide reference shape
  (`people.owner_id = _MY_UID`) is reachable only by *driving a self scenario*,
  not by flipping a decision. people_show has a self manifest for the completion
  gate (`concrete_manifest_auth_self_html.rb`, `PS_PRINCIPAL = User.find(9)`,
  `username: "alice@localhost"` **[V]**) but I did not check whether the DSE
  variant set includes one. If it does not, that shape stays unrecovered and
  should be recorded as a declared gap rather than quietly missed.
- **Q4 — is D7's repair enough, or does the escape wall reopen?** The
  `description` mock exists because a tracked `SymbolicString` bio crashes
  downstream HTML-escape machinery (`targets.rb:566-587`) **[V]**. Reading
  `receiver.bio` for its *effect* and discarding the value should be safe
  precisely because the value is discarded — but "should be" is doing work there,
  and it wants a scratch run.
- **Q5 — people_show cannot be seed-replayed** (no `concolic_seeds`, runner
  deletes the corpus on startup) **[V-ref]**. Since people_show is one of the two
  endpoints that actually gains from this design, the verification story there is
  unresolved: either the runner gains seed recording first, or people_show's
  verification is folded into the completion gate now being built.
- **Q6 — conversations_index's render path was not traced** (§5).
- **Q7 — six copies.** With `results3/shared/target_boundary.rb` absent **[V]**,
  D1-D6 would be replicated six times. The divergence this invites is the exact
  failure Rule T's T1 rationale cites (the same `Post.exists?` defect landing
  three times). A mechanical equality check across the six copies should be part
  of the change, or the change should wait for the shared file.

---

## 8. What I did not do

- No production code. No file under `src/`, `src_new/`,
  `ruby_examples/dse-apps/apps/diaspora/`, or any batch's `concolic_targets.rb`
  / `targets.rb` was modified. No mock changed.
- No corpus was driven, replayed or extracted.
- Nothing committed or pushed.
- I did not read the quarantined reference at
  `ruby_examples/dse-apps/policies/` (confirmed still unreadable). The
  measurements in §2 are over `policy-extraction-bench/data/answers/diaspora/`,
  which is the graded artifact `bench.grade` already scores against.
