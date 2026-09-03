SELECT `people`.* FROM `people`, `mentions`, `posts`, `comments`, `mentions` AS `mentions0`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `posts`, `comments`, `mentions` AS `mentions0`, `notifications` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `mentions`, `posts`, `mentions` AS `mentions0`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `profiles`, `people`, `contacts` WHERE `taggings`.`taggable_id` = `profiles`.`id` AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags' AND `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `contacts`.`person_id`;

SELECT `mentions`.* FROM `mentions`, `posts`, `mentions` AS `mentions0`, `notifications` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `mentions`, `comments`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `mentions`, `posts`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `comments`, `mentions`, `notifications` WHERE `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `comments`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `comments`.`author_id` AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `notification_actors`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `people`, `posts`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspects`.* FROM `aspects`, `aspect_memberships`, `contacts` WHERE `aspects`.`id` = `aspect_memberships`.`aspect_id` AND `aspect_memberships`.`contact_id` = `contacts`.`id`;

SELECT `comments`.* FROM `comments`, `mentions`, `notifications` WHERE `comments`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `comments`, `notifications` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `posts`, `notifications` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people` INNER JOIN `notification_actors` ON `people`.`id` = `notification_actors`.`person_id`, `notifications` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `comments`, `notifications` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `people`.* FROM `people`, `posts`, `notifications` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `mentions`, `notifications` WHERE `posts`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `profiles`.* FROM `profiles`, `people`, `contacts` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `contacts`.`person_id`;

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
