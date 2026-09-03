-- our generated queries NOT answerable from the reference set
-- 6 queries

SELECT `participations`.* FROM `participations`, `people`, `posts`, `share_visibilities` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`text` = '';

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`public` = TRUE AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`public` = TRUE AND `posts`.`text` = '';

SELECT `posts`.* FROM `posts`;
