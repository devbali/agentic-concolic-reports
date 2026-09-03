# ADVERSARY ROUND 10 — comments_index (CommentsController#index, GET /posts/:post_id/comments)

Date 2026-09-01. Corpus under attack: **cycle 12** — `complete: true`, **84 nodes**,
0 missing, **26 528 dumps** / 928 746 PCs, assumptions 4 182 declared / 3 648 tested /
3 648 PASS / 0 FAIL / 0 NOT-TESTABLE, shims 19 PASS / 11 PROTOCOL, **zero waivers**
(`h6_answered: []`).

**RESULT: 0 WINS.** 8 near-misses / positive refutations, including the three the
coordinator named as the round's primary targets. The M-17 resolution survives every
attack I could construct.

**Ops.** 2 manifests, 2 JRuby processes (`adversary10/K01`, `K02`), run one at a
time inside `systemd-run --user --pipe --wait -p MemoryMax=4000M -p MemorySwapMax=0`
via `tools/slot scripts/diaspora-concolic …/concrete_run_probe.rb`, with
`unset JAVA_TOOL_OPTIONS`. **37 real endpoint requests / 293 endpoint SQL statements
captured with their frames**, plus **7 scenario-body probes / 7 probe statements**,
kept separate throughout. **0 JVM aborts** — every profile-less fixture person carries
a URI-hostile `diaspora_handle` (domain contains `[`), so Faraday raises
`URI::InvalidURIError` in pure Ruby before any FFI call.
No mocks, stubs or monkey-patches; only fixture rows, session, params, headers and
format. Batch instruments byte-identical after the round —
`md5sum -c adversary10/runs/_batch_md5_before.txt`: **6/6 OK**
(`targets.rb`, `concolic_targets.rb`, `run_dse.rb`, `coverage_assumptions.py`,
`completion_config.json`, `concrete_aliases.json`).

**Probe hygiene (the trap the brief named).** `mock_note_check` is **RED on both
manifests**, and **every RED shape is a scenario-body probe of mine**, not an endpoint
statement. K01's two are `PROBE_R3` (`people.diaspora_handle` fast path) and `PROBE_R4`
(`people.id = @ LIMIT @`); K02's two are `PROBE_S1` (`pods`) and `PROBE_S2`
(`tags`⋈`taggings`). Attribution is machine-derivable from the `tag` field of
`adversary10/runs/_frames_K0*.json`. `note_fidelity_audit` on the endpoint statements
is **16 EXACT / 0 MISSING (K01)** and, once the two probe shapes are set aside,
**13 EXACT (K02)**. `_multiset_counts.py` **passes both**: 0 per-request shapes
under-emitted, 0 over-emitted (K01 16 requests, K02 21 requests, 26 524 dumps).

**Entrypoint evidence.** A harness-side `sql.active_record` subscriber
(`adversary10/_frames10.rb`) records `caller` per statement. Every statement in every
ENDPOINT column below has a captured stack ending inside the action:
`app/controllers/comments_controller.rb:50 in 'index'` (the finder chain via
`comment_service.rb:24 find_for_post`), or `:52 in 'block in index'` via
`base_presenter.rb:14 as_collection` → `comment_presenter.rb:12/13/15` (json), or
`app/views/comments/index.mobile.haml:3` → `_comment.mobile.haml:12/23` (mobile).
Files: `adversary10/runs/_frames_K01.json`, `_frames_K02.json`.

---

## 1. Scenario table

| manifest | scenarios | requests / probes | outcome | new? |
|---|---|---|---|---|
| **K01** `third_rep_and_wall_order` | 3 comments × 3 authors with the THIRD profile-less (json / mobile / auth-json); 3 comments × 2 author keys, third walls; TWO distinct wallers in one request; first-comment waller (json + mobile, wall ORDER); mention-tree waller without a display name; ONE comment with **six** `diaspora://` post links; three mentions with the **middle** one dangling; controls | 16 / 4 | 10 × `DiscoveryError`/`Template::Error`, 5 × 200, 1 × `Template::Error(NoMethodError)` | **no win** — N10-3…N10-5 |
| **K02** `formats_pods_and_principal` | comment author **on a real `pods` row** (anon/mobile/auth); podded author with no profile; `#hashtag` text; **html / xml / js / atom** (anon and auth); `session[:mobile_view]` + html; BOTH mention persons absent; `Reshare`-typed post; a 16-character `post_id`; inflected-locale (`pl`) principal; principal with no `profiles` row; principal with no `people` row | 21 / 3 | 13 × 200, 4 × `UnknownFormat`/`MissingTemplate`, 4 × terminals | **no win** — N10-2, N10-6 |

---

## 2. WINS

**None.**

---

## 3. THE THREE PRIMARY TARGETS, ANSWERED

### N10-1 — the M-17 deletion has **zero** collateral blast radius (attack 3)

The brief's most likely hiding place. I ran a full differential of the archived
cycle-11 corpus (`_bak_corpus_cycle11/`, **26 931 of 26 931** dumps scanned) against
the cycle-12 corpus (**26 528 of 26 528** scanned), on five independent axes, each
number derived twice by different methods.

| axis | c11 | c12 | lost | lost that are NOT `*_discovery_failed` |
|---|---|---|---|---|
| coverage nodes (distinct PC expressions) | 94 | 84 | 10 | **0** |
| decision variable names in PCs | 88 | 78 | 10 | **0** |
| distinct statement shapes (notes) | 20 | 18 | 2 | **0** |
| distinct `(type, target)` call pairs | 30 | 27 | 3 | **0** |
| declared assumptions | 5 315 | 4 182 | 1 135 | **0** (2 gained) |
| terminal classes | 7 | 7 | 0 | — |
| `concolic_scenario.name` values | 4 | 4 | 0 | — |

The 10 lost nodes are exactly the ten `…_discovery_failed == True` decisions
(author tree `records_1`/`to_a_1` × row/row2, mention tree `records_1/2/4` ×
row/row2). The 2 lost shapes — the `fetch_and_save` wall note and
`SELECT "people".* … "id" = @ LIMIT @` (post-discovery `reload`) — appear on the
**7 272 success-arm dumps and on no other dump in the 26 931-file population**;
independently re-derived by grep, not by the shape scanner. c12's node set is a
strict subset of c11's; nothing was gained except two new independence
declarations, both naming no discovery variable. Method validated before use:
replaying the (byte-identical) assumption generator reproduced
`25 408 runs / 1 120 dups / 4 182` on c12 and `25 073 / 1 858 / 5 315` on c11,
matching `coverage_summary.json` and `_c11/cov5.log` exactly.

Two corrections to the brief's premise, stated because they matter for future rounds:
`discovery_returns` appears in **zero dumps of either corpus** — the c11 decision was
named `*_discovery_failed`, and the success arm is that PC with `taken=false`; and the
`fetch_and_save` **call** still exists in c12 (4 657 dumps), it just always raises.

The honest framing of 94 → 84, which the batch should adopt: the deletion removed the
DECISION, not one of its outcomes, so the checker can no longer *demand* any
combination involving "discovery succeeded". The arm is not unexplored, it is outside
the demand universe. `complete: true` at 84 nodes is therefore a cheaper claim than at
94 — but it is not a false one, and no state reachable without discovery was lost.

### N10-2 — there is no second route to `pods`, `tags` or `taggings` (attack 2)

**37 real endpoint requests issued 293 statements. Not one names `pods`, `tags` or
`taggings`** — including three requests whose comment author sits on a real `pods` row
(`people.pod_id = 3`, `pods` row inserted), one whose podded author also lacks a
profile, and two whose comment text carries four `#hashtags`.

Positive evidence that the tables *are* reachable in this app, off this route, from
scenario-body probes in the same process:

```
PROBE_S1  Person#url on a podded person -> "https://pod3.example/"
          SELECT "pods".* FROM "pods" WHERE "pods"."id" = ? LIMIT ?
          frames: app:app/models/person.rb:300:in `url_to'  <- app:app/models/person.rb:282:in `url'
PROBE_S2  Profile#tags
          SELECT "tags".* FROM "tags" INNER JOIN "taggings" ON "tags"."id" = "taggings"."tag_id" …
```

`pods` has exactly one reader in the app outside the persistence callback —
`Person#url_to` (`person.rb:300`) — whose only four callers are `Person#url`,
`#profile_url`, `#atom_url`, `#receive_url`. None is on this endpoint's route: the json
projection is `acts_as_api :backbone` = `{id, guid, name, diaspora_id, avatar}`
(`person.rb:12-24`, avatar = `profile.image_url`), and the mobile partial calls only
`person_image_link` / `person_link` / `comment.message.markdownified`, all of which
route through `person_path` (`to_param`) rather than `url`. `tags`⋈`taggings` is
reachable only through `Profile#tags`, which nothing on this route calls —
`Taggable.format_tags` in `markdownified` is a pure regex-to-link pass and issued no
SQL in either hashtag request. **The gap declaration's scope is correct.**

### N10-3 — `fetch_and_save` has no non-HTTP return path (attack 1)

Refuted by code and re-confirmed live. `fetch_and_save`
(`diaspora_federation-0.2.6/.../discovery/discovery.rb:19-31`) is
`validate_diaspora_id` → `DiasporaFederation.callbacks.trigger(...)` → `person`.
`validate_diaspora_id` (`:35-40`) is `return if diaspora_id == clean_diaspora_id(webfinger.acct_uri)`
— it **evaluates `webfinger` unconditionally**, and `webfinger` (`:75-84`) is
`get(webfinger_url, …)` with a `rescue` that falls back to
`legacy_webfinger_url_from_host_meta` → `get("https://#{domain}/.well-known/host-meta", true)`.
Both are `HttpClient.get` (`:48`). The class has **no** local-pod, cached-hcard,
caller-supplied-entity or already-has-profile short circuit; `person` and `hcard`
(`:86-98`) add a second fetch on top.

Measured, this round: all ten wall requests failed at
`http://ba[d…example/.well-known/host-meta` — i.e. at the **legacy fallback**, which
means the code had already tried the primary webfinger URL and taken its rescue. Two
HTTP attempts, both refused by `URI.parse` in pure Ruby, before `DiscoveryError`.
`PROBE_R1`: `Faraday.default_adapter == :typhoeus`, unchanged. I did **not** re-run a
parseable-URL abort — R8 and cycles 11 and 12 each measured it once, in its own
systemd unit, and a fourth abort buys nothing.

`PROBE_R3` confirms the one app-level fast path that *does* skip discovery,
`Person.find_or_fetch_by_identifier` (`person.rb:317-325`, `return person if
person.present? && person.profile.present?`, two statements, no network) — and confirms
it is **not on `fix_profile`'s route**: `fix_profile` (`person.rb:373`) constructs
`Discovery` directly. Its other callers,
`Diaspora::Mentionable.find_or_fetch_person_by_identifier` ← `people_from_string`, are
reached only from `filter_people` / `backport_mention_syntax` / `create_mentions` and
from `mentioned_people` when the container is **not** persisted — and
`render_mentions` (`message_renderer.rb:71-80`) reaches `filter_people` only under
`disable_hovercards` or `link_all_mentions`, both `false` in `DEFAULTS` and never
overridden by `Comment#message` (`mentions_container.rb:42`) or by the two call sites
(`comment.message.plain_text_for_json`, `comment.message.markdownified`, neither
passing opts). **The success arm is unreachable from this endpoint, and so is every
other route into the callback's statements.**

---

## 4. NEAR-MISSES

**N10-4 — a THIRD representative row changes no shape and no predicate.** K01 post 990
(3 comments, 3 distinct authors, the third with no `profiles` row) renders two comments
in full and then walls — a request no corpus dump can carry, because the corpus models
two representative rows. Measured multiset (anon json): `{posts 1, comments 1,
people IN(3) 1, profiles IN(3) 1, mentions 5, people = @ 4, profiles = @ 4}` +
`DiscoveryError`. Every element is an existing corpus shape; the only differences are
**IN-arity 3** (corpus max 2) and **per-ROW counts** (`mentions` real ×5 vs corpus max
×4). `_multiset_counts` classes both as the declared one-representative limit and
returns **pass — 0 under / 0 over**. Post 991 (3 rows, 2 author keys) and post 995
(two distinct wallers in one request) give the same verdict. This extends N9-1 from a
plain arity measurement to a **wall-terminated** three-row render, which is the
strongest form of the third-rep attack I could construct. Status: open (declared
limit), not a win.

**N10-5 — the declared `diaspora://` link ceiling is not exceeded at the request
level.** `targets.rb:1160-1185` caps the link chain at `_text_dlink_ge4` ("4 stands for
four or more"). A single comment carrying **six** `post`-entity links issues **six**
`SELECT 1 AS one FROM "posts" WHERE "posts"."guid" = ? LIMIT ?` — but the corpus's
per-request maximum for that shape is **8** (two representatives × four links), so
`_multiset_counts` records `ROWSCALE corpus x8 > ground x6` and judges nothing. The
ceiling is real but is a **per-COMMENT** limit that the per-REQUEST judge cannot see;
exceeding it needs ≥ 3 link-bearing comments, which is the SampledList ceiling again.
Recorded so the ceiling is a measurement rather than an assertion.

**N10-6 — R7's ledger row 113 still holds on the cycle-12 corpus, re-measured.**
`format: :html` reaches the action and stops after the post finder alone
(`comment_service.rb:24` returns an unmaterialised Relation; `ActionView::MissingTemplate`);
`:xml`, `:js`, `:atom` do the same and raise `ActionController::UnknownFormat`. Anon
multiset `{posts 1}`; signed-in `{posts⋈share_visibilities 1, posts…author_id 1,
posts…public 1}`. Corpus census over all 26 528 dumps: **68 dumps carry no `comments`
read, and every one is accounted for** — `head :not_found` 14, `public == False`
(NonPublic → `authenticate_user!`) 4, `SubclassNotFound` 38, pre-action filter
terminals (`I18n::InvalidLocale`, `NoMethodError`, `Module::DelegationError`) 12 —
**0 in which the lookup succeeds, the post is public, and no `comments` read follows**.
So the html/xml/js/atom request class remains a real request shape the corpus cannot
produce. It is R7's finding, still `open` and unrepaired through cycles 11 and 12, not
a round-10 win; I re-verified it rather than re-claim it. (Row 113's parenthetical
"the only comment-less successes are the 61 `SubclassNotFound` dumps" is now 38 on this
corpus; the conclusion is unchanged.) Positive corollary: `session[:mobile_view] = true`
with `format: :html` takes `mobile_switch` (`application_controller.rb:145-149`) and
renders the full mobile body — statement-identical to an explicit mobile request.

**N10-7 — the wall's statement ORDER differs by format, and both orders are in the
corpus.** In json, `CommentPresenter#as_json` evaluates `text` before `author`, so a
profile-less author's comment issues its `mentions` read (and the nested
`people`/`profiles` preloads) **before** the raise: K01 post 994 json = `{posts 1,
comments 1, people IN(2) 1, profiles IN(2) 1, mentions 1, people = @ 1, profiles = @ 1}`.
In mobile the raise happens at `_comment.mobile.haml:12` (`person_link` →
`person.name`), **before** line 23's `markdownified`, so the same fixture issues
`{posts 1, comments 1, people IN(2) 1, profiles IN(2) 1}` and **no `mentions` read at
all**. Both multisets are reproducible from the corpus (the 630
`Template::Error(DiscoveryError)` dumps and the 4 027 `DiscoveryError` dumps). The
statements that lead into `fix_profile` are complete and faithful — 16/16 EXACT on
`note_fidelity_audit`, 0 MISSING.

**N10-8 — the `fetch_and_save` call count reconciles exactly with its terminals, and
the batch's self-reported empty-note defect is confirmed.** Over all 26 528 dumps:
`('call', 'CommentsInertDiscovery.fetch_and_save')` **4 657**, `('symbolic_call', …)`
**0** (the call always raises, so no result and **no note** is attached — the
`Thread.current[:concolic_pending_note]` line is a no-op, exactly as `AGENT_RUN.md`
cycle 12 states). Terminals: `DiscoveryError` 4 027 + `ActionView::Template::Error`
with a `DiscoveryError` cause 630 = **4 657**. No dump reaches `fetch_and_save` and
ends any other way. The dead line remains a cosmetic defect to remove at the next
regeneration; leaving the note absent is the right call under H3/T-a.

---

## 5. TARGETS REFUTED WITH POSITIVE EVIDENCE (no ledger row needed)

1. **A preload whose parents are all missing skips its nested step, and the corpus
   models it.** K02 post 904 (one comment, two mentions, both `person_id` absent)
   issues `people.id IN (?, ?)` ×2 and **no** `profiles.person_id IN` at all
   (`targets.rb:443` `if nested && survivors.any? && loaded_keys.any?`). Corpus census:
   **1 980 of 26 528 dumps** carry a `people.id IN` note with no
   `profiles.person_id IN` note. Modelled.
2. **A dangling comment author is FK-prevented, so "author preload finds zero parents"
   is determined, not free.** `db/schema.rb:624`
   `add_foreign_key "comments", "people", column: "author_id", on_delete: :cascade` —
   and `targets.rb:106` `FK_UNCONSTRAINED_BELONGS_TO = {"Mention" => %w[person]}`
   already says so. The corpus's combination census confirms it: **0 of 26 528 dumps**
   have a `people` preload with no `profiles` preload anywhere, which is the correct
   modelling.
3. **Two mentions of one person in one container is schema-impossible**, so the mention
   step's key count is determined by its row count: `db/schema.rb:207`,
   `index_mentions_on_person_and_mc_id_and_mc_type … unique: true`. Consistent with
   `targets.rb:139` `DETERMINED_BY_ROWS`, and with the absence of any
   `*_person_keys_many` variable in the corpus (**0 dumps**, verified by literal grep).
4. **The `head :not_found` arm is explored in all four scenario classes** — 14 dumps
   (anon_json 2, anon_mobile 2, auth_json 5, auth_mobile 5), each with the correct
   not-found PCs (`first_1_not_found` for anon; all three of
   `ci_vis_first`/`ci_author_first`/`ci_public_first` for auth). Rare, but present and
   correctly shaped.
5. **The 38 `SubclassNotFound` dumps are exactly the calls that raise before returning
   a result** — `call` minus `symbolic_call` per finder target is 15 + 4 + 9 + 10 = 38,
   matching the terminal count. The corpus's call/result accounting is internally
   consistent.
6. **`Reshare`-typed posts, a 16-character `post_id` (the `post_key` boundary), an
   inflected-locale principal, a principal with no `profiles` row and a principal with
   no `people` row all produce statement sets the corpus already carries** — including
   the `set_grammatical_gender` chain's `people.owner_id = @ LIMIT @` →
   `profiles.person_id = @ LIMIT @` under `language = 'pl'`, and its
   `Module::DelegationError` / `NoMethodError` terminals.
7. **Mock RETURN KINDS are right per target** (checker step 5): `exists?` → `Bool`
   (75 847 False / 10 152 True); `Relation.records`/`to_a` → list length ∈ {0,1,2};
   `FinderMethods.first`, `ci_*_first`, `devise_user_first`,
   `SingularAssociation.find_target` → a model instance or `None`;
   `load_intermediate` → a note-only probe. No target returns a kind the real call
   does not.

---

## 6. WHAT I COULD NOT REACH

* `fetch_and_save` returning normally — see N10-3. Refuted by reading the gem class
  and by measuring that even the *fallback* webfinger URL is an `HttpClient.get`.
* A third representative row in the corpus — N10-4 measures the consequence rather
  than removing it.
* A per-COMMENT diaspora-link count above 4 that is visible to a per-REQUEST judge —
  N10-5.
* `pods` / `tags` / `taggings` / any DML from inside the entrypoint — N10-2; the app
  has no other caller on this route.
