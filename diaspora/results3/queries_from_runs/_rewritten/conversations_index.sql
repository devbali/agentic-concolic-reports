-- conversations_index — ConversationsController#index
-- Extracted from the concolic corpus (results3/conversations_index):
--   18623 dumps, 18623 runs loaded, 383090 raw queries,
--   95 distinct, 37 subsumed, 58 views.
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

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people`, `people` AS `people0`, `messages`, `conversation_visibilities`, `conversations` WHERE `people`.`id` = `people0`.`id` AND `people0`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people`, `people` AS `people0`, `messages`, `conversation_visibilities`, `conversations` WHERE `people`.`id` = `people0`.`id` AND `people0`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` > 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `people`, `conversation_visibilities`, `conversation_visibilities` AS `conversation_visibilities0`, `conversations` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `conversation_visibilities`.`person_id` AND `conversation_visibilities`.`conversation_id` = `conversation_visibilities0`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversation_visibilities0`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `people`, `conversation_visibilities`, `conversation_visibilities` AS `conversation_visibilities0`, `conversations` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `conversation_visibilities`.`person_id` AND `conversation_visibilities`.`conversation_id` = `conversation_visibilities0`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversation_visibilities0`.`unread` > 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `people`, `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `conversation_visibilities`.`person_id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversations`.`subject` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `people`, `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `conversation_visibilities`.`person_id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversations`.`subject` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `people`, `messages`, `conversation_visibilities`, `conversations` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `people`, `messages`, `conversation_visibilities`, `conversations` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` > 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT COUNT(*) FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversation_visibilities` AS `conversation_visibilities0`, `conversations` WHERE `conversation_visibilities`.`conversation_id` = `conversation_visibilities0`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversation_visibilities0`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT COUNT(*) FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversation_visibilities` AS `conversation_visibilities0`, `conversations` WHERE `conversation_visibilities`.`conversation_id` = `conversation_visibilities0`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversation_visibilities0`.`unread` > 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT COUNT(*) FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = _MY_UID;

SELECT `contacts`.`id`, `profiles`.`first_name`, `profiles`.`last_name`, `people`.`diaspora_handle` FROM `contacts` INNER JOIN `people` ON `people`.`id` = `contacts`.`person_id` INNER JOIN `profiles` ON `profiles`.`person_id` = `people`.`id`, `users` WHERE `contacts`.`user_id` = `users`.`id` AND `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE AND `users`.`id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversation_visibilities` AS `conversation_visibilities0`, `conversations` WHERE `conversation_visibilities`.`conversation_id` = `conversation_visibilities0`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversation_visibilities0`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversation_visibilities` AS `conversation_visibilities0`, `conversations` WHERE `conversation_visibilities`.`conversation_id` = `conversation_visibilities0`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversation_visibilities0`.`unread` > 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversations`.`subject` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people` INNER JOIN `conversation_visibilities` ON `people`.`id` = `conversation_visibilities`.`person_id`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversations`.`subject` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people`, `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0` WHERE `people`.`id` = `conversation_visibilities`.`person_id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` <> 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people`, `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0` WHERE `people`.`id` = `conversation_visibilities`.`person_id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` = 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people`, `messages`, `conversation_visibilities`, `conversations` WHERE `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people`, `messages`, `conversation_visibilities`, `conversations` WHERE `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` > 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people`, `messages`, `conversations`, `conversation_visibilities` WHERE `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversations`.`subject` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people`, `messages`, `conversations`, `conversation_visibilities` WHERE `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversations`.`subject` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `messages`, `conversation_visibilities`, `conversations` WHERE `profiles`.`person_id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `messages`, `conversation_visibilities`, `conversations` WHERE `profiles`.`person_id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` > 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `messages`, `conversations`, `conversation_visibilities` WHERE `profiles`.`person_id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversations`.`subject` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `messages`, `conversations`, `conversation_visibilities` WHERE `profiles`.`person_id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversations`.`subject` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT COUNT(*) FROM `messages`, `conversation_visibilities`, `conversations` WHERE `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT COUNT(*) FROM `messages`, `conversation_visibilities`, `conversations` WHERE `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` > 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `messages`.* FROM `messages`, `conversation_visibilities`, `conversations` WHERE `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `messages`.* FROM `messages`, `conversation_visibilities`, `conversations` WHERE `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` > 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `messages`.* FROM `messages`, `conversations`, `conversation_visibilities` WHERE `messages`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `messages`.`author_id` FROM `messages`, `conversation_visibilities`, `conversations` WHERE `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` <= 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `messages`.`author_id` FROM `messages`, `conversation_visibilities`, `conversations` WHERE `messages`.`conversation_id` = `conversation_visibilities`.`conversation_id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = _MY_UID AND `conversation_visibilities`.`unread` > 0;

SELECT `tags`.* FROM `tags` INNER JOIN `tag_followings` ON `tags`.`id` = `tag_followings`.`tag_id`, `users` WHERE `tag_followings`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT 1 AS one FROM `contacts`, `users` WHERE `contacts`.`user_id` = `users`.`id` AND `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE AND `users`.`id` = _MY_UID;

SELECT COUNT(*) FROM `contacts`, `users` WHERE `contacts`.`user_id` = `users`.`id` AND `contacts`.`receiving` = TRUE AND `users`.`id` = _MY_UID;

SELECT COUNT(*) FROM `notifications`, `users` WHERE `notifications`.`recipient_id` = `users`.`id` AND `notifications`.`unread` = TRUE AND `users`.`id` = _MY_UID;

SELECT `aspects`.* FROM `aspects`, `users` WHERE `aspects`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `conversation_visibilities`.`id` AS t0_r0, `conversation_visibilities`.`conversation_id` AS t0_r1, `conversation_visibilities`.`person_id` AS t0_r2, `conversation_visibilities`.`unread` AS t0_r3, `conversation_visibilities`.`created_at` AS t0_r4, `conversation_visibilities`.`updated_at` AS t0_r5, `conversations`.`id` AS t1_r0, `conversations`.`subject` AS t1_r1, `conversations`.`guid` AS t1_r2, `conversations`.`author_id` AS t1_r3, `conversations`.`created_at` AS t1_r4, `conversations`.`updated_at` AS t1_r5 FROM `conversation_visibilities` LEFT OUTER JOIN `conversations` ON `conversations`.`id` = `conversation_visibilities`.`conversation_id` WHERE `conversation_visibilities`.`person_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `conversations`.* FROM `conversations` INNER JOIN `conversation_visibilities` ON `conversation_visibilities`.`conversation_id` = `conversations`.`id` WHERE `conversation_visibilities`.`person_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people`, `people` AS `people0` WHERE `people`.`id` = `people0`.`id` AND `people0`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles`, `people` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = _MY_UID;

SELECT `services`.* FROM `services`, `users` WHERE `services`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT 1 AS one FROM `posts`;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT 1 AS one FROM `roles` WHERE `roles`.`name` IN ('moderator', 'admin') AND `roles`.`person_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT 1 AS one FROM `roles` WHERE `roles`.`person_id` = _MY_UID AND `roles`.`name` = 'admin';

SELECT COUNT(*) FROM `reports` WHERE `reports`.`reviewed` = FALSE;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT SUM(`conversation_visibilities`.`unread`) FROM `conversation_visibilities` WHERE `conversation_visibilities`.`person_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people` WHERE `people`.`id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people` WHERE `people`.`id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people` WHERE `people`.`id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `people`.* FROM `people` WHERE `people`.`id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _MY_UID
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _MY_UID;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;
