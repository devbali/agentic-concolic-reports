SELECT `people`.* FROM `people` WHERE `people`.`diaspora_handle` = 'alice@example.org' AND `people`.`closed_account` = FALSE AND `people`.`owner_id` IS NOT NULL;
