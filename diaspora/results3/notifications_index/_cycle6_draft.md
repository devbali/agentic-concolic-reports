
## Cycle 6 — the 28 gate FAILs withdrawn, B-4/B-5 closed, §7 finished (2026-08-28)

Handover state (14:08 report, rc=0): `coverage_complete: false`, **55 missing**
(44 blocking) at 188 nodes / 16 707 runs; assumption gate **17 471 PASS /
28 FAIL**; shims 13 PASS / 20 PROTOCOL; `empty_relation_emission` RED;
`complete: false`.

### 1. The 28 FAILs — WITHDRAWN, never re-declared

The gate's 28 rejections are withdrawn as CLASSES, not as the individual pairs
that happened to be probed. The probe picks ONE snapshot per declaration, so a
sibling PASS on another rep is a property of the probe corpus, not of the code:
narrowing a refuted class to "the rep that failed" is how a hollow declaration
survives. The withdrawal ledger lives in `coverage_assumptions.py` (block
`WITHDRAWN`), and every withdrawn pair stays in the generator's `already` set so
no later tier can re-declare it in another form.

| class | what it claimed | why the gate refuted it | withdrawn |
|---|---|---|---|
| **W-A** display-suffix UntrackedPath (`_first_name`, `_last_name`, `_public_details`, `_birthday_year`, `_text_has_mention`, `_mention_inline_name`, `_guid == ''`) | "the outcome changes only rendered text/CSS; no query differs" | 20 of the 28 FAILs. "flipping the branch changed 3 / 4 / 10 target-call shape(s)". Real mechanism: a blank first/last name reaches `Person#name` -> `fix_profile` -> `reload` (`SELECT "people".* … LIMIT 1`); `_text_has_mention` gates the `mentions` read; a blank actor guid changes 10 shapes | whole family; the ONLY survivors of the tier are the badge COUNT compare and the Journey formatter's `_guid != StringVal('')` (a different expression at `formatter.rb:41`, PASS on all three instances, and its True side is unreachable in actionpack) |
| **W-B** own-profile var-vs-var UntrackedPath | "`current_user.person == person` decides only a CSS class" | FAILed on `…_actors_row_id == …_devise_user_first_1_person_id` (3 shapes). The tier ALSO mis-matched `X == True` as a var-vs-var compare (its regex accepts `True` as a variable name) — which is how `…_devise_user_first_1_person_not_found == True`, a real has_one not-found DECISION, was ever declared display-only | whole tier (6 declarations) |
| **W-C** dispatch ⊥ `_not_found` | "flipping the STI type only adds/removes a whole type-branch's reads" | 4 FAILs on `SYM_POST_STI == 0/1` × `…_mentions_container[_commentable]_author_profile_not_found`: flip-both produced `find_target` ; `reload` ; `load_intermediate SELECT "people".* … LIMIT 1` — shapes absent from base and from both singles. The dispatch decides WHICH chain the not-found decision sits on | the pairs where the non-dispatch side is a `_not_found` decision (dispatch-independence survives for every other decision kind) |
| **W-D** profile-display link family ⊥ contact relationship / identity | tier-2 "disjoint reps" | 4 FAILs, all producing `exists?` + `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1`: `_sharing` is what makes `PersonPresenter` render the bio at all, so the bio's diaspora-link probe is gated by it | every tier-2 pair joining a `_disp_has_dlink`/`_disp_dlink_*` decision to a `_sharing`/`_receiving` decision or to a person-identity compare |

### 2. The assumption-set SHAPE — §7 finished (coordinator item 3)

The cycle-5 answer ("tier2 is the inherent complement of the subtractive
complete-graph model") was only half true. Measured on the cycle-5 corpus,
tier2 was still 10 270 declarations over **68 rep keys**, and the audit
(`_tier2_audit.py`, batch-local) found the remaining artefacts:

1. **Finder ordinals.** `one_fact` was keyed on `receiver.object_id`. That
   collapses repeated ASSOCIATION loads (the same association object answers
   twice) but never a FINDER: `Contact.where(...).find_by(...)` builds a FRESH
   relation per call, so rendering the ONE representative row three times minted
   `find_by_1` / `_4` / `_7`, `_2/_5/_8`, `_3/_6/_9` — three variables for a
   query with byte-identical binds. The checker then demanded their pairwise
   identity combinations (`find_by_1_person_id == find_by_4_person_id` and
   friends): **13 of the 44 blocking misses and 4 of the 8 independence FAILs**,
   i.e. states in which three copies of the SAME row have different contacts —
   unobservable by construction. FIX: `one_fact` is keyed on the RENDERED SQL
   (SELECT-shaped notes only), which carries every bind BY VARIABLE NAME, so
   identical SQL in one run is one fact. Measured: a 3-row html run went from
   9 find_by REP families to **3**, with all **9 EVENTS still recorded** (the
   memo returns the first call's row; the interceptor still logs each call, so
   the D1 multiset is unchanged).
2. **A preloaded association modelled twice.** `CollectionProxy#records` /
   `#load_target` re-described a load the preloader had already performed:
   it emitted a SECOND `SELECT "notification_actors".* … = ?` probe event
   (measured: **2 events per dump for 1 real statement**, 58 of 60 dumps) and
   built a SECOND REPRESENTATIVE for the same row
   (`…_CollectionProxy_records_1_row_*` beside the preloader's
   `…_to_ary_1_row_actors_row_*`) — one fact, two reps, and the entire cross-rep
   clique the checker then demanded between them. FIX: when the association is
   already `loaded?`, return the loaded target — same representative, the SAME
   length variable the preload step already recorded its {0,1,4} decision on,
   and NO note. Rails does exactly this (`load_target` returns early when
   loaded). Measured after: `notification_actors` note events **1 per dump**;
   `CollectionProxy_records_*` reps survive only for genuinely UNPRELOADED
   collections (`post.photos`, `contact.aspect_memberships`).

So the answer to the coordinator's question is (b) again — an artefact of the
modelling, in two more places — and it is fixed rather than declared away.

### 3. B-4 — one load, one predicate (and the belongs_to pin was factually wrong)

The cycle-5 pin read: *"BELONGS_TO stays pinned found — every belongs_to FK this
endpoint loads is NOT NULL with an ON DELETE CASCADE foreign key"*. Checked
against `db/schema.rb`'s `add_foreign_key` list (lines 615-645): **false**.
`mentions`, `photos` and `notifications` appear in NO `add_foreign_key` at all,
so `mentions.person_id`, `photos.status_message_guid`, `photos.author_id`,
`notifications.recipient_id` and `notifications.target_id` are all FK-LESS —
the exact shape comments_index's M-3 turned into a win.

The pin is therefore narrowed to what the schema actually licenses:
`ConcolicTargets::FK_BACKED_COLUMNS` transcribes the schema's FK list, and
`ConcolicTargets.fk_backed?(refl)` decides per reflection. A belongs_to over an
FK-LESS column now carries a **LIVE** not-found decision:

* on the `find_target` path (`SingularAssociation#find_target`, concolic_targets.rb),
  and
* on the PRELOAD path (`emit_includes_preloads`, targets.rb) — which previously
  had NO not-found arm at all and always attached a row plus its nested step.
  The preload arm mints **the same predicate name** `find_target` would use
  (`ConcolicTargets.assoc_base_name(owner, assoc) + "_not_found"`), and on its
  closing arm attaches `nil`, sets the association `loaded!`, emits NO read and
  SKIPS the nested step — so the load has exactly one decision whichever path
  performs it, and there is no dead decision paired with a phantom nested read.

New decisions the corpus now carries (verified live):
`…_Relation_records_2_row_person_not_found` (the `mentions.includes(person: :profile)`
preload — `mentions_container.rb:19`), `…_target_status_message_not_found`
(`Photo#status_message`, photo.rb:43), `…_target_author_not_found` (a Photo
target's `photos.author_id`), `…_row_recipient_not_found`.

They expose real app 500s on real database states, recorded as `dump_errors`
exactly as the polymorphic-target ones were: a dangling `mentions.person_id`
makes `mentionable.rb:35` `people.find {|p| p.diaspora_handle == …}`
dereference nil, and a Photo with no status message makes `posts_helper.rb:9-10`
`post.status_message_author_name` dereference nil.

### 4. B-5 — the residue the first pass left

`empty_relation_emission_audit` was RED on the handover corpus: **4 shapes,
1 483 dumps, 6 517 note events**. The cycle-5 fix gated the REPRESENTATIVE and
the preload step on the length, but not the NOTE: the `preloaded` branch of the
CollectionProxy mock rewrote `sql` to
`SELECT "people".* … "id" = $$(<name>_row_id)` BEFORE the length was read, and
that string became the list's note (and its `len(...)` var's note) even at
length 0 — a note binding a row variable the run never mints. Length is now
read FIRST and the per-representative note is built only when it is non-zero.
(The §7 fix above subsumes most of it: a preloaded association now carries no
note at all.) `empty_relation_emission_audit` is wired into `extra_audit_cmds`,
so the engine runs it on every report.

### 5. Rule G (DISCIPLINE §11) — gate list and pin ledger, now BOTH declared

`pc_gate_columns` carried `text` — which is **blind under the audit's own rule**
(`pc_visibility_audit` matches `name.endswith("_" + col)`, and this corpus mints
`_text_nil` / `_text_has_mention` / `_text_has_dlink` / `_text_dlink_is_post`,
never a bare `_text`). Measured on the handover corpus: 0 references. The
10-column list in the config had never been run through the audit — the audit
was invoked with only `type,unread,persisted,guid`.

Fixed in `completion_config.json`, and the pin half is now DECLARED rather than
living only in prose:

* **GATE** (asserted app-compared AND verified PC-visible): `type`, `unread`,
  `persisted`, `guid`, `first_name`, `last_name`, `person_id`,
  `diaspora_handle`, `rows`.
* **`pc_pin_ledger`** (each with its entry in `pc_gate_ledger_notes`):
  `text`, `bio`, `location` (concrete strings WITH the recorded decision family
  the app actually branches on inside them), `target_type`,
  `mentions_container_type`, `commentable_type` (derived from a recorded
  dispatch decision; BOTH values occur in the corpus, so no subclass family is
  foreclosed), `taggable_type` (the literal of the REAL acts_as_taggable scope),
  `language` (compared only by before_actions this batch does not dispatch).
  Request parameters `type` / `page` / `per_page` are recorded in the same block.
* The blanket **belongs_to-pinned-found** entry is REPLACED by the schema-derived
  `FK_BACKED_COLUMNS` rule (§3) — the pin now covers exactly the FKs the schema
  backs, and nothing else.

Gate ∩ pin = ∅; the union is checked against a re-read of
`notifications_controller.rb`, `index.html.haml`, `index.mobile.haml`,
`_notification.haml`, `notifications_helper.rb`, `people_helper.rb`,
`posts_helper.rb`, `mentionable.rb`, `mentions_container.rb` and
`person_presenter.rb`.

### 6. Round-1 adversary wins — still closed, verified in THIS corpus

| item | evidence in the cycle-6 corpus |
|---|---|
| **N-1** `Post.exists?` link family | `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1` present as its own note shape; `MessageRenderer#title`, `Processor.process` and `people_from_string` remain WITHDRAWN as targets (the bodies run). `hardening_lint` H2 = "an exists?-family target in the corpus: yes / any existence-probe note: yes"; H3's three remaining opaque-note CHECKs are answered below |
| **N-2** `Photo` notification target | `SELECT "photos".* FROM "photos" WHERE "photos"."id" = ? LIMIT 1` and `SELECT "posts".* FROM "posts" WHERE "posts"."type" IN ('StatusMessage') AND "posts"."guid" = ? LIMIT 1` both present; `target_type` is the `_target_is_photo` DECISION over {Post, Photo} |
| **N-3** `conversations` read | still absent by design — documented pin, now DECLARED (`private_message` in the pin block): `private_message.rb:22-28` `notify` never persists such a row |
| collection lengths are decisions (0/1/many) | `len(…_to_ary_1_rows)` {0,1,3} and `len(…_actors_row_rows)` {0,1,4}, both with `== 0` and `> 1` / `> 3` recorded explicitly |
| `people INNER JOIN notification_actors` | 0 occurrences (was 494 850) |
| `COUNT(*) FROM "photos"` | 0 occurrences (was 2 332) |
| `params[:per_page]` | recorded pin, now in `pc_gate_ledger_notes._params_pins`, with the branch-relevant effect explored as the `rows` length decision |

### 7. Answers to `hardening_lint`

* **H1 formats** — all seven variants are corpus scenarios; `format_coverage_audit.py`
  enforces it in `extra_audit_cmds`.
* **H2 link-bearing text** — the decision family and the `1 AS one` probe note are
  in the corpus on both arms.
* **H3 opaque notes** — three CHECKs, each a proven leaf or a documented wall:
  `ActiveRecord::Base.to_param` = `id && id.to_s` (pure formatting);
  `User#blocks` returns a real `Block.where(user_id:)` RELATION — the statement is
  issued at materialization by the collection target, with its own note, and the
  reader itself issues none; `Anonymous.new` is
  `DiasporaFederation::Discovery::Discovery.singleton_class#new` — the B11 federation
  WALL at the object boundary (`discovery.rb:43` normalizes the handle in the
  CONSTRUCTOR), whose real path aborts the JVM on all three endpoints.
* **H4 collection lengths** — see §6.
* **H5 pinned type columns** — every one is declared in `pc_pin_ledger` with a
  ledger entry (§5).

### 8. The coordinator's propagation matrix (2026-08-28), row by row

| item | this batch |
|---|---|
| **T-a** link-bearing text / no non-SQL note over a SQL-reaching body | closed in cycle 2 (N-1); re-verified: `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT 1` is a corpus note shape, `MessageRenderer#title` / `Processor.process` / `people_from_string` are withdrawn as targets, `statement_note_lint` shows 4 JUNK notes and each is answered (§7) |
| **T-c (B-4)** FK-less belongs_to | done this cycle, on BOTH paths, with one shared predicate — see §3 |
| **T-d (B-5)** nothing exists for an empty relation | `empty_relation_emission_audit` PASS and wired into `extra_audit_cmds` — see §4 |
| **T-e (Rule V)** DERIVED-MISBOUND 0 | one of the two names is fixed by a call-site-stable alias; the OTHER IS IRREDUCIBLE — see §9 |
| **T-f (M-5)** `set_locale` | MODELLED, not pinned — see §10 |
| **T-g (M-6)** STI `*_type` is a placeholder | reachability + consequence argument in the pin ledger for `notifications.type` and `target_type`; the consequence of an out-of-tree value is a request TRUNCATION whose statement set is a strict PREFIX of the modelled one — see `completion_config.json` `pc_gate_ledger_notes.type_STI_reachability` |
| **T-h** `reload` mints its single-row re-read; `escape_segment` / `Discovery.new` mint nothing | `reload` is a target minting exactly `SELECT "people".* … "id" = ? LIMIT 1` (B-1, cycle 5). `escape_segment` is already a SHIM here (`EscapeSegmentShim`), not a target — 0 events. `Discovery.new` is still a declared target minting an EMPTY note (147 events in a 2 747-dump sample): it is the object-boundary WALL, and demoting it to a shim is impossible to VERIFY under Rule S because the real body aborts the JVM (now diagnosed as Faraday typhoeus → Ethon → libcurl via JFFI). **Reported as a BOUNDARY item, not changed** |
| **T-i** length is a decision, one fact one variable | see §2 and §6 |
| **T-j** over-emission | `people INNER JOIN notification_actors` and `COUNT(*) FROM "photos"` are both 0 corpus-wide |
| `note_fidelity_audit` now judges `=` vs `IN`, `LIMIT`, `ORDER BY` | RE-RUN and REPAIRED — see §9 |

### 9. note_fidelity with the new judges, and the one irreducible DERIVED-MISBOUND

The re-run was **RED**: `PRED-OP-DIFF 7`, `LIMIT-DIFF 3`. Both had the same
root cause, and it was a real modelling defect, not a normalizer artefact:

* **LIMIT-DIFF** — the controller's `includes(:target, actors: :profile)`
  PRELOADS the polymorphic target, so the real statement is
  `SELECT "posts".* FROM "posts" WHERE "posts"."id" = ?` with **no LIMIT**
  (26x in this batch's concrete runs), while the corpus modelled that same load
  as a lazy `find_target` with `LIMIT 1`. `emit_includes_preloads` skipped every
  polymorphic reflection (`next unless r2 && !r2.polymorphic?`). It now emits
  the polymorphic step, attaches the row, and `find_target` no longer fires for
  it — so `posts.id = ?` (preload) and `posts.id = ? LIMIT ?` (the genuinely
  lazy `mentions_container` / `commentable`, 10x real) are BOTH in the corpus,
  each from the load that really issues it. `LIMIT-DIFF: 0`.
* **PRED-OP-DIFF** — ActiveRecord's `ArrayHandler` builds an EQUALITY for a
  one-element key set and `IN (…)` for several, so the endpoint really issues
  BOTH (`notification_actors.notification_id = ?` 4x and `IN (…)` 22x;
  `people.id = ?` 56x and `IN (…)` 2x; `profiles.person_id = ?` 48x and
  `IN (…)` 2x). The corpus had only `=`. The preload note now follows the
  modelled OWNER COUNT — which is already a recorded decision, the list length
  — so `len == 1` renders `=` and `len > 1` renders `IN (…)`, and both shapes
  are in the corpus for every preload step.

**DERIVED-MISBOUND** went 42 → 1 on the same sample. The fixed one was
`…_target_status_message_author_id`: the rep base came from the ASSOCIATION
name `status_message`, whose `_message_` matched the audit's
`DERIVED_RE`; a call-site-stable alias (`status_message` → `statusmessage`,
Rule T1 — naming only) removes the substring collision without changing what
the variable is.

The remaining one is **IRREDUCIBLE and is an AUDIT DEFECT**:
`…_target_status_message_guid` is the **real `photos` column
`status_message_guid`** (`db/schema.rb:338`), and the note it appears in is the
real join `photo.rb:43` performs
(`belongs_to :status_message, foreign_key: :status_message_guid, primary_key: :guid`
→ `SELECT "posts".* … "posts"."guid" = $$(<photo>_status_message_guid)`).
The fold resolves it CORRECTLY today: `status_message_guid` is the longest
suffix that is a real `photos` column. Renaming it to satisfy `DERIVED_RE`
would make the longest matching suffix `guid` — i.e. would make the fold assert
`posts.guid = photos.guid`, **creating exactly the Rule V defect the audit
exists to catch**. `DERIVED_RE` should key on the value's PROVENANCE (the
`SYM_PARAM_*` family) rather than on a substring of a column name; as written it
cannot distinguish `messages.text`-derived values from the column
`photos.status_message_guid`.

### 10. T-f (M-5) — `set_locale` is modelled, not pinned

`run_dse.rb` now dispatches the REAL `ApplicationController#set_locale` inside
the interceptor run, before the action body, and the User representative carries
a LAZY decision `<rep>_language_available` (minted only when the column is
actually read, so the notification's `recipient` User rep does not acquire a
consequence-free PC). Measured on a 60-run smoke: the decision is recorded on
BOTH polarities, and its closing arm raises the app's own
`I18n::InvalidLocale` after **exactly one target call** — the Devise principal
load — which is precisely M-5's shape. `language` therefore MOVES from the pin
ledger to the GATE list (Rule G: the two sets change in the same edit).

### 11. BOUNDARY CHANGES (Rule T3 — for harvest into `shared/target_boundary.rb`)

Every item is a change to a TARGET DECLARATION or to the shared association
toolkit, implemented batch-locally only because `shared/target_boundary.rb`
does not exist yet. Each voids every endpoint (T2).

| # | target / toolkit | OLD | NEW | the real statement that justifies it |
|---|---|---|---|---|
| C1 | `emit_includes_preloads` (shared preload toolkit) | skipped every POLYMORPHIC reflection, so `includes(:target)` was modelled as a lazy `find_target` with `LIMIT 1` | emits the polymorphic step, attaches the row and leaves the association loaded, so `find_target` does not fire for it | real: `SELECT "posts".* FROM "posts" WHERE "posts"."id" = ?` / `"mentions"."id" = ?` / `"photos"."id" = ?`, all WITHOUT `LIMIT` (26 / 12 / 4 occurrences in this batch's concrete runs) — the corpus had only the `LIMIT 1` form |
| C2 | `emit_includes_preloads` predicate shape | always `= $$(key)` | `IN ($$(key))` when the modelled OWNER COUNT > 1, `= $$(key)` when it is 1 | ActiveRecord's `PredicateBuilder::ArrayHandler` builds an equality for a one-element key set and `IN (…)` for several; both are real (`notification_actors.notification_id` `= ?` 4x / `IN (…)` 22x, `people.id` `= ?` 56x / `IN (…)` 2x, `profiles.person_id` `= ?` 48x / `IN (…)` 2x) |
| C3 | `emit_includes_preloads` belongs_to rep name | `<owner>_<assoc>_row` | `assoc_base_name(owner, assoc)` — the SAME base `find_target` uses | one fact, one variable: a load done by the preloader and a load done lazily must be one rep, and the belongs_to target's `id` IS the owner's FK (same value, same variable) |
| C4 | `SingularAssociation#find_target` belongs_to arm | pinned FOUND unconditionally ("every belongs_to FK … is NOT NULL with an ON DELETE CASCADE foreign key" — factually FALSE) | pinned found only when the FK column is in `FK_BACKED_COLUMNS` (transcribed from `db/schema.rb`'s `add_foreign_key` list); otherwise a LIVE not-found decision | `mentions`, `photos` and `notifications` appear in NO `add_foreign_key`: `mentions.person_id`, `photos.status_message_guid` (`optional: true`), `photos.author_id`, `notifications.recipient_id`, `notifications.target_id` can all dangle |
| C5 | `emit_includes_preloads` belongs_to arm | no not-found arm at all; always attached a row AND its nested step | the same LIVE decision as C4, attaching nil, emitting no read and skipping the nested step | comments_index M-3: a dead decision plus a phantom nested read |
| C6 | `CollectionProxy#records` / `#load_target` | re-described a load the preloader had already performed (a duplicate join-table probe event and a duplicate representative) | returns `@association.target` when the association is `loaded?` — same rep, same length variable, no note | Rails `CollectionAssociation#load_target` returns early when loaded; measured 2 `notification_actors` note events per dump for 1 real statement |
| C7 | `one_fact` memo key | `(kind, receiver.object_id, sql)` | `(kind, sql)` for SELECT-shaped notes | a finder builds a FRESH relation per call, so the same query rendered three times minted three variables |
| C8 | `Discovery.new` (`Anonymous.new`) | a declared TARGET minting an EMPTY note | **unchanged — reported, not changed.** T-h wants it to mint nothing, i.e. to be a shim; Rule S then requires the real body to RUN, and it aborts the JVM (Faraday typhoeus → Ethon → libcurl via JFFI). A shim that cannot be tested is not an improvement over a wall that is declared |

### 12. The second coordinator harvest (B-6 … B-8, M-5 … M-9, T-k … T-p)

| item | this batch |
|---|---|
| **B-6 / T-k** never raise inside a `returns` lambda | The only mock that raises is the SHARED `finder_mock(raise_on_missing: true)` (`concolic_targets.rb:739/749`, `ActiveRecord::RecordNotFound`). LEDGER ENTRY (the allowed close): that arm is **unreachable on this endpoint** — a 2 000-dump scan finds **0** events for every `raise_on_missing: true` target (`FinderMethods#find/find_by!/first!/last!/take!`, `Core::ClassMethods#find/find_by!`) and **0** `RecordNotFound` terminals; the only terminals in this corpus are raises by REAL APP CODE (`I18n::InvalidLocale` from `set_locale`, `ActionView::Template::Error` from the nil-mention / nil-status-message / nil-contact paths), which is what B-6 asks for. Reported as a BOUNDARY item for the shared finder mock; not changed here |
| **B-7 / T-l** length domain 0 / 1 / MANY | APPLIED. `Relation#to_a`/`#records` and `CollectionProxy#records`/`#load_target` now clamp to {0, 1, 3} and record BOTH edges (`len == 0`, `len > 1`) as decisions, exactly as `to_ary` already did; `coverage_report.apply_len_bounds` raises the solver bound for every `*_rows` variable from 1 to 3 (4 for a preloaded association, which carries the extra `>= 4` arm of `notifications_helper.rb:63`). BEFORE: `Relation_records_1/2_rows`, `CollectionProxy_records_*_rows` and `_target_photos_row_rows` were all {0,1} |
| **B-8 / M-9** a note-less target call loses its statement | APPLIED, `noteless_call_audit` PASS (was **5 624 events across 3 267 dumps**, 10 targets). Two distinct classes, fixed differently: (a) arms that DID issue a statement and returned falsy — `FinderMethods#exists?` false arm, `SingularAssociation#find_target` / `BelongsToPolymorphicAssociation#find_target` not-found arms, the shared `finder_mock` not-found arm, and the `emit_includes_preloads` belongs_to not-found arm (which now also EMITS the read it performed) — publish the real SQL via `Thread.current[:concolic_pending_note]`; (b) arms that issue NOTHING — `first`/`last`/`take` on a LOADED relation, `CollectionProxy#records` on a preloaded association, the same on an EMPTY preloaded association, the `Discovery.new` wall and `User#blocks` — publish an explicit NON-SQL note saying so, because "no statement" and "swallowed statement" must not look alike |
| **M-7 / T-o** the preload predicate follows the DISTINCT FK COUNT | APPLIED, and it WITHDREW a change made earlier in this same cycle: the preload note had been made cardinality-driven (`IN (…)` when the modelled owner count > 1) to clear `note_fidelity`'s new `PRED-OP-DIFF`. M-7 is right that a MANY list of N copies of ONE representative has ONE distinct key, so `= $$(key)` is the only shape this model can honestly emit. **Consequence, reported not hidden — see §13** |
| **M-8 / T-p** a nested preload step follows the parents actually loaded | APPLIED: `emit_includes_preloads` threads a `child_count` down (`ocount` through a belongs_to, `ocount * an` through a collection) instead of reusing the outer cardinality, and the nested step is skipped entirely when the parent was not loaded (the B-4 not-found arm) |
| **T-m** an n-valued column encoded as a compare chain | ALREADY SATISFIED, structurally: the dispatch variables are INTEGER seeds with a declared closed domain (`coverage_report.apply_len_bounds`: `SYM_NOTE_TYPE_PROFILE` 0..7, `SYM_POST_STI` 0..1), so `x == v1 ∧ x == v2` is UNSAT for the solver and is never demanded; the STI `type` string compares are compares of ONE string variable against distinct literals, which Z3 also refutes without a declaration |

### 13. The one thing this cycle could NOT close: the multi-key preload shape

With M-7 applied, `note_fidelity_audit` reports `PRED-OP-DIFF` for exactly one
family: the real bulk preloads issued when the page holds MORE THAN ONE
notification —

    real: SELECT "notification_actors".* … WHERE "notification_actors"."notification_id" IN (?, ?)      (22 occurrences)
    note: SELECT "notification_actors".* … WHERE "notification_actors"."notification_id" = $$(…_row_id)
    real: SELECT "people".*   … WHERE "people"."id"          IN (?, ?, ?, ?)
    real: SELECT "profiles".* … WHERE "profiles"."person_id"  IN (?, ?, ?, ?)

This is not a batch defect and no batch action fixes it:

* the app issues `= ?` for ONE owner key and `IN (…)` for several
  (`PredicateBuilder::ArrayHandler` builds an equality for a one-element key
  set) — both are real, and this batch's own concrete runs contain both;
* `src/ruby_runtime/list.rb`'s sampled list holds **one representative row**
  ("Honest limits: one rep row, not N distinct rows"), so a modelled list of
  length 3 is three copies of one row and has exactly ONE distinct key;
* M-7 therefore forbids the only note the model could otherwise render
  (`IN ($$(one_bind))`), and the multi-key state is INEXPRESSIBLE.

The two ways out both live outside a batch: give the sampled list N distinct
row KEYS (a `list.rb` change), or make the projection judge compare per STATE
(a real statement from a state the corpus cannot express is a Class-B gap, not
a Class-S mis-shape). Raised to the coordinator; `note_fidelity_audit` is left
WIRED into `extra_audit_cmds` rather than quietly unwired, so the residue stays
visible in every report.

### 14. Rule G repair found by running the gate audit for real

`pc_visibility_audit --gate` matches a column by `name.endswith("_" + col)`.
Two entries of the inherited `pc_gate_columns` list had never been run through
it (the audit had only ever been invoked with `type,unread,persisted,guid`),
and both were BLIND under that rule:

* **`text`** — this corpus mints `_text_nil`, `_text_has_mention`,
  `_text_has_dlink`, `_text_dlink_is_post`, never a bare `_text`: 0 references.
  `text` is a PIN here (a concrete string with a recorded decision family over
  what the app branches on inside it), so it MOVES to `pc_pin_ledger` with its
  entry — the Rule G edit that adds it to one set removes it from the other.
* **`language`** — the T-f decision was first named `<rep>_language_available`,
  i.e. named for the PREDICATE rather than for the COLUMN, so gating `language`
  read as a blind branch. Renamed to `<rep>_stale_language` (true = the stored
  value is no longer a shipped locale), which is both what the decision means
  and what the audit can see.

### 15. Instrument defects found and reported (not worked around)

1. **`bind_resolution_audit` DERIVED-MISBOUND is a FALSE POSITIVE on a real
   column** — `photos.status_message_guid`. `DERIVED_RE`
   (`_(?:text|body|message|subject)_[a-z0-9_]+\Z`) matches the `_message_guid`
   inside the COLUMN NAME. The audit has already RESOLVED the bind to a real
   `photos` column at that point and then overrides its own positive
   resolution on a name heuristic. The note is the real join `photo.rb:43`
   performs (`belongs_to :status_message, foreign_key: :status_message_guid,
   primary_key: :guid`), and renaming the variable to escape the regex would
   make the fold's longest-column-suffix matcher bind `photos.guid` instead —
   i.e. would CREATE the `posts.guid = photos.guid` join that Rule V exists to
   prevent. SUGGESTED ONE-LINE FIX: re-label as `derived` only when the matched
   suffix is NOT itself a real column of the producing row's table (the audit
   computes exactly that a few lines earlier). The other DERIVED name of this
   batch (`…_target_status_message_author_id`, from the ASSOCIATION name) IS
   fixed here, by a call-site-stable alias.
2. **`note_fidelity_audit` vs the sampled-content model** — see §13.
3. **`skipped_pcs_audit` needs the `queries_from_runs` venv** (`sqlglot`); run
   under plain `python3` it dies with `ModuleNotFoundError` and EXIT=1, which
   is indistinguishable from a RED. Now invoked with the venv interpreter in
   this batch's `_audits6.sh`, as `bind_resolution` already was.
