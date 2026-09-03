-- comments_index — CommentsController#index  (GET /posts/:post_id/comments)
--
-- CANONICAL HEADER. This text is maintained at
-- reports/diaspora/results3/comments_index/POLICY_HEADER.txt and MUST be
-- re-applied to the top of this file by every extraction. Under the M-17
-- resolution below, the declaration IS the safeguard: a policy file that
-- simply stops at the wall is indistinguishable from one that covers
-- everything, so the exclusion may not live only in a report.
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
-- EXTRACTION PROVENANCE
--   corpus  : results3/comments_index, 26528 dumps, 26528 runs loaded
--   queries : 413594 raw -> 79 distinct -> 0 subsumed -> 79 views
--   fold    : _experiment/variant_d assoc_fold INSTALLED (mandatory —
--             the vanilla src/ fold drops 73 461 `(VAR == VAR(_))` PCs
--             on this corpus; measured by skipped_pcs_audit both ways)
--

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id
SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id
SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id
SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id
SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

SELECT `mentions`.* FROM `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

SELECT `mentions`.* FROM `mentions`, `comments`, `posts`, `share_visibilities`, `users` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

SELECT `people`.* FROM `people`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

SELECT `people`.* FROM `people`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id
SELECT `people`.* FROM `people`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id
SELECT `people`.* FROM `people`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id
SELECT `people`.* FROM `people`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id
SELECT `people`.* FROM `people`, `comments`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

SELECT `profiles`.* FROM `profiles`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

SELECT `profiles`.* FROM `profiles`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id
SELECT `profiles`.* FROM `profiles`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id
SELECT `profiles`.* FROM `profiles`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id
SELECT `profiles`.* FROM `profiles`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id
SELECT `profiles`.* FROM `profiles`, `comments`, `posts`, `share_visibilities`, `users` WHERE `profiles`.`person_id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

SELECT `comments`.* FROM `comments`, `posts`, `share_visibilities`, `users` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

SELECT `comments`.* FROM `comments`, `posts`, `share_visibilities`, `users` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `posts`.`type` <> 'Photo' AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id
SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id
SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id
SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id
SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id
SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id
SELECT `mentions`.* FROM `mentions`, `comments`, `posts` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

SELECT `mentions`.* FROM `mentions`, `comments`, `posts` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `users` WHERE `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `users` WHERE `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id
SELECT `profiles`.* FROM `profiles`, `comments`, `posts` WHERE `profiles`.`person_id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

SELECT `profiles`.* FROM `profiles`, `comments`, `posts` WHERE `profiles`.`person_id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id
SELECT `profiles`.* FROM `profiles`, `comments`, `posts` WHERE `profiles`.`person_id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id
SELECT `profiles`.* FROM `profiles`, `comments`, `posts` WHERE `profiles`.`person_id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_records_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id
SELECT `profiles`.* FROM `profiles`, `comments`, `posts` WHERE `profiles`.`person_id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id
SELECT `profiles`.* FROM `profiles`, `comments`, `posts` WHERE `profiles`.`person_id` IN (`comments`.`author_id`, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_author_id) AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id AND `posts`.`type` <> 'Photo';

SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`type` <> 'Photo';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id, _SYM_RESULT_ActiveRecord__Relation_records_4_row2_person_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_4_row2_person_id) AND `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `users`.`language` <> 'pl' AND `users`.`language` <> 'xx';

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `users`.`language` = 'pl';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id
SELECT `profiles`.* FROM `profiles`, `mentions` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id
SELECT `profiles`.* FROM `profiles`, `mentions` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id, _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id
SELECT `profiles`.* FROM `profiles`, `mentions` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id) AND `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id, _SYM_RESULT_ActiveRecord__Relation_records_4_row2_person_id
SELECT `profiles`.* FROM `profiles`, `mentions` WHERE `profiles`.`person_id` IN (`mentions`.`person_id`, _SYM_RESULT_ActiveRecord__Relation_records_4_row2_person_id) AND `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

SELECT 1 AS one FROM `posts`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_records_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _SYM_RESULT_ActiveRecord__Relation_to_a_1_row2_id AND `mentions`.`mentions_container_type` = 'Comment';

SELECT `posts`.* FROM `posts`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`author_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id;

SELECT `posts`.* FROM `posts` WHERE `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Relation_records_1_row2_person_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Relation_records_2_row2_person_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Relation_records_4_row2_person_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Relation_records_4_row2_person_id;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;
