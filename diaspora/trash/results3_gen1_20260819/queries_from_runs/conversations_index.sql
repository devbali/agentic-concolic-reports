SELECT `profiles`.* FROM `profiles`, `people`, `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` AS `people0` WHERE `profiles`.`person_id` = `people`.`id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people` INNER JOIN `conversation_visibilities` ON `conversation_visibilities`.`person_id` = `people`.`id`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` AS `people0` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people` INNER JOIN `conversation_visibilities` ON `conversation_visibilities`.`person_id` = `people`.`id`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` AS `people0` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `conversation_visibilities0`.`unread` <= 0;

SELECT `people`.* FROM `people` INNER JOIN `conversation_visibilities` ON `conversation_visibilities`.`person_id` = `people`.`id`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` AS `people0` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities0`.`conversation_id` AND `conversation_visibilities0`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `conversation_visibilities0`.`unread` > 0;

SELECT `people`.* FROM `people`, `messages`, `conversations`, `conversation_visibilities`, `people` AS `people0` WHERE `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `messages`, `conversations`, `conversation_visibilities`, `people` AS `people0` WHERE `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `conversation_visibilities`.`unread` <= 0;

SELECT `people`.* FROM `people`, `messages`, `conversations`, `conversation_visibilities`, `people` AS `people0` WHERE `people`.`id` = `messages`.`author_id` AND `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `conversation_visibilities`.`unread` > 0;

SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `conversations`, `conversation_visibilities` AS `conversation_visibilities0`, `people` WHERE `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities0`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `messages`.* FROM `messages`, `conversations`, `conversation_visibilities`, `people` WHERE `messages`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`conversation_id` = `conversations`.`id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `messages`.* FROM `messages`, `conversations`, `conversation_visibilities`, `people` WHERE `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `conversation_visibilities`.`unread` <= 0;

SELECT `messages`.* FROM `messages`, `conversations`, `conversation_visibilities`, `people` WHERE `messages`.`conversation_id` = `conversations`.`id` AND `conversations`.`id` = `conversation_visibilities`.`conversation_id` AND `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `conversation_visibilities`.`unread` > 0;

SELECT `contacts`.* FROM `contacts` INNER JOIN `people` ON `people`.`id` = `contacts`.`person_id` INNER JOIN `profiles` ON `profiles`.`person_id` = `people`.`id` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE;

SELECT `conversations`.* FROM `conversations` INNER JOIN `conversation_visibilities` ON `conversation_visibilities`.`conversation_id` = `conversations`.`id`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `contacts`.* FROM `contacts` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `people`.* FROM `people`;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_author_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _assoc_author_id;
