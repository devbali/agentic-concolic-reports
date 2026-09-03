# ADVERSARY REPORT 7 — conversations_index (POST-AUTH scope)

**Endpoint:** `ConversationsController#index` (`reports/diaspora/results3/conversations_index/`)
**Round:** 7 — 2026-08-31 — first round under the Bali post-auth entrypoint scope (DISCIPLINE §15).
**State attacked:** cycle 22 — engine `complete: true`, blocking `[]`; 105 nodes, 0 missing,
747,915 PCs, 18,623 dumps, ten scenarios; assumptions 5,877 PASS; per-request multiset 0/0.
**Harness:** `adversary7/_common.rb` — adversary6's seed helpers with the warden SWITCHED to the
batch's HOOK-LESS stub (`install_hookless_warden`, the `concrete_manifest_auth.rb` /
notifications_index pattern): Devise's REAL `serialize_from_session` resolves the principal from
the real users row; NO Warden::Manager, NO after_set_user hooks, NO strategies. Verified per
request (see below): exactly ONE `users` SELECT (the principal fetch = the symbolic
`devise_user_first`), ZERO `UPDATE users` (no boundary writes). The only write any request issues
is `UPDATE conversation_visibilities` — the action's own `set_read` (C-5). Every non-principal
statement is therefore issued inside the action frame → the §15 entrypoint check is satisfied for
every statement examined.

3 manifests / 3 JRuby processes / 23 real requests. 1 JVM SIGSEGV (JRuby C2 JIT,
`StartupInterpreterEngine.interpret`) on the first A2 attempt — a runtime abort, not app logic;
re-run under `JRUBY_OPTS=--dev` (JIT off) and isolated the absent-profile principal into its own
process (A3), MEMORY.md JVM-abort discipline. Ops: `flock /tmp/concolic-slot.lock`,
`unset JAVA_TOOL_OPTIONS`, `systemd-run --user -p MemoryMax=4000M`, one scenario per process.

## Result

**0 wins (no missing shape).** `mock_note_check` and `note_fidelity_audit` are EXACT/green on all
three runs: every SQL-issuing target's real statements match a corpus note, and every real
statement has a projection-faithful note (A1: 30 distinct SELECTs, all EXACT; A2: all NOTE-OK;
A3: all NOTE-OK). No depth-0 target call and no real statement shape lacked a corpus counterpart.

**1 substantive near-miss** (the batch's OWN multiset judge goes RED on a many-conversation
request) — a multiplicity/classifier gap, not a missing shape. See below.

All nine standing wins re-verified by real run and STAY closed (none moved backward).

## Scenarios tried

| # | manifest / request | fixture state | format | result | note |
|---|---|---|---|---|---|
| 1 | A1 c8_html_plain | alice, 2 convs, layout rows | html | 200 | base content + full real layout |
| 2 | A1 c7_html_page2_beyond | " | html page2 | 200 | beyond-last page (count>0, empty rows) — C-7 |
| 3 | A1 c5_html_cid1 | " | html cid=1 | 200 | set_read UPDATE (unread 1→0) — C-5 |
| 4 | A1 c8_json_plain | " | json | 200 | — C-8 |
| 5 | A1 json_cid1 | " | json cid=1 | 200 | cid lookup + set_read then json body |
| 6 | A1 c6_html_cid_array | " | html cid=[1,2] | 200 | `IN (?, ?)` — C-6 |
| 7 | A1 c8_js_empty | dora, empty inbox | js | 500 | full render → `no_contacts` Template::Error — C-8 |
| 8 | A1 html_uid11_fresh | fay | html | 200 | second principal, fetch family |
| 9 | A1 c15_cid_empty_array | alice | html `?conversation_id[]` | 200 | `AND 1=0` — C-15 |
| 10 | A1 c18_cid_oor | alice | html cid=huge | 500 | `ActiveModel::RangeError` — C-18 |
| 11 | A1 m5_invalid_locale | uid30 language `xx` | html | 500 | `I18n::InvalidLocale` before the action, one stmt — M-5 |
| 12 | A1 json_cid1_page2 | alice | json cid=1 page2 | 200 | cid found + beyond page on json |
| 13 | A1 mobile_cid1 | alice | mobile cid=1 | 200 | mobile layout + cid + set_read — C-12 |
| 14 | A1 mobile_plain | alice | mobile | 200 | mobile layout base — C-12 |
| 15 | A1 html_cid2_nowrite | alice, conv2 unread 0 | html cid=2 | 200 | set_read finds visibility, unread already 0 → save is a no-op (C-5 clean side) |
| 16 | A1 c7_page_abc | alice | html page=abc | 500 | `Integer("abc")` InvalidPage — C-7 |
| 17 | A1 c7_page_zero | alice | html page=0 | 500 | `invalid page: 0` — C-7 |
| 18 | A2 many_html_cid1 | alice, **12 convs** (self-only, 5-party, empty, unread mix) | html cid=1 | 200 | multiplicity + participant-render branches |
| 19 | A2 many_html_plain | " | html | 200 | 12 convs render |
| 20 | A2 many_json_plain | " | json | 200 | map(&:conversation) × 12 |
| 21 | A2 many_mobile_cid1 | " | mobile cid=1 | 200 | mobile per-conv render × 12 |
| 22 | A3 absent_profile_json | uid50, person 60, NO profile row | json | 200 | empty inbox, no layout — no novel shape |
| 23 | A3 absent_profile_html | " | html | 500 | crashes in the layout on a federation host-meta network fetch (`Faraday::ConnectionFailed`), not a DB statement — out of scope |

## Near-miss (the multiset judge goes RED on many conversations)

**A2 `_multiset_counts.py` → RESULT: RED, per-request shapes under-emitted 1.** The under-emitted
shape is

```
SELECT "profiles".* FROM "profiles" WHERE "profiles"."person_id" = ?      (NO LIMIT)
```

real **x11** in the `many_html_cid1` request (12 conversations) vs corpus max **x1**.

- **Source:** `Conversation#last_author` (`conversation.rb:59`)
  `@last_author ||= Person.includes(:profile).find_by(id: @last_author_id)`. The `includes(:profile)`
  eager-load issues this no-LIMIT `profiles.* WHERE person_id = ?` once per rendered conversation
  that has messages (via `_conversation.haml:33` / `_conversation.mobile.haml:19`). 11 such
  conversations → 11 issues in one request.
- **Why it is NOT a missing-shape win:** `mock_note_check` is NOTE-OK and `note_fidelity` is EXACT
  for it — the SHAPE and its projection ARE in the corpus. It is a *multiplicity* mismatch only.
- **Why the multiset judge misses the exemption:** the corpus binds this shape to a find_by
  **ordinal representative** — `$$(…_find_by_1_id)` / `$$(…_find_by_2_id)` — never to a `_row_`
  variable, and it appears at most once per dump. `_multiset_counts.py`'s `per_row` exemption is
  keyed on notes containing `$$(…_row…)`, so it classifies this per-conversation read as a plain
  per-request shape and flags real x11 > corpus x1 as `UNDER` (RED). The sibling
  `profiles.* … person_id = ? LIMIT ?` (the `person.profile` `has_one`, WITH LIMIT) IS bound to a
  `_row_` var and is correctly classified `LIMIT` (known one-representative limit) at real x21.
- **Class hypothesis:** Class-S *evidence-shape / multiset-classifier* gap, **TARGET-LEVEL** in
  cause (the shared runtime models a repeated per-collection `includes(:assoc).find_by` with
  ordinal representatives; the multiset judge's per-row detector does not recognise that family as
  the same known one-representative limit). It surfaced only now because the batch's own
  `concrete_run_auth.json` uses **2** conversations, so the last_author preload never exceeded the
  corpus's two ordinals — the completeness engine's per-request multiset gate never witnessed the
  true per-conversation multiplicity.
- **Entrypoint evidence:** issued from the view render during the action dispatch; the run shows
  1 `users` SELECT and 0 `UPDATE users` for the request, so it is unambiguously an action-frame
  statement (not boundary).
- **Recommended repair (batch/coordinator, not the adversary):** either (a) extend
  `_multiset_counts.py`'s `per_row` detection to also exempt ordinal-representative per-collection
  reads (notes bound to `…_find_by_N_…` issued once per rendered row), OR (b) add a
  many-conversation request to the batch's concrete run so the gate measures the true multiplicity
  and records it as a declared known limit (as the `posts.guid` / `messages.size` families already
  are). Until then the completeness claim's multiset gate is green only because the concrete run
  under-samples conversation count.

The A2 `OVER` lines (`roles … moderator … x2`, the will_paginate `COUNT(DISTINCT …) x2`) are the
corpus OVER-approximating relative to my 4-request mix (sound; a moderator-but-not-admin principal
on mobile reads `moderator?` twice — drawer `elsif` + presenter — a case my A2 alice, an admin,
does not hit). OVER is corpus conservatism, never an adversary win.

## Re-verification verdicts (all STAY closed)

| win | R7 real-run evidence | verdict |
|---|---|---|
| C-5 write dirtiness / partial write | A1 c5_html_cid1: `UPDATE conversation_visibilities SET unread=?, updated_at=?` on unread 1→0; A1 html_cid2_nowrite (unread already 0) issues NO update; note EXACT | reproduces, closed |
| C-6 cid array `IN (?, ?)` | A1 c6_html_cid_array: `… conversation_id IN (?, ?) …`; `note_fidelity` PRED-OP-DIFF 0 | reproduces, closed |
| C-7 page domain | A1 page2 beyond 200; page=abc → `Integer()` InvalidPage 500; page=0 → `invalid page: 0` 500; all terminals with only the principal SELECT | reproduces, closed |
| C-8 format domain (js full render) | A1 js empty → `no_contacts` `Template::Error` 500; json 200 | reproduces, closed |
| C-12 mobile layout | A1 mobile_plain / mobile_cid1 rendered `fmt=mobile`; drawer reads (`reports`/`tags`/roles) present; A2 mobile ×12 | reproduces, closed |
| C-13 services ×1 | A1+A2 note_fidelity found no over-emission of `services … user_id`; single note matched | reproduces, closed |
| C-15 cid empty array → `AND 1=0` | A1 c15_cid_empty_array `?conversation_id[]` 200; corpus note matched | reproduces, closed |
| C-18 out-of-range cid RangeError | A1 c18_cid_oor → `ActiveModel::RangeError` 500 after the finder cast; corpus carries it as a designed terminal (RangeError ×11) | reproduces; corpus models it (NOTE: ledger row still `open` — see below) |
| M-5 locale three-armed | A1 m5_invalid_locale (language `xx`) → `I18n::InvalidLocale` before the action, exactly the one principal SELECT | reproduces, closed |

**Ledger note on C-18:** its row is still marked `open` although the corpus now carries the
RangeError as a designed terminal and the real run reproduces it. I did not change the row (the
discipline permits moving only a row I personally re-verified from `repaired`→`verified`, and C-18
is marked `open`, not `repaired`). Flagging for the coordinator to reconcile.

## Branches considered and why they yielded nothing

- **Principal-column domain (the fresh scope's headline surface):** language (M-5), `id` / `person_id`
  (the fetch reps), admin/moderator roles, `getting_started`, gender, unread banner. Verified in the
  corpus: `roles … name='admin' …` exists?, `roles … name IN ('moderator','admin') …` exists?,
  `notifications COUNT`, `services`, `aspects`, `tags`, `contacts receiving COUNT`,
  `SUM(conversation_visibilities.unread)`, `contacts.mutual` exists?/pluck, `people`/`profiles` by
  `person_id` — all present and projection-faithful. `getting_started?` / `basic_profile_present?`
  live only in `current_user_redirect_path` (the sign-in redirect), NOT reached by `#index`.
  `set_grammatical_gender` reads `current_user.gender` only under an inflected locale (`pl`), and
  `Profile#lazy_load` (gender/bio/birthday/location) is INACTIVE under `RAILS_ENV=concolic` (the guard
  needs `mod`/`test`), so gender is a plain column of `profiles.*` (already read) — no separate
  projection, no new shape.
- **Absent person/profile:** absent-profile json is an empty inbox (no new shape); absent-profile
  html crashes on a federation network fetch, not a DB statement; absent-person is a DB-invariant
  violation (every user has a person at signup) and out of the symbolic-user declaration.
- **Interactions page×cid×format:** json+cid+page2, mobile+cid, cid=2 no-write, cid array, cid[]
  empty, cid out-of-range — all reproduce existing corpus shapes; both `if @conversation` arms are
  covered (found via cid=1/array; nil via cid[] empty `AND 1=0`).
- **Rescue/ensure paths:** the action has none of its own; the terminals (InvalidLocale, InvalidPage,
  RangeError, js Template::Error, xml UnknownFormat) are the designed ones and all reproduce.
