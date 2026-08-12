-- NOTE: query had no symbolic binds in the recorded run (all literals); verify against app code whether these should be symbolic vars
SELECT posts.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' WHERE `posts`.`id` = 'abc123' AND `share_visibilities`.`user_id` = 1;
SELECT `posts`.* FROM `posts` WHERE `posts`.`guid` = 'SYM_RESULT_Anonymous_diaspora_initialize_1_guid_v';
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = 1;
-- NOTE: query had no symbolic binds in the recorded run (all literals); verify against app code whether these should be symbolic vars
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = 'abc123' AND `posts`.`public` = TRUE;
-- NOTE: query had no symbolic binds in the recorded run (all literals); verify against app code whether these should be symbolic vars
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = 'abc123' AND `posts`.`author_id` = 1;
