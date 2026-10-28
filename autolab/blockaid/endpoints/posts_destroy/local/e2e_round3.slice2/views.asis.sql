SELECT `people`.* FROM `people`, `posts`, `people` AS `people0`, `users` WHERE `people`.`id` = `posts`.`author_id` AND `users`.`id` = _MY_UID AND `people0`.`owner_id` = `users`.`id` AND `posts`.`author_id` = `people0`.`id`;
SELECT `people`.* FROM `people`, `posts`, `share_visibilities`, `users` WHERE `people`.`id` = `posts`.`author_id` AND `users`.`id` = _MY_UID AND `share_visibilities`.`user_id` = `users`.`id`;
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `users` WHERE `share_visibilities`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;
SELECT `posts`.* FROM `posts`, `people`, `users` WHERE `posts`.`author_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;
SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `users`.`id` = _MY_UID AND `people`.`owner_id` = `users`.`id`;
SELECT `people`.* FROM `people`, `posts` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`public` = TRUE;
SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;
SELECT `posts`.* FROM `posts` WHERE `posts`.`public` = TRUE;
SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;
