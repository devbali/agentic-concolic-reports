SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' WHERE `share_visibilities`.`user_id` = 1;

SELECT `posts`.* FROM `posts`, `people` WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `posts`.* FROM `posts` WHERE `posts`.`public` = TRUE;
