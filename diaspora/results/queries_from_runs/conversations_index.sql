SELECT `contacts`.* FROM `contacts` INNER JOIN `people` ON `people`.`id` = `contacts`.`person_id` INNER JOIN `profiles` ON `profiles`.`person_id` = `people`.`id` WHERE `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE;

SELECT `conversations`.* FROM `conversations` INNER JOIN `conversation_visibilities` ON `conversation_visibilities`.`conversation_id` = `conversations`.`id`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `conversation_visibilities`.`unread` > 0 AND `people`.`owner_id` = _MY_UID;

SELECT `contacts`.* FROM `contacts` WHERE `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `conversation_visibilities`.* FROM `conversation_visibilities`;

SELECT `messages`.* FROM `messages`;
