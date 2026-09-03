SELECT `notifications`.* FROM `notifications`;

SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = 1 AND `notifications`.`unread` = TRUE;
