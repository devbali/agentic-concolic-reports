-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` <> '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` <> '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` = '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` = '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `share_visibilities` AS `share_visibilities0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `share_visibilities0`.`shareable_id` = `posts0`.`id` AND `share_visibilities0`.`shareable_type` = 'Post' AND `share_visibilities0`.`user_id` = _MY_UID AND `posts0`.`guid` <> '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `share_visibilities` AS `share_visibilities0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `share_visibilities0`.`shareable_id` = `posts0`.`id` AND `share_visibilities0`.`shareable_type` = 'Post' AND `share_visibilities0`.`user_id` = _MY_UID AND `posts0`.`guid` <> '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `share_visibilities` AS `share_visibilities0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `share_visibilities0`.`shareable_id` = `posts0`.`id` AND `share_visibilities0`.`shareable_type` = 'Post' AND `share_visibilities0`.`user_id` = _MY_UID AND `posts0`.`guid` = '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `share_visibilities` AS `share_visibilities0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `share_visibilities0`.`shareable_id` = `posts0`.`id` AND `share_visibilities0`.`shareable_type` = 'Post' AND `share_visibilities0`.`user_id` = _MY_UID AND `posts0`.`guid` = '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` = '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` = '' AND `posts0`.`text` = '';

SELECT `likes`.* FROM `likes`, `posts`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`text` <> '';

SELECT `likes`.* FROM `likes`, `posts`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`text` = '';

SELECT `likes`.* FROM `likes`, `posts`, `share_visibilities` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`text` <> '';

SELECT `likes`.* FROM `likes`, `posts`, `share_visibilities` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`text` = '';

SELECT `participations`.* FROM `participations`, `posts`, `people` WHERE `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `posts`, `people` WHERE `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`text` = '';

SELECT `participations`.* FROM `participations`, `posts`, `share_visibilities` WHERE `participations`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `posts`, `share_visibilities` WHERE `participations`.`target_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`public` = TRUE AND `posts0`.`guid` <> '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`public` = TRUE AND `posts0`.`guid` <> '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`public` = TRUE AND `posts0`.`guid` = '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`public` = TRUE AND `posts0`.`guid` = '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` <> '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` <> '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` = '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` = '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `posts0`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `posts0`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `posts0`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` = '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `posts0`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` = '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` <> '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` <> '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` = '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `posts0`.`guid` = '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`guid` <> '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`guid` <> '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`guid` = '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`guid` = '' AND `posts0`.`text` = '';

SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`public` = TRUE AND `posts`.`text` <> '';

SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`public` = TRUE AND `posts`.`text` = '';

SELECT `participations`.* FROM `participations`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `posts`.`public` = TRUE AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `posts`.`public` = TRUE AND `posts`.`text` = '';

SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' WHERE `share_visibilities`.`user_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `people` WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `posts0`.`public` = TRUE AND `posts0`.`guid` <> '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `posts0`.`public` = TRUE AND `posts0`.`guid` <> '' AND `posts0`.`text` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `posts0`.`public` = TRUE AND `posts0`.`guid` = '' AND `posts0`.`text` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `posts0`.`public` = TRUE AND `posts0`.`guid` = '' AND `posts0`.`text` = '';

SELECT `posts`.* FROM `posts` WHERE `posts`.`public` = TRUE;
