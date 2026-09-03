-- our generated queries NOT answerable from the reference set
-- 1 queries

SELECT `photos`.* FROM `photos`, `people` WHERE `photos`.`author_id` = `people`.`id` AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE AND `people`.`closed_account` = FALSE;
