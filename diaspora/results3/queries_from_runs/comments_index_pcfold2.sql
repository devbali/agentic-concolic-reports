-- comments_index — CommentsController#index  (GET /posts/:post_id/comments)
--
-- CANONICAL HEADER. This text is maintained at
-- reports/diaspora/results3/comments_index/POLICY_HEADER.txt and MUST be
-- re-applied to the top of this file by every extraction. Under the M-17
-- resolution below, the declaration IS the safeguard: a policy file that
-- simply stops at the wall is indistinguishable from one that covers
-- everything, so the exclusion may not live only in a report.
--
-- ASSUMPTION BASIS (2026-09-13). This endpoint's completeness claim rests on
-- co-evaluation (DISCIPLINE §16), foreclosure (§16b) and its 4 182 DECLARED
-- independences. It relies on CONFINEMENT (§16c) for NOTHING: the coverage
-- pass runs with `CONFINEMENT=0`, no footprint is measured, no confined pair
-- is inferred, and the engine declares no `ConfinementAssumption` for the
-- gate to test. The endpoint is `COMPLETE=True; NODES=84; MISSING=0;
-- BLOCKING=0` and `OVERALL_COMPLETE=True` under that strictly weaker set;
-- confinement was worth 5 demand sets out of 85 and its 46 inferred licences
-- were refuted by the gate 15 times, so it was withdrawn entirely rather than
-- repaired. Record: `_RESTORED_20260913.md` §4;
-- rationale: `docs/CONFINEMENT_PRECISION_20260913.md` §5.2, §6.
--
-- SCOPE (DISCIPLINE §15): the entrypoint is the POST-AUTH action with a
-- SYMBOLIC principal. The authentication stages run ABOVE the entrypoint and
-- are not part of this file; the endpoint's complete policy is THIS FILE
-- UNION §2 of results3/_auth_boundary/BOUNDARY_POLICY.md. On this controller
-- `authenticate_user!` is `except: :index`, so the principal is fetched
-- lazily by `set_locale`/`user_signed_in?` rather than by the Devise filter —
-- the same statements and hooks, so the boundary artifact applies unchanged —
-- and an ANONYMOUS request touches no authentication stage at all.
--
-- ============================================================================
-- COMPLETENESS OF THIS POLICY, AND THE ONE PLACE IT STOPS  (M-17, cycle 12)
-- ============================================================================
-- This file describes the endpoint's data access on EVERY PATH A REAL REQUEST
-- IN THIS ENVIRONMENT CAN TAKE.
--
-- There is exactly one place where the description ends before the
-- application does. Rendering a person's name calls `Person#name`
-- (app/models/person.rb:249), which on a person with no `profiles` row calls
-- `Person#fix_profile` (:373), which calls
-- `DiasporaFederation::Discovery::Discovery#fetch_and_save`. That method has
-- two arms:
--
--   * the RAISING arm — modelled here in full. Reached by a
--     `people.diaspora_handle` whose domain is not a legal URI host: Faraday
--     parses the URL with `URI.parse` before the adapter, raises
--     `URI::InvalidURIError` in pure Ruby, and `fetch_and_save` converts it to
--     `DiscoveryError`. It issues no SQL before raising. The reads that
--     precede it and the resulting terminal ARE in this file.
--
--   * the SUCCESS arm — UNREACHABLE in this environment, and therefore
--     DECLARED UNMODELLED, NOT SHOWN ABSENT. Returning normally requires two
--     live HTTP fetches (`discovery.rb:73` `webfinger`, `discovery.rb:84`
--     `hcard`, both `HttpClient.get`; the gem class has no local-pod,
--     cached-hcard or caller-supplied-entity short circuit). This
--     JRuby/typhoeus/JFFI stack SIGSEGVs on any parseable URL — measured, unit
--     exit status 134, in
--     reports/diaspora/results3/comments_index/_c12/probe_parseable.log (and
--     _c11/probe_parseable.log), against exit 0 for the URI-hostile handle in
--     the matching probe_uri_hostile.log.
--
-- SO: THE ABSENCE OF DISCOVERY-SUCCESS STATEMENTS BELOW IS A DECLARED GAP, NOT
-- A FINDING THAT THE PATH READS NOTHING. If that arm ever becomes reachable
-- (a working HTTP adapter), the policy GAINS, from the application's own
-- `:save_person_after_webfinger` callback
-- (config/initializers/diaspora_federation.rb:59-77):
--
--     writes : INSERT INTO people, INSERT INTO profiles, UPDATE profiles
--     reads  : pods (by host, and by id), tags JOIN taggings,
--              people by diaspora_handle, people by guid (uniqueness probes),
--              and a `people.diaspora_handle` PLUCK
--
-- measured by this batch, with no network, by running the app's own callback
-- directly:
--     evidence : reports/diaspora/results3/comments_index/_c12/_discovery_gap_evidence.json
--     probe    : reports/diaspora/results3/comments_index/_c12/discovery_gap_probe.rb
--     result   : new-person branch 17 statements, 13 of them data access;
--                existing-person branch did NOT complete under this batch's
--                fixture (ActiveRecord::RecordInvalid: "Specify an owner or a
--                pod, not both" — the person.rb owner_xor_pod validation)
--                after issuing the people read, the profiles read, INSERT INTO
--                profiles, the tags JOIN taggings read and both uniqueness
--                probes, then ROLLBACK.
--
-- Those statements are NOT asserted in this file, because no real run of this
-- endpoint in this environment can issue them and this project verifies every
-- note against a real endpoint statement. They are recorded here so a consumer
-- knows the boundary of what is claimed.
-- ============================================================================

--
-- Extracted from 26528 dumps, 26528 runs loaded, 413594 raw queries,
--   248 distinct (query, conditions) pairs, 57 distinct statements,
--   3 subsumed, 54 views.  subsume_ran=None
--   PC predicates: 844 rendered, 50 kept — a predicate the corpus
--   shows this query running BOTH WITH AND WITHOUT does not constrain it and is dropped.
--   fold: src/queries_from_runs (no patches)
--   two_query_cap=2; exclude_rejected=True (0 runs dropped: the application REFUSED those requests, so their reads were not granted and are not in this policy
--   CAVEAT: this policy describes the queries of requests that were
--   SERVED. A read performed on a path the application then rejected
--   is excluded, although the query WAS issued and the database DID
--   return the row — a reader concerned with data exposure rather
--   than with granted access should know it is not covered here.

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users`, `mentions` AS `mentions0`, `people` AS `people1` WHERE `people`.`id` IN (`mentions`.`person_id`, `mentions0`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `mentions0`.`mentions_container_id` = `comments`.`id` AND `mentions0`.`mentions_container_type` = 'Comment' AND `people1`.`id` = `people1`.`id` AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users`, `people` AS `people1`, `people` AS `people2` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people1`.`id` IN (`people1`.`id`, `people2`.`id`) AND `people2`.`id` IN (`people1`.`id`, `people2`.`id`) AND `people0`.`id` = `people1`.`id` AND `people1`.`id` = `people0`.`id` AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users`, `people` AS `people1`, `people` AS `people2` WHERE `people`.`id` IN (`mentions`.`person_id`, `people1`.`id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people1`.`id` IN (`mentions`.`person_id`, `people1`.`id`) AND `people2`.`id` = `people2`.`id` AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `people` AS `people0`, `mentions`, `comments`, `posts`, `people` AS `people1`, `users`, `people` AS `people2` WHERE `people`.`id` IN (`people0`.`id`, `mentions`.`person_id`) AND `people0`.`id` IN (`people0`.`id`, `mentions`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people1`.`id` AND `people1`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people2`.`id` = `people2`.`id` AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users`, `people` AS `people1` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` IN (`mentions`.`person_id`, `people`.`id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people1`.`id` = `people1`.`id` AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users`, `people` AS `people1` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` IN (`people`.`id`, `mentions`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people1`.`id` = `people1`.`id` AND `posts`.`type` <> 'Photo';

SELECT `mentions`.* FROM `mentions`, `comments`, `posts`, `people`, `users`, `people` AS `people0`, `people` AS `people1` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` IN (`people0`.`id`, `people1`.`id`) AND `people1`.`id` IN (`people0`.`id`, `people1`.`id`) AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users`, `mentions` AS `mentions0` WHERE `people`.`id` IN (`mentions`.`person_id`, `mentions0`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `mentions0`.`mentions_container_id` = `comments`.`id` AND `mentions0`.`mentions_container_type` = 'Comment' AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users`, `people` AS `people1` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people1`.`id` = `people1`.`id` AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users`, `people` AS `people1` WHERE `people`.`id` IN (`mentions`.`person_id`, `people1`.`id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people1`.`id` IN (`mentions`.`person_id`, `people1`.`id`) AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users`, `mentions` AS `mentions0` WHERE `people`.`id` IN (`mentions`.`person_id`, `mentions0`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `mentions0`.`mentions_container_id` = `comments`.`id` AND `mentions0`.`mentions_container_type` = 'Comment' AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users`, `people` AS `people0` WHERE `people`.`id` IN (`mentions`.`person_id`, `people0`.`id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` IN (`mentions`.`person_id`, `people0`.`id`) AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `people` AS `people0`, `mentions`, `comments`, `posts`, `people` AS `people1`, `users` WHERE `people`.`id` IN (`people0`.`id`, `mentions`.`person_id`) AND `people0`.`id` IN (`people0`.`id`, `mentions`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people1`.`id` AND `people1`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `people` AS `people0`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` IN (`people0`.`id`, `mentions`.`person_id`) AND `people0`.`id` IN (`people0`.`id`, `mentions`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` IN (`mentions`.`person_id`, `people`.`id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` IN (`people`.`id`, `mentions`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` IN (`mentions`.`person_id`, `people`.`id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` IN (`people`.`id`, `mentions`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `comments`.* FROM `comments`, `posts`, `people`, `users`, `people` AS `people0`, `people` AS `people1` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` IN (`people0`.`id`, `people1`.`id`) AND `people1`.`id` IN (`people0`.`id`, `people1`.`id`) AND `posts`.`type` <> 'Photo';

SELECT `mentions`.* FROM `mentions`, `comments`, `posts`, `people`, `users`, `people` AS `people0` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` = `people0`.`id` AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `people` AS `people0`, `users` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `comments`.* FROM `comments`, `posts`, `people`, `users`, `people` AS `people0` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` = `people0`.`id` AND `posts`.`type` <> 'Photo';

SELECT `mentions`.* FROM `mentions`, `comments`, `posts`, `people`, `users` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `mentions`.* FROM `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `mentions` AS `mentions0` WHERE `people`.`id` IN (`mentions`.`person_id`, `mentions0`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `mentions0`.`mentions_container_id` = `comments`.`id` AND `mentions0`.`mentions_container_type` = 'Comment' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` IN (`mentions`.`person_id`, `people0`.`id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `people0`.`id` IN (`mentions`.`person_id`, `people0`.`id`) AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `people` AS `people0`, `mentions`, `comments`, `posts` WHERE `people`.`id` IN (`people0`.`id`, `mentions`.`person_id`) AND `people0`.`id` IN (`people0`.`id`, `mentions`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `people` AS `people0`, `people` AS `people1`, `people` AS `people2`, `users` WHERE `people`.`id` IN (`people0`.`id`, `people1`.`id`) AND `people0`.`id` IN (`people0`.`id`, `people1`.`id`) AND `people1`.`id` IN (`people0`.`id`, `people1`.`id`) AND `people2`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `people`, `users`, `people` AS `people0`, `people` AS `people1` WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` IN (`people0`.`id`, `people1`.`id`) AND `people1`.`id` IN (`people0`.`id`, `people1`.`id`);

SELECT `profiles`.* FROM `profiles`, `people`, `mentions`, `comments`, `posts` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` IN (`mentions`.`person_id`, `people`.`id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `people`, `mentions`, `comments`, `posts` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` IN (`people`.`id`, `mentions`.`person_id`) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `people`, `people` AS `people0`, `people` AS `people1`, `users` WHERE `profiles`.`person_id` IN (`people`.`id`, `people0`.`id`) AND `people`.`id` IN (`people`.`id`, `people0`.`id`) AND `people0`.`id` IN (`people`.`id`, `people0`.`id`) AND `people1`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `users`, `people` AS `people0`, `people` AS `people1` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` IN (`people0`.`id`, `people1`.`id`) AND `people1`.`id` IN (`people0`.`id`, `people1`.`id`) AND `users`.`language` = 'pl';

SELECT `comments`.* FROM `comments`, `posts`, `people`, `users` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `comments`.* FROM `comments`, `posts`, `share_visibilities`, `users` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `people` AS `people0`, `people` AS `people1`, `users` WHERE `people`.`id` = `people0`.`id` AND `people0`.`id` = `people0`.`id` AND `people1`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `people`, `users`, `people` AS `people0` WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` = `people0`.`id`;

SELECT `profiles`.* FROM `profiles`, `people`, `people` AS `people0`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `people`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `users`, `people` AS `people0` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` = `people0`.`id` AND `users`.`language` = 'pl';

SELECT `mentions`.* FROM `mentions`, `comments`, `posts` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `people` AS `people0`, `people` AS `people1` WHERE `people`.`id` IN (`people0`.`id`, `people1`.`id`) AND `people0`.`id` IN (`people0`.`id`, `people1`.`id`) AND `people1`.`id` IN (`people0`.`id`, `people1`.`id`);

SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `users` WHERE `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `people`, `users` WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `people` AS `people0` WHERE `profiles`.`person_id` IN (`people`.`id`, `people0`.`id`) AND `people`.`id` IN (`people`.`id`, `people0`.`id`) AND `people0`.`id` IN (`people`.`id`, `people0`.`id`);

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `users`.`language` = 'pl';

SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `people` AS `people0` WHERE `people`.`id` = `people0`.`id` AND `people0`.`id` = `people0`.`id`;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `people`.`id`;

-- NOTE: flag unscoped
SELECT 1 AS one FROM `posts`;

SELECT `posts`.* FROM `posts`;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;
