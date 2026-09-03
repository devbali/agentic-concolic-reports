# conversations_index — ADVERSARY REPORT 5 (round 5, 2026-08-30)

Concrete checker, adversarial sub-agent
(`src/end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md`).
Endpoint `ConversationsController#index`, signed-in only.

**State attacked.** Cycle 18 (`AGENT_RUN.md` A4-1…A4-8, written 06:18 today):
engine `complete: true`, `blocking: []`; 106 nodes, 0 missing, 1,018,658 PCs,
24,020 dumps over ten scenarios; assumptions 5,986/5,986 PASS; shims 15 PASS /
23 PROTOCOL / 0 NO-TEST; note check green; note fidelity 32 EXACT / 0 defects;
eight external audits PASS; hardening lint clean (DML-aware `_is_dml`);
per-request multiplicity 0 under / 0 over. Round 4 built a REAL
`Warden::Proxy` from `Devise.warden_config` and rendered the REAL html/mobile
layouts; C-10..C-13 were repaired at cause.

**Method.** Real app only — `concrete_env.rb` sqlite/JDBC + app schema, fixture
ROWS by raw `INSERT`, real Devise session/strategy resolution, real dispatch,
real templates. No mocks, no stubs, no monkey-patch of app code; nothing under
`src/`, the app, or the batch runner/targets/mocks was touched. Harness
`adversary5/_common.rb` carries every instrument fix of rounds 3–4 (INSTR-1/2/3/
5/8/9/10) plus three new rig inputs, all configuration or request data:

* **A real signed `remember_user_token` cookie** in Devise's own
  `serialize_into_cookie` shape (`[to_key, rememberable_value, generated_at]`),
  so `Devise::Strategies::Rememberable` runs when the session carries no
  principal — the "remember me" return visit. Round 4 and every batch manifest
  only ever put the principal in the SESSION, i.e. a `Warden::Proxy#user`
  **fetch**; a cookie login is an **authentication** event.
* **A raw `QUERY_STRING`** so `?conversation_id[]`, `[a]=1`, `[][]=1` reach
  the action as the arrays/hashes production's Rack parser builds
  (`ActionController::TestCase#process` cannot express them through `params:`).
* **The full middleware stack** — `Rails.application.call(env)` with a real
  encrypted `_diaspora_session` / signed remember cookie: the app's own Warden
  manager, cookie session store, executor (AR query cache ON), exception
  handling, mobile-fu. Strictly MORE of the real app than the TestCase rig.

One INSTR fix this round (INSTR-11): `Warden::Manager.new(nil,
Devise.warden_config.dup)` — round 4's rig **and** the batch's
`concrete_manifest_auth.rb` — is wrong the moment a STRATEGY has to run:
`Manager#initialize` re-splats `default_strategies` and files the scope's
strategy list under `:_all`, dropping the `:user` scope, so every session-less
request raises `"Invalid strategy user"`. A session fetch never runs
strategies, which is why rounds 3–4 and the batch never hit it. Round 5 pulls
the app's OWN `Warden::Manager` out of the built middleware stack.

Ops: `flock /tmp/concolic-slot.lock` inside `systemd-run --user -p
MemoryMax=4000M`, `JAVA_TOOL_OPTIONS` unset, one scenario file per JRuby
process, one process at a time. **8 manifests / 9 processes / 78 requests; 1
JVM abort** (Q06 html/mobile no-profile — the `Person#fix_profile → Discovery`
JFFI/libcurl crash of DISCIPLINE §12, isolated to its own process, re-run
json-only as Q06b).

---

## 1. Re-verification of the round-4 items (real runs against THIS 24,020-dump corpus)

| item | verdict | evidence |
|---|---|---|
| **C-10** (`last_seen` stamp on stale principal) | **VERIFIED — move to `verified`** | `Q04_c10_alice_stale_html`: `UPDATE "users" SET "last_seen" = ?, "updated_at" = ? …` **×1** before `set_locale`; `Q04_c10_alice_fresh_json` (fresh): **×0**. Corpus now carries the shape in 18,218 dumps, both polarities. |
| **C-11** (locked principal logged out at the boundary) | **VERIFIED — move to `verified`** | `Q04_c11_gus_locked_remembered_html` (`remember_created_at` set): `UPDATE "users" SET "remember_created_at" = ?, "updated_at" = ?` **×1** then `throw :warden, message: :locked` → 401, action never runs. `Q04_c11_hal_locked_notremembered_mobile` (`remember_created_at` NULL): the 401 with **no** UPDATE (1 statement = the users read) — the C-5 no-change-save rule, now measured, not inferred. Corpus: 33 `remember_created_at` UPDATEs + 66 `WardenThrow401` dumps, both polarities (33 with the write, 33 without). |
| **C-12 / NM-5(mobile)** (the mobile layout's tags/reports/badge multiplicity) | **VERIFIED — move to `verified`** | `Q04_c12_*_mobile`: `tags … INNER JOIN tag_followings … ORDER BY tags.name` ×1 every mobile request; `reports … WHERE reviewed = ?` ×1 for admin (`c12_alice`) and moderator (`c12_dora`); `notifications` COUNT ×2 (×3 with an unread notification — `c12_alice_mobile_cid1`), `SUM` ×2–3, `roles` person-exists ×2, `roles … IN (…)` ×2 when not admin (`c12_fay_nonadmin`, `c12_dora`). Corpus scan: `tags`/`reports` notes present, mobile badge shapes at ×2/×3. Every shape now in the corpus. |
| **C-13** (`services` read once, not twice) | **VERIFIED — move to `verified`** | `Q04_c13_alice_2services_html` and `c13_fay_1service_html`: `services … WHERE user_id = ?` **×1**. `_multiset_counts` does not flag `services` OVER on any Q04 request — corpus max == real max == ×1. The `CollectionProxy#loaded?` repair holds. |

All four round-4 wins are confirmed repaired at cause by real runs and moved to
`verified` in the ledger.

---

## 2. Scenarios run

| manifest | rig | requests | outcome |
|---|---|---|---|
| `Q01_remember_cookie` | real warden + real layout, cookie login | 13 | **C-14**; anon 401; expired/never/bad-token/older cookie → 401; stale session-salt → 401 then cookie rescue |
| `Q02_cid_domain` | real warden + real layout, raw query strings | 13 | **C-15** (empty-array `AND 1=0`); hash/empty-string/nested arms mapped |
| `Q03_fullstack` | **full middleware stack** (`Rails.application.call`) | 14 | **C-14 confirmed under production middleware** (`erin_cookie_only` 200, both writes); anon → 302 sign_in; json → 401; xml → 500 |
| `Q04_reverify` | real warden + real layout | 22 | §1 (C-10..C-13, NM-5 mobile); page-beyond × empty/non-empty × 5 formats; `_remembered` phantom |
| `Q05_no_person` | real warden | 4 | principal with NO people row → `Module::DelegationError` after `{users, people.owner_id}` |
| `Q06_no_profile` | real layout | 1 (+3 aborted JVM) | json no-profile → 200; html/mobile abort (Discovery, §12) |
| `Q06b_no_profile_json` | real layout | 1 | json no-profile → 200, no profile access |
| `Q07_cookie_arms` | real warden + real layout, cookie login | 5 | C-14 on every error terminal (InvalidLocale / RangeError / js / xml) |

---

## 3. WINS

### C-14 — the authentication boundary runs the `except: :fetch` hooks: a remember-me cookie login issues the TRACKABLE write `UPDATE "users" SET "sign_in_count", "current_sign_in_at", "last_sign_in_at", "current_sign_in_ip", "last_sign_in_ip", "updated_at"` — Class B · TARGET-LEVEL

**Scenario** (`adversary5/Q01_remember_cookie.rb`, `Q03_fullstack.rb`,
`Q07_cookie_arms.rb`): a signed-in request whose SESSION carries no principal
but whose request carries a valid signed `remember_user_token` cookie — the
ordinary "remember me" return visit after the session cookie expires.
`authenticate_user!` finds no session user, runs the strategy chain,
`Devise::Strategies::Rememberable` validates the cookie and calls
`set_user(event: :authentication)`. Because the event is **not** `:fetch`,
Warden runs the four `after_set_user except: :fetch` hooks the fetch path
skips — including **trackable**.

**Novel shape, verbatim** (`Q01_alice_cookie_stale_html`, frame
`ActiveRecord::Base#save`; also under the full production stack in
`Q03_erin_cookie_only_html`):

    BEGIN TRANSACTION
    UPDATE "users" SET "sign_in_count" = ?, "current_sign_in_at" = ?, "last_sign_in_at" = ?,
                       "current_sign_in_ip" = ?, "last_sign_in_ip" = ?, "updated_at" = ?
                 WHERE "users"."id" = ?
    COMMIT TRANSACTION

issued BEFORE `set_locale`, `people.owner_id`, everything — and followed by the
lastseenable `last_seen` UPDATE (C-10) in the same request. On alice's SECOND
cookie request the `last_sign_in_ip`/`current_sign_in_ip` columns don't change,
so the shape narrows to `SET sign_in_count, current_sign_in_at, last_sign_in_at,
last_sign_in_ip, updated_at` — a second novel note (the C-5 dirty-column rule
applied to trackable).

**Code line.** `conversations_controller.rb:4 authenticate_user!` →
`Warden::Proxy#authenticate!` → `_run_strategies_for` →
`Devise::Strategies::Rememberable#authenticate!` (`strategies/rememberable.rb`)
→ `success!(resource)` → `set_user(…, event: :authentication)` →
`Warden::Manager._run_callbacks(:after_set_user)` →
`devise/hooks/trackable.rb:1-5` (`record.update_tracked_fields!(request)`) →
`devise/models/trackable.rb:update_tracked_fields!` → `save(validate: false)`.
`:trackable` is declared at `user.rb:30`.

**What the corpus has.** `grep -l 'sign_in_count.*=' dump_*.json` → **0 of
24,020**; `SET current_sign_in_at` → 0. The only `UPDATE "users"` shapes in the
corpus are `SET last_seen` (18,218) and `SET remember_created_at` (33). The
corpus's `devise_user_first` mints exactly THREE decisions
(`_last_seen_stale`, `_locked`, `_remembered`) — it models
`Warden::Proxy#user`'s session **fetch** only. An authentication event runs
trackable, lockable and rememberable's `except: :fetch` hooks, none of which
the fetch path ever reaches.

**Why it is a Class B.** The write is decided by whether the principal arrived
by cookie-login (authentication) vs session (fetch) — a boundary state the
model has no variable for. It fires on the FIRST request of every
remember-me return visit for every signed-in endpoint, and it is confirmed
under the REAL production middleware stack (`Q03_erin_cookie_only_html` → 200,
`trackable` + `lastseenable` both present, full layout rendered), not only the
TestCase rig. Every modeled error terminal gains it on the cookie path
(`Q07`): `I18n::InvalidLocale` → `{users, trackable UPDATE, lastseenable
UPDATE}` (3, not M-5's one or C-10's two); `RangeError`/invalid page,
`.js Template::Error`, `.xml UnknownFormat` likewise.

**TARGET-LEVEL.** `authenticate_user!` + Warden's `after_set_user except:
:fetch` hooks run for every Devise-signed controller on any authentication
event. The batch's `devise_user_first` models the fetch boundary alone; this
is the fetch boundary's authentication sibling. Propagation-matrix row T-x2.

### C-15 — the `conversation_id` param domain has an empty-array arm the corpus never expresses: `?conversation_id[]` → `params[:conversation_id] == []` (truthy) → `… AND 1=0 ORDER BY …` — Class B (S-shape consequence) · ENDPOINT-LEVEL

**Scenario** (`adversary5/Q02_cid_domain.rb`, raw `QUERY_STRING =
"conversation_id[]"`): production's Rack parser turns `?conversation_id[]` into
`[nil]`, `deep_munge` strips the nil → `params[:conversation_id] == []`. The
controller guard is `if params[:conversation_id]` (a TRUTHY check, not
`.present?`), and `[]` is truthy, so the lookup branch is ENTERED with an empty
array.

**Novel shape, verbatim** (`Q02_cid_empty_array_html`, frame
`ActiveRecord::Relation#records`; identical on json and mobile):

    SELECT "conversations".* FROM "conversations"
      INNER JOIN "conversation_visibilities"
        ON "conversation_visibilities"."conversation_id" = "conversations"."id"
     WHERE "conversation_visibilities"."person_id" = ? AND 1=0
     ORDER BY "conversations"."id" ASC LIMIT ?

`ActiveRecord` renders `where(conversation_id: [])` as the constant-false
`AND 1=0`. `.first` returns nil → the not-found arm, but with a predicate note
no corpus dump carries.

**Code line.** `conversations_controller.rb:11-16`
(`if params[:conversation_id]` → `Conversation.joins(:conversation_visibilities)
.where(conversation_visibilities: {person_id:…, conversation_id: params[:conversation_id]}).first`).

**What the corpus has.** `grep -l '1=0' dump_*.json` → **0 of 24,020**. The
corpus's cid arm is always scalar `conversation_id = ?` (`SYM_PARAM_cid_is_array
== False`, C-6's `= ?`) or a non-empty `conversation_id IN (?, …)`
(`cid_is_array == True`); no dump expresses the empty-array `1=0` predicate.
`note_fidelity_audit` on `Q02` scored **PRED-DIFF 1** on exactly this frame;
`_req_stats` marked it **ABSENT-CORPUS**.

**Why it is a Class B with an S consequence.** `cid_is_array` is recorded as a
boolean, but the array's EMPTINESS is a third arm (`[]` vs `[x]` vs `[x,y]`)
the model collapses — and the note the policy inherits for the empty case
(`AND 1=0`, an unconditionally-empty read of `conversations`) differs from both
recorded predicates. The hash arm (`?conversation_id[a]=1`), the empty-string
arm (`?conversation_id=`) and the nested-array arm (`?conversation_id[][]=1`)
all collapse to the scalar `= ?` and are correctly covered (mapped in `Q02`);
only the empty array is novel.

**ENDPOINT-LEVEL.** The guard and the finder are this action's own; the
`AND 1=0` is AR's generic empty-`IN` rendering but the branch that issues it is
`ConversationsController#index`'s.

---

## 4. Near-misses

* **NM-1 — the `_remembered` decision is a PHANTOM on the fetch path.** The
  corpus records `SYM_RESULT_…devise_user_first_N_remembered` on 23,954/23,954
  non-locked dumps, but the fetch-path code never reads `remember_created_at`
  for a non-locked principal: rememberable's hook is `except: :fetch`, and
  `remember_created_at` is consulted only by `forget_me!` on the LOCKED path
  (C-11). `Q04_c10_ivy_stale_remembered_notlocked_html` (stale + remembered +
  NOT locked) issues only the `last_seen` write — no remember read, no remember
  write. A recorded decision with no effect on any statement is a harmless
  over-approximation (extra branch coverage), not a missing shape — reported
  for the model's honesty, not as a win.
* **NM-2 — the full-stack SESSION-cookie principal did not resolve** (302 to
  `/users/sign_in` for every `uid:`-in-session `Q03` request); only the
  remember-COOKIE path authenticated. This is a rig limitation of my encrypted
  `_diaspora_session` construction (marshal serializer / key derivation under
  `RAILS_ENV=concolic`), NOT an app finding — and it does not weaken C-14,
  whose production-stack evidence comes through the remember cookie
  (`Q03_erin_cookie_only_html` → 200, both writes, full layout). A better
  full-stack session-cookie builder would let every Q03 arm run through the real
  middleware; the remember path was enough to confirm the win.
* **NM-3 — the `if params[:conversation_id]` guard is a truthiness check, not
  `.present?`.** `[]` and `{}` both pass it (C-15); had it been `.present?` the
  empty array would skip the lookup entirely. Informational: the arm exists
  because of the exact guard the code uses.
* **NM-4 — per-row one-representative ceiling** (R4 NM-2, unchanged): `Q02`/`Q04`
  cid requests show `profiles … LIMIT` ×9 vs corpus 5, `messages` ×3 vs 2,
  participants ×3 vs 2 — the shared runtime's designed one-representative
  under-count (per-ROW shapes; `_multiset_counts` reports them as the known
  limit, not RED). Re-observed, not a win.
* **NM-5 — the `.js` beyond-page exception re-read** (declared
  `multiset_renderer_re_reads`, R4-NM-3): `Q04_pg_dora_beyond_js` re-issues the
  paginated `t0_r0` read ×4 and the count ×6 via the `NameError#message`
  view-context inspect; decided by the exception renderer, not the app.
  Re-confirmed.

---

## 5. Branches reached / not reached

| branch | outcome |
|---|---|
| remember-me cookie login (authentication event) | **C-14** — reached, real + full-stack |
| expired / never-remembered / bad-token / cookie-older-than-`remember_created_at` | all → `throw :warden` 401 after the single users read, no write (`Q01`) — correct: `serialize_from_cookie` / `remember_me?` reject before any hook |
| stale session salt (password changed elsewhere) | `Q01_kim_stale_session_html` → 401, no write; `kim_stale_session_cookie` → the cookie rescues it, trackable + lastseenable writes fire (C-14) |
| `?conversation_id[]` empty array | **C-15** — reached, html/json/mobile |
| `?conversation_id[a]=1` hash / `[][]=1` nested / `=` empty string | reached, all collapse to scalar `= ?` — corpus-covered |
| principal with NO people row | `Module::DelegationError` (`User#person_id` → `person.id`, person nil) after `{users, people.owner_id}` — matches the corpus `person_persisted == False` shape's prefix; the delegate raises where the corpus's listed-author variant does not, but no data-access differs (`Q05`) |
| principal with NO profile, json | 200, no profile access (`Q06b`) — json builds no layout, so `UserPresenter` is never serialized |
| principal with NO profile, html/mobile | **JVM abort** (`Person#fix_profile → Discovery`, JFFI/libcurl, DISCIPLINE §12) — not reachable on this JRuby; isolated to its own process |
| timeoutable hook | inert — `User` is `:trackable` but not `:timeoutable`; the `timeoutable` hook needs `record.respond_to?(:timedout?)`, which the model does not (measured: no timeout write on any run) |

---

## 6. Summary

**2 wins**, both blocking; `complete: true` is void until each is in the
corpus AND a check exists for its class.

| # | class | level | one line |
|---|---|---|---|
| C-14 | B | TARGET | a remember-me cookie login is an AUTHENTICATION event, so Warden runs the `except: :fetch` hooks the corpus's fetch-only `devise_user_first` skips: `UPDATE "users" SET "sign_in_count", "current_sign_in_at", "last_sign_in_at", "current_sign_in_ip", "last_sign_in_ip", "updated_at"` (trackable) fires before the action — 0 of 24,020 dumps; confirmed under the full production middleware stack |
| C-15 | B (S consequence) | ENDPOINT | `?conversation_id[]` → `params[:conversation_id] == []` (truthy) → the conversation lookup issues `… WHERE person_id = ? AND 1=0 ORDER BY …`; the corpus's `cid_is_array` boolean collapses the empty-array arm, and the `1=0` predicate note appears in 0 of 24,020 dumps |

**Re-verified and moved `open`→`verified`:** C-10, C-11, C-12, C-13, and
NM-5(mobile) — all confirmed repaired at cause by real runs against this
corpus. **5 near-misses** (§4). **1 instrument fix** (INSTR-11: the Warden
manager must come from the built stack, not `Manager.new(Devise.warden_config)`
— the batch's own `concrete_manifest_auth.rb` has the same defect and would
raise on any strategy-running scenario).

**Where the round's wins live.** As in round 4, both are in what the corpus's
boundary model does not cover rather than in what DSE explored: the corpus
models the session-FETCH boundary (three decisions) and the cid arm as a
boolean; round 5 shows the AUTHENTICATION boundary (the `except: :fetch` hook
family, reached by the remember-me cookie) and the cid arm's empty-array third
value. A ground truth is only as complete as its least-explored boundary state,
and "authenticated by cookie" was never one the rig produced.
