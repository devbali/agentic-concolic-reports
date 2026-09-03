SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts`, `aspect_memberships` AS `aspect_memberships0`, `aspects`, `aspect_memberships` AS `aspect_memberships1` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id` AND `aspect_memberships`.`aspect_id` = `aspects`.`id` AND `aspect_memberships0`.`contact_id` = `contacts`.`id` AND `aspect_memberships1`.`aspect_id` = `aspects`.`id`;

SELECT `aspects`.* FROM `aspects` INNER JOIN `aspect_memberships` ON `aspect_memberships`.`aspect_id` = `aspects`.`id`;

SELECT `contacts`.* FROM `contacts` INNER JOIN `aspect_memberships` ON `aspect_memberships`.`contact_id` = `contacts`.`id`;
