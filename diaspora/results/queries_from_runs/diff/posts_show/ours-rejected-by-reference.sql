-- our generated queries NOT answerable from the reference set
-- 12 queries

SELECT `participations`.* FROM `participations`, `posts`, `people` WHERE `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`guid` <> '' AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `posts`, `people` WHERE `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`guid` <> '' AND `posts`.`text` = '';

SELECT `participations`.* FROM `participations`, `posts`, `people` WHERE `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`guid` = '' AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `posts`, `people` WHERE `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`guid` = '' AND `posts`.`text` = '';

SELECT `participations`.* FROM `participations`, `posts`, `share_visibilities` WHERE `participations`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '' AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `posts`, `share_visibilities` WHERE `participations`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '' AND `posts`.`text` = '';

SELECT `participations`.* FROM `participations`, `posts`, `share_visibilities` WHERE `participations`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '' AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `posts`, `share_visibilities` WHERE `participations`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '' AND `posts`.`text` = '';

SELECT `participations`.* FROM `participations`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `posts`.`public` = TRUE AND `posts`.`guid` <> '' AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `posts`.`public` = TRUE AND `posts`.`guid` <> '' AND `posts`.`text` = '';

SELECT `participations`.* FROM `participations`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `posts`.`public` = TRUE AND `posts`.`guid` = '' AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `posts`.`public` = TRUE AND `posts`.`guid` = '' AND `posts`.`text` = '';
