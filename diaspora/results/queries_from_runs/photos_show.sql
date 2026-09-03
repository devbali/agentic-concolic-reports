-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `photos`.* FROM `photos`, `people` WHERE `photos`.`author_id` = 15 AND `photos`.`created_at` < `people`.`id` AND `photos`.`id` = '2026-08-16 03:10:12 +0000' AND `people`.`owner_id` = _MY_UID;

SELECT `photos`.* FROM `photos` WHERE `photos`.`public` = TRUE;
