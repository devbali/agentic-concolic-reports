-- people_show — PeopleController#show  (GET /people/:id, GET /u/:username)
--
-- CANONICAL HEADER. This text is maintained at
-- reports/diaspora/results3/people_show/POLICY_HEADER.txt and MUST be
-- re-applied to the top of this file by every extraction. Under the M-17
-- resolution (comments C12), the declaration IS the safeguard: a policy file
-- that simply stops at a wall is indistinguishable from one that covers
-- everything, so every exclusion is stated HERE, not only in a report.
--
-- SCOPE (DISCIPLINE §15): the entrypoint is the POST-AUTH action with a
-- SYMBOLIC principal. The authentication stages run ABOVE the entrypoint and
-- are not part of this file; the endpoint's complete policy is THIS FILE
-- UNION §2 of results3/_auth_boundary/BOUNDARY_POLICY.md. `show` is reachable
-- both signed-in and anonymous; the corpus carries both (the anon arm touches
-- no authentication stage at all, the warden-401 arm is the boundary's).
--
-- ============================================================================
-- STANDING OF THIS FILE  (READ THIS BEFORE USING IT)
-- ============================================================================
-- people_show is NOT a CLOSED endpoint by the results3 standard. It reached a
-- MILESTONE close-out on 2026-09-05:
--
--   * the completion engine ran COVERAGE-ONLY: coverage_summary.json says
--     `coverage_complete: true` and carries NO `completion` / `complete` key —
--     THE COMPLETION GATE DID NOT RUN. No shim-mock test pass, no
--     assumption-checker replay pass, no engine-run audit block is claimed by
--     this corpus. (Re-confirmed 2026-09-19: this endpoint has no
--     `completion_config.json`, `shim_tests.rb`, `concrete_run.json` or
--     `assumption_manifest.json` at all, and its `coverage_report.py` is an
--     older port with no completion hook — so the gate is not merely unrun,
--     it is not yet constructible here. See _REOPEN_20260919_STATUS.md §6.)
--     Coverage numbers, 2026-09-19 re-drive: 97 nodes, 0 missing,
--     tree_complete true, 0 tree_missing, demand_sets 239, not truncated,
--     solver_lost 0, 10,656 dumps, 414,532 PCs, 130 assumptions used.
--     The 2026-09-05 corpus reported the same 97 nodes / 0 missing over
--     12,997 dumps and 525,378 PCs;
--   * adversary R1 (2026-09-04) found 10 wins; 8 were repaired at the shared
--     boundary (write / exists? / pluck / owner_id) and re-witnessed by the
--     drain campaign; adversary R2 (2026-09-05, independent, 8 real runs) was
--     a ZERO-WIN round against this corpus;
--   * TWO adversary wins are DECLARED OPEN by explicit user decision
--     (Option A, 2026-09-05) — see below.
--
-- So: this file is the policy extracted from a corpus whose coverage is
-- complete and whose last adversary round found nothing, with the residual
-- demand named. It is not backed by the three-check closure the README
-- defines for conversations_index and comments_index.
--
-- ============================================================================
-- DECLARED OPEN — statements a real request CAN issue that are NOT below
-- ============================================================================
-- P-7  publisher aspects.post_default (signed-in SELF, html layout)
--        SELECT "aspects".* FROM "aspects" WHERE "aspects"."user_id" = ?
--          AND "aspects"."post_default" = ? ORDER BY order_id ASC
--        SELECT COUNT(*) FROM "aspects" WHERE "aspects"."user_id" = ?
--      source: app/models/user.rb post_default_aspects /
--              aspect_global_helper.rb publisher_aspects_for
--      wall  : the html layout's sprockets asset load fails ("couldn't find
--              file 'underscore'") and truncates the render before the
--              publisher partial's aspects queries fire.
--
-- P-8  mobile stream content queries (mobile layout), sub-shapes #2-#5:
--        SELECT "likes".*     … author_id = ? AND target_id IN (?, ?)
--                                              AND target_type = ?
--        SELECT "mentions".*  … mentions_container_id = ?
--                                AND mentions_container_type = ?   (x2 forms)
--        SELECT "polls".*     … status_message_id = ? LIMIT ?
--        SELECT "locations".* … status_message_id = ? LIMIT ?
--        SELECT "photos".*    … status_message_guid = ? ORDER BY id LIMIT ?
--        SELECT COUNT(*) FROM "photos" WHERE status_message_guid = ?
--      wall  : the mobile layout truncates at a ROUTE-GENERATION wall before
--              the per-post association queries fire — "No route matches
--              {:action=>show, :controller=>people, :format=>mobile,
--              :username=><SymStr …>}": a symbolic username reaching the URL
--              builder. Verified across the 6,370 auth_mobile dumps.
--      NOTE  : P-8 sub-shape #1 (DISTINCT posts LEFT OUTER JOIN
--              share_visibilities) is NOT open — the drain campaign
--              re-witnesses it in every auth_mobile dump, and it IS below.
--
-- THE ABSENCE OF THE ABOVE STATEMENTS FROM THIS FILE IS A DECLARED GAP, NOT A
-- FINDING THAT THOSE PATHS READ NOTHING. Both are endpoint-level TEMPLATE
-- walls, outside the four sanctioned boundary families; no assumption was
-- added to hide either. Full text: results3/people_show/AGENT_RUN.md
-- "DECLARED OPEN ITEMS", mirrored in coverage_summary.json `declared_open`.
--
-- ============================================================================
-- FOLD FIDELITY — PCs THE EXTRACTION COULD NOT REPRESENT  (measured)
-- ============================================================================
-- `skipped_pcs_audit` was run BOTH ways on this corpus (RUNBOOK, MANDATORY
-- before every extraction), 525,378 PC records:
--
--   vanilla src/ fold          parsed 421,355 | dropped 48,047  -> RED
--   variant_d assoc_fold       parsed 443,340 | dropped 26,062  -> RED
--
-- The patch is therefore INSTALLED by this extraction (it recovers 21,985
-- `(VAR == VAR(_))` / `(VAR != VAR(_))` records — the StringVal equality
-- branches — exactly as on comments_index).
--
-- UNLIKE comments_index and conversations_index, a SECOND dropped class
-- survives the patch on this endpoint, and it is declared here rather than
-- left silent (26,062 records, 4.96% of all PCs, 5 shapes):
--
--    7,792  Not(Contains(VAR(_), VAR))
--    7,513  Contains(VAR(_), VAR)
--    7,513  IndexOf(VAR, VAR(_)) == N
--    2,538  Contains(VAR(_), VAR(VAR, N, N))
--      706  (VAR(VAR, N, N) == '_')
--
-- These are the app's substring/index decisions on `people.diaspora_handle`
-- (and its `SubString(...)` prefixes) — the local-vs-remote handle split and
-- the '@' / '.' parsing behind Person#local?, #remote?, the pod-host arm and
-- the Discovery wall. They are branches on a QUERY-RESULT COLUMN, but the
-- fold's PC grammar has no SQL form for Contains/IndexOf (a LIKE '%@%'-shaped
-- predicate), so they cannot be folded into a view's WHERE.
--
-- CONSEQUENCE, stated precisely: the SET of query shapes below is unaffected
-- (these PCs never gate whether a statement is issued in the corpus; they
-- constrain the values a handle can take). What is lost is PRECISION on the
-- WHERE side — the views below are therefore BROADER (less constrained) than
-- the app's real behaviour on the handle-parsing arms, never narrower. This
-- is a Class B in fold-space and remains OPEN; it is the same RUNBOOK gap 3
-- (fold patches not upstreamed into src/) reaching a deliverable, extended by
-- a grammar limit the assoc_fold patch does not address.
--
-- Independently corroborated by `complement_audit` (exit 0) on this corpus:
-- for every one of those Contains/SubString expressions the note families are
-- present on BOTH sides and MERGEABLE to unscoped — i.e. the decision does not
-- change WHICH statements are issued, only what is true of the handle. That is
-- the evidence for the "set unaffected, precision lost" claim above.
--
-- ============================================================================
-- F6 IDENTITY SYMBOLICITY — REPAIRED AND GREEN  (2026-09-19 reopen)
-- ============================================================================
-- `identity_symbolicity_audit` on THIS corpus (10,656 dumps): **pass**.
--
--   owner_id       symbolic  8,740   literal 0
--   recipient_id   symbolic 10,262   literal 0
--   user_id        symbolic 36,026   literal 0
--
--   RESULT: pass — every principal bind is symbolic.
--
-- HISTORY. The corpus this header previously described (12,997 dumps,
-- extracted 2026-09-07) was RED: 7,030 literal `recipient_id` and 20,696
-- literal `user_id` binds — 27,726 in all — because
-- `PeopleTargets.signed_in_user` pinned the principal's `id`/`person_id`/
-- `guid` to a fixture user and bound `User#blocks` to `Block.where(user_id: 1)`.
-- The shipped file carried 32 `user_id = 1` and 2 `recipient_id = 1` literals,
-- so its views were stated FOR ONE USER. `AGENT_RUN.md` named this "the thing
-- to fix first if people_show is ever reopened".
--
-- THE REPAIR (results3/people_show/_REOPEN_20260919_STATUS.md §3) removed those
-- pins; `ConcolicTargets.symbolic_instance` already minted a symbolic var per
-- `users` column, which the singleton definitions had been shadowing. The
-- principal is now `SYM_USER_PE_id`, seeded through `seed_for` and flippable by
-- the DSE worklist like any other symbolic variable, and `user.person_id` /
-- `user.guid` route through the real `delegate … to: :person` has_one reader.
--
-- WHAT THIS MEANS FOR THE FILE BELOW: there is no literal principal id left to
-- reinterpret. Every principal bind reads as the symbolic principal, and the
-- views below are stated for an ARBITRARY signed-in user, not for user 1.
--
-- DISCIPLINE §15 note: this endpoint achieves the "symbolic principal" clause
-- by un-pinning its minted principal, NOT by resolving `current_user` through
-- the real Devise `serialize_from_session` chain as conversations_index and
-- notifications_index do. The audited property (every principal bind symbolic)
-- holds either way; the two Devise principal-resolution statements those
-- endpoints record are NOT part of this policy.
--
-- ============================================================================
-- B-1 CLASS-LEVEL FINDER WHERE — REPAIRED BY REGENERATION  (2026-09-19)
-- ============================================================================
-- TODO.md item 1: a class-level finder (`*rest` + keyword syntax) dropped its
-- WHERE clause, so the fold could not resolve the bind and kept a placeholder.
-- The fix landed in `src/ruby_runtime/call_interceptor.rb` and the mock's
-- `extract_finder_where`, and blocked only on corpus regeneration.
--
-- Measured across three extractions of the same endpoint:
--
--                                     shipped      control        THIS
--                                  (old src,    (current src,  (current src,
--                                   old corpus)  old corpus)    new corpus)
--   `_SYM_..._find_by_1_id` lines        10           22             0
--   `_SYM_..._find_by_2_id` lines         -            -             0
--   "unresolved symbolic binds" NOTEs      7           13             1
--   placeholder families                   3            3             1
--
-- The control column is why the regeneration was necessary: a src-only change
-- did NOT clear the placeholders (it raised them, because the alias-collision
-- precision fix keeps more statements). Only the fresh corpus resolves them.
--
-- The ONE remaining placeholder is `_SYM_POSTS_GUID`, which TODO.md item 7
-- records as NOT a defect: a deliberate free symbolic leaf with no query
-- behind it. Any fix for it is extraction-side (treat it like a request
-- parameter), not a mock change.
--

-- ============================================================================
-- CORPUS TERMINALS
-- ============================================================================
-- dump_errors on this corpus: ActionView::Template::Error 4,008 (the two
-- template walls above, plus the app's own render terminals) and
-- Warden::Unauthenticated => 401 6 (the NM-1 boundary-stage arm, adjudicated
-- in ADVERSARY_REPORT.md R2 §3). Statements recorded BEFORE each terminal are
-- in this file; the terminal itself is an application outcome, not a gap.
--
-- EXTRACTION PROVENANCE
--   corpus  : results3/people_show, 10656 dumps, 10656 runs loaded
--   queries : 274326 raw -> 162 distinct -> 96 subsumed -> 66 views
--   fold    : _experiment/variant_d AssocFoldingTransformer (mandatory —
--             the vanilla src/ fold drops 21 985 `(VAR == VAR(_))` /
--             `(VAR != VAR(_))` PCs on this corpus; measured by
--             skipped_pcs_audit both ways. 26 062 Contains/IndexOf PCs
--             remain undroppable by either fold — see FOLD FIDELITY)
--

SELECT 1 AS one FROM `likes`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942`, `people` AS `people900` WHERE `likes`.`author_id` = `people900`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`target_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people900`.`owner_id` = _MY_UID AND `people942`.`closed_account` = FALSE;

SELECT 1 AS one FROM `likes`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942`, `people` AS `people900` WHERE `likes`.`author_id` = `people900`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`target_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people900`.`owner_id` = _MY_UID AND `people942`.`closed_account` = FALSE AND `people942`.`guid` = '';

SELECT `likes`.* FROM `likes`, `posts` AS `posts415`, `share_visibilities` AS `share_visibilities225`, `people` AS `people942`, `people` AS `people900` WHERE `likes`.`author_id` = `people900`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`target_id` = `posts415`.`id` AND `share_visibilities225`.`shareable_id` = `posts415`.`id` AND `share_visibilities225`.`shareable_type` = 'Post' AND `posts415`.`author_id` = `people942`.`id` AND (`share_visibilities225`.`user_id` = _MY_UID OR `posts415`.`public` = TRUE) AND `posts415`.`created_at` < _NOW AND `posts415`.`type` IN ('StatusMessage', 'Reshare') AND `people900`.`owner_id` = _MY_UID AND `people942`.`closed_account` = FALSE;

SELECT `likes`.* FROM `likes`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942`, `people` AS `people900` WHERE `likes`.`author_id` = `people900`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`target_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people900`.`owner_id` = _MY_UID AND `people942`.`closed_account` = FALSE AND `people942`.`guid` <> '';

SELECT `likes`.* FROM `likes`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942`, `people` AS `people900` WHERE `likes`.`author_id` = `people900`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`target_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people900`.`owner_id` = _MY_UID AND `people942`.`closed_account` = FALSE AND `people942`.`guid` = '';

SELECT `posts`.* FROM `posts`, `posts` AS `posts415`, `share_visibilities` AS `share_visibilities225`, `people` AS `people942`, `people` AS `people900` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`author_id` = `people900`.`id` AND `posts`.`root_guid` = `posts415`.`guid` AND `share_visibilities225`.`shareable_id` = `posts415`.`id` AND `share_visibilities225`.`shareable_type` = 'Post' AND `posts415`.`author_id` = `people942`.`id` AND (`share_visibilities225`.`user_id` = _MY_UID OR `posts415`.`public` = TRUE) AND `posts415`.`created_at` < _NOW AND `posts415`.`type` IN ('StatusMessage', 'Reshare') AND `people900`.`owner_id` = _MY_UID AND `people942`.`closed_account` = FALSE;

SELECT `posts`.* FROM `posts`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942`, `people` AS `people900` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`author_id` = `people900`.`id` AND `posts`.`root_guid` = `posts795`.`guid` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people900`.`owner_id` = _MY_UID AND `people942`.`closed_account` = FALSE AND `people942`.`guid` <> '';

SELECT `posts`.* FROM `posts`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942`, `people` AS `people900` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`author_id` = `people900`.`id` AND `posts`.`root_guid` = `posts795`.`guid` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people900`.`owner_id` = _MY_UID AND `people942`.`closed_account` = FALSE AND `people942`.`guid` = '';

SELECT `profiles`.* FROM `profiles`, `people` AS `people614`, `posts` AS `posts415`, `share_visibilities` AS `share_visibilities225`, `people` AS `people942` WHERE `profiles`.`person_id` = `people614`.`id` AND `people614`.`id` = `posts415`.`author_id` AND `share_visibilities225`.`shareable_id` = `posts415`.`id` AND `share_visibilities225`.`shareable_type` = 'Post' AND `posts415`.`author_id` = `people942`.`id` AND (`share_visibilities225`.`user_id` = _MY_UID OR `posts415`.`public` = TRUE) AND `posts415`.`created_at` < _NOW AND `posts415`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE;

SELECT `profiles`.* FROM `profiles`, `people` AS `people614`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942` WHERE `profiles`.`person_id` = `people614`.`id` AND `people614`.`id` = `posts795`.`author_id` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE AND `people942`.`guid` <> '';

SELECT `profiles`.* FROM `profiles`, `people` AS `people614`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942` WHERE `profiles`.`person_id` = `people614`.`id` AND `people614`.`id` = `posts795`.`author_id` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE AND `people942`.`guid` = '';

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `profiles` AS `profiles14`, `people` AS `people791`, `users` AS `users970` WHERE `taggings`.`taggable_id` = `profiles14`.`id` AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags' AND `profiles14`.`person_id` = `people791`.`id` AND `people791`.`owner_id` = `users970`.`id`;

SELECT `aspects`.* FROM `aspects`, `aspect_memberships` AS `aspect_memberships104`, `contacts` AS `contacts270`, `people` AS `people942` WHERE `aspects`.`id` = `aspect_memberships104`.`aspect_id` AND `aspect_memberships104`.`contact_id` = `contacts270`.`id` AND `contacts270`.`user_id` = _MY_UID AND `contacts270`.`person_id` = `people942`.`id` AND `people942`.`closed_account` = FALSE;

SELECT `aspects`.* FROM `aspects`, `aspect_memberships` AS `aspect_memberships364`, `contacts` AS `contacts270`, `people` AS `people942` WHERE `aspects`.`id` = `aspect_memberships364`.`aspect_id` AND `aspect_memberships364`.`contact_id` = `contacts270`.`id` AND `contacts270`.`user_id` = _MY_UID AND `contacts270`.`person_id` = `people942`.`id` AND `contacts270`.`sharing` = FALSE AND `people942`.`closed_account` = FALSE;

SELECT `comments`.`id`, `posts415`.`id`, `share_visibilities225`.`id`, `people942`.`id` FROM `comments`, `posts` AS `posts415`, `share_visibilities` AS `share_visibilities225`, `people` AS `people942` WHERE `comments`.`commentable_id` = `posts415`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities225`.`shareable_id` = `posts415`.`id` AND `share_visibilities225`.`shareable_type` = 'Post' AND `posts415`.`author_id` = `people942`.`id` AND (`share_visibilities225`.`user_id` = _MY_UID OR `posts415`.`public` = TRUE) AND `posts415`.`created_at` < _NOW AND `posts415`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE;

SELECT `comments`.`id`, `posts795`.`id`, `share_visibilities402`.`id`, `people942`.`id` FROM `comments`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942` WHERE `comments`.`commentable_id` = `posts795`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE AND `people942`.`guid` <> '';

SELECT `comments`.`id`, `posts795`.`id`, `share_visibilities402`.`id`, `people942`.`id` FROM `comments`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942` WHERE `comments`.`commentable_id` = `posts795`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE AND `people942`.`guid` = '';

SELECT `likes`.`id`, `posts415`.`id`, `share_visibilities225`.`id`, `people942`.`id` FROM `likes`, `posts` AS `posts415`, `share_visibilities` AS `share_visibilities225`, `people` AS `people942` WHERE `likes`.`target_id` = `posts415`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities225`.`shareable_id` = `posts415`.`id` AND `share_visibilities225`.`shareable_type` = 'Post' AND `posts415`.`author_id` = `people942`.`id` AND (`share_visibilities225`.`user_id` = _MY_UID OR `posts415`.`public` = TRUE) AND `posts415`.`created_at` < _NOW AND `posts415`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE;

SELECT `likes`.`id`, `posts795`.`id`, `share_visibilities402`.`id`, `people942`.`id` FROM `likes`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942` WHERE `likes`.`target_id` = `posts795`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE AND `people942`.`guid` <> '';

SELECT `likes`.`id`, `posts795`.`id`, `share_visibilities402`.`id`, `people942`.`id` FROM `likes`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942` WHERE `likes`.`target_id` = `posts795`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE AND `people942`.`guid` = '';

SELECT `people`.* FROM `people`, `posts` AS `posts415`, `share_visibilities` AS `share_visibilities225`, `people` AS `people942` WHERE `people`.`id` = `posts415`.`author_id` AND `share_visibilities225`.`shareable_id` = `posts415`.`id` AND `share_visibilities225`.`shareable_type` = 'Post' AND `posts415`.`author_id` = `people942`.`id` AND (`share_visibilities225`.`user_id` = _MY_UID OR `posts415`.`public` = TRUE) AND `posts415`.`created_at` < _NOW AND `posts415`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE;

SELECT `posts`.`id`, `posts415`.`id`, `share_visibilities225`.`id`, `people942`.`id` FROM `posts`, `posts` AS `posts415`, `share_visibilities` AS `share_visibilities225`, `people` AS `people942` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`root_guid` = `posts415`.`guid` AND `share_visibilities225`.`shareable_id` = `posts415`.`id` AND `share_visibilities225`.`shareable_type` = 'Post' AND `posts415`.`author_id` = `people942`.`id` AND (`share_visibilities225`.`user_id` = _MY_UID OR `posts415`.`public` = TRUE) AND `posts415`.`created_at` < _NOW AND `posts415`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE;

SELECT `posts`.`id`, `posts795`.`id`, `share_visibilities402`.`id`, `people942`.`id` FROM `posts`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`root_guid` = `posts795`.`guid` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE AND `people942`.`guid` <> '';

SELECT `posts`.`id`, `posts795`.`id`, `share_visibilities402`.`id`, `people942`.`id` FROM `posts`, `posts` AS `posts795`, `share_visibilities` AS `share_visibilities402`, `people` AS `people942` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`root_guid` = `posts795`.`guid` AND `share_visibilities402`.`shareable_id` = `posts795`.`id` AND `share_visibilities402`.`shareable_type` = 'Post' AND `posts795`.`author_id` = `people942`.`id` AND (`share_visibilities402`.`user_id` = _MY_UID OR `posts795`.`public` = TRUE) AND `posts795`.`created_at` < _NOW AND `posts795`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE AND `people942`.`guid` = '';

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `profiles` AS `profiles370`, `people` AS `people942` WHERE `taggings`.`taggable_id` = `profiles370`.`id` AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags' AND `profiles370`.`person_id` = `people942`.`id` AND `people942`.`closed_account` = FALSE;

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `profiles` AS `profiles370`, `people` AS `people989` WHERE `taggings`.`taggable_id` = `profiles370`.`id` AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags' AND `profiles370`.`person_id` = `people989`.`id` AND `people989`.`closed_account` = TRUE;

SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts` AS `contacts270`, `people` AS `people942` WHERE `aspect_memberships`.`contact_id` = `contacts270`.`id` AND `contacts270`.`user_id` = _MY_UID AND `contacts270`.`person_id` = `people942`.`id` AND `people942`.`closed_account` = FALSE;

SELECT `blocks`.* FROM `blocks`, `people` AS `people791`, `users` AS `users567` WHERE `blocks`.`person_id` = `people791`.`id` AND `blocks`.`user_id` = _MY_UID AND `people791`.`owner_id` = `users567`.`id`;

SELECT `contacts`.* FROM `contacts`, `people` AS `people791`, `users` AS `users567` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`person_id` = `people791`.`id` AND `people791`.`owner_id` = `users567`.`id`;

SELECT `notifications`.* FROM `notifications`, `people` AS `people791`, `users` AS `users567` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Person' AND `notifications`.`target_id` = `people791`.`id` AND `notifications`.`unread` = TRUE AND `people791`.`owner_id` = `users567`.`id`;

SELECT `people`.* FROM `people`, `contacts` AS `contacts270`, `people` AS `people942` WHERE `people`.`id` = `contacts270`.`person_id` AND `contacts270`.`user_id` = _MY_UID AND `contacts270`.`person_id` = `people942`.`id` AND `people942`.`closed_account` = FALSE;

SELECT `people`.* FROM `people`, `contacts` AS `contacts44`, `people` AS `people942` WHERE `people`.`id` = `contacts44`.`person_id` AND `contacts44`.`user_id` = _MY_UID AND `contacts44`.`person_id` = `people942`.`id` AND `contacts44`.`sharing` = FALSE AND `people942`.`closed_account` = FALSE;

SELECT `people`.* FROM `people`, `contacts` AS `contacts44`, `people` AS `people942` WHERE `people`.`id` = `contacts44`.`person_id` AND `contacts44`.`user_id` = _MY_UID AND `contacts44`.`person_id` = `people942`.`id` AND `contacts44`.`sharing` = TRUE AND `people942`.`closed_account` = FALSE;

SELECT `photos`.`id`, `people791`.`id`, `users567`.`id` FROM `photos`, `people` AS `people791`, `users` AS `users567` WHERE `photos`.`author_id` = `people791`.`id` AND `photos`.`created_at` < _NOW AND `photos`.`pending` = FALSE AND `people791`.`owner_id` = `users567`.`id`;

SELECT `photos`.`id`, `people791`.`id`, `users567`.`id` FROM `photos`, `people` AS `people791`, `users` AS `users567` WHERE `photos`.`author_id` = `people791`.`id` AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE AND `people791`.`owner_id` = `users567`.`id`;

SELECT `photos`.`id`, `share_visibilities`.`id`, `people942`.`id` FROM `photos` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `photos`.`id` AND `share_visibilities`.`shareable_type` = 'Photo', `people` AS `people942` WHERE `photos`.`author_id` = `people942`.`id` AND (`share_visibilities`.`user_id` = _MY_UID) AND `photos`.`created_at` < _NOW AND `photos`.`pending` = FALSE AND `people942`.`closed_account` = FALSE;

SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `people` AS `people942` WHERE `posts`.`author_id` = `people942`.`id` AND (`share_visibilities`.`user_id` = _MY_UID) AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people942`.`closed_account` = FALSE;

SELECT `profiles`.* FROM `profiles`, `people` AS `people338`, `posts` AS `posts593` WHERE `profiles`.`person_id` = `people338`.`id` AND `people338`.`id` = `posts593`.`author_id` AND `posts593`.`public` = TRUE AND `posts593`.`created_at` < _NOW AND `posts593`.`type` IN ('StatusMessage', 'Reshare');

SELECT `profiles`.* FROM `profiles`, `people` AS `people791`, `users` AS `users567` WHERE `profiles`.`person_id` = `people791`.`id` AND `people791`.`owner_id` = `users567`.`id`;

SELECT 1 AS one FROM `roles`, `people` AS `people900` WHERE `roles`.`person_id` = `people900`.`id` AND `roles`.`name` = 'admin' AND `people900`.`owner_id` = _MY_UID;

SELECT 1 AS one FROM `roles`, `people` AS `people900` WHERE `roles`.`person_id` = `people900`.`id` AND `roles`.`name` IN ('moderator', 'admin') AND `people900`.`owner_id` = _MY_UID;

SELECT `blocks`.* FROM `blocks`, `people` AS `people942` WHERE `blocks`.`person_id` = `people942`.`id` AND `blocks`.`user_id` = _MY_UID AND `people942`.`closed_account` = FALSE;

SELECT `comments`.`id`, `posts593`.`id` FROM `comments`, `posts` AS `posts593` WHERE `comments`.`commentable_id` = `posts593`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts593`.`public` = TRUE AND `posts593`.`created_at` < _NOW AND `posts593`.`type` IN ('StatusMessage', 'Reshare');

SELECT `contacts`.* FROM `contacts`, `people` AS `people942` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`person_id` = `people942`.`id` AND `people942`.`closed_account` = FALSE;

SELECT `conversation_visibilities`.`id`, `conversation_visibilities`.`unread` FROM `conversation_visibilities`, `people` AS `people900` WHERE `conversation_visibilities`.`person_id` = `people900`.`id` AND `people900`.`owner_id` = _MY_UID;

SELECT `likes`.`id`, `posts593`.`id` FROM `likes`, `posts` AS `posts593` WHERE `likes`.`target_id` = `posts593`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts593`.`public` = TRUE AND `posts593`.`created_at` < _NOW AND `posts593`.`type` IN ('StatusMessage', 'Reshare');

SELECT `notifications`.* FROM `notifications`, `people` AS `people942` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Person' AND `notifications`.`target_id` = `people942`.`id` AND `notifications`.`unread` = TRUE AND `people942`.`closed_account` = FALSE;

SELECT `people`.* FROM `people`, `posts` AS `posts593` WHERE `people`.`id` = `posts593`.`author_id` AND `posts593`.`public` = TRUE AND `posts593`.`created_at` < _NOW AND `posts593`.`type` IN ('StatusMessage', 'Reshare');

SELECT `people`.* FROM `people`, `users` AS `users567` WHERE `people`.`owner_id` = `users567`.`id`;

SELECT `photos`.`id`, `people942`.`id` FROM `photos`, `people` AS `people942` WHERE `photos`.`author_id` = `people942`.`id` AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE AND `people942`.`closed_account` = FALSE;

SELECT `photos`.`id`, `people989`.`id` FROM `photos`, `people` AS `people989` WHERE `photos`.`author_id` = `people989`.`id` AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE AND `people989`.`closed_account` = TRUE;

SELECT `posts`.`id`, `posts593`.`id` FROM `posts`, `posts` AS `posts593` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`root_guid` = `posts593`.`guid` AND `posts593`.`public` = TRUE AND `posts593`.`created_at` < _NOW AND `posts593`.`type` IN ('StatusMessage', 'Reshare');

SELECT `profiles`.* FROM `profiles`, `people` AS `people900` WHERE `profiles`.`person_id` = `people900`.`id` AND `people900`.`owner_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people` AS `people942` WHERE `profiles`.`person_id` = `people942`.`id` AND `people942`.`closed_account` = FALSE;

SELECT `profiles`.* FROM `profiles`, `people` AS `people989` WHERE `profiles`.`person_id` = `people989`.`id` AND `people989`.`closed_account` = TRUE;

SELECT `tags`.* FROM `tags` INNER JOIN `tag_followings` ON `tags`.`id` = `tag_followings`.`tag_id` WHERE `tag_followings`.`user_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_POSTS_GUID
SELECT 1 AS one FROM `posts` WHERE `posts`.`guid` = _SYM_POSTS_GUID;

SELECT `aspects`.* FROM `aspects` WHERE `aspects`.`user_id` = _MY_UID;

SELECT `contacts`.`id` FROM `contacts` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`receiving` = TRUE;

SELECT `notifications`.`id` FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`unread` = TRUE;

SELECT `people`.* FROM `people` WHERE `people`.`closed_account` = FALSE;

SELECT `people`.* FROM `people` WHERE `people`.`closed_account` = TRUE;

SELECT `posts`.* FROM `posts` WHERE `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

SELECT `reports`.`id` FROM `reports` WHERE `reports`.`reviewed` = FALSE;

SELECT `services`.* FROM `services` WHERE `services`.`user_id` = _MY_UID;

SELECT `users`.* FROM `users`;
