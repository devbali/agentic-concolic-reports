SELECT `people`.* FROM `people` INNER JOIN `notification_actors` ON `people`.`id` = `notification_actors`.`person_id`, `notifications`, `people` AS `people0`, `notification_actors` AS `notification_actors0` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `people0`.`id` AND `people0`.`id` = `notification_actors0`.`person_id` AND `notification_actors0`.`notification_id` = `notifications`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `mentions`, `comments`, `mentions` AS `mentions0`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`commentable_id` AND `mentions`.`mentions_container_type` = 'Post' AND `comments`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `mentions`, `notifications`, `people` AS `people0`, `notification_actors` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Post' AND `notifications`.`recipient_id` = `people0`.`id` AND `people0`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `posts`, `comments`, `mentions`, `notifications` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `posts`, `notifications`, `people` AS `people0`, `notification_actors` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = `people0`.`id` AND `people0`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `photos`.* FROM `photos`, `posts`, `comments`, `mentions`, `notifications` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `photos`.* FROM `photos`, `posts`, `notifications`, `people`, `notification_actors` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `mentions` AS `mentions0`, `notifications` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `comments`.`commentable_id` AND `mentions`.`mentions_container_type` = 'Post' AND `comments`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `mentions`, `notifications`, `people`, `notification_actors` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Post' AND `notifications`.`recipient_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `people`, `notification_actors`, `notifications`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `posts`, `comments`, `mentions`, `notifications` WHERE `profiles`.`person_id` = `posts`.`author_id` AND `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `posts`, `notifications`, `people`, `notification_actors` WHERE `profiles`.`person_id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `tags`.`name`, `taggings`.`id` FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `profiles`, `contacts`, `notifications` WHERE `taggings`.`taggable_id` = `profiles`.`id` AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags' AND `profiles`.`person_id` = `contacts`.`person_id` AND `contacts`.`user_id` = `notifications`.`recipient_id` AND `contacts`.`person_id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `aspects`.* FROM `aspects`, `aspect_memberships`, `contacts`, `notifications` WHERE `aspects`.`id` = `aspect_memberships`.`aspect_id` AND `aspect_memberships`.`contact_id` = `contacts`.`id` AND `contacts`.`user_id` = `notifications`.`recipient_id` AND `contacts`.`person_id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `aspects`.* FROM `aspects`, `people`, `notification_actors`, `notifications` WHERE `aspects`.`user_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `people`.`id`;

SELECT `contacts`.* FROM `contacts`, `people`, `notification_actors`, `notifications` WHERE `contacts`.`user_id` = `people`.`id` AND `contacts`.`receiving` = TRUE AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `people`.`id`;

SELECT `mentions`.* FROM `mentions`, `comments`, `mentions` AS `mentions0`, `notifications` WHERE `mentions`.`mentions_container_id` = `comments`.`commentable_id` AND `mentions`.`mentions_container_type` = 'Post' AND `comments`.`id` = `mentions0`.`mentions_container_id` AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `mentions`.* FROM `mentions`, `notifications`, `people`, `notification_actors` WHERE `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Post' AND `notifications`.`recipient_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `notification_actors`.* FROM `notification_actors`, `notifications`, `people`, `notification_actors` AS `notification_actors0` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `people`.`id` AND `people`.`id` = `notification_actors0`.`person_id` AND `notification_actors0`.`notification_id` = `notifications`.`id`;

SELECT `notifications`.* FROM `notifications`, `people`, `notification_actors`, `notifications` AS `notifications0` WHERE `notifications`.`recipient_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications0`.`id` AND `notifications0`.`recipient_id` = `people`.`id`;

SELECT `people`.* FROM `people` INNER JOIN `notification_actors` ON `people`.`id` = `notification_actors`.`person_id`, `notifications`, `users` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `mentions`, `mentions` AS `mentions0`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `mentions0`.`mentions_container_id` AND `mentions`.`mentions_container_type` = 'Post' AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `mentions`, `notifications`, `users` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Post' AND `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `posts`, `mentions`, `notifications` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `posts`, `notifications`, `users` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `photos`.* FROM `photos`, `posts`, `mentions`, `notifications` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `posts`.* FROM `posts`, `comments`, `mentions`, `notifications` WHERE `posts`.`id` = `comments`.`commentable_id` AND `comments`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `posts`.* FROM `posts`, `notifications`, `people`, `notification_actors` WHERE `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `mentions`, `mentions` AS `mentions0`, `notifications` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `mentions0`.`mentions_container_id` AND `mentions`.`mentions_container_type` = 'Post' AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `mentions`, `notifications`, `users` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Post' AND `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `people`, `notification_actors`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `people`, `notification_actors`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `people`, `notification_actors`, `notifications` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `people`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `posts`, `mentions`, `notifications` WHERE `profiles`.`person_id` = `posts`.`author_id` AND `posts`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `posts`, `notifications`, `users` WHERE `profiles`.`person_id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `services`.* FROM `services`, `people`, `notification_actors`, `notifications` WHERE `services`.`user_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `people`.`id`;

SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts`, `notifications` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id` AND `contacts`.`user_id` = `notifications`.`recipient_id` AND `contacts`.`person_id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `comments`.* FROM `comments`, `mentions`, `notifications` WHERE `comments`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `contacts`.* FROM `contacts`, `contacts` AS `contacts0`, `notifications` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`person_id` = `contacts0`.`person_id` AND `contacts0`.`user_id` = `notifications`.`recipient_id` AND `contacts0`.`person_id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `conversation_visibilities`.* FROM `conversation_visibilities`, `people`, `users` WHERE `conversation_visibilities`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `mentions` AS `mentions0`, `notifications` WHERE `mentions`.`mentions_container_id` = `mentions0`.`mentions_container_id` AND `mentions`.`mentions_container_type` = 'Post' AND `mentions0`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `mentions`.* FROM `mentions`, `notifications`, `users` WHERE `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Post' AND `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `notification_actors`.* FROM `notification_actors`, `notifications`, `users` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `notifications`.* FROM `notifications`, `people`, `notification_actors` WHERE `notifications`.`recipient_id` = `people`.`id` AND `people`.`id` = `notification_actors`.`person_id` AND `notification_actors`.`notification_id` = `notifications`.`id`;

SELECT `people`.* FROM `people` INNER JOIN `notification_actors` ON `people`.`id` = `notification_actors`.`person_id`, `notifications` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people` INNER JOIN `notification_actors` ON `people`.`id` = `notification_actors`.`person_id`, `notifications` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `people`.* FROM `people` INNER JOIN `notification_actors` ON `people`.`id` = `notification_actors`.`person_id`, `notifications` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = `people`.`id` AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `comments`, `notifications` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `contacts`, `notifications` WHERE `people`.`id` = `contacts`.`person_id` AND `contacts`.`user_id` = `notifications`.`recipient_id` AND `contacts`.`person_id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `mentions`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Comment' AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `mentions`, `notifications` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Post' AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `posts`, `notifications` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `photos`.* FROM `photos`, `posts`, `notifications` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `posts`.* FROM `posts`, `mentions`, `notifications` WHERE `posts`.`id` = `mentions`.`mentions_container_id` AND `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `posts`.* FROM `posts`, `notifications`, `users` WHERE `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `comments`, `notifications` WHERE `profiles`.`person_id` = `comments`.`author_id` AND `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `contacts`, `notifications` WHERE `profiles`.`person_id` = `contacts`.`person_id` AND `contacts`.`user_id` = `notifications`.`recipient_id` AND `contacts`.`person_id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `mentions`, `notifications` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Comment' AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `mentions`, `notifications` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Post' AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `profiles`.* FROM `profiles`, `people`, `users` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `profiles`.* FROM `profiles`, `posts`, `notifications` WHERE `profiles`.`person_id` = `posts`.`author_id` AND `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `roles`.* FROM `roles`, `people`, `users` WHERE `roles`.`name` IN ('moderator', 'admin') AND `roles`.`person_id` = `people`.`id` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `roles`.* FROM `roles`, `people`, `users` WHERE `roles`.`person_id` = `people`.`id` AND `roles`.`name` = `admin` AND `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `aspects`.* FROM `aspects`, `users` WHERE `aspects`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `comments`.* FROM `comments`, `notifications` WHERE `comments`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `contacts`.* FROM `contacts`, `users` WHERE `contacts`.`user_id` = `users`.`id` AND `contacts`.`receiving` = TRUE AND `users`.`id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `notifications` WHERE `mentions`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `mentions`.* FROM `mentions`, `notifications` WHERE `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Comment' AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `mentions`.* FROM `mentions`, `notifications` WHERE `mentions`.`mentions_container_id` = `notifications`.`target_id` AND `mentions`.`mentions_container_type` = 'Post' AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `notification_actors`.* FROM `notification_actors`, `notifications` WHERE `notification_actors`.`notification_id` = `notifications`.`id` AND `notifications`.`recipient_id` = _MY_UID;

SELECT `notifications`.* FROM `notifications`, `users` WHERE `notifications`.`recipient_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `people`.* FROM `people`, `notifications` WHERE `people`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `notifications` WHERE `people`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `people`.* FROM `people`, `users` WHERE `people`.`owner_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `notifications` WHERE `posts`.`id` = `notifications`.`target_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` <> 'Notifications::StartedSharing';

SELECT `services`.* FROM `services`, `users` WHERE `services`.`user_id` = `users`.`id` AND `users`.`id` = _MY_UID;

SELECT `users`.* FROM `users`, `notifications` WHERE `users`.`id` = `notifications`.`recipient_id` AND `notifications`.`recipient_id` = _MY_UID AND `notifications`.`type` = 'Notifications::StartedSharing';

SELECT `blocks`.* FROM `blocks` WHERE `blocks`.`user_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id
SELECT `conversation_visibilities`.* FROM `conversation_visibilities` WHERE `conversation_visibilities`.`person_id` = _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id;

SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id
SELECT `roles`.* FROM `roles` WHERE `roles`.`name` IN ('moderator', 'admin') AND `roles`.`person_id` = _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id
SELECT `roles`.* FROM `roles` WHERE `roles`.`person_id` = _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id AND `roles`.`name` = `admin`;

SELECT `users`.* FROM `users` WHERE `users`.`id` = _MY_UID;
