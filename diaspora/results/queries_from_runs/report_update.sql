SELECT `reports`.* FROM `reports`, `reports` AS `reports0` WHERE `reports`.`item_id` = `reports0`.`item_id` AND `reports`.`item_type` = `reports0`.`item_type` AND `reports0`.`id` = '1';

SELECT `reports`.* FROM `reports` WHERE `reports`.`id` = '1';

SELECT `roles`.* FROM `roles` WHERE `roles`.`name` IN ('moderator', 'admin');
