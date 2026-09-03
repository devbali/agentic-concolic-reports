-- reference queries NOT answerable from our generated query set
-- 9 queries

SELECT 1 AS `one` FROM `people`,     `roles` WHERE `roles`.`person_id` = `people`.`id` AND `roles`.`name` = 'admin' AND `people`.`owner_id` = _MY_UID;

SELECT 1 AS `one` FROM `people`,     `roles` WHERE `roles`.`name` IN ('admin', 'moderator') AND `roles`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `profiles`.`id`, `profiles`.`diaspora_handle`, `profiles`.`first_name`, `profiles`.`last_name`, `profiles`.`image_url`, `profiles`.`image_url_small`, `profiles`.`image_url_medium`, `profiles`.`searchable`, `profiles`.`person_id`, `profiles`.`created_at`, `profiles`.`updated_at`, `profiles`.`full_name`, `profiles`.`nsfw`, `profiles`.`public_details` FROM `people`,     `profiles` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT * FROM `aspects` WHERE `user_id` = _MY_UID;

SELECT * FROM `contacts` WHERE `user_id` = _MY_UID AND `receiving` = TRUE;

SELECT * FROM `people` WHERE `owner_id` = _MY_UID;

SELECT * FROM `services` WHERE `user_id` = _MY_UID;

SELECT * FROM `notifications` WHERE `recipient_id` = _MY_UID AND `unread` = TRUE;

SELECT * FROM `users` WHERE `id` = _MY_UID;
