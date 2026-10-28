SELECT `profiles`.* FROM `profiles`, `people`, `notification_actors`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND 1 = 0 AND `notifications`.`recipient_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `notifications` WHERE `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _assoc_target_author_id;
