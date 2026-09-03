SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `people` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`;
