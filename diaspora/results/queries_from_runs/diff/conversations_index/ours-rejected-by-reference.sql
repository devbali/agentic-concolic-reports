-- our generated queries NOT answerable from the reference set
-- 4 queries

SELECT `contacts`.* FROM `contacts` INNER JOIN `people` ON `people`.`id` = `contacts`.`person_id` INNER JOIN `profiles` ON `profiles`.`person_id` = `people`.`id` WHERE `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE;

SELECT `contacts`.* FROM `contacts` WHERE `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE;

SELECT `conversation_visibilities`.* FROM `conversation_visibilities`;

SELECT `messages`.* FROM `messages`;
