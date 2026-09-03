# ADVERSARY ROUND 8 — comments_index (CommentsController#index, GET /posts/:post_id/comments)

Date 2026-09-01. Corpus under attack: cycle 10 — `complete: true`, 71 nodes,
**20 879 dumps** / 359 770 PCs, 0 missing, assumptions 2 713/2 713 PASS,
shims 19 PASS / 11 PROTOCOL / 0 red, `hardening_lint` clean over 57 evidence
files, `rig_crash_census` pass, multiplicity matrix 0 under / 0 over,
`boundary_declaration_audit` pass.

**Ops.** 6 manifests, 6 JRuby processes (`adversary8/H01…H06`), **67 real HTTP
requests + 18 in-process probes, 452 request-scoped SQL statements**. One
deliberate JVM abort (H01 probe 99/08, the *baseline* that had to abort); every
other process exited cleanly. Each process: `unset JAVA_TOOL_OPTIONS`,
`reports/diaspora/tools/slot scripts/diaspora-concolic …/concrete_run_probe.rb
<manifest>` inside `systemd-run --user --pipe --wait -p MemoryMax=4000M
-p MemorySwapMax=0`; never more than 2 JRubys at once. No mocks, stubs or
monkey-patches; only fixture rows, session/user, params, headers and format.
Batch instruments byte-identical after the round —
`md5sum -c adversary8/runs/_batch_md5_before.txt`: 10/10 **OK**
(`concrete_run*.json` ×7, `targets.rb`, `concolic_targets.rb`,
`completion_config.json`).

**Result: 2 wins (W8-1, W8-2 — both TARGET-LEVEL), 6 near-misses, 1 named
target refuted with positive evidence.**

**Entrypoint evidence.** Round 8 adds a harness-side
`ActiveSupport::Notifications.subscribe("sql.active_record")` probe
(`adversary8/_frames8.rb`) that records `caller` at the moment each statement is
issued, plus a full-backtrace request wrapper (H05). Nothing in the app, in
`src/` or in the batch is touched. Every statement and every `fix_profile` call
reported below is shown, with its stack, inside
`app/controllers/comments_controller.rb:50-52 in 'index'` — the post-auth action
frame, principal concretely instantiated. Files:
`adversary8/runs/_frames_H0*.json`, `adversary8/runs/_backtraces_H05.json`.

**Probe hygiene (N7-7).** My own probes (`adv_probe`) issue statements too. The
only judge RED of the round is H03's `mock_note_check`, whose single complaint is
`SELECT "users".* … "users"."id" = ? LIMIT ?` *outside any target frame* — that is
the harness's own salt cache (`prime_salts!` → `User.find(uid)`), the rig artifact
DISCIPLINE §13 already records, not an endpoint statement. Every statement in
every table below is an **endpoint** statement: its captured stack ends in
`comments_controller.rb:50` or `:52`.

---

## 1. Scenario table

| manifest | scenarios | requests / probes | outcome | new? |
|---|---|---|---|---|
| **H01** `discovery_reach` | 12 crash-isolated probes: `URI.parse` / `Faraday::Utils.URI` with a space and a `[` in the host; `Discovery#clean_diaspora_id`; `fetch_and_save` with a space-, a bracket- and a no-`@` handle; `Person(7).name` / `.as_api_response`; BASELINE `fetch_and_save` on a well-formed handle | 0 / 12 | probes 06/07 **DiscoveryError, no abort**; probe 08 (parseable URL) **aborted the JVM** | **W8-1** |
| **H02** `fix_profile_authors` | comment AUTHOR with no `profiles` row (URI-hostile handle); 1 / 2 / 3 authors; both orders; link+mention text; signed-in share-visible; CONTROL with a profile | 14 / 0 | 12 × DiscoveryError, 2 × 200 | **W8-2**, N8-1 |
| **H03** `principal_shapes` | five principals (en+person+profile, en+no person, pl+no person, pl+person+profile, pl+person+no profile) × json/mobile; non-public post | 13 / 5 | 200 ×4, `NoMethodError` ×3, `DelegationError` ×5, 404 ×1 | positives |
| **H04** `mention_fix_profile` | UNNAMED vs NAMED mention markup on a profile-less person; 2 profile-less mentions; **1/2/3/4 distinct comment authors**; 4 mentions; 4 mentions with 2 dangling | 20 / 1 | 8 × DiscoveryError, 1 × `Template::Error`, 11 × 200 | **W8-2**, N8-2, N8-3 |
| **H05** `backtrace_and_states` | full backtraces of the DiscoveryError; 2 and 10 comments by ONE author; signed-in share-visible json; author == mentioned person; NAMED mention on json | 10 / 0 | 4 × DiscoveryError, 6 × 200 | entrypoint evidence, N8-1 |
| **H06** `k2_differential` | **byte-identical fixture pairs, only WHICH key lacks the profile differs** — author tree and mentions tree, both orders, json + mobile; principal without a profile on an uninflected locale | 10 / 0 | 8 × DiscoveryError, 2 × 200 | **W8-2** |

---

## 2. WINS

### W8-1 — `Person#fix_profile` and `Discovery#fetch_and_save` ARE reachable by a real run: the `reload` H6 waiver and DISCIPLINE §12 both rest on a false premise

**Class: instrument / discipline (a waiver whose stated evidence is refuted).
TARGET-LEVEL** — the claim is made app-wide in `DISCIPLINE.md §12` and is the
sole justification for `completion_config.json`'s `h6_answered` entry and for the
"unreachable by a real run" status of ledger rows 78, 113 and near-miss N7-6.

**The claim under test**, `completion_config.json` verbatim:

> `reload`'s ONLY call site on this endpoint is `Person#fix_profile`
> (person.rb:371-375), which runs only after
> `DiasporaFederation::Discovery::Discovery.new(handle).fetch_and_save` returns
> NORMALLY; **every path into it aborts the JVM on the first FFI call**
> (typhoeus -> Ethon -> libcurl through JRuby's JFFI; DISCIPLINE 12), **so no
> real run on any rig can reach it**.

**Why it is false.** The gem's `fetch_and_save`
(`diaspora_federation-0.2.6/lib/diaspora_federation/discovery/discovery.rb:19-31`)
is `validate_diaspora_id` → `webfinger` → `get(url)` → `HttpClient.get` →
`Faraday::Connection#get`, and Faraday parses the URL with `URI.parse` **before
the adapter is ever consulted**. `domain` is `diaspora_id.split("@")[1]`
(`discovery.rb:60`), and `people.diaspora_handle` is a plain column with no
format constraint (`db/schema.rb`) and no validation on an existing row. A
fixture handle whose domain is not a legal URI host therefore makes Faraday
raise `URI::InvalidURIError` **in pure Ruby**, and `fetch_and_save` converts it
to `DiscoveryError` — control returns to Ruby, the JVM lives.

**Real evidence.** `adversary8/runs/H01_discovery_reach.log`:

```
[adv8] PROBE 06 fetch_and_save space-in-domain -> DiasporaFederation::Discovery::DiscoveryError:
        Failed to fetch http://ex ample.com/.well-known/host-meta for ghost@ex ample.com:
        URI::InvalidURIError: bad URI(is not URI?): "http://ex ample.com/.well-known/host-meta"
[adv8] PROBE 07 fetch_and_save bracket-in-domain -> DiasporaFederation::Discovery::DiscoveryError: …
[adv8] PROBE 08 fetch_and_save no-at-sign START
munmap_chunk(): invalid pointer            <-- the BASELINE abort, still real
```

Probe 08 uses a handle with no `@`, so `domain` is nil and the URL
`https://.well-known/webfinger?…` **parses** — the request reaches libcurl and
aborts the JVM exactly as §12 describes. The contrast is the point: the abort is
at the curl call, not at `fix_profile`.

**Through the endpoint, 31 times.** `target_calls` of the four run files that
reach it (`Person#fix_profile` at depth 0, `#fetch_and_save` at depth 1):

```
H02_fix_profile_authors.json   fix_profile=12  fetch_and_save=12  reload=0
H03_principal_shapes.json      fix_profile= 0  fetch_and_save= 0  reload=0
H04_mention_fix_profile.json   fix_profile= 7  fetch_and_save= 7  reload=0
H05_backtrace_and_states.json  fix_profile= 4  fetch_and_save= 4  reload=0
H06_k2_differential.json       fix_profile= 8  fetch_and_save= 8  reload=0
                               TOTAL 31 / 31 / 0, 0 JVM aborts
```

**Entrypoint verification** — `adversary8/runs/_backtraces_H05.json`,
scenario `H05_860_author_noprofile_json`, root `URI::InvalidURIError`:

```
faraday-0.15.4/lib/faraday/utils.rb:275:in `URI'
faraday-0.15.4/lib/faraday/connection.rb:477:in `proxy_for_request'
diaspora_federation-0.2.6/lib/diaspora_federation/http_client.rb:15:in `get'
diaspora_federation-0.2.6/lib/diaspora_federation/discovery/discovery.rb:22:in `fetch_and_save'
app/models/person.rb:373:in `fix_profile'
app/models/person.rb:249:in `name'
app/presenters/comment_presenter.rb:13:in `as_json'
app/presenters/base_presenter.rb:14:in `as_collection'
app/controllers/comments_controller.rb:52:in `block in index'   <-- the entrypoint
…
app/controllers/comments_controller.rb:51:in `index'
```

and the mobile twin ends
`app/views/comments/_comment.mobile.haml:12` → `index.mobile.haml:3`, i.e. inside
the action's own template. Anonymous requests need no principal; the signed-in
ones (H02 806) instantiate uid 9 concretely within its symbolic declaration.

**What survives and what does not.**

* The waiver's **conclusion** survives *for this rig*: `reload` is still not
  reached, because every reachable `fetch_and_save` **raises**. `reload` appears
  in **0** of all 31 calls' `target_calls`. I could not find an app-own path that
  returns normally without the network — `person` (and therefore the
  `save_person_after_webfinger` callback) is built from `hcard`, which is an HTTP
  GET, and `Faraday.default_adapter` is `:typhoeus` (H01 probe 03).
* The waiver's **stated evidence** does not survive, and that matters under
  DISCIPLINE §14 ("an audit may read a batch's DECLARATION to know what to check,
  never to conclude that the check is unnecessary"). The true reason is
  *"`fetch_and_save` always raises on every fixture-reachable path"*, not
  *"every path aborts the JVM"*. The distinction is not cosmetic: it is exactly
  what makes W8-2 measurable.
* **DISCIPLINE §12's blanket statement is now false for all three trees.** N7-1
  narrowed it once ("every arm on the author and principal trees" remains
  unreachable); H02/H05/H06 reach the **author** tree's
  `…_author_profile_not_found == True` arm **19** times (H02 12, H05 3, H06 4) and
  H04/H05/H06 reach the **mention** tree's arm through `person.name` **12** times
  (H04 7, H05 1, H06 4) — split by the backtraces in
  `runs/_backtraces_H05.json` (`comment_presenter.rb:13` = author,
  `:15` = mentioned_people, `people_helper.rb:32` = the mobile partial). §12 should be rewritten
  as: *the JVM aborts only when the handle's domain yields a parseable URL; a
  fixture handle with an unparseable domain reaches `fix_profile` and returns a
  `DiscoveryError`.*

**Repair asked for:** rewrite the `h6_answered` reason and DISCIPLINE §12 to the
measured rule, and re-open rows 78/113 and N7-6 as reachable (W8-2 is the first
consequence).

---

### W8-2 — the SECOND key's `…_profile_k2_not_found == True` is a PHANTOM DECISION: the corpus renders a clean 200 where the real request 500s and truncates

**Class B (unexplored branch) with a Class S consequence (the corpus asserts
statements the real request never issues). TARGET-LEVEL** — the cause is in the
shared association/preload toolkit (`targets.rb:334-357`), not in this action's
view, and it is live on BOTH `includes` trees this endpoint has.

**The defect.** Cycle 9's M-13 repair materializes a SECOND representative row
only where the step is an FK-less `belongs_to` (`needs_second_row?` →
`dangling_belongs_to?`, `targets.rb:174-189`). For every other step the second
KEY's outcome is recorded as a bare boolean:

```ruby
# targets.rb:349-354
k2nf = "#{base}_k2_not_found"
loaded_keys << keys[1] unless symbool(k2nf, ct.seed_for(k2nf, false), note: psql) == true
```

`loaded_keys` is consumed only by the NESTED step
(`emit.call(nested_owner, nil, r2.klass, nested, loaded_keys)`, `targets.rb:368`).
Both steps that own a `_k2_not_found` are the **deepest** step of their tree —
`Comment{author: :profile}` and `Mention{person: :profile}` — so on the `True`
arm `loaded_keys` is read by nothing. **No child is attached, so nothing ever
calls `Person#name` on key 2, so no `…_discovery_failed` decision is taken and no
terminal follows.** The decision changes no note either: the preload SELECT is
emitted before the outcome (correctly — that is what AR does).

**Corpus census (all 20 879 dumps).** Terminals in the state
"key 1 found, key 2 NOT found":

| tree | decision pair | dumps | terminal |
|---|---|---|---|
| author (`…_row_author_profile_*`) | `not_found == False` ∧ `k2_not_found == True` | **439** | **429 CLEAN (200)** + 10 whose terminal comes from the *other* tree |
| author | `not_found == True` ∧ `k2_not_found == False` | 788 | `…_row_author_discovery_failed == True` → **DiscoveryError** |
| mentions (`…_row_person_profile_*`) | `not_found == False` ∧ `k2_not_found == True` | **948** | **916 CLEAN (200)** + 32 from the other tree |

Verbatim from `dump_anon_json_dse0012_d1.json` (`"concolic_terminal": null`):

```
True   (len(SYM_RESULT_ActiveRecord__Relation_records_1_rows) > 1)
True   (SYM_RESULT_ActiveRecord__Relation_records_1_row_author_keys_many == True)
False  (SYM_RESULT_ActiveRecord__Relation_records_1_row_author_profile_not_found == True)
True   (SYM_RESULT_ActiveRecord__Relation_records_1_row_author_profile_k2_not_found == True)
… 8 statements, full render, 200 …
```

and its mirror `dump_anon_json_dse0013_d1.json` (`not_found == True`,
`k2_not_found == False`) DOES record
`…_row_author_discovery_failed == True` and terminates
`DiasporaFederation::Discovery::DiscoveryError`. So the corpus models the
consequence **for key 1 only**. Corpus-wide there is no
`…_row2_author_discovery_failed` and no `…_row2_author_profile_not_found`
variable at all.

**Scenario (H06, the differential).** `adversary8/H06_k2_differential.rb`, posts
870 and 871 — identical fixtures, differing only in WHICH comment's author has
no `profiles` row:

```ruby
person 7  grace@other.example    profile 17            # key FOUND
person 8  wraith@ba[d.example    NO profiles row       # key NOT found (URI-hostile domain)
post 870:  comment 880 author 7 , comment 881 author 8   # -> corpus (F,T): CLEAN 200
post 871:  comment 882 author 8 , comment 883 author 7   # -> corpus (T,F): DiscoveryError
request:   GET /posts/87x/comments   format: :json and :mobile   anonymous
```

**The real runs** (`adversary8/runs/_frames_H06.json`; every stack ends at
`comments_controller.rb:52 in 'index'`):

| scenario | statements | terminal | corpus says |
|---|---|---|---|
| 870 json (**key 2 missing**) | 7 — `posts`×1, `comments`×1, `people.id IN (?, ?)`×1, `profiles.person_id IN (?, ?)`×1, `mentions`×3 | **`DiscoveryError`, 500** | **CLEAN 200, full render** (429 dumps) |
| 870 mobile | 5 — `posts`, `comments`, `people IN(2)`, `profiles IN(2)`, `mentions`×1 | **`Template::Error ← DiscoveryError`** | CLEAN 200 |
| 871 json (key 1 missing, control) | 5 | `DiscoveryError`, 500 | `DiscoveryError` ✓ |
| 871 mobile (control) | 4 | `Template::Error ← DiscoveryError` | ✓ |

and the same pair on the MENTIONS tree (posts 872 / 873, unnamed markup
`@{wraith@ba[d.example}`): **both orders 500**, json 10 statements and mobile 7
statements in each, while the corpus's `(F,T)` state is a clean 200 in 916 dumps.
H02 posts 801/802 reproduce the author pair independently (7 and 5 statements,
both `DiscoveryError`).

**The code line that issues it.** `app/models/person.rb:249` (`name` → `if
self.profile.nil? then fix_profile end`), entered from
`app/presenters/comment_presenter.rb:13` (`@comment.author.as_api_response`) on
json and `app/helpers/people_helper.rb:32` (`person_link` → `person.name`) from
`_comment.mobile.haml:12` on mobile. AR's `Preloader` attaches `nil` for whichever
key came back empty **regardless of its position**, so key 2's missing profile is
observed exactly as key 1's is.

**Why the corpus is wrong, precisely.** In 1 345 dumps it asserts (a) a **200**
where the app returns **500**, and (b) the statements of a full render — the
second comment's `mentions` reads and, on the corpus's own json path, everything
after `comment_presenter.rb:13` — where the real request stops. That is
over-emission on the `k2 == True` arm and a missing branch (`k2 ⇒
discovery_failed ⇒ terminal`) at the same time. It is the same defect class as
M-13, on the two steps M-13's repair did not cover, and it is the first time
ledger row 113 / N7-6 has been reached by a REAL run instead of by code reading.

**Repair direction (the batch agent's call, not mine):** the `k2` outcome needs a
consequence — either materialize a second row for these steps too (as M-13 did
for FK-less `belongs_to`), or attach the second child and let the render call
`name` on it. A `k2` boolean that only edits an unread `loaded_keys` is a phantom
decision (DISCIPLINE, "a `_remembered` variable nothing reads is a phantom
decision, not a decision").

---

## 3. The named targets, judged

| # | target | verdict |
|---|---|---|
| **1** | the `cardinality_consistency_audit` seam (a recorded `keys_many` that is really determined) | **REFUTED — no win.** See §4. |
| **2** | a signed-in principal whose `person` is nil | **REACHABLE, and the corpus models it.** See §4. |
| **3** | the one-representative `SampledList` ceiling changing a per-REQUEST shape | **NOT FOUND — the ceiling is arity only.** See §4. |
| **4** | the `reload` H6 waiver | **W8-1** (premise dead; conclusion survives — `reload` still unreached). |
| **5** | `CommentsInertDiscovery.fetch_and_save` as the endpoint's only WRITE site | **Unreachable by a real run; recorded in §6 with the code evidence.** |

---

## 4. Named targets 1–3 in detail (negative results, with evidence)

### 4.1 Target 1 — the audit's `keys_many` seam is not exploitable on this endpoint

`cardinality_consistency_audit` over the whole 20 879-dump corpus:

```
== cardinality_consistency_audit: 20879 dumps, 48485 list-cardinality decisions ==
-- MANY-row `=` notes EXPLAINED by the run's own decisions --
      11366 events  key-count decision (`keys_many == False`)
       2094 events  sibling row's parent not found
RESULT: pass
```
`cardinality_audit_selftest.py`: **pass** (4/4, the escape fires only where AR
really emits `=`).

I replicated the audit's inner loop and recorded every suppressed case
(13 460 events / 7 342 dumps, 7 distinct (note, step) pairs).

* **`keys_many` is recorded for exactly ONE step**, in two scenario variants:
  `…Relation_records_1_row_author` and `…Relation_to_a_1_row_author` — i.e.
  `Comment belongs_to :author`. Never for a mentions step, never for a `profile`
  step, never for a `_row2_` step (4 distinct exprs corpus-wide, 8 186 events).
* That step's key count is **genuinely free**: `comments` fixes
  `(commentable_id, commentable_type)` and there is **no** unique index over
  those plus `author_id` (`db/schema.rb`, `create_table "comments"` — three
  indexes: `author_id`, `(commentable_id, commentable_type)`, `guid` UNIQUE).
  Ten comments by one author and two comments by two authors are both real and I
  measured both (H05 861/862, H04 844–847). So no *determined* quantity is being
  decided freely, and the escape excuses nothing AR would not emit.
* Escape B (`sibling row's parent not found`, 2 094 events) is sound on this
  corpus: in 2 094/2 094 the list has exactly two row generations with one parent
  found and one missing, and the bind in the escaped note is the **found** row's.
  It would become unsound the moment a third row generation existed — the corpus
  has **zero** `_row3_` anywhere, so today it cannot.

Two things I did find, both reported as near-misses rather than wins (N8-4,
N8-5): a third, **uncounted** suppression in the audit, and the fact that the
`keys_many == False` assertion is never expressed over the two author-id symbols
it summarises.

### 4.2 Target 2 — the nil-`person` principal is reachable, and the corpus has it

Five principals, each with its own uid so the harness's per-uid warden memo
(R4-N4-5) cannot hide a principal read (`adversary8/H03_principal_shapes.rb`):

| uid | `users.language` | `people` row | `profiles` row | real outcome (json) | statements |
|---|---|---|---|---|---|
| 30 | en | yes | yes | 200 | 10 |
| 31 | en | **none** | — | `NoMethodError: undefined method 'id' for nil` | 3: `users`, `posts⋈share_visibilities`, `people.owner_id` |
| 32 | **pl** | **none** | — | `Module::DelegationError: User#gender … person is nil` | 2: `users`, `people.owner_id` |
| 33 | pl | yes | yes | 200 | 11 (incl. the principal `profiles … LIMIT ?`) |
| 34 | pl | yes | **none** | `Module::DelegationError: Person#gender … profile is nil` | 3: `users`, `people.owner_id`, `profiles … LIMIT ?` |

So the state **is** reachable for a principal that authenticates: the `people`
table has no FK from `users` and `people.owner_id` is nullable, so a user row
with no person is a legal database state, and `set_grammatical_gender`
(`application_controller.rb:120-136`) only reaches `current_user.gender` when
`I18n.inflector.inflected_locale?` — true for `pl` (probe:
`inflected_locales(:gender) == [:pl, :all]`), false for `en`. Two columns, two
different terminals.

**The corpus models all of it.** Terminal census over 20 879 dumps: 14 ×
`NoMethodError undefined method 'id' for nil`, **7 × `User#gender … person is
nil`** and **7 × `Person#gender … profile is nil`** — the two DelegationError
messages are distinct families and both are present. And the three statement
multisets are exact matches:

| real (H03) | corpus multiset | dumps |
|---|---|---|
| uid 32 → `{users, people.owner_id}` | present | **7** (`dump_auth_json_dse0021.json`) |
| uid 34 → `{users, people.owner_id, profiles … LIMIT ?}` | present | **21** (`dump_auth_json_dse0022.json`) |
| uid 31 → `{users, posts⋈share_visibilities, people.owner_id}` | present | **28** (`dump_auth_json_dse0058.json`) |

Control H06 874 (principal with a person but **no** profile, language `en`)
renders **200** on json and mobile with the ordinary statement set — confirming
that the missing principal profile reaches a statement only through the
inflected-locale path, which is what the corpus's lopsided
`devise_user_first_1_person_profile_not_found` (True 7 / False 3 868) says.
**No win; positive evidence.**

Scope note: `set_grammatical_gender` is a filter, not the action, so even had the
corpus lacked these they would have been boundary findings rather than endpoint
wins. It does not lack them.

### 4.3 Target 3 — a wider key set changes ARITY and nothing else

Measured on both trees, 1 → 4 distinct keys, json and mobile
(`adversary8/H04_mention_fix_profile.rb`):

| distinct keys | comment authors (H04 844/845/846/847) | mentions in one comment (H04 848/849, H02 805) |
|---|---|---|
| 1 | `people.id = ?` → `profiles.person_id = ?` | `= ?` → `= ?` |
| 2 | `IN (?, ?)` → `IN (?, ?)` | `IN (?, ?)` → `IN (?, ?)` |
| 3 | `IN (?, ?, ?)` → `IN (?, ?, ?)` | `IN (?, ?, ?)` → `IN (?, ?, ?)` |
| 4 | `IN (?, ?, ?, ?)` → `IN (?, ?, ?, ?)` | `IN (?, ?, ?, ?)` → `IN (?, ?, ?, ?)` |

**No new table is read, no new predicate column appears, no branch fires only at
3+.** The tables touched at width 4 are exactly the tables touched at width 1
(`posts`, `comments`, `people`, `profiles`, `mentions`, and `posts` again for the
link probe). `connection.in_clause_length` is `nil` (H04 probe), so no `IN`
splitting can manufacture a second statement, and `PredicateBuilder::ArrayHandler`
has only the two forms (`1 → equality`, `2+ → IN`). The one *pair* that needs 3+
keys to exist at all is H04 849's `people.id IN (?, ?, ?, ?)` followed by
`profiles.person_id IN (?, ?)` (4 mentions, 2 dangling) — still arity, on both
halves.

For the record, the corpus ceiling is exact: a grep over all 20 879 dumps yields
**444 200 `IN (…)` binds, every one of arity 2**, and zero occurrences of a
three-bind `IN` anywhere. **The disposition stands; I could not break it.**

---

## 5. Near-misses

| # | finding | why it matters |
|---|---|---|
| **N8-1** | **Ledger row 108 / N7-1 is wrong for `json`.** It records that a NAMED mention markup avoids `person.name`, so the mention tree's `profile_not_found == True` arm is reached *without* `fix_profile`. True on **mobile** only. On json `CommentPresenter#as_json:15` calls `@comment.mentioned_people.as_api_response(:backbone)`, and `api_accessible :backbone` adds `:name` (`person.rb:12-24`) — so **every** mentioned person without a `profiles` row enters `fix_profile`, display name or not. Byte-identical fixtures, H05 865: **json → `DiscoveryError`**, **mobile → 200 (969 bytes)**. The ledger line should be split by format. |
| **N8-2** | `Post.exists?` per-render cardinality and the `mentions` per-row count re-measured, unchanged as declared limits: H05 862 (10 comments by one author) issues **20** `mentions` SELECTs in one json request (`mentioned_people` is evaluated twice per comment, R6-N6-3); the corpus's maximum is 2. H04 847 issues 8. Still the designed `SampledList` under-count. |
| **N8-3** | **A `_row3_` generation does not exist anywhere in the corpus** (853 192 `_row2_`, **0** `_row3_`). `cardinality_consistency_audit`'s escape B is sound *because* of that and would become unsound the moment a third generation is modelled — worth a comment in the audit so a future list model does not silently invalidate it. |
| **N8-4** | **INSTRUMENT: `cardinality_consistency_audit` has a THIRD suppression that is neither counted nor printed**, contradicting its own docstring ("Both are COUNTED and PRINTED — an escape that fires silently is a green about nothing"). The `if partial: continue` at line ~179 fires on **44 385 events across 5 378 dumps**, 6 distinct shapes. On this corpus it is inert (0 of those events would have become findings, 0 escape events are hidden by it, so the printed totals are not understated **today**) — but it is prefix-anchored to the note's binds rather than step-normalized, i.e. looser than the escape that replaced it, and it is exactly the silent-green mechanism DISCIPLINE §14 forbids. Count and print it. |
| **N8-5** | **The `keys_many == False` state asserts "one distinct author" without ever expressing it over the two author symbols.** In all 5 683 such dumps `…_row2_author_id` is minted as a `symbolic_var` (`second_key`, `targets.rb:216-225`, runs unconditionally) but appears in **0** path conditions and **0** declared assumptions (`grep -c row2_author_id _assumptions_declared.json` → 0), while the emitted note reads only `…_row_author_id`. Real counterpart H05 861/862: with 2 and with 10 comments by one author the single `people.id = ?` really does cover every rendered comment's author, *because the values are equal* — a fact the corpus carries only in a free boolean. A policy extracted from those dumps carries a second author-id parameter that no statement reads and no constraint pins. Hygiene, not a wrong statement; reported so the seam is on the record rather than in a docstring. |
| **N8-6** | The signed-in **share-visible** arm reads no principal `people` row on json: H05 863 / H02 806 issue `{users, posts⋈share_visibilities, comments, people.id = ?, profiles.person_id = ?, mentions×2}` and never `people.owner_id` — because `querent_has_visibility.first` succeeds and `querent_is_author` (`lib/evil_query.rb:116`, the only `@querent.person.id` reader) is short-circuited. On **mobile** the same request DOES read it, late, from `person_link_class` (`people_helper.rb:59` `current_user.person == person`) inside the partial. Both set-shapes are in the corpus (multiset #32, #5); recorded because the *position* differs by format and nothing judges ordering. |

---

## 6. Branches I could not reach, and why

* **`fetch_and_save` returning NORMALLY, and therefore `reload` and the
  endpoint's only WRITE.** `person` (`discovery.rb:85-93`) is built from `hcard`,
  which is `get(webfinger.hcard_url)`; `webfinger` is `get(...)`; both are
  `HttpClient.get` → Faraday → `Faraday.default_adapter == :typhoeus` (H01 probe
  03). There is no app-own local-pod short circuit in `fetch_and_save` — the only
  local check in diaspora is in `Person.find_or_fetch_by_identifier`
  (`person.rb:318-328`), which `fix_profile` does not use. So the success arm
  needs the network, and the network aborts the JVM. **This is a code-reading
  claim, and it is the arm the corpus models 6 475 times**: its wall note says
  `DiasporaFederation::Discovery#fetch_and_save (discovered person; network wall,
  no sql)`, while the real gem on that arm runs
  `DiasporaFederation.callbacks.trigger(:save_person_after_webfinger, person)`
  (`discovery.rb:24`), whose diaspora-side callback persists a `Person` and a
  `Profile`. A corpus statement of "no SQL" for a call that in the deployed app
  writes to `people` and `profiles` is the one place a T-t/T-v WRITE could land on
  this endpoint. I could not turn that into a real-run win and am not claiming it
  as one; it is filed here so the next round or the shared-boundary assembly can
  decide whether to model it.
* **`Mentionable.people_from_string` / `filter_people`** — 0 calls in 67
  requests; `render_mentions` reaches them only via `disable_hovercards` /
  `link_all_mentions`, neither settable from a request (config, not fixture).
  Unchanged from R7.
* **`Diaspora::Camo`** — guarded by `AppConfig.privacy.camo.proxy_markdown_images?`;
  a fixture cannot flip it and it issues no SQL either way.
* **A dangling `comments.author_id`** — `db/schema.rb:624`
  `add_foreign_key "comments", "people", column: "author_id", on_delete: :cascade`,
  so `dangling_belongs_to?` is correctly false for that step and the corpus is
  right to model the author as always found. (`mentions` has no FK, which is why
  the mention tree does carry the decision.)
* **`ActiveRecord::RecordNotFound` / `UnknownFormat` / `MissingTemplate` as
  corpus terminals** — 0 dumps each (the 404/`UnknownFormat` paths R7 measured are
  recorded as decisions, not as terminals). Not attacked further this round;
  noted because the terminal census makes the asymmetry visible.

---

## 7. Files

`adversary8/_common8.rb` (round-7 harness, paths changed) · `_frames8.rb` (new:
statement-level `caller` capture for entrypoint evidence) ·
`H01_discovery_reach.rb` · `H02_fix_profile_authors.rb` ·
`H03_principal_shapes.rb` · `H04_mention_fix_profile.rb` ·
`H05_backtrace_and_states.rb` · `H06_k2_differential.rb` · `run8.sh` ·
`runs/*.log`, `runs/*.json`, `runs/*.judge.txt`, `runs/_frames_H0*.json`,
`runs/_backtraces_H05.json`, `runs/_body_*.txt`, `runs/_done.log`,
`runs/_batch_md5_before.txt`.
Nothing outside `adversary8/` was written except this report and the ledger
appends in `reports/diaspora/docs/ADVERSARY_WINS.md` (2 wins, 6 near-misses, one
round-log line).
