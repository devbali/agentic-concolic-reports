-- our generated queries NOT answerable from the reference set
-- 3 queries

SELECT `notifications`.* FROM `notifications`;

SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = 1;

SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = 25;
