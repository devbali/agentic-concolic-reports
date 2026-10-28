-- conversations_index — ConversationsController#index
--
-- SCOPE (Bali decision, 2026-08-31; DISCIPLINE §15): this endpoint's
-- entrypoint is the POST-AUTH action with a SYMBOLIC principal. The
-- authentication stages (principal SELECT by session/token, and the
-- trackable / lastseenable / rememberable / lockable decisions and
-- writes) run ABOVE the entrypoint and are NOT part of this file.
--
-- THE ENDPOINT'S COMPLETE POLICY IS THIS FILE **UNION** THE SHARED
-- AUTH-BOUNDARY POLICY:
--   reports/diaspora/results3/_auth_boundary/BOUNDARY_POLICY.md
-- Consumers that need the whole request (boundary + action) must take
-- the union; this file alone covers the action only.
-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_devise_user_first_1_person_id

--
-- Extracted from 18623 dumps, 18623 runs loaded, 404127 raw queries,
--   129 distinct (query, conditions) pairs, 56 distinct statements,
--   18 subsumed, 38 views.  subsume_ran=None
--   PC predicates: 119 rendered, 1 kept — a predicate the corpus
--   shows this query running BOTH WITH AND WITHOUT does not constrain it and is dropped.
--   fold: src/queries_from_runs (no patches)

SELECT `people`.* FROM `people`, `people` AS `people0`, `messages`, `conversation_visibilities`, `conversations`, `people` AS `people1`, `users` WHERE `people`.`id` = `people0`.`id` AND `people0`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people1`.`id` AND `people1`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `conversation_visibilities`, `conversation_visibilities` AS `conversation_visibilities0`, `conversations`, `people` AS `people0`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `conversation_visibilities`.`person_id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `people0`.`id` <> `people`.`id`;

SELECT `profiles`.* FROM `profiles`, `people`, `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` AS `people0`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `conversation_visibilities`.`person_id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `messages`, `conversation_visibilities`, `conversations`, `people` AS `people0`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversation_visibilities` AS `conversation_visibilities0`, `conversations`, `people` AS `people0`, `users` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` AS `people0`, `users` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` AS `people0`, `users` WHERE `people`.`id` = `conversation_visibilities`.`person_id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = `people0`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `messages`, `conversation_visibilities`, `conversations`, `people` AS `people0`, `users` WHERE `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `people`.`id`, `conversation_visibilities`.`id`, `conversation_visibilities0`.`id`, `conversations`.`id`, `people0`.`id`, `users`.`id` FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversation_visibilities` AS `conversation_visibilities0`, `conversations`, `people` AS `people0`, `users` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `people`.`id`, `conversation_visibilities`.`id`, `conversations`.`id`, `conversation_visibilities0`.`id`, `people0`.`id`, `users`.`id` FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` AS `people0`, `users` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people`, `users` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `messages`.* FROM `messages`, `conversation_visibilities`, `conversations`, `people`, `users` WHERE `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `messages`.* FROM `messages`, `conversations`, `conversation_visibilities`, `people`, `users` WHERE `messages`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `messages`.`author_id` FROM `messages`, `conversation_visibilities`, `conversations`, `people`, `users` WHERE `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `messages`.`id`, `conversation_visibilities`.`id`, `conversations`.`id`, `people`.`id`, `users`.`id` FROM `messages`, `conversation_visibilities`, `conversations`, `people`, `users` WHERE `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `contacts`.`id`, `profiles`.`first_name`, `profiles`.`last_name`, `people`.`diaspora_handle` FROM `contacts` INNER JOIN `people` ON `people`.`id` = `contacts`.`person_id` INNER JOIN `profiles` ON `profiles`.`person_id` = `people`.`id`, `users` WHERE `contacts`.`user_id` = `users`.`id` AND `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE AND `users`.`id` = _MY_UID;

-- NOTE: flag outer-join-as-inner
SELECT `conversation_visibilities`.`id` AS t0_r0, `conversation_visibilities`.`conversation_id` AS t0_r1, `conversation_visibilities`.`person_id` AS t0_r2, `conversation_visibilities`.`unread` AS t0_r3, `conversation_visibilities`.`created_at` AS t0_r4, `conversation_visibilities`.`updated_at` AS t0_r5, `conversations`.`id` AS t1_r0, `conversations`.`subject` AS t1_r1, `conversations`.`guid` AS t1_r2, `conversations`.`author_id` AS t1_r3, `conversations`.`created_at` AS t1_r4, `conversations`.`updated_at` AS t1_r5 FROM `conversation_visibilities` INNER JOIN `conversations` ON `conversations`.`id` = `conversation_visibilities`.`conversation_id`, `people`, `users` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
-- NOTE: flag from-subquery-flattened
-- NOTE: flag outer-join-as-inner
SELECT `conversation_visibilities`.`id`, `conversations`.`id`, `people`.`id`, `users`.`id` FROM `conversation_visibilities` INNER JOIN `conversations` ON `conversations`.`id` = `conversation_visibilities`.`conversation_id`, `people`, `users` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `conversations`.* FROM `conversations` INNER JOIN `conversation_visibilities` ON `conversation_visibilities`.`conversation_id` = `conversations`.`id`, `people`, `users` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT 1 AS one FROM `roles`, `people`, `users` WHERE `roles`.`name` IN ('moderator', 'admin') AND `roles`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT 1 AS one FROM `roles`, `people`, `users` WHERE `roles`.`person_id` = `people`.`id` AND `roles`.`name` = 'admin' AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `conversation_visibilities`.`id`, `conversation_visibilities`.`unread` FROM `conversation_visibilities`, `people`, `users` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `people` AS `people0`, `people` AS `people1` WHERE `people`.`id` = `people0`.`id` AND `people0`.`id` = `people1`.`id` AND `people1`.`id` = `people1`.`id`;

SELECT `people`.* FROM `people`, `people` AS `people0`, `users` WHERE `people`.`id` = `people0`.`id` AND `people0`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `people` AS `people0` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `people0`.`id` AND `people0`.`id` = `people0`.`id`;

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `tags`.* FROM `tags` INNER JOIN `tag_followings` ON `tags`.`id` = `tag_followings`.`tag_id`, `users` WHERE `tag_followings`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT 1 AS one FROM `contacts`, `users` WHERE `contacts`.`user_id` = `users`.`id` AND `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE AND `users`.`id` = _MY_UID;

SELECT `aspects`.* FROM `aspects`, `users` WHERE `aspects`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `contacts`.`id`, `users`.`id` FROM `contacts`, `users` WHERE `contacts`.`user_id` = `users`.`id` AND `contacts`.`receiving` = TRUE AND `users`.`id` = _MY_UID;

-- NOTE: flag aggregate-as-rows
SELECT `notifications`.`id`, `users`.`id` FROM `notifications`, `users` WHERE `notifications`.`recipient_id` = `users`.`id` AND `notifications`.`unread` = TRUE AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `people` AS `people0` WHERE `people`.`id` = `people0`.`id` AND `people0`.`id` = `people0`.`id`;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `people`.`id`;

SELECT `services`.* FROM `services`, `users` WHERE `services`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: flag unscoped
SELECT 1 AS one FROM `posts`;

-- NOTE: flag aggregate-as-rows
SELECT `reports`.`id` FROM `reports` WHERE `reports`.`reviewed` = FALSE;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;
