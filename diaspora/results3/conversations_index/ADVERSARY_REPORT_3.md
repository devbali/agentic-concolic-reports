# conversations_index — ADVERSARY REPORT 3 (round 3, 2026-08-29)

Concrete checker, adversarial sub-agent
(`src/end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md`).
Endpoint `ConversationsController#index`, signed-in only.

**State attacked.** The corpus regenerated after the B-1/B-2 boundary harvest and
regenerated again: engine `complete: true`, `blocking: []`, coverage complete
(75 nodes, 0 missing, 31 846 dumps, 946 326 PCs, `truncated: false`),
assumptions 2 886/2 886 PASS, shims 13 PASS / 18 PROTOCOL / 0 waivers, note
check green, eight audits green, `hardening_lint` clean.

**Method.** Real app only — `concrete_env.rb` sqlite/JDBC with the app schema,
fixture ROWS by raw `INSERT`, real Devise warden resolution, real
`ActionController::TestCase` dispatch, real templates. No mocks, no stubs, no
monkey-patch of app code; nothing under `src/`, the app or the batch's
runner/targets/mocks was touched. Manifests: `adversary3/P*.rb`, runs and
judge output in `adversary3/runs/`.

**One request per concrete SCENARIO** (round 2 put 4–6 requests in one scenario
and could not attribute a statement to a request). Two harness corrections were
needed before any measurement was trustworthy — both are instrument findings in
their own right and are in §5.

---

## 1. The five briefed items

| # | item | verdict | evidence |
|---|---|---|---|
| 1a | **B-1 `reload`** is a target minting exactly its single-row re-read | **CONFIRMED by code + corpus; not judgeable by a real run** | corpus: one note per call, `SELECT "people".* FROM "people" WHERE "people"."id" = $$(<receiver id var>) LIMIT 1`, receiver-bound, never a literal; 1 822 of 12 000 sampled dumps (15.18 %) carry it, always in the sequence `profiles(preload, not-found) → people find_by → Discovery.new WALL → reload → profiles find_target(found)`, which is exactly `person.rb:247-252 name` → `:371-375 fix_profile`. Real `reload` is `self.class.unscoped { self.class.find(id) }` → `SELECT "people".* … "id" = ? LIMIT ?`; the note matches projection, predicate and LIMIT, and the second `profiles` read after the cache clear is emitted, while `profile.nil?` before `fix_profile` is answered from the `includes(:profile)` preload with no query — all four steps faithful. `reload` fired **0** times in 7 real requests over profile-bearing rows (P06), as it must. The only path that reaches it aborts the JVM: `P09_noprofile_lastauthor` (isolated process, one request, a last author with no `profiles` row) died with `SIGSEGV … Problematic frame: C [libjffi-1.2.so+0x7189] closure_invoke+0x39`, exit 134, no `concrete_run.json` — the third confirmation on this endpoint (R1 A03, R2 R03, R3 P09) and exactly the JFFI signature DISCIPLINE §12 diagnosed. Crash log kept at `adversary3/runs/_hs_err_pid159394_P09.log`. |
| 1b | **B-2 `escape_segment`** is a shim minting nothing | **VERIFIED BY A REAL RUN** | the real endpoint calls `ActionDispatch::Journey::Router::Utils.escape_segment` at **depth 0** 1–22 times per request (P06: json 1, html_plain 4, html_cid2 8, html_cid3 10, html_cid1 **22**) and the corpus contains **zero** `escape_segment` events. Minting nothing is correct and now measured, not asserted. |
| 1c | **B-2 `Discovery.new`** is a shim minting nothing | **NOT APPLIED — the matrix cell is wrong** | `Discovery.new` is still a declared TARGET (`targets.rb:1620-1628`) minting the note `DiasporaFederation::Discovery::Discovery.new WALL (network federation discovery; no SQL)` in 1 822 of 12 000 sampled dumps. `ADVERSARY_WINS.md` row **T-h** marks conversations ✅ for "`escape_segment` and `Discovery.new` are shims minting nothing"; only the `escape_segment` half is true. The batch states the reason (AGENT_RUN C8: Rule S requires a shim's real body to RUN and it aborts the JVM), so this is a **matrix bookkeeping error, not a corpus defect** — the cell must be split. No evidence is lost either way: the note is a declared wall carrying no SQL and `statement_note_lint` classes it with `gon`. |
| 2 | **B-8 note channel** — exactly once per call, right shape, no leak | **CLEAN** | `noteless_call_audit` over the full corpus: 682 847 target-call events, **0** note-less non-wall calls. Independent scan of 2 500 dumps: 0 note-less non-wall events; **0** adjacent-identical-note/different-target pairs (the leak signature). Structurally the leak is foreclosed twice: `call_interceptor.rb:248-262 extract_note` clears `Thread.current[:concolic_pending_note]` unconditionally at read, and the one raising finder (`declare_target(fm, :find, raise_on_missing: true)`) returns a `PoisonedRecord` (B-6) instead of raising inside the `returns` lambda — so `ADVERSARY_WINS.md`'s R6 target-level row ("the pending-note channel has no `ensure`") is **inert on this endpoint**, and `find` has 0 events corpus-wide. Falsy arms checked individually: `Relation#empty?` FALSE (contacts) 446 events / 1 note; every `_not_found == True` finder arm carries the finder SQL. The one arm whose *shape* is right but whose *state* is unreachable is in W1 / NM-2, not here. One RETURN-KIND divergence noted and checked inert: the existence family's FALSE arm returns `nil` (`targets.rb:976 v == true ? v : publish_note(...)`), not `false`, a deliberate Ruby-truthiness workaround (`- if no_contacts` and `… && Post.exists?(…) ? a : b` both consume the value in truthiness position, where a `SymbolicBool` would always be true). Every consumer on this endpoint is a truthiness test — `index.haml:32`, `message_renderer.rb:103`, and `messages.present?` via `Object#blank?` → `empty?` (`!nil == !false`) — so the divergence changes no branch and no statement here; it is still a Rule T4 return-kind mismatch and would not be inert on an endpoint that stores or serializes the value. |
| 3 | **Rule D machinery INERT** (`pred_for`, `unique_owner_column?`, `key_set_for`, `second_key`, `loaded_count`) | **the INERT claim HOLDS — verified, not assumed**; but the converse found two defects | No real request produces a multi-owner bulk preload, and the reason is structural: the only two `.includes` on this path are (a) `ConversationVisibility.includes(:conversation).order("conversations.updated_at DESC")`, which `references` `conversations` and therefore **eager-loads into a LEFT OUTER JOIN** — the Preloader never runs (real statement `SELECT "conversation_visibilities"."id" AS t0_r0 … LEFT OUTER JOIN "conversations"`), and (b) `conversation.rb:57 Person.includes(:profile).find_by(id: @last_author_id)`, whose owner set is **one row by construction** (`find_by` ⇒ `LIMIT 1`). Across every real request of this round the preload statement is always `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?` — single key, no `IN`, no `LIMIT`. **The converse found two Rule-D violations, both wins: W1 and W3.** |
| 4a | pinned **`guid`** — is `guid == ''` genuinely unreachable? | **VERIFIED UNREACHABLE BY A REAL RUN** | P07 stored `guid = ''` on a `conversations` row, a `messages` row and a `people` row and read them back through the app: `conversation.guid = "cba3455085b1013f78f6518ff3a98bad"`, `message.guid = "cba6a03085b1013f78f6518ff3a98bad"`, `person.guid = "cbaf581085b1013f78f6518ff3a98bad"`, `blank?` **false** for all three — `Diaspora::Fields::Guid`'s `after_initialize :set_guid` fills it on a row loaded from the database, exactly as the pin argues. All six requests over those rows returned 200. The pin also costs no evidence: the only `guid` predicate any real statement carries is `posts.guid = ?` from a value parsed out of `messages.text` (a `SYM_PARAM_dlink_guid_*`, Rule V), never a rep's own guid. |
| 4b | pinned **`text`** | **pin is sound at the shape level; the recorded decision family is the right model** | the only query-bearing consumer of `messages.text` on this endpoint is `message_renderer.rb:100-105 diaspora_links` → `Post.exists?(guid:)`; the mention family cannot query here, and that is now proved rather than argued: both renderers this action uses pass `mentioned_people: []` and neither sets `link_all_mentions`/`disable_hovercards`, so `Mentionable.format` takes `mention_link`'s `return display_name &#124;&#124; diaspora_id unless person.present?` branch and `people_from_string` (the only `people.diaspora_handle` reader) is never entered. Real: `SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?` 1–2 per request (P07), corpus max 2 — matched. |
| 4c | pinned **`language`** — is the invalid-locale state modelled? | **VERIFIED BY A REAL RUN; the two-arm model is complete** | P08 measured the domain on the live app: `I18n.enforce_available_locales == true`, `AVAILABLE_LANGUAGE_CODES − I18n.available_locales == []`, `inflected_locales == [:pl]`, `DEFAULT_LANGUAGE == "en"`. `language = "xx"` and `language = ""` both raise `I18n::InvalidLocale` in `application_controller.rb:100-108` **before the action body**, and the request issues **exactly one statement** — `SELECT "users".* FROM "users" WHERE "users"."id" = ? ORDER BY "users"."id" ASC LIMIT ?` — on html and on json. The corpus carries exactly that: 13 dumps with `dump_errors {"I18n::InvalidLocale": 13}` and a one-note multiset `{users}`. `language = NULL` is the 200 arm, as the ledger says (but see NM-4). `"en-GB"`, `"de"`, `"pl"` all 200. **T-f/M-5 is applied and correct on this endpoint.** |
| 5 | **H6** — two contacts-tree shapes "no run file has issued" | **NEITHER over-emission NOR a run-coverage gap: an instrument normalizer gap, now fixed in the tool** | both shapes ARE issued by my own real runs — `SELECT contacts.id, profiles.first_name, profiles.last_name, people.diaspora_handle FROM "contacts" INNER JOIN "people" … INNER JOIN "profiles" … WHERE "contacts"."user_id" = ? AND "contacts"."sharing" = ? AND "contacts"."receiving" = ?` in **every request that reaches the action body** — it is `gon.contacts = contacts_data` (`conversations_controller.rb:25`), before `respond_with`, so the only requests without it are the nine invalid-`page` ones that raise two lines earlier, and `SELECT 1 AS one FROM "contacts" WHERE "contacts"."user_id" = ? AND "contacts"."sharing" = ? AND "contacts"."receiving" = ? LIMIT ?` in every **html** request (it is inside `format.html { … no_contacts: current_user.contacts.mutual.empty? }`, so json and mobile correctly do not issue it — the corpus agrees: `contacts_exists` occurs in 100 % of html dumps and 0 % of json/mobile dumps). The CHECK came from `hardening_lint._shape` normalizing `?`, digits and quoted strings to `@` but leaving bare `true`/`false`, so a note rendered through `to_sql` (which INLINES booleans) could never match the wire form that BINDS them. `reports/diaspora/tools/hardening_lint.py:39-50` now carries `re.sub(r"\b(true\|false)\b", "@", s)` and H6 prints `ok` on the unchanged corpus. Nothing is owed by the batch. |

---

## 2. Scenarios run

**75 requests + 3 in-process probes over 12 manifests / 15 JRuby processes**
(P01–P03 were re-run after the two harness corrections of §5, so three
processes are superseded; one process — P09 — aborted the JVM, as expected).
One scenario per request; `flock /tmp/concolic-slot.lock` inside
`systemd-run --user -p MemoryMax=4000M -p MemorySwapMax=0`,
`JAVA_TOOL_OPTIONS` unset.

| manifest | fixtures | requests | outcome |
|---|---|---|---|
| `P01_page_domain` | batch's 2 conversations | page `nil`, `1`, `0`, `-1`, `abc`, `""`, `["2"]`, `1.5`, `99999999999999999999`, `0`+json, `0`+mobile, `2` | **W3** — every invalid value raises before any read of the inbox |
| `P02_cid_shapes` | batch's 2 conversations | `conversation_id` = `"1"`, `["1","2"]`, `["1"]`, `["1","2","999"]`, `["998","999"]`, `["1","2"]`+json, `["1","2"]`+mobile, `""`, `{"foo"=>"1"}`, `[["1","2"]]` | **W2** — `IN (…)`; judge RED |
| `P03_formats` | batch's 2 conversations | html, js, js+cid, xml, xml+cid, atom, csv, text, `Accept: application/xml`, explicit mobile | **W4** |
| `P04_setread_unchanged` | conv 1 my `unread = 0`; conv 2 my `unread = 3`, 4 messages | cid 1 ×2 html + json + mobile; cid 2 html, cid 2 html again, cid 2 json | **W1** |
| `P05_real_layout` | batch's 2 conversations, `layout(false)` NOT applied (`ADV3_REAL_LAYOUT=1`) | html, html+cid, mobile, json | rig cannot render the real layout — §6 |
| `P06_cardinality` | conv 1: 5 messages / 2 authors / **6 participants**; conv 2: **0 messages**; conv 3: 1 message / 2 participants | html, mobile, html+cid1, mobile+cid1, json, html+cid2, html+cid3 | **NM-1** (multiplicity), 1b, 1a |
| `P07_row_edges` | `guid = ''` on a conversation, a message and a person; NULL / `""` / `"   "` / 40-char subjects; participant with **no profile**; **closed account**; **remote pod** (`pods` row + `people.pod_id`); message author who is **not a participant**; blank-name profile; a `diaspora://…/post/<guid>` link | probe + html, mobile, html+cid1, mobile+cid1, html+cid3, json | 4a, 4b — all 200 |
| `P08_language` | 7 principals: `en`, `xx`, `""`, `pl`, NULL, `en-GB`, `de`, each with its own person+profile | domain probe + 8 requests | 4c |
| `P09_noprofile_lastauthor` | last author has **no `profiles` row** (isolated process) | html | JVM `SIGSEGV`, exit 134 — §6 |
| `P10_locale_leak` | principals `de`, NULL, `pl` interleaved | 6 requests | **NM-4** |
| `P11_layout_gon_probe` | batch's 2 conversations + an `aspects` and a `notifications` row | 1 in-process probe (`UserPresenter#to_json`) + 1 control request | **NM-5** — the `layout(false)` pin costs 7 shapes over 4 tables |
| `P12_unread_negative` | my visibility `unread = -3` (raw insert; no app path writes a negative, the column has no CHECK) | cid ×2 + a control | completes W1's derivation |

---

## 3. WINS

### W1 — a write target's note is unconditional; Rails partial writes issue **no statement** for an unchanged record — **Class S (with a Class-B cause) · TARGET-LEVEL**

**Scenario** (`adversary3/P04_setread_unchanged.rb`): a conversation whose
`conversation_visibilities` row for the signed-in person already has
`unread = 0`, requested with `?conversation_id=<that conversation>`. Reproduced
on html (twice), json and mobile, and by simply repeating the *same* request
that had just zeroed the counter (`cid2_unread3_first` → `cid2_now0_second`).

**What the corpus asserts.** `ActiveRecord::Base.save` carries exactly ONE note
corpus-wide, emitted on every call:

    UPDATE "conversation_visibilities" SET "unread" = ?, "updated_at" = ? WHERE "conversation_visibilities"."id" = $$(SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_id)

**What the real endpoint issues** in that state (verbatim, `P04_cid1_unread0_json`):

    BEGIN TRANSACTION                                                       under ActiveRecord::Base#save
    SELECT "people".* FROM "people" WHERE "people"."id" = ? LIMIT ?          under SingularAssociation#find_target
    COMMIT TRANSACTION                                                      under ActiveRecord::Base#save

— **no UPDATE at all.** `conversation.rb:37-42 set_read` assigns `unread = 0` to
a row that is already 0, so `changed?` is false, the timestamp callback does not
fire and `_update_record` writes nothing
(`activerecord-5.2.4.3/lib/active_record/persistence.rb`, partial writes). The
`belongs_to :person` presence validation still runs, which is why the
transaction and the `people` read remain.

**Code line.** `app/models/conversation.rb:41 visibility.save`, from
`app/controllers/conversations_controller.rb:22 @conversation.set_read(current_user)`.
Emitted by `targets.rb`'s `ActiveRecord::Base#save` declaration (the shared
write-target family, `TARGET_FUNCTIONS.md` §1 "writes | `ActiveRecord::Base` |
`save save! update update! update_attribute touch destroy destroy!`").

**Why it is a Rule D (DISCIPLINE §13) defect, and how large.** Whether the write
happens is *determined* by a fact the corpus already records:
`first_unread_message` (`conversation.rb:32`) runs
`conversation_visibilities.where(person_id: …).where('unread > 0').first` on the
SAME physical row (`(conversation_id, person_id)` is UNIQUE,
`db/schema.rb:146`), so for every state the APPLICATION can produce, "the
first-unread finder found nothing" ⇒ that row's `unread` is 0 ⇒ **no UPDATE is
possible** (and for a schema-permitted negative value it is the opposite — see
P12 below). Over a 12 000-dump systematic sample (37.7 % of the
corpus) **1 488 dumps (12.40 %, ≈ 3 950 corpus-wide)** assert the UPDATE note
together with the first-unread finder having returned NOTHING. The corpus's only route to "no
UPDATE" is set_read's own `find_by` returning nil —
which is **unreachable**: the conversation was selected *by* that very row
(`conversations_controller.rb:14-18` joins `conversation_visibilities` on
`person_id = mine AND conversation_id = params[:conversation_id]`) and the pair
is uniquely indexed. That decision is taken TRUE in **1 607 of 12 000 dumps
(13.39 %, ≈ 4 265 corpus-wide)**. So one variable carries two facts ("the
visibility row exists" and "the write happens"), and the reachable half of the
write decision is not modelled at all — the §13 pattern M-13 named, on a WRITE.

**Policy consequence.** A policy extracted from this corpus says *"the endpoint
writes `conversation_visibilities` unless the visibility row is missing"*. The
truth is *"it writes iff that row's `unread` was non-zero"* — a different
predicate, over a different (and reachable) condition. Both judges are EXACT on
the run and all eight audits pass, because the UPDATE shape *is* issued by
*some* real request.

**Completed by `P12_unread_negative`: the write is not a function of anything the
corpus records.** `unread` is `integer default 0 NOT NULL` with no CHECK
(`db/schema.rb:143`) and no app path writes a negative value (`Message#increase_unread`
only increments, `set_read` writes 0) — legacy data, the standing M-6 established.
With `unread = -3` the first-unread finder
(`… AND (unread > 0) … ORDER BY "conversation_visibilities"."id" ASC LIMIT ?`)
still returns **nothing** — the corpus state — and the real request **does** issue
the `UPDATE`, because `-3 → 0` is a change. Repeating the request (now 0) gives
BEGIN/COMMIT and none; the `unread = 0` control gives BEGIN/COMMIT and none. So
inside ONE corpus state the endpoint both writes and does not write, decided by a
value the corpus does not model at all. The unconditional note is therefore not
"wrong on one arm" — the write has no representation in the corpus.

**Corroborated accidentally.** `P02_cid_shapes` reproduces it without trying: its
first request (`ctl_scalar1`, `conversation_id=1`) carries `UPDATE cv ×1`, and the
next request in the same process — a *different* parameter shape over the *same*
conversation — carries none, because the first one zeroed the counter. Nine of the
ten P02 requests therefore run in the state the corpus cannot express — and the same
happens inside `P03_formats`, `P06_cardinality` and `P07_row_edges`.

**TARGET-LEVEL**: the rule — *a write target's note follows the record's dirty
state; an unchanged record issues no statement* — lives in the shared write
target family, not in this action. Every batch that models `save` / `update` /
`touch` / `update_attribute` inherits it.

### W2 — `params[:conversation_id]` is a QUERY parameter and may be an Array: `conversation_id IN (?, ?)` — **Class B (S consequence) · ENDPOINT-LEVEL**

**Scenario** (`adversary3/P02_cid_shapes.rb`):
`GET /conversations?conversation_id[]=1&conversation_id[]=2`.
`resources :conversations` (`config/routes.rb:79`) makes `conversation_id` a
plain query parameter of `#index` — unlike comments_index's `post_id`, which is
a path segment and therefore could never carry an array (that batch's R2
near-miss). `conversations_controller.rb:13-18` puts the value straight into
`where(conversation_visibilities: { …, conversation_id: params[:conversation_id] })`.

**Novel shape, verbatim** (`P02_array_1_2`, under `ActiveRecord::Relation#records`):

    SELECT "conversations".* FROM "conversations" INNER JOIN "conversation_visibilities" ON "conversation_visibilities"."conversation_id" = "conversations"."id" WHERE "conversation_visibilities"."person_id" = ? AND "conversation_visibilities"."conversation_id" IN (?, ?) ORDER BY "conversations"."id" ASC LIMIT ?

**Code line.** `app/controllers/conversations_controller.rb:14-18`
(`Conversation.joins(:conversation_visibilities).where(conversation_visibilities: {person_id: …, conversation_id: params[:conversation_id]}).first`).

**What the corpus has.** `run_dse.rb:266` mints `params[:conversation_id]` as a
single `symint` (`SYM_PARAM_conversation_id`), so the predicate is always `= $$(…)`.
`grep -l ' IN (' dump_*.json` over all **31 846** dumps returns **0 files** —
there is no `IN (…)` note of any kind in this corpus, and AGENT_RUN C10-2 records
that as a positive property ("0 `IN` in either").

**Reproduced at arities 2 and 3, on html, json and mobile, on both arms**:
`["1","2"]`, `["1","2","999"]` (found ⇒ the full `first_unread_message` +
`set_read` + render follow), `["998","999"]` (not found ⇒ `@conversation` nil,
4 082-byte body identical to the no-cid render), `[["1","2"]]` (Rails flattens
the nested array ⇒ same `IN (?, ?)`). A **one**-element array `["1"]` collapses to
`= ?` — ActiveRecord's `PredicateBuilder::ArrayHandler` (`when 1 then build(attribute, values.first)`),
the same mechanism as M-7 on comments_index. `""`, a Hash and a non-numeric value
all render the corpus's `= ?` shape and were already covered.

**Confirmed independently by the batch's own judge**: `note_fidelity_audit`
returns **PRED-OP-DIFF ×2, EXIT=1** on `adversary3/runs/P02_cid_shapes.json`
(`adversary3/runs/P02_cid_shapes.judge.txt`) — the only RED of the round.

**ENDPOINT-LEVEL** (this action's own parameter), but the *class* is
cross-endpoint: any query parameter fed into a `where` can arrive as an Array,
and modelling it as a scalar forecloses the `IN` predicate. See the new
cross-endpoint pattern in `ADVERSARY_WINS.md`.

### W3 — the `params[:page]` domain: an invalid page terminates the action after **two** statements — **Class B · ENDPOINT-LEVEL**

**Scenario** (`adversary3/P01_page_domain.rb`): `GET /conversations?page=0` (also
`-1`, `abc`, `""` , `1.5`, `99999999999999999999`, `page[]=2`), on html, json and
mobile.

**Behaviour.** `will_paginate-3.3.0/lib/will_paginate/page_number.rb:14-23`
does `value = Integer(value)` and raises, tagged `WillPaginate::InvalidPage`:
`RangeError: invalid page: 0` / `invalid page: -1`,
`ArgumentError: invalid value for Integer(): "abc" / "" / "1.5"`,
`TypeError: no implicit conversion of Array into Integer`, and for a page past
`BIGINT/per_page`, `RangeError: invalid offset: 1499999999999999999970`. The
raise happens inside `conversations_controller.rb:8-11 .paginate(page: params[:page], per_page: 15)`
— i.e. **after** `set_locale`'s `user_signed_in?` has resolved the Devise user
and **after** `current_user.person_id` has loaded the principal's person, but
**before** `gon.contacts = contacts_data`, before the visibilities COUNT, before
the visibilities load and before the `contacts.mutual.empty?` probe.

**The multiset the corpus lacks — measured, all eleven invalid values.** With the
corrected warden (§5 INSTR-1) every one of `0`, `-1`, `abc`, `""`, `["2"]`, `1.5`,
`99999999999999999999`, on html, json and mobile, issues exactly

    SELECT "users".* FROM "users" WHERE "users"."id" = ? ORDER BY "users"."id" ASC LIMIT ?
    SELECT "people".* FROM "people" WHERE "people"."owner_id" = ? LIMIT ?

— the multiset `{users ×1, people.owner_id ×1}`, two statements, then a 500.
`_multiset_check.py` over an 8 000-dump systematic sample: **`set_exact = 0`** — no
corpus dump has that statement set (and none has that multiset). Over a 12 000-dump systematic sample the corpus's
per-dump statement-note count is `1` (5 dumps — the `I18n::InvalidLocale` arm)
and then jumps straight to `4`; **there is no 2-statement and no 3-statement
dump anywhere**, and `grep -l 'InvalidPage' dump_*.json` returns **0 of 31 846**. `run_dse.rb:252-264` models `page` as the single boolean
`SYM_PARAM_page_beyond` with the concrete values `nil` and `"2"`; every other
value in the domain is foreclosed, and no `WillPaginate::InvalidPage` terminal
exists in `dump_errors` (which lists only `I18n::InvalidLocale`; the corpus has exactly **13** dumps with any
`error` field at all, and 0 mentioning `Template::Error`, `UnknownFormat` or
`InvalidPage`). The control `page=2` (beyond the last page, the cycle-4 NM-2 repair)
scores **EXACT against 7 corpus dumps** — so the modelled half of the `page` domain is
verified correct by the same run.

**Code line.** `app/controllers/conversations_controller.rb:11`
`.paginate(page: params[:page], per_page: 15)` →
`will_paginate/active_record.rb:171 ::WillPaginate::PageNumber(num.nil? ? 1 : num)`.

**Why round 2 missed it.** `ADVERSARY_REPORT_2.md` ran the same values (N03) and
concluded "raised … **before** Devise's user lookup — no statement can result".
That reading came from a harness in which the resolved `User` is memoised on the
lambda's `self` (= `main`) and therefore **once per PROCESS**: after the first
request of a manifest, the `users` and `people.owner_id` reads simply stop being
issued. Fixed in `adversary3/_common.rb` (memo moved onto the per-request warden
object) — see §5, INSTR-1.

### W4 — the FORMAT domain: `.js` performs the whole html render (and the WRITE) before its 500, and four undeclared formats stop after three statements — **Class B · ENDPOINT-LEVEL**

`respond_to :html, :mobile, :json, :js` (`conversations_controller.rb:5`) and a
`respond_with` block that registers only `format.html` and `format.json`
(`:26-30`). `format_coverage_audit.py` judges the DECLARED list only, so `:xml`,
`:atom`, `:csv`, `:text` are outside every check this batch runs. Measured
(`P03_formats`, one request per scenario):

| request | statements | terminal |
|---|---|---|
| `GET /conversations.xml` (also `.atom`, `.csv`, `.text`) | `{users, people.owner_id, contacts_pluck}` — **3** | `ActionController::UnknownFormat` |
| `GET /conversations.xml?conversation_id=1` | `{users, people.owner_id, conv_lookup, cv_first_unread, cv_find, people.id, contacts_pluck}` + `BEGIN`/`COMMIT` (+ the `UPDATE` when `unread > 0`) — **9** | `ActionController::UnknownFormat` |
| `GET /conversations.js` | `{users, people.owner_id, contacts_pluck, vis_count, vis_rows, msg_rows ×2, people.id ×3, part_rows ×2, profiles LIMIT ×3, profiles preload}` — **16** (the html control is 17; the one missing statement is `contacts_exists`) | `ActionView::Template::Error: undefined local variable or method 'no_contacts'` |
| `GET /conversations.js?conversation_id=1` | the full html read set **including** `UPDATE "conversation_visibilities"` — **34** | same |

Two things follow.
(a) The corpus has **no 3-statement dump** (per-dump note counts over a
12 000-dump systematic sample are `1` — the locale arm — then `4`), and
`_multiset_check.py` gives `set_exact = 0` for the `.xml` and `.xml?conversation_id=`
sets over an 8 000-dump sample, so neither is a state the corpus models; and the `.xml?conversation_id=`
variant performs the endpoint's WRITE without ever reading the inbox, which no
corpus path does.
(b) `.js` is DECLARED, and the responder falls through to `default_render`, which
renders `index.haml` itself — so `.js` performs the whole conversation-list
render, every `_conversation.haml` partial included. The only thing it does *not*
issue is the `contacts.mutual.empty?` probe, because that lives inside the
`format.html` block that never runs.


**Why this is a win and not a near-miss.** The exclusion of `:js` rests on one
sentence — `run_dse.rb:219-221`, "*templateless (responders' to_js →
default_render → Template::Error, a real 500 with **no data access beyond the
html prefix**) — not a corpus scenario*" — and `format_coverage_audit.py` reports
`js TEMPLATELESS … not required` on the strength of it. The measurement refutes
it: `.js` renders `index.haml` in full. `GET /conversations.js?conversation_id=1`
therefore issues **34** statements including
`UPDATE "conversation_visibilities" SET "unread" = ?, "updated_at" = ? WHERE "conversation_visibilities"."id" = ?`
and terminates in `ActionView::Template::Error`, a terminal that appears in no
corpus dump (`dump_errors` lists only `I18n::InvalidLocale`). This is the M-5
pattern: a pinned-away state whose written neutrality argument is factually
wrong. The undeclared formats are the same defect one step further out —
`format_coverage_audit` cannot see a format that is not in `respond_to`, and
`GET /conversations.xml?conversation_id=1` performs the endpoint's only WRITE
without reading the inbox at all, on a 9-statement path whose statement SET
no corpus dump has (`set_exact = 0`).

**Code line.** `app/controllers/conversations_controller.rb:26-30`
(`respond_with do |format| format.html {…}; format.json {…} end`) with
`:5 respond_to :html, :mobile, :json, :js`; the raise for `:js` is
`ActionView::Template::Error` out of `index.haml:32 - if no_contacts`
(the local is only supplied by the `format.html` block), and for an undeclared
format `ActionController::UnknownFormat` out of `respond_with`'s collector.


---

## 4. Near-misses (a real defect, no novel SQL shape)

### NM-1 — per-render MULTIPLICITY: the corpus ceiling is roughly a third of a real render

The sampled-list model keeps one (or two) representative rows, so every
per-row statement is emitted once per representative while the real request
issues one per row. Measured on `P06_cardinality` (conv 1: 5 messages / 2
authors / 6 participants; conv 2: 0 messages; conv 3: 1 message):

| statement | corpus MAX per dump (8 000-dump systematic sample) | real (P06) |
|---|---|---|
| `SELECT COUNT(*) FROM "messages" …` | 2 | **5** |
| `SELECT "messages"."author_id" FROM "messages" …` | 1 | **2** |
| `SELECT "messages".* FROM "messages" …` | 2 | **4** |
| `SELECT COUNT(*) FROM "people" INNER JOIN "conversation_visibilities" …` | 2 | **4** |
| `SELECT "people".* FROM "people" INNER JOIN "conversation_visibilities" …` | 2 | **4** |
| `SELECT "people".* FROM "people" WHERE "people"."id" = ? LIMIT ?` | 6 | **14** |
| `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?` | 5 | **19** |
| `SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?` (preload) | 1 | **2** |

The mobile messages COUNT is worth stating exactly, because it is not a simple
"once per conversation": `_conversation_subject.haml:3 conversation.messages.size`
and `conversation.rb:55 messages.size > 0` (inside `last_author`) each issue a
COUNT, **except** that `CollectionAssociation#count_records` calls `loaded!` when
the count is zero — so a conversation with messages costs **two** COUNTs and an
empty one costs **one**. P06's three conversations (5 / 0 / 1 messages) issue
exactly `2 + 1 + 2 = 5`, and the corpus tops out at 2 per dump. Same family as
comments_index R5-N5-2 / R6 (`open (declared limit)`); this is the first
measurement of it on conversations_index.

### NM-2 — two `_not_found` decisions over states the SCHEMA forecloses

Beside set_read's `find_by` not-found (folded into W1 above, ≈ 4 265 dumps), the corpus
takes the last-author finder's `_not_found == True` in **1 063 of 12 000** sampled dumps
(8.86 %, ≈ 2 820 corpus-wide). That is
`conversation.rb:57 Person.includes(:profile).find_by(id: @last_author_id)`
returning nil. It cannot: `last_author` returns early unless `messages.size > 0`
(`conversation.rb:55`), `@last_author_id` is then `messages.pluck(:author_id).last`,
a non-nil `messages.author_id`, and `messages.author_id` carries
`add_foreign_key "messages", "people", column: "author_id", on_delete: :cascade`
(`db/schema.rb`). On that arm the corpus also drops the real
`profiles.person_id = ? LIMIT ?` read for the last author, so the state removes
evidence as well as adding a branch. Cross-endpoint pattern 8 ("a decision over
an impossible state inflates the universe"), same class as the `guid == ''`
family this batch already retired. The batch's own B-4 rule (`targets.rb:409-430`)
states the FK argument for `belongs_to`; it just does not reach a class-level
`find_by` on an FK-backed column.

### NM-3 — `<list>_index_in_range` is a FREE decision over a quantity two other recorded decisions determine

`conversation.rb:33 self.messages.to_a[-visibility.unread]`. The corpus records
`((- …_first_2_unread) == 0)`, `((- …_first_2_unread) == -1)`,
`(len(<messages list>_rows) > 1)` **and** `(<messages list>_rows_index_in_range == True)`
as four independent decisions, but the fourth is determined by the second and
third: the index is in range iff `unread <= len(messages)`. In a 3 000-dump
sample, **47 dumps** pair `(-unread) == -1` FALSE (so `unread >= 2`, since the
row came from `where('unread > 0')`) with `len(rows) > 1` FALSE (so exactly one
message) and `index_in_range == True` — `[-2]` on a one-element array is `nil`,
so that combination cannot occur. Rule D §13. **No statement consequence**: the
result only reaches `@first_unread_message_id`, which
`_message.html.haml:1` / `_message.mobile.haml:1` render as an HTML `id`
attribute — which is why it is a near-miss and not a win.

### NM-4 — `users.language = NULL` does not RESET the locale, so the principal's `profiles` read depends on the PREVIOUS request in the thread

`application_controller.rb:100-108` assigns `I18n.locale = current_user.language`;
for a NULL language that is `I18n.locale = nil`, which stores nil and lets the
getter fall back to `default_locale` — it does not restore the inflector's
notion of the locale. In `P08_language` the NULL principal, requested
immediately after the `pl` principal, issued the inflected-locale read
`SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ? LIMIT ?`
(`set_grammatical_gender` → `current_user.gender`) that only `pl` should cause —
19 statements, identical to the `pl` principal, while `de` and `en-GB` issued 18.
**Isolated in `P10_locale_leak`** — the SAME principal (uid 13, `language = NULL`), the SAME fixtures, the SAME request, six times, alternating with a `de` and a `pl` principal:

| request | `I18n.locale` after it | `inflected_locale?` | principal `profiles` read | body |
|---|---|---|---|---|
| `de` | `:de` | false | no | 2 243 B |
| **NULL after `de`** | **`:de`** | false | **no** | 2 243 B |
| `pl` | `:pl` | true | yes | 2 215 B |
| **NULL after `pl`** | **`:pl`** | **true** | **yes** | 2 215 B |
| `de` again | `:de` | false | no | 2 243 B |
| **NULL after `de`** | **`:de`** | false | **no** | 2 243 B |

So `I18n.locale = nil` does not restore the default — it leaves the previous
request's locale in place — and the NULL-language principal's statement set is
decided by whoever used the thread before it. The ledger's claim that
`language = NULL` is the 200 arm holds; what does not hold is that the arm has a
fixed statement set. Both polarities of the read are already in the corpus
(`…_devise_user_first_1_person_profile_not_found`), so no evidence is lost —
but the batch's `language` ledger note says the inflected branch "costs no
evidence" on the strength of it being tied to `pl`, and it is not.

---

### NM-5 — the `layout(false)` scope pin costs SEVEN statement shapes over FOUR tables the corpus never mentions

Every batch sets `ConversationsController.layout(false)` "for render-config
parity"; the real action renders
`layout proc { request.format == :mobile ? "application" : "with_header_with_footer" }`
(`application_controller.rb:45`), whose `_head.haml:24` calls
`include_gon(camel_case: true, nonce: …)`, which serializes the `UserPresenter`
`gon_set_current_user` pushed at `application_controller.rb:183-188`. `P05` shows
the rig cannot render that layout (sprockets), so `P11_layout_gon_probe` measures
`UserPresenter#to_json` directly on the real principal. It issues **ten**
statements, of which **seven shapes over four tables appear nowhere in the
corpus** (`notifications`, `roles`, `aspects`, `services` occur **0** times in all
31 846 dumps, by `grep -l` and by a 4 000-dump note scan):

    SELECT COUNT(*) FROM "notifications" WHERE "notifications"."recipient_id" = ? AND "notifications"."unread" = ?
    SELECT SUM("conversation_visibilities"."unread") FROM "conversation_visibilities" WHERE "conversation_visibilities"."person_id" = ?
    SELECT 1 AS one FROM "roles" WHERE "roles"."person_id" = ? AND "roles"."name" = ? LIMIT ?
    SELECT 1 AS one FROM "roles" WHERE "roles"."name" IN (?, ?) AND "roles"."person_id" = ? LIMIT ?
    SELECT "aspects".* FROM "aspects" WHERE "aspects"."user_id" = ? ORDER BY order_id ASC
    SELECT "services".* FROM "services" WHERE "services"."user_id" = ?
    SELECT COUNT(*) FROM "contacts" WHERE "contacts"."user_id" = ? AND "contacts"."receiving" = ?

The second one matters most: it is a **`conversation_visibilities` aggregate**
(`User#unread_message_count`, `user.rb:113-115`) with a projection and a predicate
the action itself never issues — on the very table this endpoint's access control
is about. The fourth carries an `IN (?, ?)`, a predicate operator the corpus has
none of (cf. W2).

**Why this is a near-miss and not a fifth win.** I could not make the ENDPOINT
issue them: the rig fails on the asset pipeline before `include_gon` runs, so the
evidence is a probe over the presenter the endpoint's own `before_action`
constructs, not the endpoint's render. The link is code-level and solid
(`_head.haml:24` is in `with_header_with_footer.html.haml`'s `_head` and
`gon_set_current_user` runs on every signed-in request), but the standard this
project sets is "a win is only closed — or opened — by a REAL run". It is
**TARGET-LEVEL** if it stands: `gon_set_current_user` and the layout are
`ApplicationController`'s, and all three active batches carry the same pin.

---

## 5. Instrument findings (the rig, not the corpus)

**INSTR-1 — the concrete rig resolves the principal ONCE PER PROCESS, so every
request after the first is missing the Devise `users` read and the
`people.owner_id` read.** `install_real_warden`'s memo is written as
`@concrete_user ||= User.serialize_from_session(uid, salt)` inside a lambda
defined at method scope, so the ivar belongs to `main`, not to the per-request
warden object. The batch's own `concrete_manifest_auth.rb`, `adversary/_common.rb`
and `adversary2/_common.rb` all have this form — which is why
`concrete_run.json` shows **one** `SELECT "users".*` for **five** requests. It is
not cosmetic: it is exactly the evidence the M-5 / T-f one-statement multiset is
made of, and it is why round 2 concluded that an invalid `page` produces "no
statement" (W3). Fixed for this round in `adversary3/_common.rb` by moving the
memo onto the warden object. R4 recorded the same memo as a comments_index
harness note; the consequence for a *statement* differential was not.

**INSTR-2 — `concrete_run_probe.rb` drops query-cached statements
(`next if payload[:cached]`), and the ActiveRecord query cache is not cleared
between requests of a manifest.** So a statement repeated by a later request of
the same process silently disappears from the ground truth. `adversary3/_common.rb`
now calls `ActiveRecord::Base.connection.clear_query_cache` before each request
(a real deployment gives every request its own cache). Combined with INSTR-1
this means **every multi-request concrete manifest in this batch under-reports**,
and the under-report grows with the number of requests in the scenario.

**INSTR-3 — `ConcreteEnv.quote` now writes booleans in the adapter's
representation, and the adapter's is `'t'` — so every fixture that wrote
`sharing: 1, receiving: 1` has matched NOTHING.** Measured live:
`adapter=SQLite quoted_true="'t'" quoted_false="'f'"`. `concrete_manifest_auth.rb:33`,
`adversary/_common.rb:35` and `adversary2/_common.rb:35` all insert the contact
with integer `1`, so `Contact.mutual` (`where(sharing: true, receiving: true)`)
returned nothing in **every** concrete run this batch has ever made:
`contacts_data` plucked an empty list and `no_contacts` was always **true**, so
`_new.haml` was never rendered. This round's fixtures pass `true`; the
`no_contacts == false` arm is now exercised for the first time
(`_body_ctl_nil.txt` contains `new-conversation form-horizontal`) and it changes
**no statement** — `_new.haml` renders `form_for Conversation.new`, which issues
nothing. So the arm is closed positively, but the fixture bug should be fixed in
the batch's manifest before the next round reads anything into a `contacts` result.

**INSTR-4 — `hardening_lint` H6's normalizer gap is fixed.** See §1 item 5.
`reports/diaspora/tools/hardening_lint.py:39-50` now normalizes bare
`true`/`false` the same way it already normalized `?`, digits and quoted
strings, and H6 prints `ok` on the unchanged 31 846-dump corpus. My own real
runs issue both flagged shapes, so the verdict is independent of the tool fix.

**INSTR-6 — a `SYM_RESULT_*` ordinal names a CALL ORDER, not a call SITE, so any
corpus cross-tab keyed on the variable NAME silently conflates call sites.**
`SYM_RESULT_ActiveRecord__Relation_to_a_1` is the paginated `@visibilities` list in
the `*_plain` scenarios and the SELECTED conversation's `messages` in the
`*_withcid` ones; `…_FinderMethods_find_by_1` is `set_read`'s visibility lookup with
a `conversation_id` and `last_author`'s `Person.find_by` without one. A first pass at
this round's W1 numbers, keyed on `find_by_1`/`find_by_2`, gave 18.48 % / 3.77 %;
keyed on the NOTE the same sample gives 13.39 % / 8.86 %. Every figure in §7 is
note-keyed. Worth stating because the corpus's own `pc_visibility` and
`cardinality_consistency` machinery matches by name suffix — the same hazard
notifications_index diagnosed for `cardinality_consistency` (DISCIPLINE §13, "attributed binds by name prefix").

**INSTR-5 — the judges score the adversary's own in-process probes.** R7
recorded this on comments_index; it reproduced here. `P07_guid_probe`'s
`Conversation.find(1)` / `Message.find(31)` / `Person.find(4)` appear in
`concrete_run.json` as `SELECT "conversations".* FROM "conversations" WHERE
"conversations"."id" = ? LIMIT ?` and `SELECT "messages".* … "id" = ? LIMIT ?`
and are reported by `_multiset_check.py` as novel shapes. They are mine, not the
endpoint's; a round that reads those as findings files phantoms.

---

## 6. Branches I could not reach, and why

| branch | why |
|---|---|
| `Person#fix_profile` → `Discovery#fetch_and_save` → `reload` (a profile-less LAST AUTHOR or message author) | JVM abort — `Faraday.default_adapter == :typhoeus` → Ethon → libcurl through JRuby's JFFI (DISCIPLINE §12, diagnosed by comments_index R4). Attempted isolated in `P09_noprofile_lastauthor`: `SIGSEGV`, `C [libjffi-1.2.so+0x7189] closure_invoke+0x39`, exit 134, 5 min 32 s, no run file. Note that comments_index R7 narrowed the blanket claim: a `…_profile_not_found == True` arm IS reachable where the caller supplies a display name instead of calling `person.name`. **That narrowing does not help this endpoint**: every profile-less rep here is either guarded by `person_image_tag` / `person_image_link` (`people_helper.rb:37,43` return `""` before `Person#name` — verified, P07's profile-less carol renders 200 on html, mobile and json) or reaches `person.name` with no display-name alternative (`_conversation.haml:31`, `_conversation.mobile.haml:17`, `_message.html.haml:5` / `_message.mobile.haml:6` via `person_link`). There is no `display_name` call site on this action. |
| a `conversation_visibilities` row whose `conversation` is missing; a `messages.author_id` / `conversations.author_id` that dangles | `add_foreign_key … on_delete: :cascade` on all four columns (`db/schema.rb`), all `NOT NULL`. Not an app state — the same standing as rounds 1 and 2 recorded. |
| the real layout / site chrome (`gon_set_current_user` → `UserPresenter`) | a declared batch scope pin (`layout(false)`). Attacked directly in `P05_real_layout` (`ADV3_REAL_LAYOUT=1`, no `layout(false)`): the rig cannot render it — `ActionView::Template::Error: couldn't find file 'underscore' with type 'application/javascript'` on html and `'jquery-textchange'` on mobile, i.e. sprockets fails before `include_gon` is reached. json (no layout) matched the corpus EXACTLY. So the pin stays unjudged by a real run; what it excludes is measured with an in-process probe in `P11_layout_gon_probe` — `UserPresenter#to_json` (`application_controller.rb:183-188`) reads `user.person.as_api_response(:backbone)`, `user.unread_notifications.count`, **`user.unread_message_count` = `ConversationVisibility.where(person_id: …).sum(:unread)`** — a `conversation_visibilities` AGGREGATE with a projection and predicate the action never issues — `user.contacts.receiving.count`, `user.aspects` and `user.services`. |
| an anonymous request | `before_action :authenticate_user!` with no `except:`; Devise 401s before the action. |
| `Mentionable.people_from_string` / `Person.find_or_fetch_by_identifier` (the `people.diaspora_handle` family) | unreachable by code, now with a proof rather than an assertion: `Message#message` builds `MessageRenderer.new(text)` with no options, so `mentioned_people` is `[]` and neither `link_all_mentions` nor `disable_hovercards` is set; `render_mentions` therefore takes `make_mentions_plain_text` → `Mentionable.format(text, [], plain_text: true)` → `mention_link`'s `return display_name &#124;&#124; diaspora_id unless person.present?`. `filter_people`, the only caller of `people_from_string`, is unreachable. 0 such statements in 45 real requests, several of which carried `@{…}` markup. |
| blocked / ignored people | not re-tested and not testable: `blocks` and `ignored` appear **nowhere** on this path — `grep -n "blocks\|ignored"` over `app/views/conversations/*.haml`, `conversations_helper.rb`, `people_helper.rb`, `conversation.rb`, `conversation_visibility.rb`, `message.rb` and `conversations_controller.rb` returns nothing. Round 1 (A08) drove a blocked participant for real and it changed no statement; comments_index R4 closed the same item positively. |
| `people.pod_id` / `Person#local?` | `people_helper.rb` reaches `person_path`, never `local_or_remote_person_path`. P07 seeded a `pods` row and a person on it: **0** statements against `pods` in any request. |

---

## 7. Corpus measurements this round rests on

All taken with `adversary3/_multiset_check.py` and ad-hoc scans over the
unchanged 31 846-dump corpus; systematic samples are evenly spaced over the
sorted dump list, never random-and-small.

| measurement | value |
|---|---|
| dumps containing the substring `" IN ("` anywhere (full corpus, `grep -l`) | **0 of 31 846** |
| `_keys_many` / `_k2_not_found` / second-key `row2_` variables (full corpus, `grep -l`) | **0 / 0 / 0** — the Rule D distinct-key machinery is exactly as INERT as the batch claims |
| distinct `ActiveRecord::Base.save` notes (8 000-dump systematic sample) | **1** (`UPDATE "conversation_visibilities" …`), 4 638 events |
| dumps asserting that UPDATE while the FIRST-UNREAD finder returned nothing (12 000-dump systematic sample, keyed on the NOTE, not the ordinal) | **1 488 (12.40 %)** |
| dumps in which SET_READ's `find_by` returned nothing (same sample) | **1 607 (13.39 %)** — impossible |
| dumps in which the LAST-AUTHOR `find_by` returned nothing (same sample) | **1 063 (8.86 %)** — impossible |
| per-dump statement-note count (same sample) | `1`→5 dumps, then `4`→6, `5`→7, `6`→8, `7`→22, `8`→398 …, max 29. **No 2- and no 3-statement dump.** |
| dumps carrying `Anonymous.new` (= `Discovery.new`) and `ActiveRecord::Base.reload` | **1 822 (15.18 %)** each, always together |
| `escape_segment` events | **0** |
| note-less non-wall `symbolic_call` events (full-corpus `noteless_call_audit`) | **0 of 682 847** |
| adjacent identical-note / different-target pairs (2 500-dump scan, the B-8 leak signature) | **0** |
| `contacts_exists` note by scenario (3 000-dump sample) | html 100 %, json 0 %, mobile 0 % — matches the real `format.html`-only placement |
| corpus statement multisets | 186 distinct over a 6 000-dump sample; 19 distinct statement shapes |
| dumps whose text contains `Template::Error` / `UnknownFormat` / `InvalidPage` (full corpus, `grep -l`) | **0 / 0 / 0** |
| dumps carrying any `error` field at all (full corpus) | **13**, all `I18n::InvalidLocale` — the ONLY non-200 terminal the corpus models |

## 8. Judge verdicts on this round's runs

| run | `mock_note_check` | `note_fidelity_audit` |
|---|---|---|
| `P01_page_domain` | green | **EXACT**, 0 defects |
| `P02_cid_shapes` | green | **RED — PRED-OP-DIFF ×2, EXIT=1** (W2) |
| `P03_formats` | green | **EXACT**, 0 defects |
| `P04_setread_unchanged` | green | **EXACT**, 0 defects (W1 is invisible to both judges — they only ask whether each REAL statement has a note) |
| `P05_real_layout` | green | **EXACT**, 0 defects (the statements captured before the sprockets raise are the same set as the `layout(false)` runs) |
| `P06_cardinality` | green | **EXACT**, 0 defects |
| `P07_row_edges` | RED — 3 statements outside any target frame, **all three are my own `guid` probe's `Conversation.find` / `Message.find` / `Person.find`** (INSTR-5) | **EXACT**, 0 defects |
| `P08_language` | RED — 6 statements outside any target frame, **all `User.find(uid)` from my harness's salt computation** (INSTR-5) | **EXACT**, 0 defects |
| `P10_locale_leak` | green | **EXACT**, 0 defects |
| `P11_layout_gon_probe` | RED | **RED — 6 statements with no note**: the `notifications` COUNT, the `conversation_visibilities` SUM, both `roles` probes, the `aspects` read and the `services` read. These are the layout's, reached by an in-process probe (NM-5), not by the endpoint — but they are what the pin costs, stated by the batch's own judge |
| `P12_unread_negative` | green | **EXACT**, 0 defects |

The pattern is the one R5 recorded and R7 re-recorded: every judge run over the
endpoint's own statements is EXACT
while the round's four wins sit inside the corpus. Both judges are SHAPE-level
and state-blind; W1 and W4 are multiset/state defects and W3 is a missing path,
so only W2 — which introduces a new predicate OPERATOR — could be caught, and it
was.

---

## 9. Summary

**4 wins**, all blocking; `complete: true` is void until each is in the corpus
AND a check exists that catches its class.

| # | class | level | one line |
|---|---|---|---|
| W1 | S (B cause) | **TARGET-LEVEL** | `ActiveRecord::Base.save` asserts its `UPDATE "conversation_visibilities" …` note unconditionally; Rails partial writes issue **no statement** for an unchanged record, and the corpus's only "no UPDATE" route is a finder outcome the endpoint cannot reach |
| W2 | B (S consequence) | ENDPOINT-LEVEL | `?conversation_id[]=1&conversation_id[]=2` issues `… "conversation_visibilities"."conversation_id" IN (?, ?) …`; the corpus has **zero** `IN (…)` notes in 31 846 dumps, and `note_fidelity_audit` goes RED on it |
| W3 | B | ENDPOINT-LEVEL | any `params[:page]` that is not an integer ≥ 1 raises `WillPaginate::InvalidPage` inside the action: the request issues exactly `{users, people.owner_id}` and 500s — a 2-statement multiset and a terminal the corpus does not have |
| W4 | B | ENDPOINT-LEVEL | `.js` renders the whole html page (16 statements, 34 with a `conversation_id`, **including the write**) before its 500, refuting the written ground for excluding it; four undeclared formats stop after 3 statements (9 with a `conversation_id`, again including the write) |

**5 near-misses** (NM-1…NM-5 in §4) plus the item-1c matrix correction, and
**6 instrument findings** (§5).

**What held up.** The B-1 `reload` note, the B-2 `escape_segment` demotion, the
whole B-8 pending-note channel, the Rule D INERT claim, the `guid` pin, the
`text` pin's decision family and the `language` two-arm model are all correct —
and five of the seven are now verified by a real run rather than by argument.
The cycle-4 `page`-beyond repair (NM-2 of round 2) scores EXACT. Nothing in
rounds 1–2 regressed.

**Where the round's wins live.** Three of the four are in the same place: a
*domain* the runner pinned to one or two values (`page`, the response format,
the shape of `conversation_id`) and one *fact* the corpus welded onto another
variable (whether the write happens). None of them is a projection or a
predicate-column defect, which is why eight audits and two judges pass while
they sit in the corpus — the one exception being W2, which changes a predicate
OPERATOR and was caught by `note_fidelity_audit` exactly as T-l intends.
