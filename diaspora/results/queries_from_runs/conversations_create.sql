SELECT `contacts`.* FROM `contacts` WHERE `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE AND `contacts`.`id` IN ('1', '2');

SELECT `contacts`.* FROM `contacts` WHERE `contacts`.`sharing` = TRUE AND `contacts`.`receiving` = TRUE AND `contacts`.`person_id` = '7';

SELECT `people`.* FROM `people` WHERE `people`.`id` IN (1, 1);
