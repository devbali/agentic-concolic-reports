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
--     `coverage_complete: true` (97 nodes, 0 missing, not truncated, 12,997
--     dumps, 525,378 PCs, 130/284 assumptions used) and carries NO
--     `completion` / `complete` key — THE COMPLETION GATE DID NOT RUN. No
--     shim-mock test pass, no assumption-checker replay pass, no engine-run
--     audit block is claimed by this corpus;
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
-- F6 IDENTITY SYMBOLICITY — RED, NOT REPAIRED  (the principal is CONCRETE on
-- every signed-in arm of this corpus)
-- ============================================================================
-- `identity_symbolicity_audit` on this corpus (12,997 dumps): RED.
--
--   owner_id       symbolic 11,436   literal      0
--   recipient_id   symbolic  6,599   literal  7,030   <-- RED
--   user_id        symbolic 27,008   literal 20,696   <-- RED
--
--   e.g.  SELECT "notifications".* … WHERE "notifications"."recipient_id" = 1 …
--
-- The signed-in harness built during the R1 repair drives the action with a
-- CONCRETELY instantiated principal (fixture user 9 / person 1) rather than a
-- symbolic one; a per-scenario census confirms every `auth_*` scenario
-- (auth_self_html, auth_other_html, auth_json, auth_mobile) carries literal
-- principal binds. The anon arms and the owner_id family are unaffected
-- (owner_id: 0 literal).
--
-- WHAT THIS MEANS FOR THE FILE BELOW: wherever the fold could not see a
-- symbolic principal it emits the LITERAL id instead of `_MY_UID`. Those views
-- are therefore stated FOR ONE USER, not for an arbitrary principal — they are
-- correct statements the endpoint issues, but they under-generalise, and a
-- consumer must NOT read `= 1` as a policy constant. Read every literal
-- principal id below as `_MY_UID`.
--
-- This is a genuine open defect, dispositioned here rather than repaired: the
-- repair is a re-run of the signed-in scenarios with a symbolic principal
-- (DISCIPLINE §15's "symbolic principal" clause), which regenerates the
-- corpus and is out of scope for this extraction (user decision: extract and
-- set the endpoint aside, 2026-09-07).
--
-- ============================================================================
-- CORPUS TERMINALS
-- ============================================================================
-- dump_errors on this corpus: ActionView::Template::Error 4,784 (the two
-- template walls above, plus the app's own render terminals) and
-- Warden::Unauthenticated => 401 6 (the NM-1 boundary-stage arm, adjudicated
-- in ADVERSARY_REPORT.md R2 §3). Statements recorded BEFORE each terminal are
-- in this file; the terminal itself is an application outcome, not a gap.
--
-- EXTRACTION PROVENANCE
--   corpus  : results3/people_show, 12997 dumps, 12997 runs loaded
--   queries : 341665 raw -> 75 distinct -> 16 subsumed -> 59 views
--   fold    : _experiment/variant_d AssocFoldingTransformer (mandatory —
--             the vanilla src/ fold drops 21 985 `(VAR == VAR(_))` /
--             `(VAR != VAR(_))` PCs on this corpus; measured by
--             skipped_pcs_audit both ways. 26 062 Contains/IndexOf PCs
--             remain undroppable by either fold — see FOLD FIDELITY)
--

SELECT 1 AS one FROM `likes`, `posts`, `share_visibilities`, `people`, `people` AS `people0` WHERE `likes`.`author_id` = `people0`.`id` AND `likes`.`target_type` = `Post` AND `likes`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`owner_id` = _MY_UID AND `people`.`closed_account` = FALSE;

SELECT 1 AS one FROM `likes`, `posts`, `share_visibilities`, `people`, `people` AS `people0` WHERE `likes`.`author_id` = `people0`.`id` AND `likes`.`target_type` = `Post` AND `likes`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`owner_id` = _MY_UID AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` <> 'mobile' AND `posts`.`public` = FALSE;

SELECT 1 AS one FROM `likes`, `posts`, `share_visibilities`, `people`, `people` AS `people0` WHERE `likes`.`author_id` = `people0`.`id` AND `likes`.`target_type` = `Post` AND `likes`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`owner_id` = _MY_UID AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` <> 'mobile' AND `posts`.`public` = TRUE;

SELECT 1 AS one FROM `likes`, `posts`, `share_visibilities`, `people`, `people` AS `people0` WHERE `likes`.`author_id` = `people0`.`id` AND `likes`.`target_type` = `Post` AND `likes`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`owner_id` = _MY_UID AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` = 'mobile' AND `posts`.`public` = FALSE;

SELECT 1 AS one FROM `likes`, `posts`, `share_visibilities`, `people`, `people` AS `people0` WHERE `likes`.`author_id` = `people0`.`id` AND `likes`.`target_type` = `Post` AND `likes`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`owner_id` = _MY_UID AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` = 'mobile' AND `posts`.`public` = TRUE;

SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people`, `people` AS `people0` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`author_id` = `people0`.`id` AND `posts`.`root_guid` = `posts0`.`guid` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts0`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts0`.`public` = 't') AND `posts0`.`created_at` < _NOW AND `posts0`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`owner_id` = _MY_UID AND `people`.`closed_account` = FALSE;

SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people`, `people` AS `people0` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`author_id` = `people0`.`id` AND `posts`.`root_guid` = `posts0`.`guid` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts0`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts0`.`public` = 't') AND `posts0`.`created_at` < _NOW AND `posts0`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`owner_id` = _MY_UID AND `people`.`closed_account` = FALSE AND `posts0`.`provider_display_name` <> 'mobile' AND `posts0`.`public` = TRUE;

SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people`, `people` AS `people0` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`author_id` = `people0`.`id` AND `posts`.`root_guid` = `posts0`.`guid` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts0`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts0`.`public` = 't') AND `posts0`.`created_at` < _NOW AND `posts0`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`owner_id` = _MY_UID AND `people`.`closed_account` = FALSE AND `posts0`.`provider_display_name` = 'mobile' AND `posts0`.`public` = TRUE;

SELECT `profiles`.* FROM `profiles`, `people`, `posts`, `share_visibilities`, `people` AS `people0` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `posts`.`author_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE;

SELECT COUNT(*) FROM `comments`, `posts`, `share_visibilities`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE;

SELECT COUNT(*) FROM `comments`, `posts`, `share_visibilities`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` <> 'mobile' AND `posts`.`public` = FALSE;

SELECT COUNT(*) FROM `comments`, `posts`, `share_visibilities`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` <> 'mobile' AND `posts`.`public` = TRUE;

SELECT COUNT(*) FROM `comments`, `posts`, `share_visibilities`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` = 'mobile' AND `posts`.`public` = FALSE;

SELECT COUNT(*) FROM `comments`, `posts`, `share_visibilities`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` = 'mobile' AND `posts`.`public` = TRUE;

SELECT COUNT(*) FROM `likes`, `posts`, `share_visibilities`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE;

SELECT COUNT(*) FROM `likes`, `posts`, `share_visibilities`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` <> 'mobile' AND `posts`.`public` = FALSE;

SELECT COUNT(*) FROM `likes`, `posts`, `share_visibilities`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` <> 'mobile' AND `posts`.`public` = TRUE;

SELECT COUNT(*) FROM `likes`, `posts`, `share_visibilities`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` = 'mobile' AND `posts`.`public` = FALSE;

SELECT COUNT(*) FROM `likes`, `posts`, `share_visibilities`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`provider_display_name` = 'mobile' AND `posts`.`public` = TRUE;

SELECT COUNT(*) FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`root_guid` = `posts0`.`guid` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts0`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts0`.`public` = 't') AND `posts0`.`created_at` < _NOW AND `posts0`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE;

SELECT COUNT(*) FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`root_guid` = `posts0`.`guid` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts0`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts0`.`public` = 't') AND `posts0`.`created_at` < _NOW AND `posts0`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts0`.`provider_display_name` <> 'mobile' AND `posts0`.`public` = TRUE;

SELECT COUNT(*) FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`root_guid` = `posts0`.`guid` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts0`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts0`.`public` = 't') AND `posts0`.`created_at` < _NOW AND `posts0`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts0`.`provider_display_name` = 'mobile' AND `posts0`.`public` = TRUE;

SELECT `aspects`.* FROM `aspects`, `aspect_memberships`, `contacts`, `people` WHERE `aspects`.`id` = `aspect_memberships`.`aspect_id` AND `aspect_memberships`.`contact_id` = `contacts`.`id` AND `contacts`.`user_id` = 1 AND `contacts`.`person_id` = `people`.`id` AND `people`.`closed_account` = FALSE;

SELECT `people`.* FROM `people`, `posts`, `share_visibilities`, `people` AS `people0` WHERE `people`.`id` = `posts`.`author_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE;

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `profiles`, `people` WHERE `taggings`.`taggable_id` = `profiles`.`id` AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags' AND `profiles`.`person_id` = `people`.`id`;

SELECT COUNT(*) FROM `photos` LEFT OUTER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `photos`.`id` AND `share_visibilities`.`shareable_type` = 'Photo', `people` WHERE `photos`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `photos`.`public` = 't') AND `photos`.`created_at` < _NOW AND `photos`.`pending` = FALSE AND `people`.`closed_account` = FALSE;

SELECT DISTINCT `posts`.* FROM `posts` LEFT OUTER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `people` WHERE `posts`.`author_id` = `people`.`id` AND (`share_visibilities`.`user_id` = 1 OR `posts`.`public` = 't') AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE;

SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts`, `people` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id` AND `contacts`.`user_id` = 1 AND `contacts`.`person_id` = `people`.`id` AND `people`.`closed_account` = FALSE;

SELECT `people`.* FROM `people`, `contacts`, `people` AS `people0` WHERE `people`.`id` = `contacts`.`person_id` AND `contacts`.`user_id` = 1 AND `contacts`.`person_id` = `people0`.`id` AND `people0`.`closed_account` = FALSE;

SELECT `profiles`.* FROM `profiles`, `people`, `posts` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `posts`.`author_id` AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

SELECT 1 AS one FROM `roles`, `people` WHERE `roles`.`person_id` = `people`.`id` AND `roles`.`name` = `admin` AND `people`.`owner_id` = _MY_UID;

SELECT 1 AS one FROM `roles`, `people` WHERE `roles`.`person_id` = `people`.`id` AND `roles`.`name` IN ('moderator', 'admin') AND `people`.`owner_id` = _MY_UID;

SELECT COUNT(*) FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

SELECT COUNT(*) FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

SELECT COUNT(*) FROM `photos`, `people` WHERE `photos`.`author_id` = `people`.`id` AND `photos`.`created_at` < _NOW AND `photos`.`pending` = FALSE AND `people`.`owner_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT COUNT(*) FROM `photos`, `people` WHERE `photos`.`author_id` = `people`.`id` AND `photos`.`created_at` < _NOW AND `photos`.`pending` = FALSE AND `people`.`owner_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id;

SELECT COUNT(*) FROM `photos`, `people` WHERE `photos`.`author_id` = `people`.`id` AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE;

SELECT COUNT(*) FROM `posts`, `posts` AS `posts0` WHERE `posts`.`type` IN ('Reshare') AND `posts`.`root_guid` = `posts0`.`guid` AND `posts0`.`public` = TRUE AND `posts0`.`created_at` < _NOW AND `posts0`.`type` IN ('StatusMessage', 'Reshare');

SELECT SUM(`conversation_visibilities`.`unread`) FROM `conversation_visibilities`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `blocks`.* FROM `blocks`, `people` WHERE `blocks`.`person_id` = `people`.`id` AND `blocks`.`user_id` = 1 AND `people`.`closed_account` = FALSE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `blocks`.* FROM `blocks`, `people` WHERE `blocks`.`person_id` = `people`.`id` AND `blocks`.`user_id` = 1 AND `people`.`owner_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id;

SELECT `contacts`.* FROM `contacts`, `people` WHERE `contacts`.`user_id` = 1 AND `contacts`.`person_id` = `people`.`id` AND `people`.`closed_account` = FALSE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `contacts`.* FROM `contacts`, `people` WHERE `contacts`.`user_id` = 1 AND `contacts`.`person_id` = `people`.`id` AND `people`.`owner_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id;

SELECT `notifications`.* FROM `notifications`, `people` WHERE `notifications`.`recipient_id` = 1 AND `notifications`.`target_type` = 'Person' AND `notifications`.`target_id` = `people`.`id` AND `notifications`.`unread` = TRUE AND `people`.`closed_account` = FALSE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `notifications`.* FROM `notifications`, `people` WHERE `notifications`.`recipient_id` = 1 AND `notifications`.`target_type` = 'Person' AND `notifications`.`target_id` = `people`.`id` AND `notifications`.`unread` = TRUE AND `people`.`owner_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id;

SELECT `people`.* FROM `people`, `posts` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

SELECT `profiles`.* FROM `profiles`, `people` WHERE `profiles`.`person_id` = `people`.`id`;

SELECT `tags`.* FROM `tags` INNER JOIN `tag_followings` ON `tags`.`id` = `tag_followings`.`tag_id` WHERE `tag_followings`.`user_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_POSTS_GUID
SELECT 1 AS one FROM `posts` WHERE `posts`.`guid` = _SYM_POSTS_GUID;

SELECT COUNT(*) FROM `contacts` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`receiving` = TRUE;

SELECT COUNT(*) FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`unread` = TRUE;

SELECT COUNT(*) FROM `reports` WHERE `reports`.`reviewed` = FALSE;

SELECT `aspects`.* FROM `aspects` WHERE `aspects`.`user_id` = _MY_UID;

SELECT `people`.* FROM `people`;

SELECT `people`.* FROM `people` WHERE `people`.`owner_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people` WHERE `people`.`owner_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_id
SELECT `people`.* FROM `people` WHERE `people`.`owner_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_id;

SELECT `posts`.* FROM `posts` WHERE `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

SELECT `services`.* FROM `services` WHERE `services`.`user_id` = _MY_UID;
