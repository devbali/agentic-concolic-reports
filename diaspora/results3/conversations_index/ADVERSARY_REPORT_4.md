# conversations_index — ADVERSARY REPORT 4 (round 4, 2026-08-30)

Concrete checker, adversarial sub-agent
(`src/end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md`).
Endpoint `ConversationsController#index`, signed-in only.

**State attacked.** Cycle 15 (AGENT_RUN.md, written 00:57 today): engine
`complete: true`, `blocking: []`; 93 nodes, 0 missing, 784 361 PCs, 20 229
dumps over ten scenarios (html/json/mobile/js/xml × plain/withcid);
assumptions 4 330/4 330 PASS; shims 14 PASS / 18 PROTOCOL / 0 NO-TEST; note
check green; note fidelity 27 EXACT / 0 defects; eight audits green;
`hardening_lint` clean; `boundary_declaration_audit` pass.

**Method.** Real app only — `concrete_env.rb` sqlite/JDBC with the app schema,
fixture ROWS by raw `INSERT`, real Devise session resolution, real
`ActionController::TestCase` dispatch, real templates. No mocks, no stubs, no
monkey-patch of app code; nothing under `src/`, the app, or the batch's
runner/targets/mocks was touched. Manifests `adversary4/Q*.rb`, harness
`adversary4/_common.rb` (carries INSTR-1/2/3/5: warden-bound principal memo,
`CompletionChecker.new_request!` + per-request `clear_query_cache`,
adapter-quoted booleans, every principal's salt computed at fixture load),
runs and judge output in `adversary4/runs/`, per-request multiplicity tables
in `adversary4/runs/*.stats.txt` (`adversary4/_req_stats.py` against a
3 000-dump systematic corpus scan). One request per concrete scenario.

Two RIG knobs are new this round; both are configuration of the rig, not code
in the app, and both are of the same class as the `check_precompiled_asset =
false` every harness already sets:

* `ADV4_DEVISE_WARDEN=1` — `env["warden"]` is a real `Warden::Proxy` built from
  `Devise.warden_config` (the app's own middleware block, instantiated by
  building the stack once) with the principal under Devise's own session key.
  Every earlier round and every batch manifest put a stub `Object` there.
* `ADV4_REAL_LAYOUT=1` — `layout(false)` is NOT applied and the sprockets
  resolvers on the view are emptied (`ActionView::Base.resolve_assets_with =
  []`, `unknown_asset_fallback = true`), so asset helpers emit plain public
  paths instead of raising on the stripped asset tree. **The real layout
  renders on this rig** (31 KB html bodies, 28–30 KB mobile bodies) — the
  round-3 obstacle ("couldn't find file 'underscore'") is gone.

---

## 1. Re-verification of the round-3 items (real runs against THIS corpus)

| item | verdict | evidence |
|---|---|---|
| **C-5** (write follows dirty state) | **VERIFIED — moved to `verified`** | `Q04`: `cid=1, unread=1` → `UPDATE "conversation_visibilities" SET "unread" = ?, "updated_at" = ? …` ×1; the same request again → `BEGIN`/`people` read/`COMMIT`, **no UPDATE**; `cid=2, unread=0` (json) → no UPDATE; `cid=3, unread=-3` (mobile, the P12 legacy arm) → UPDATE. Corpus (all 5 439 `html_withcid` dumps): 4 265 dumps with the visibility found, `(…_find_by_N_unread == 0)` TRUE and **no** UPDATE; 336 with it FALSE and the UPDATE; the remaining 838 are the conversation-not-found arm (no set_read). Both polarities present, the write decided by the recorded fact. `note_fidelity` EXACT. |
| **C-6** (`conversation_id[]` → `IN`) | **VERIFIED — moved to `verified`** | `Q04`: `["1","2"]` html and `["998","999"]` mobile both issue `… "conversation_visibilities"."conversation_id" IN (?, ?) ORDER BY "conversations"."id" ASC LIMIT ?`; `note_fidelity` **PRED-OP-DIFF 0** (round 3 scored ×2 here). Corpus: `SYM_PARAM_cid_is_array` recorded in both polarities; the `IN ($$(…), $$(…_2))` note is in 455 of 806 sampled `html_withcid` dumps. |
| **C-7** (`page` domain third arm) | **VERIFIED — moved to `verified`** | `Q04`: `page=0` (RangeError), `page=abc` (ArgumentError), `page[]=2` (TypeError) on html/json/mobile each issue exactly `{users, people.owner_id}` then raise. `_multiset_check`: **EXACT, set_exact=17** over a 6 000-dump sample; the 2-statement `ArgumentError` dump exists in all TEN variants (41 corpus-wide). The corpus terminal is always `ArgumentError` (`page = "abc"`); the real domain also raises `RangeError`/`TypeError`, same multiset — no evidence differs. |
| **C-8** (format domain) | **VERIFIED — moved to `verified`** | `Q04`: `.js` → full `index.haml` render then `ActionView::Template::Error` (24 statements plain, 36 with cid; multiset **set_exact=245 / 406**); `.xml` → 3 statements `{users, people.owner_id, contacts_pluck}` + `UnknownFormat` (set_exact=1; the corpus holds only **4** `xml_plain` UnknownFormat dumps — thin, but present), 7 (+`BEGIN`/`COMMIT`) with a cid. `dump_errors`: `Template::Error` 5 451, `UnknownFormat` 677. |
| **NM-5** (the `layout(false)` pin) | **VERIFIED BY A REAL ENDPOINT RUN — for html; EXTENDED for mobile (W3)** | `Q02`, real layout rendered by the endpoint: html requests issue exactly the seven presenter shapes once each (`notifications` COUNT, `conversation_visibilities` SUM, `roles` ×2, `aspects`, `services`, `contacts` COUNT) — all in the corpus, `note_fidelity` EXACT on them, `_multiset_check` **set_exact=448** for `alice_html_plain`. The round-3 near-miss is a verified corpus property for html. The mobile layout is a different template and is NOT modelled — W3 below. |
| **M-5** (locale domain, three-armed) | **VERIFIED (under the batch's rig)** | `Q04`: `language = "xx"` (html) and `""` (json) raise `I18n::InvalidLocale` after **exactly one** statement (`SELECT "users".* … ORDER BY "users"."id" ASC LIMIT ?`; set_exact=2); `NULL` → 200 (6 statements, empty inbox); `"pl"` → 200 with the extra principal `profiles` read. Three-armed as the batch re-derived. **But** see W1: with the REAL warden the raise arm's multiset is `{users, UPDATE users}` whenever `last_seen` is stale — the one-statement multiset is a property of the stub, not of the app. |
| will_paginate loaded-relation model (A3-9/10) | **VERIFIED** | `Q03`: empty inbox html/mobile → visibilities COUNT **×2** (never loaded → `total_entries` counts again); exactly 15 rows page 1 → ×2 (full page); 15 rows page 2 (beyond) → ×2; 16 rows page 2 (one row, partial) → **×1**; json → 0. Corpus, every non-error html/mobile_plain dump: `count > 0` FALSE → ×2 (273 dumps), `len < 15` FALSE → ×2 (418), beyond with rows → ×2 (291), partial page → ×1 (4 062). Every arm's multiplicity matches. |
| A3-9(b) finder-from-count on `.js` empty inbox | **VERIFIED, with a harness caveat** | `Q03_dora_empty_js`: the `take(11)` re-read is real, but it is issued once per `NameError#message` READ — my harness read the message four times and got four; the batch's rig reads it twice. The count of that statement is decided by the exception renderer, not the app. |

---

## 2. Scenarios run

**47 requests over 5 manifests / 7 JRuby processes** (two processes were
re-runs after a manifest keyword-argument bug; 0 JVM aborts).
`flock /tmp/concolic-slot.lock` inside `systemd-run --user -p MemoryMax=4000M
-p MemorySwapMax=0`, `JAVA_TOOL_OPTIONS` unset, one manifest per process.

| manifest | rig | fixtures | requests | outcome |
|---|---|---|---|---|
| `Q01_devise_warden` | **real Warden** | alice `last_seen NULL`; erin `last_seen` −10 min; fay −1 min; gus `locked_at` + `remember_created_at`; hal `language="xx"`; ivy stale + `page=0` | stub control, 4× alice (html, html again, json+cid, mobile), erin json, fay html, gus html, hal html, ivy html | **W1, W2** |
| `Q02_real_layout` | **real layout** | batch's 2 conversations + 2 aspects, 2 notifications (1 unread), 1 service, 2 followed tags, alice `admin` role, 2 reports (1 unreviewed); dora: `moderator` role, empty inbox | alice html, html+cid, mobile, json; dora html, mobile; alice mobile+cid2 | **W3, W4**, NM-5 verified |
| `Q02b_real_layout_unread` | real layout | as above, alice unread=1, 2 services | mobile, html, mobile+cid1 | W3 badge branches, W4 |
| `Q03_page_multiplicity` | batch's | dora empty; alice exactly 15 conversations; erin 16 | empty html/mobile/js; 15: page 1 html/mobile, page 2, json; 16: page 2 html/mobile, page 1 | will_paginate model verified |
| `Q04_reverify` | batch's | conv 1 unread 1, conv 2 unread 0, conv 3 unread −3; principals `xx`/`""`/NULL/`pl` | 17 requests (C-5 ×4, C-6 ×2, C-7 ×3, C-8 ×4, M-5 ×4) | §1 |

---

## 3. WINS

### W1 — the authentication boundary WRITES: `devise_lastseenable` stamps `users.last_seen` on every signed-in request older than 5 minutes — **Class B · TARGET-LEVEL**

**Scenario** (`adversary4/Q01_devise_warden.rb`, `ADV4_DEVISE_WARDEN=1`): any
signed-in request by a principal whose `users.last_seen` is NULL or more than
five minutes old. Reproduced on html (alice), json (erin, −10 min), on the
`I18n::InvalidLocale` arm (hal, `language = "xx"`) and on the invalid-`page` arm
(ivy, `page=0`). NOT issued when `last_seen` is fresh (alice's second request,
fay at −1 min).

**Novel shape, verbatim** (`Q01_alice_stale_html`, frame `ActiveRecord::Base#save`):

    BEGIN TRANSACTION
    UPDATE "users" SET "last_seen" = ?, "updated_at" = ? WHERE "users"."id" = ?
    COMMIT TRANSACTION

issued immediately after the Devise `users` read and BEFORE `set_locale`, before
`current_user.person` — so the real multisets of the terminals the corpus models
are: locale raise `{users, UPDATE users}` (hal — 2 statements, not M-5's one),
invalid page `{users, UPDATE users, people.owner_id}` (ivy — 3, not C-7's two),
and every 200 path gains the write.

**Code line.** `before_action :authenticate_user!` (`conversations_controller.rb:4`)
→ Devise `warden.authenticate!(scope: :user)` → `Warden::Proxy#user` →
`set_user` → `Warden::Manager._run_callbacks(:after_set_user)` →
`bundler/gems/devise_lastseenable-dc003d84c532/lib/devise_lastseenable/hooks/lastseenable.rb:1-5`
(`record.stamp!`) → `…/model.rb:6-10`
(`update_attribute(:last_seen, DateTime.now) if last_seen.to_i < (Time.now - 5.minutes).to_i`).
`devise … :lastseenable` is declared at `app/models/user.rb:31`.

**What the corpus has.** `grep -l 'UPDATE \"users\"' dump_*.json` → **0 of 20 229**;
no note mentions `last_seen`; `users.last_seen` is not a gate or pin column
(`completion_config.json pc_gate_columns`). The batch's runner defines
`current_user` itself (`run_dse.rb:280-286`, `User.serialize_from_session` on a
memo) and stubs `authenticate_user!` (`:289`); the concrete manifests install a
stub warden `Object` whose `authenticate!` returns the user (`concrete_manifest_auth.rb:115-133`).
Warden's callback chain never runs in either. The "note check green — 0
statements outside a frame" is measured with that stub.

**Why it is a Class B with a Rule-D shape.** The write is decided by a column
the corpus never reads (`users.last_seen`, threshold 5 minutes), so it is not a
missing arm of a recorded decision — it is a decision the model does not have.
Under production traffic it fires on the FIRST request of every session and
every five minutes thereafter, for every signed-in endpoint.

**TARGET-LEVEL.** `authenticate_user!` is `ApplicationController`'s filter on
every signed-in controller; `Warden::Manager.after_set_user` runs for all of
them. Every batch's stub warden hides it identically. Six `after_set_user`
hooks are registered in this app (`Warden::Manager._after_set_user.size == 6`:
Devise activatable, timeoutable, lockable, rememberable, trackable,
devise_lastseenable); on a session FETCH only activatable, timeoutable (inert —
`User` is not `:timeoutable`) and lastseenable run.

### W2 — a LOCKED principal is logged out at the boundary: `UPDATE "users" SET "remember_created_at"` + `throw :warden` before the action — **Class B · TARGET-LEVEL**

**Scenario** (`Q01_gus_locked_html`): `users.locked_at` set (User is
`:lockable` with `lock_strategy: :none, unlock_strategy: :none`, so
`access_locked?` is simply `!!locked_at` — `devise/models/lockable.rb:61-63,144-148`),
`remember_created_at` set. Real run: Devise's activatable hook
(`devise/hooks/activatable.rb:6-11`) finds `active_for_authentication?` false →
`warden.logout(:user)` → `before_logout` → forgetable hook
(`devise/hooks/forgetable.rb`) → `User#forget_me!` → `save(validate: false)`:

    SELECT "users".* FROM "users" WHERE "users"."id" = ? ORDER BY "users"."id" ASC LIMIT ?
    BEGIN TRANSACTION
    UPDATE "users" SET "remember_created_at" = ?, "updated_at" = ? WHERE "users"."id" = ?
    COMMIT TRANSACTION

then `throw :warden, scope: :user, message: :locked` — a 401 through Devise's
failure app; the action, `set_locale`, `people.owner_id` are never reached. (Hook
order matters: activatable throws before lastseenable, so no `last_seen` stamp.)
With `remember_created_at` NULL the `save` is a no-change partial write — the
C-5 rule again — and only `BEGIN`/`COMMIT` remain (inferred from C-5, not
measured this round).

**What the corpus has.** No `locked_at` decision, no 401 terminal, no
`UPDATE "users"` (0 of 20 229). `dump_errors` lists only
`InvalidLocale`/`ArgumentError`/`Template::Error`/`UnknownFormat`.

**TARGET-LEVEL.** Same boundary as W1. `users.locked_at` is a schema-permitted
state (`Devise::Models::Lockable#lock_access!` writes it on failed logins).

### W3 — the MOBILE layout is a different template with reads the html presenter model never issues: `tags`/`tag_followings`, `reports`, and 2–3× the badge counts — **Class B · TARGET-LEVEL**

**Scenario** (`adversary4/Q02_real_layout.rb`, `Q02b`, `ADV4_REAL_LAYOUT=1`):
any mobile request (`session[:mobile_view] = true`, plain or with a cid),
rendered by the endpoint through `application.mobile.haml` — which the batch's
`layout(false)` pin suppresses and which its NM-5 repair does not model: the
repair drives `UserPresenter#to_json` ("only for html/mobile", `run_dse.rb:398-427`),
i.e. the `_head.haml` gon block that BOTH layouts share, and nothing else.
`application.mobile.haml:22-24` also renders `layouts/_header.mobile.haml`
and `layouts/_drawer.mobile.haml`.

**Novel shapes, verbatim** (`Q02_dora_mobile_plain`, frames `Relation#records` /
`Calculations#count`; both absent from all 20 229 dumps by `grep -l`):

    SELECT "tags".* FROM "tags" INNER JOIN "tag_followings" ON "tags"."id" = "tag_followings"."tag_id" WHERE "tag_followings"."user_id" = ? ORDER BY tags.name
    SELECT COUNT(*) FROM "reports" WHERE "reports"."reviewed" = ?

**Code lines.** `_drawer.mobile.haml:26` `current_user.followed_tags.each`
(`user.rb:79 has_many :followed_tags, -> { order('tags.name') }, through: :tag_followings`)
— every mobile request; `_drawer.mobile.haml:49/58` `unreviewed_reports_count`
(`report_helper.rb:22-24`, `Report.where(reviewed: false).size`) — when the
principal is admin (`:38`) or moderator (`:55`), a `roles` row. And the
per-request MULTIPLICITY of shapes the corpus does have (corpus MAX 1 each):

| statement | html (presenter) | mobile, inbox read | mobile, unread > 0 | code |
|---|---|---|---|---|
| `SELECT COUNT(*) FROM "notifications" WHERE … "unread" = ?` | 1 | **2** | **3** | `_header.mobile.haml:13,15` `unread_notifications.size` (a fresh relation each call) + presenter |
| `SELECT SUM("conversation_visibilities"."unread") …` | 1 | **2** | **3** | `_header.mobile.haml:21,23` `unread_message_count` + presenter |
| `SELECT 1 AS one FROM "roles" WHERE "person_id" = ? AND "name" = ?` | 1 | **2** | 2 | `_drawer.mobile.haml:38` `admin?` + presenter |
| `SELECT 1 AS one FROM "roles" WHERE "name" IN (?, ?) …` | 1 | 1 (admin) / **2** (not admin) | — | `_drawer.mobile.haml:55` `moderator?` (only when not admin) + presenter |

Measured: `Q02_alice_mobile_plain` (admin, unread 0): notifications ×3
(one unread notification → badge branch), SUM ×2, roles-admin ×2;
`Q02_dora_mobile_plain` (moderator, nothing unread): ×2 / ×2 / ×2 / ×2;
`Q02b_alice_mobile_unread_plain` (unread 1): SUM ×3. The batch's
`_multiset_check` reports every mobile request **NO-CORPUS-COUNTERPART /
SET-NOVEL** and both judges go **RED** (`mock_note_check`: `Calculations.count`
and `Relation.records` each have a real shape with NO corpus note anywhere —
`Q02_real_layout.judge.txt`).

**Not issued (measured, not assumed).** `person_image_tag(current_user, …)`
(`_drawer.mobile.haml:35`) does NOT issue the has-one-through
`profiles INNER JOIN people` read one would predict from `user.rb:55`, because
`user.rb:57-58` `delegate … :profile … to: :person` shadows the association and
the person's profile is already loaded by the presenter's `as_api_response`.
`current_user.aspects` (`:19`) is answered from the association the presenter
loaded. `sidekiq_path` and the admin links render without SQL.

**TARGET-LEVEL.** The mobile layout is `ApplicationController`'s
(`application_controller.rb:46`) and `_header.mobile`/`_drawer.mobile` render
on every signed-in mobile page. Every batch that pins `layout(false)` and
models "the layout" as the presenter alone has the same hole. It is the
round-3 NM-5 argument carried one template further: the repair modelled the
layout the rig could not render by reading its code, and read the html one.

### W4 — `SELECT "services".* …` is emitted TWICE per html/mobile dump; the app issues it ONCE — **Class S (over-emission) · TARGET-LEVEL**

**Measurement.** Full corpus: **13 137 of 13 160** non-error html/mobile dumps
(99.8 %) carry the note
`SELECT "services".* FROM "services" WHERE "services"."user_id" = $$(…)` **twice**
(the other 23 are pre-layout terminals with 0). Real: every html/mobile
request of `Q02`/`Q02b` (10 requests, with 1 or 2 services rows) issues it
**once**, under `CollectionProxy#load_target`; the batch's own
`concrete_run.json` agrees (4 presenter-driven requests → 4 statements, 2 → 2).

**Code line.** `user_presenter.rb:24-30` calls `user.services` twice
(`ServicePresenter.as_collection(user.services)` then
`user.services.map(&:provider)`); a real `has_many` proxy is loaded by the
first `map` (`CollectionAssociation#load_target` → `loaded!`) and answers the
second from memory. The batch's `CollectionProxy` targets (`targets.rb:1235-1240`,
`%i[to_a to_ary records load_target]` → `rows_mock`) re-materialise on every
call and never mark the association loaded — the corpus's own gate table
documents the result as three `(len(…CollectionProxy_records_N_rows) != 0)`
decisions per request ("`user.services` twice", AGENT_RUN A3-8 item 1),
i.e. the double was read as a property of the app.

**Why it is blocking by the batch's own standard.** A3-9(c) treated the
visibilities COUNT being emitted twice where the app emits once as a
"multiplicity over-emission across the WHOLE corpus" and regenerated all ten
variants for it. This is the same defect one table over, and — as in A3-9(c) —
neither judge can see it (both match note families, not counts). The policy
inherits a second `services` read per request that never happens; the
`records_3` length decision is over a phantom read.

**TARGET-LEVEL.** The `CollectionProxy` rows_mock is the shared association
toolkit; any endpoint whose code touches the same `has_many` twice in a
request (the presenter does, on every layout) over-emits identically.

---

## 4. Near-misses

### NM-1 (INSTR-7) — both judges are SELECT-only: a run containing `UPDATE "users"` scores EXACT / green

`mock_note_check.py:132,139` and `note_fidelity_audit.py:124,131` filter corpus
notes and real statements with `startswith("SELECT")`. `Q01_devise_warden`
contains four `UPDATE "users"` statements under `ActiveRecord::Base#save`, a
target with no `users` note anywhere in the corpus, and both judges report
**EXIT=0 / 18 EXACT** (`Q01_devise_warden.judge.txt`); `ActiveRecord::Base.save`
does not even appear in the mock_note_check table. Only
`adversary3/_multiset_check.py` (which admits `UPDATE|INSERT|DELETE`) flags the
runs — `SET-NOVEL, NOVEL-SHAPES=update users …` for all four. The cycle-15
"note check green" was therefore never a statement about writes. INSTRUMENT,
all batches.

### NM-2 — per-render multiplicity (round-3 NM-1) re-measured; the ceiling is still one representative

`Q04`/`Q03` (batch rig): `people.id` ×10 vs corpus max 6; `profiles LIMIT` ×9
vs 5; `messages.*` ×4 vs 2; `part_rows` ×4 vs 2; `profiles preload` ×3 vs 1;
mobile `messages` COUNT ×6 vs 2 (three conversations: 2+2+2); a 15-row page
issues `people.id` ×30, `profiles LIMIT` ×15, `messages.*` ×15, mobile
`messages` COUNT ×30. Unchanged declared limit (ledger row R3 NM-1); recorded
here because the round's brief asked for every shape's multiplicity.

### NM-3 — the `.js` `take` re-read count is decided by the exception RENDERER, not the app

A3-9(b) made `take(11)` a real read on the empty-inbox `.js` path; it is
issued once per `NameError#message` CALL (`Relation#inspect` every time).
`Q03_dora_empty_js` shows **4** (my harness read the message four times);
the batch rig reads it twice (`concrete_manifest_auth.rb:183-184`);
ActionDispatch's exception wrapper reads it at least once. The corpus's
`take` multiplicity is a rig constant, not an app fact — a caveat on
A3-9(b), no evidence lost.

### NM-4 — `services`' sibling: the presenter's `aspects` is answered from memory by the mobile drawer (correct in the corpus, stated for symmetry)

`_drawer.mobile.haml:19 current_user.aspects.each` issues nothing after the
presenter loaded the same proxy — the corpus emits `aspects` once per dump,
which matches. The two associations differ only in where the second read
sits (presenter vs drawer); the model got one right by luck of not modelling
the drawer at all.

---

## 5. Instrument findings

* **INSTR-7** (NM-1 above): SELECT-only judges.
* **INSTR-8 — the real layout renders on this rig.** `ActionView::Base.resolve_assets_with = []`
  + `unknown_asset_fallback = true` (sprockets-rails 3.2.1 `helper.rb:76-95`:
  with no resolver strategy `resolve_asset_path` returns nil and the fallback
  path is taken instead of `AssetNotFound`) lets `with_header_with_footer` and
  `application.mobile.haml` render completely — `include_gon`, `_header.mobile`,
  `_drawer.mobile`, `_footer`. The round-3 RIG row ("the real layout cannot be
  rendered on this rig") is closed; the `layout(false)` pin no longer has a rig
  reason to exist in the concrete manifests, and the runner could drive the
  real layout instead of the presenter.
* **INSTR-9 — the stub warden.** Every concrete manifest and every adversary
  harness so far replaced `env["warden"]` with an `Object` that answers
  `user`/`authenticate!`. `Warden::Proxy.new(env, Warden::Manager.new(nil,
  Devise.warden_config.dup))` after `Rails.application.app` (which runs the
  `use Warden::Manager` block) and `Devise.configure_warden!` gives the real
  proxy with the real callbacks; the session key is
  `"warden.user.user.key" => [[uid], salt]`. Pattern in `adversary4/_common.rb`
  `devise_warden_ready!` / `install_devise_warden`.
* **INSTR-10 — a manifest keyword-argument trap.** `req("x", :json, { conversation_id: "1" })`
  with a `uid:` keyword in the signature makes Ruby 2.6 take the params hash as
  keywords (`unknown keyword: conversation_id`); two processes were lost to it.
  Pass an options hash positionally.

---

## 6. Branches I could not reach, and why

| branch | why |
|---|---|
| `Person#fix_profile` → `Discovery` → `reload` (a profile-less last author) | not re-attempted: three rounds have shown it aborts the JVM (JFFI/libcurl, DISCIPLINE §12). |
| Devise `timeoutable` / `trackable` / `rememberable` hooks | `User` is not `:timeoutable`; trackable and rememberable are `except: :fetch` and a session fetch is the only event this endpoint sees. Measured inert by `Warden::Manager._after_set_user` inspection and by W1's runs (no `sign_in_count`/`current_sign_in_at` write). |
| a `forget_me!` on a locked principal with `remember_created_at` NULL | not measured; by the C-5 rule it is `BEGIN`/`COMMIT` with no UPDATE. |
| `_drawer.mobile.haml` admin links' SQL | none: `unreviewed_reports_count` is the only query in the admin/moderator branches (measured). |
| anonymous request | `authenticate_user!` with no `except:`; a real Warden with no session key would run the failure app (401) after zero statements — not attempted, no statement can result. |

---

## 7. Judge verdicts on this round's runs

| run | `mock_note_check` | `note_fidelity_audit` | `_multiset_check` |
|---|---|---|---|
| `Q01_devise_warden` | green (SELECT-only — NM-1) | **EXACT 18, 0 defects** (SELECT-only) | **SET-NOVEL ×5** (`update users …`) |
| `Q02_real_layout` | **RED** — `Calculations.count`, `Relation.records`: a real shape with no corpus note | **MISSING 2** (`reports` COUNT, `tags` join) | mobile: **SET-NOVEL ×3**; html: set_exact 448 / 23 |
| `Q02b_real_layout_unread` | **RED** — `Relation.records` (`tags`) | **MISSING 1** | mobile SET-NOVEL |
| `Q03_page_multiplicity` | green | EXACT 15 | subsets/supersets (layout absent under `layout(false)`) |
| `Q04_reverify` | green | EXACT 19, PRED-OP-DIFF 0 | C-7 set_exact 17, M-5 set_exact 2, js 245/406, xml 1/1 |

---

## 8. Summary

**4 wins**, all blocking, all TARGET-LEVEL; `complete: true` is void until each
is in the corpus AND a check exists for its class.

| # | class | level | one line |
|---|---|---|---|
| W1 | B | TARGET | the real Warden runs `devise_lastseenable`: `UPDATE "users" SET "last_seen" = ?, "updated_at" = ? WHERE "users"."id" = ?` on every signed-in request whose `last_seen` is NULL or > 5 min old — 0 of 20 229 dumps; every modelled terminal's multiset (M-5, C-7, all 200s) gains the write |
| W2 | B | TARGET | a locked principal (`users.locked_at`) is logged out at the boundary: `UPDATE "users" SET "remember_created_at" = ?, "updated_at" = ?` then `throw :warden` (401) — a terminal and a column the corpus has no decision for |
| W3 | B | TARGET | the mobile layout (`_header.mobile` + `_drawer.mobile`) issues `SELECT "tags".* … INNER JOIN "tag_followings" …` on every mobile request and `SELECT COUNT(*) FROM "reports" WHERE "reviewed" = ?` for admin/moderator principals — 0 dumps mention either table — and doubles/triples the badge counts (notifications COUNT ×2–3, SUM ×2–3, roles ×2; corpus max 1) |
| W4 | S (over-emission) | TARGET | `SELECT "services".* …` is emitted twice in 99.8 % of html/mobile dumps; the app issues it once (`CollectionProxy` rows_mock never says `loaded?` on a has_many) — the A3-9(c) COUNT defect on another table |

**4 near-misses** (§4), **4 instrument findings** (§5).

**What held up.** C-5, C-6, C-7, C-8 all verified by real runs against this
corpus and moved to `verified`; NM-5 verified for html by a REAL endpoint
render (the first time the layout has run on this rig) and M-5's three arms
verified under the batch's rig. The will_paginate loaded-relation model
(A3-9/A3-10) is verified in all four arms, the C-5 dirty-state model in both
polarities plus the negative row, and the `IN (?, ?)` predicate now scores
PRED-OP-DIFF 0.

**Where the round's wins live.** All four are in what the rig REPLACED rather
than in what the model explored: the warden (W1, W2) and the layout (W3, W4).
Two rounds of harness corrections (INSTR-1..6) fixed what the stub did wrong;
this round shows what the stub does not do at all. The lesson generalises: a
concrete "ground truth" is only as real as its least real component, and the
boundary components (auth, layout) were stubs in every batch.
