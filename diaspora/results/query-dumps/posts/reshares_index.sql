-- NOTE: query had no symbolic binds in the recorded run (all literals); verify against app code whether these should be symbolic vars
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = 1 AND `posts`.`public` = TRUE;
-- NOTE: query had no symbolic binds in the recorded run (all literals); verify against app code whether these should be symbolic vars
SELECT posts.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' WHERE `posts`.`id` = 1 AND `share_visibilities`.`user_id` = 1;
-- NOTE: query had no symbolic binds in the recorded run (all literals); verify against app code whether these should be symbolic vars
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = 1 AND `posts`.`author_id` = 1;
