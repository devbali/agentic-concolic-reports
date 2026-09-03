SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `messages`.* FROM `messages`, `conversations`, `conversation_visibilities`, `people` WHERE `messages`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `contacts`.* FROM `contacts` INNER JOIN `people` ON `people`.`id` = `contacts`.`person_id` INNER JOIN `profiles` ON `profiles`.`person_id` = `people`.`id` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE;

SELECT `conversations`.* FROM `conversations` INNER JOIN `conversation_visibilities` ON `conversation_visibilities`.`conversation_id` = `conversations`.`id`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;
