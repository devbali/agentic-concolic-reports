# conversations_index — ADVERSARY REPORT 6 (round 6, 2026-08-30)

Concrete checker, adversarial sub-agent
(`src/end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md`).
Endpoint `ConversationsController#index`, signed-in only.

**State attacked.** Cycle 20d (`AGENT_RUN.md` A5-1…A5-10, report 12:19 today):
engine `complete: true`, `blocking: []`; 111 nodes, 0 missing, 918,983 PCs,
21,835 dumps, ten scenarios; assumptions 6,524/6,524 PASS; shims 15 PASS /
26 PROTOCOL; write-aware note check green; fidelity 39 EXACT / 0 defects;
per-request multiplicity 0 under / 0 over. Round 5's C-14 (cookie login is an
authentication event) and C-15 (`conversation_id[]` → `AND 1=0`) were repaired
by a fourth boundary decision `SYM_PARAM_via_cookie`, trackable's SET list
derived from three login-history facts (six shapes), a nested
`cid_array_empty` arm and a lazily-minted `_remembered`.

**Method.** Real app only: `concrete_env.rb` sqlite/JDBC, fixture rows by raw
INSERT, the app's OWN `Warden::Manager` from the built stack (INSTR-11), real
layout, real dispatch (`ActionController::TestCase#process` for R01/R02/R04,
`Rails.application.call` — the full production middleware — for R03). No
mocks, no stubs, no monkey-patches; nothing under `src/`, the app or the
batch's runner/targets/mocks touched. Harness `adversary6/_common.rb` =
`adversary5/_common.rb` + `remote_addr:` (REMOTE_ADDR for trackable's
`request.remote_ip`), `raw_cookie:` (an unsigned cookie), `remember_uid:`;
run script `adversary6/run_scenario.sh` (flock, systemd-run MemoryMax=4000M,
`JAVA_TOOL_OPTIONS` unset, one manifest per JRuby). Corpus instruments:
`adversary6/_pc_census.py` (PC-combination census over the boundary decisions
and the trackable SET lists, output `_pc_census.out`), `_corpus_scan.py`
(adversary5's, re-run on this corpus → `_corpus_scan.json`), `_req_stats.py`
(per-request counts vs the corpus ceiling), `_summ.py`. Judges: the batch's
`mock_note_check`, `note_fidelity_audit`, `_multiset_counts` (`*.judge.txt`),
`_req_stats` (`*.stats.txt`). Manifests: **4 / 5 JRuby processes (R01 re-run
after a `people.guid` fixture collision) / 46 requests / 0 JVM aborts.** Run
files in `adversary6/runs/` only; logs in `_logs/`, bodies in `_bodies/`, DBs
in `_db/`.

---

## 1. Re-verification of C-14 and C-15 — real runs against THIS corpus

| item | verdict | evidence |
|---|---|---|
| **C-14** cookie login = authentication event; trackable's six login-history SET shapes | **VERIFIED — moved to `verified`** | `R04_h1…h6`: six principals, one cookie login each with a controlled REMOTE_ADDR, produce exactly the six corpus SET lists: h1 `sign_in_count, current_sign_in_at, last_sign_in_at, current_sign_in_ip, last_sign_in_ip, updated_at`; h2 `sign_in_count, current_sign_in_at, updated_at`; h3 `+ last_sign_in_at`; h4 `+ last_sign_in_at, current_sign_in_ip`; h5 `+ last_sign_in_at, last_sign_in_ip`; h6 `+ current_sign_in_ip` — column for column what `_pc_census.out` shows the corpus carrying (1,090 / 1,722 / 74 / 156 / 1,060 / 1,224 dumps). Confirmed under the full production stack with `X-Forwarded-For` deciding the IP (`R03_erin_cookie_xff_newip` → h4's shape, `…_sameip` → h5's). `note_fidelity_audit` EXACT on all six trackable writes. The `via_cookie ∧ remembered ∧ locked` arm (`remember_created_at` write + 401) and `via_cookie ∧ ¬remembered` (1 read, 401) are in the corpus (26+21 / 32+25+28+17 dumps). |
| **C-15** `?conversation_id[]` → `AND 1=0` | **VERIFIED — moved to `verified`** | `R04_c15_cid_empty_array_{html,json,mobile}` and `R03_fay_cookie_cid_empty_array` (full stack, cookie login): `… "person_id" = ? AND 1=0 ORDER BY "conversations"."id" ASC LIMIT ?` on every format; fidelity EXACT; `grep -l '1=0'` → 311 dumps (`cid_array_empty == True`). |

Both round-5 wins are closed by real runs. The trackable derivation, however,
is where this round's first two findings live (§3).

## 2. Scenarios run

| manifest | rig | requests | outcome |
|---|---|---|---|
| `R01_cookie_validity` | TestCase + real warden + real layout | 10 | **C-16, C-17**; NM-1..NM-4 |
| `R02_cid_overflow` | same, session principal, raw query strings | 16 | **C-18**; every other cid/page shape mapped to a corpus arm |
| `R03_fullstack` | `Rails.application.call` (full middleware), cookie logins | 9 | C-16 under production middleware on html/json/js/mobile; NM-5 (`IpSpoofAttackError`); C-15 and C-14 re-confirmed |
| `R04_reverify` | TestCase + real warden + real layout | 11 | §1 (C-14 six histories, C-15 three formats); cookie + `.js` + page beyond + empty inbox; cookie + mobile + cid + page |

## 3. WINS

### C-16 — the cookie arm's `last_seen` write is `UPDATE "users" SET "updated_at" = ?, "last_seen" = ?` — the corpus note has the columns the other way round, on every one of its ~2,600 cookie-login dumps — **Class S · TARGET-LEVEL**

**Scenario.** Any remember-me cookie login of a principal whose `last_seen` is
NULL or older than 5 minutes (the C-14 + C-10 request: trackable's UPDATE, then
lastseenable's). 16 of this round's requests carry it: `R01_carl/dan/eve/jon`,
`R03_erin_xff_newip / fay / gus_js / hal_mobile / ivy` (full production stack),
`R04_h1…h6 / kim_js / lee_mobile`.

**Real statement, verbatim** (frame `ActiveRecord::Base#save`):

    UPDATE "users" SET "updated_at" = ?, "last_seen" = ? WHERE "users"."id" = ?

**What the corpus has.** One `last_seen` shape only —
`UPDATE "users" SET "last_seen" = ?, "updated_at" = ? WHERE …` (`_corpus_scan`:
all-variant max 1; `_pc_census`: it is the second write on every
`via_cookie ∧ remembered ∧ stale` dump). The batch's own write-aware judge
says so: `_multiset_counts` → `UNDER real x1 corpus max x0  update users set
updated_at = @, last_seen = @` on R01, R03, R04; `note_fidelity_audit` →
MISSING; `mock_note_check` → NOTE-MISMATCH RED. The session-fetch arm's
`last_seen, updated_at` (`R04_c15_*`, C-10) is still right.

**Why.** A5-1 installed a fidelity rule — "AR lists changed columns in the
model's COLUMN order with the timestamp last; the save note sorts its SET list
that way". That is not AR's rule. `changed_attribute_names_to_save` iterates
the record's attribute set in the order its keys are held; for a freshly loaded
record that is column order (so trackable's first UPDATE comes out
`sign_in_count … updated_at`, as measured), but `changes_applied` after a save
rebuilds the set from the already-materialised attributes
(`forget_attribute_assignments` → `AttributeSet#map` → `LazyAttributeHash#
transform_values` → `materialize`), whose order is the order of FIRST ACCESS.
After trackable's save, `updated_at` (touched by that save) precedes
`last_seen` (first read by `stamp!` afterwards) — hence `updated_at, last_seen`
on the cookie arm and only there. The rule is right for the first save of a
request and wrong for every later one; the C-5 writer applies it to all.

**Why the batch never saw it.** Its evidence for the cookie arm never contained
a cookie login with a stale `last_seen`: `concrete_run_auth.json` (one
scenario, "conversations-index-auth-4-variants") has seven trackable writes and
two `last_seen` writes, both `last_seen, updated_at` — the session fetches. The
manifest's first alice request is a session fetch that stamps `last_seen`; the
cookie logins that follow find it fresh; principal 13 is seeded fresh. The
"six histories" evidence route (A5-7) was built with `last_seen` warm, so the
second write of the request it was meant to model was absent from every
measured request.

**Code line.** `devise_lastseenable/model.rb:6-10` (`update_attribute(:last_seen,
DateTime.now)`) after `devise/models/trackable.rb#update_tracked_fields!` →
`save(validate: false)` in the same `after_set_user` chain; AR 5.2
`active_record/attribute_methods/dirty.rb#changes_applied` /
`active_model/attribute_set.rb#map`. Corpus side: the C-5 writer's SET-order
rule (`targets.rb:1772` "timestamp last") and the T-ab row (3) of the ledger.

**TARGET-LEVEL.** The order rule is in the shared write model and the T-ab
matrix row instructs every batch to adopt it; every endpoint whose boundary
saves the principal twice in a request (cookie login + stale `last_seen`, on
every signed-in endpoint) inherits the wrong second note. Policy consequence:
column SET, not order — the projection is unchanged — but both project judges
treat it as a distinct shape, and the corpus's "0 under / 0 over" for the
cookie arm is a claim made without a single measured request carrying the
write.

### C-17 — two trackable SET lists the derivation `prev_login_first ⇒ last_sign_in_ip == current_sign_in_ip` forecloses: `SET "sign_in_count", "current_sign_in_at", "last_sign_in_ip", "updated_at"` and `SET "sign_in_count", "current_sign_in_at", "current_sign_in_ip", "last_sign_in_ip", "updated_at"` — **Class B · TARGET-LEVEL** (reachability qualified below)

**Scenario** (`R01_dan_sameSecond_ipsDiffer_sameIp`, `R01_eve_sameSecond_ipsDiffer_newIp`):
a remembered principal whose `current_sign_in_at == last_sign_in_at` but
`current_sign_in_ip (10.1.1.1) != last_sign_in_ip (10.2.2.2)`, then a cookie
login from 10.1.1.1 (dan) / 10.3.3.3 (eve).

**Real statements, verbatim** (frame `ActiveRecord::Base#save`):

    UPDATE "users" SET "sign_in_count" = ?, "current_sign_in_at" = ?, "last_sign_in_ip" = ?, "updated_at" = ? WHERE "users"."id" = ?
    UPDATE "users" SET "sign_in_count" = ?, "current_sign_in_at" = ?, "current_sign_in_ip" = ?, "last_sign_in_ip" = ?, "updated_at" = ? WHERE "users"."id" = ?

**What the corpus has.** Six SET lists (`_pc_census.out`, `_corpus_scan`);
neither of these (`_multiset_counts` UNDER ×0, fidelity MISSING ×2,
`_req_stats` ABSENT-CORPUS). Trackable's write is a function of three
independent column facts — A: `current_sign_in_at == last_sign_in_at`,
B: `current_sign_in_ip == last_sign_in_ip`, C: request IP == `current_sign_in_ip`
— giving 2³ = 8 lists; the model has A (`_prev_login_first`), C and B-given-¬A,
and on A it SETS B by Rule D ("a first-ever login set both pairs equal", A5-7).
The two missing lists are A ∧ ¬B.

**Reachability, stated honestly.** A ∧ ¬B is not produced by two trackable
writes at distinct timestamps: after a first-ever login both pairs are equal,
and every later login sets `last_sign_in_at := old current` (≠ now). It IS
produced when two logins land in the same stored second from different IPs —
diaspora's `users.current_sign_in_at` is a MySQL `DATETIME` (`db/schema.rb`,
no fractional precision; the app's primary target), so a second login within
the same wall-clock second from another address (two devices, or a password
login on one and the remember cookie on another) writes `last_sign_in_at :=
old current` equal to the truncated `now`, with the IPs distinct. On this rig
it is a fixture state. The derivation is therefore a claim the schema does not
guarantee: A is not "the previous login was the first". The batch can either
(a) keep the derivation and record the same-second collision as a declared
limit in the pin ledger with this reason, or (b) mint B as a free decision on
A too (two more arms). Either is a repair; today neither is written down, and
the write-aware lint's "six shapes, six histories" proof (A5-7) is a
proof about the model, not the column state space.

**Code line.** `devise/models/trackable.rb:20-29 update_tracked_fields`
(`self.last_sign_in_ip = old_current || new_current` — changes whenever
`old_current_ip != last_sign_in_ip`, independently of the timestamps);
corpus side `targets.rb` `_prev_login_first` block ("Rule D: a first-ever login
set BOTH pairs equal … DETERMINED here, not a free compare").

**TARGET-LEVEL.** Trackable runs on every signed-in endpoint's cookie login;
the derivation lives in the shared boundary model (T-x2).

### C-18 — an out-of-range `conversation_id` raises `ActiveModel::RangeError` inside the finder: the action terminates after THREE statements, a terminal no dump carries — **Class B · ENDPOINT-LEVEL**

**Scenario** (`R02_cid_huge_html`, `?conversation_id=99999999999999999999`):
`Conversation.joins(:conversation_visibilities).where(conversation_visibilities:
{person_id:, conversation_id: params[:conversation_id]}).first` casts the bind
through the column type; `ActiveModel::Type::Integer#ensure_in_range`
(`activemodel-5.2.4.3/lib/active_model/type/integer.rb:51-53`) raises
`ActiveModel::RangeError: … is out of range for … with limit 8 bytes` while the
statement's binds are being built. The `sql.active_record` event fires with the
SQL text, so the probe records the conversations SELECT (frame
`ActiveRecord::Relation#records`) as the third statement — and then the request
is a 500: no `contacts` pluck, no `contacts` exists, no COUNT, no page, no
`set_read`, no layout.

    users read · people.owner_id · conversations INNER JOIN … "conversation_id" = ? … LIMIT ?   → ActiveModel::RangeError

**Threshold.** On this rig the SQLite JDBC integer reports an 8-byte limit, so
2³¹ (`R02_cid_2p31_html/json`, `cid_neg_2p31`, `cid_array1_2p31`) passes and
takes the ordinary not-found arm; on diaspora's MySQL schema
(`t.integer "conversation_id"`, 4 bytes) the same code raises at
`conversation_id=2147483648` — any client can send it. The array arm
(`conversation_id[]=1&conversation_id[]=<huge>`) raises identically inside
`IN (?, ?)`.

**What the corpus has.** `grep -l RangeError dump_*.json` → **0 of 21,835**;
`ActiveModel::` → 0. The cid domain is `scalar = ?` / non-empty `IN` / empty
`1=0`, each followed by the found/not-found arms and the rest of the render;
no dump's terminal follows the conversations read. Same class as C-7 (round 3:
the invalid-`page` terminal after two statements) — a parameter-domain
terminal, one statement further in.

**Code line.** `conversations_controller.rb:11-16`; AR 5.2
`predicate_builder` → `QueryAttribute#value_for_database` → the column type's
`serialize` → `ensure_in_range`.

**ENDPOINT-LEVEL.** The finder and the guard are this action's; the same
overflow terminal exists for every endpoint that binds a user-supplied integer
to a 4-byte column — worth a row in the cross-endpoint patterns, not the matrix.

## 4. Near-misses (a real defect or a real state, no novel statement shape)

* **NM-1 — `_remembered` is a NULL check; `remember_me?` is a four-conjunct predicate.**
  `R01_alice_remembered_cookie_older` (cookie `generated_at` 2 h ago,
  `remember_created_at` 1 h ago — the production "signed out on one device,
  re-remembered on another" flow, since `forget_me!` nils the column and
  `remember_me!` re-sets it) and `R01_brian_remembered_cookie_expired`
  (`remember_for` = 2 weeks exceeded) are both **401 after ONE users read and no
  write**, on a REMEMBERED principal. `_pc_census.out`: the only
  `via_cookie ∧ remembered ∧ WardenThrow401` combination in the corpus is the
  locked one (26+21 dumps); every non-locked remembered cookie logs in. The
  statement set `{users}` exists under `¬remembered`, so no new shape — but
  the decision the policy inherits ("remember_created_at set ⇒ access") is
  wrong: the real gate is `generated_at > remember_created_at ∧ generated_at >
  remember_for.ago ∧ token == salt` (`devise/models/rememberable.rb:105-120`).
  Same for the session arm: a stale session salt (password changed elsewhere)
  is a one-read 401 the model has no decision for (round 5 Q01, re-measured in
  NM-4).
* **NM-2 — a NOT-remembered principal with a FUTURE cookie logs in with THREE writes.**
  `R01_carl_notremembered_future_cookie` (`remember_created_at` NULL, cookie
  `generated_at` +300 s — clock skew between pod nodes is the only producer):
  `remember_me?` takes `(remember_created_at || Time.now)`, a future cookie
  passes, and because `User#remember_me` returns `true` (`user.rb:594`) the
  rememberable hook's `remember_me!` finds the column NULL and writes it:
  `UPDATE "users" SET "remember_created_at" = ?, "updated_at" = ?` (the C-11
  shape, here as a REMEMBER not a forget) **before** trackable and lastseenable.
  The corpus has that shape only on the locked path and never three principal
  writes in one request. Declared limit material (skew), reported for the
  model's honesty.
* **NM-3 — a cookie (or session) naming a principal that no longer exists.**
  `R01_gus_cookie_deleted_uid`: `serialize_from_cookie` → `to_adapter.get` →
  one users read returning nothing → `cookies.delete` → 401. The corpus's
  `devise_user_first` always yields a principal; the not-found arm of the
  principal read (account deleted while a session/cookie lives) has no
  decision. Statement set `{users}` again.
* **NM-4 — both credentials stale ⇒ the users read is issued TWICE on the rig.**
  `R01_ivy_stale_session_stale_cookie` (session salt and cookie token both
  from before a password change): the session fetch reads users (salt
  mismatch → nil), then `Devise::Strategies::Rememberable` reads users again
  (token mismatch → nil) → 401. `_req_stats`: `OVER x2>1` for the users read.
  Under the production stack the executor's query cache would answer the
  second identical SELECT from memory, so this is ×2 on the TestCase rig and
  most likely ×1 in production; round 5's NM-2 (the full-stack session cookie
  does not resolve on the rig) still prevents measuring it there.
* **NM-5 — `ActionDispatch::RemoteIp::IpSpoofAttackError` is a cookie-login terminal after ONE read and NO write.**
  `R03_jon_cookie_ip_spoof` (full stack, `X-Forwarded-For` and `Client-IP`
  disagree; `ip_spoofing_check` is Rails' default): trackable's
  `extract_ip_from(request)` is the first `remote_ip` call of the request, it
  raises inside the `after_set_user` chain after `serialize_from_cookie`'s read
  and before trackable's save, and lastseenable never runs → 500. The corpus's
  `via_cookie ∧ remembered ∧ ¬locked` arm always writes. Statement set `{users}`.
* **NM-6 — every other parameter shape tried collapses to a covered arm** (R02):
  `conversation_id[]=` → `[""]` → `= ?`; `[]=&[]=` → `IN (?, ?)`; `[a][]=1` →
  `= ?`; `=1.9` → `= 1` (found, `set_read` runs); `=-2147483649` → `= ?` on
  this rig; `conversation_id=1&conversation_id[]=2` → `ActionController::
  BadRequest` in `ActionController::Instrumentation` before any filter → **0
  statements**; `page=99999999999999999999` → will_paginate `RangeError:
  invalid offset` after the two C-7 statements (the corpus records that arm as
  `ArgumentError`; same multiset); `page=2147483648` → OFFSET bound as a
  bignum, the page-beyond arm; `page=0x2` → `Integer("0x2") == 2`.
* **NM-7 — the `.js` beyond-page renderer re-read is unchanged under a cookie login**
  (`R04_kim_cookie_js_page2_empty`: t0_r0 ×4, COUNT ×6 — the declared
  `multiset_renderer_re_reads`, R5 NM-5) and the mobile layout under a cookie
  login is additive (`R03_hal_cookie_mobile_ua`, `R04_lee_cookie_mobile_cid1_page2`).

## 5. Branches reached / not reached

| branch | outcome |
|---|---|
| the six trackable histories | all six reached for real (R04) and matched; two further column states reached (C-17) |
| Devise modules on `User` | `two_factor_authenticatable`/`backupable`: no warden hooks (`devise_two_factor/models/*`); `rememberable` hook fires on the cookie login because `User#remember_me` is `true` — a no-op save when `remember_created_at` is set (verified: two writes, not three, on every remembered login) and a write when NULL (NM-2); `lockable` hook: `users` has NO `failed_attempts` column (`db/schema.rb`), so `record.respond_to?(:failed_attempts)` is false — inert by schema, not by config; `extend_remember_period` false, `expire_all_remember_me_on_sign_out` default true (a sign-out elsewhere nils `remember_created_at` — NM-1's producer); no `timeoutable`/`confirmable` on `User` |
| hook ORDER on the cookie arm | measured: activatable (locked → forget_me! + throw, no trackable), rememberable, lockable, trackable, lastseenable — trackable's UPDATE precedes `last_seen`'s on every run |
| cookie + session both present | `R01_hal_session_and_cookie`: the fetch wins, no authentication event, no trackable write — matches the `via_cookie == False` arm |
| unsigned / foreign cookie | `R01_fay_garbage_cookie`: strategy `valid?` false → 401 after **0** statements |
| `Person#fix_profile` → Discovery | not re-attempted (JVM abort, DISCIPLINE §12) |
| full-stack SESSION principal | still unresolved on the rig (R5 NM-2); every full-stack request this round authenticates by cookie |

## 6. Judge verdicts

| run | `mock_note_check` | `note_fidelity_audit` | `_multiset_counts` |
|---|---|---|---|
| R01 | RED (Base.save ×3: C-16, C-17 ×2) | MISSING 3, EXACT otherwise | UNDER 3 (same), OVER 5 (mobile-ceiling artefacts) |
| R02 | green | **EXACT 25, 0 defects** — C-18's terminal is invisible to a shape judge | OVER 5 (ceiling artefacts) |
| R03 | RED (Base.save: C-16) | MISSING 1 | UNDER 1 (C-16) |
| R04 | RED (Base.save: C-16) | MISSING 1, EXACT 33 | UNDER 2 (C-16; the declared js re-read) |

## 7. Summary

**3 wins**, `complete: true` void until each is in the corpus with a check for
its class.

| # | class | level | one line |
|---|---|---|---|
| C-16 | S | TARGET | the cookie arm's second principal write is `UPDATE "users" SET "updated_at" = ?, "last_seen" = ?` (AR orders a post-save UPDATE by attribute materialisation, not column order); every cookie-login dump's note says `last_seen, updated_at`; the batch's own judges flag it and its auth evidence never contained a cookie login with a stale `last_seen` |
| C-17 | B | TARGET | trackable has 8 SET lists over 3 column facts; the model's Rule-D derivation `prev_login_first ⇒ IPs equal` drops the A ∧ ¬B pair (`… last_sign_in_ip …` and `… current_sign_in_ip, last_sign_in_ip …` without `last_sign_in_at`) — a same-second collision on a second-precision `DATETIME` produces it |
| C-18 | B | ENDPOINT | `conversation_id` beyond the integer column's range → `ActiveModel::RangeError` raised while binding: three statements then 500; 0 dumps carry the terminal (MySQL: 2³¹) |

**Re-verified and moved `open`→`verified`:** C-14 (six histories, TestCase and
full stack) and C-15 (html/json/mobile + full stack). **7 near-misses** (§4).
