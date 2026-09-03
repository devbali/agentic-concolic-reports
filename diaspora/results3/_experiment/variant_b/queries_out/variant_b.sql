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

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_commentable_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_commentable_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_mentions_container_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_mentions_container_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Post';

SELECT `people`.* FROM `people`, `notifications` WHERE `people`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `notifications` WHERE `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_profile_id
SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id` WHERE `taggings`.`taggable_id` = _assoc_profile_id AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags';

SELECT `users`.* FROM `users`, `notifications` WHERE `users`.`id` = `notifications`.`recipient_id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `blocks`.* FROM `blocks` WHERE `blocks`.`user_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_mentions_container_id
SELECT `comments`.* FROM `comments` WHERE `comments`.`id` = _assoc_target_mentions_container_id;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `contacts`.* FROM `contacts`;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_commentable_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_commentable_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_mentions_container_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_mentions_container_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Post';

SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _assoc_target_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_mentions_container_commentable_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = _assoc_mentions_container_commentable_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_mentions_container_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = _assoc_target_mentions_container_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_author_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _assoc_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_person_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _assoc_person_id;
