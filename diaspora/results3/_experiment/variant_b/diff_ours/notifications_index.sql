SELECT `profiles`.* FROM `profiles`, `people`, `notification_actors`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspects`.* FROM `aspects`, `aspect_memberships`, `contacts` WHERE `aspects`.`id` = `aspect_memberships`.`aspect_id` AND `aspect_memberships`.`contact_id` = `contacts`.`id`;

SELECT `people`.* FROM `people` INNER JOIN `notification_actors` ON `people`.`id` = `notification_actors`.`person_id`, `notifications` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id`;

SELECT `comments`.* FROM `comments`, `notifications` WHERE `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `notifications` WHERE `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `people`.* FROM `people`, `contacts` WHERE `people`.`id` = `contacts`.`person_id`;

SELECT `people`.* FROM `people`, `notifications` WHERE `people`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `notifications` WHERE `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `users`.* FROM `users`, `notifications` WHERE `users`.`id` = `notifications`.`recipient_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `blocks`.* FROM `blocks` WHERE `blocks`.`user_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `contacts`.* FROM `contacts`;

SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID;
