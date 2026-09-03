# Shared auth-boundary policy (diaspora, results3)

**Decision (Bali, 2026-08-31):** every endpoint's entrypoint is the POST-AUTH
action with a SYMBOLIC principal. The authentication stages run ABOVE the
entrypoint and are never part of an endpoint's corpus. Their queries and
decisions live HERE, once per app, built from the conversations_index
rounds-4..6 evidence (adversary wins C-10, C-11, C-14, C-16, C-17;
near-misses R5-NM-1, R6-NM-1/2/5; instrumentation INSTR-9/INSTR-11). The
other endpoints union this policy in instead of re-deriving it.

## 1. Scope of the boundary

Devise + Warden on every authenticated request, `prepend_before_action
authenticate_user!`. Stages, in order:

1. **Credential resolution** — session key (`warden.user.user.key` =
   `[[uid], salt]`, a Warden FETCH: `Proxy#user`, `except: :fetch` hooks
   skipped) or a signed `remember_user_token` cookie with no session (an
   AUTHENTICATION event through `Devise::Strategies::Rememberable`).
2. **Principal SELECT** — `SELECT "users".* FROM "users" WHERE "users"."id" = ?
   ORDER BY "users"."id" ASC LIMIT 1` (OrmAdapter#get -> the
   `devise_user_first` finder family).
3. **Cookie validation** (cookie path) — `remember_me?`
   (models/rememberable.rb:105-120): token compare + the AGE predicate
   `generated_at > (remember_created_at || Time.now)` and within
   `remember_for` (2 weeks). Reads `users.remember_created_at`.
4. **after_set_user hooks**, in registration order:
   - activatable/lockable: `access_locked?` (= `!!locked_at`, strategy :none);
     a LOCKED principal is logged out (`before_logout` -> forgetable
     `forget_me!`: sets `remember_created_at = NULL`, an UPDATE only if it was
     set) and `throw :warden` -> 401.
   - trackable (authentication event only): `update_tracked_fields!` —
     `sign_in_count += 1`, `last_sign_in_at = current_sign_in_at || now`,
     `current_sign_in_at = now`, `last_sign_in_ip = current_sign_in_ip`,
     `current_sign_in_ip = request.remote_ip` (the request's FIRST remote_ip
     read — where the RemoteIp spoof check fires), then SAVE.
   - rememberable (future-cookie case): `remember_me!` WRITES
     `remember_created_at` (user.rb:594 `remember_me` true) before trackable.
   - devise_lastseenable: `update_attribute(:last_seen, now) if last_seen.to_i
     < (now - 5.minutes).to_i` — an UPDATE "users" on every signed-in request
     whose last_seen is NULL or > 5 min old.

## 2. Statement shapes (the boundary's SQL)

- The principal SELECT (§1.2) — the ONE statement that remains visible to
  endpoints as the symbolic fetch.
- `UPDATE "users" SET <set-list>, "updated_at" = ? WHERE "users"."id" = ?` —
  trackable; set-list membership derives from the decisions below (C-5 dirty
  tracking: only changed columns are SET).
- `UPDATE "users" SET "remember_created_at" = ?, "updated_at" = ? …` —
  rememberable remember_me! (future cookie on a not-remembered principal) /
  forget_me! (locked logout, NULL).
- `UPDATE "users" SET "last_seen" = ?, "updated_at" = ? …` — lastseenable
  (via update_attribute -> save(validate: false)).

**C-16 — SET-list column ORDER (two-phase, fits all five observed orders):**
the FIRST save of a request emits the dirty columns in FIRST-WRITE order with
`updated_at` LAST; every LATER save emits them in SCHEMA ORDER (db/schema.rb
column order for the table). Evidence: conversations_index AGENT_RUN.md
A6-1..A6-4; five distinct real orders reproduced.

**Write multiplicity:** per-request statement multiplicity is COUNT-EXACT for
these shapes (each hook writes at most once per request; the six trackable
histories below).

## 3. Decision domain (the boundary's variables)

Request-level (how the principal arrives):
- `via_cookie` — session fetch vs cookie authentication event.
- Cookie AGE arms (cookie path, mutually exclusive, closing 401 terminals):
  `cookie_expired` (older than remember_for -> one read, 401), `cookie_older`
  (before the record was re-remembered -> one read, 401), `cookie_future`
  (clock skew; on a NOT-remembered principal `(remember_created_at ||
  Time.now)` lets it pass and remember_me! writes).
- `ip_spoof` — X-Forwarded-For vs Client-IP disagreement; RemoteIp GetIp
  raises `IpSpoofAttackError` at trackable's first remote_ip read (after the
  users read, before any write). Public addresses only (private ones are
  TRUSTED_PROXIES).

Principal-record state (the rep's columns):
- `not_found` — deleted uid (401 family).
- `locked` (= locked_at set) — logout + forget_me! + 401. A locked principal
  NEVER reaches any action: out of every endpoint's domain.
- `remembered` (= remember_created_at set; LAZY mint on first read — R5-NM-1:
  eager minting was a phantom; a REMEMBERED record was remembered in the PAST,
  value now-3600, else remember_me? rejects every valid cookie).
- `last_seen_stale` (= last_seen NULL or > 5 min) — decides the lastseenable
  write.
- `prev_login_first` — whether the previous login was the FIRST ever
  (last_sign_in_at == current_sign_in_at); decides trackable's SET list
  (A5-7). Minted lazily at trackable's read of current_sign_in_at.
- `last_sign_in_ip == current_sign_in_ip` (C-17: an IP fact of its OWN — a
  second-precision DATETIME lets two same-second logins differ in IP; never
  derived from the timestamp equality).
- `current_sign_in_ip == '0.0.0.0'` (first-sign-in marker compare).
- `sign_in_count` — ConcolicIntValue; the increment is a change by DERIVATION
  (C-14); no compare.

## 4. The boundary constraint (unobservability)

`Or(remembered, cookie_future)` over any post-terminal observation:
a cookie login on a NOT-remembered principal passes remember_me? ONLY through
the future arm; a fresh/plain cookie 401s before the action. Ground truth
(conversations_index corpus, 30,410 dumps, runs that evaluated page_beyond):
(remembered, cookie_future) cells F/T 3,524 — T/F 3,280 — T/T 4,993 —
**F/F 0**. Implementation: `_auth_terminal_observability` in
evidence/coverage_assumptions_auth_inclusive.py — corpus-DERIVED (emitted
only while the closed cell is empty; one counter-example withdraws it).

Second structural fact (same corpus): `remembered == False` with
`cookie_expired/older == True` is a one-read 401 — every post-read decision
forecloses (tier-1 one-sided handling suffices there).

## 5. The six trackable histories (evidence fixtures)

concrete_manifest_auth.rb (copied here) drives 26 real cookie/session logins:
- ned/14: stale last_seen session fetch (lastseenable write only).
- dan/15, eve/16: two same-second logins, SAME then DIFFERENT IP (C-17).
- hal/13: full sign-in histories — first-ever login (prev_login_first,
  5-column SET measured against real 6-column, the C-14 last_sign_in_at cast
  fix), second login, re-remember.
- uid 99: deleted principal (not_found 401).
- out-of-range/older/expired/future cookies; spoofed pair.

## 6. What endpoints keep (post-auth scope)

- The symbolic principal FETCH (`devise_user_first` family): the SELECT, the
  rep, `persisted`/`profile_not_found`/`language_available`, username pin.
- ALL action-level decisions: params (page/cid arms incl. C-15 empty array,
  C-18 out-of-range), content reps, layout/gon (INSTR-8), will_paginate,
  C-5 write dirtiness, C-13 loaded?, M-5.
- NOT kept: via_cookie/cookie-age/trackable/IP/lastseenable/lockable
  decisions, auth writes, 401 terminals.

## 7. Evidence files (this directory)

- evidence/run_dse_auth_inclusive.rb — the auth-inclusive harness (rounds
  4-6 final state; the real Warden manager, credential arms, spoof plumbing).
- evidence/targets_auth_inclusive.rb — the auth-inclusive principal rep
  (C-10/C-11/C-14/C-16/C-17 machinery, C-5 writer, two-phase SET order).
- evidence/coverage_assumptions_auth_inclusive.py — GATE_TABLE entries for
  every boundary expr + the derived constraint.
- evidence/concrete_manifest_auth.rb, concrete_manifest_mobile.rb — the 26
  real requests incl. the six trackable histories.
- evidence/dumps/ — exemplar runs per boundary family (401 arms, future-arm
  survivor, spoof raise, first/second cookie login, stale session write).
- Full derivations: conversations_index/AGENT_RUN.md sections A4-*, A5-*,
  A6-1..A6-14 (kept in the endpoint directory).

## 8. Status, provenance and how to reuse this

**What is VERIFIED here, and by what.**
- Every statement shape in §2 and every decision in §3 was observed in REAL
  requests: `evidence/concrete_run_auth.json` — 26 requests through the app's
  own Devise/Warden stack (real `Warden::Manager` from the built middleware
  stack, real `after_set_user` hooks, real layout), no mocks. The six
  trackable histories of §5 are those requests.
- C-10 (lastseenable write), C-11 (locked -> forget_me! + 401), C-14
  (remember-cookie login = authentication event -> trackable), C-16 (the
  two-phase SET-list ORDER rule), C-17 (the IP equality is a fact of its own)
  were each found by an adversary round against a model that lacked them, and
  each was then reproduced by the real requests above. R6-NM-1/2/3/5 (cookie
  age arms, future-cookie remember write, deleted principal, IP spoof) the
  same way.
- The unobservability constraint of §4 is DERIVED from a corpus, not asserted:
  its emitter recomputes the four cells at build time and withdraws itself on
  a single counter-example. The cell counts quoted there come from the
  18,623-dump auth-inclusive corpus of 2026-08-31.

**What is NOT claimed.** This artifact is a POLICY DESCRIPTION plus its
evidence. The boundary has never been driven as its own concolic entrypoint,
so there is no engine `complete: true` for a boundary-only corpus, and no
coverage claim is made here. Closing the boundary as an entrypoint in its own
right (symbolic credential, symbolic principal record, the hook chain as the
action) is a separate, once-per-app job; when it is done, its
`coverage_summary.json` belongs beside this file and §2/§3 become its
checklist.

**How another endpoint reuses this.** Nothing needs to be re-derived. The
endpoint models the POST-AUTH action with a symbolic principal that EXISTS
(the fetch always yields the rep; `not_found`, `locked` and the cookie arms
are boundary 401s that never reach any action), and its final policy is
`<endpoint>.sql` UNION §2 of this file. State that union in the endpoint's SQL
header and in its REPORT.md, as conversations_index does.

**How to reproduce the evidence.** `evidence/run_dse_auth_inclusive.rb` +
`evidence/targets_auth_inclusive.rb` are the complete auth-inclusive rig
(rounds 4-6 final state: INSTR-8 real layout, INSTR-9/11 real Warden manager,
the credential arms, the C-5 dirty writer and the two-phase SET-order rule);
`evidence/coverage_assumptions_auth_inclusive.py` carries a documented
GATE_TABLE entry for every boundary PC expr plus the derived constraint
(`_auth_terminal_observability`); `evidence/concrete_manifest_auth.rb` and
`_mobile.rb` rebuild the fixtures and the 26 requests. `evidence/dumps/`
holds one exemplar run per boundary family: the four 401 arms (expired,
older, fresh-not-remembered, locked), the future-arm survivor, the IP-spoof
raise, the first and second cookie logins, and the stale-last_seen session
write.
