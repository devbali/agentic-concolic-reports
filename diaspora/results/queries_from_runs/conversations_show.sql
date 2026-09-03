SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `conversation_visibilities`.`unread` > 0 AND `people`.`owner_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `conversation_visibilities`.* FROM `conversation_visibilities`;

SELECT `conversations`.* FROM `conversations`;

SELECT `messages`.* FROM `messages`;
