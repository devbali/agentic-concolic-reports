-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `contacts`.* FROM `contacts`;

SELECT `people`.* FROM `people` WHERE `people`.`closed_account` = FALSE;
