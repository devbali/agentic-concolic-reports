SELECT `people`.* FROM `people`, `participations`, `posts`, `share_visibilities`, `people` AS `people0` WHERE `people`.`id` = `participations`.`author_id` AND `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people0`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `people0`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `mentions`.* FROM `mentions` INNER JOIN `comments` ON `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment', `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions` INNER JOIN `comments` ON `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment', `posts`, `share_visibilities` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `mentions`.* FROM `mentions`, `people`, `posts`, `share_visibilities` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `mentions`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `participations`.* FROM `participations`, `people`, `posts`, `share_visibilities` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `participations`.* FROM `participations`, `people`, `posts`, `share_visibilities` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `participations`.* FROM `participations`, `people`, `posts`, `share_visibilities` WHERE `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `participations`.* FROM `participations`, `people`, `posts`, `share_visibilities` WHERE `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `share_visibilities` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `share_visibilities` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `people`.* FROM `people`, `likes`, `posts`, `people` AS `people0` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `people`.* FROM `people`, `likes`, `posts`, `people` AS `people0` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `people`.* FROM `people`, `likes`, `posts`, `share_visibilities` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `people`.* FROM `people`, `likes`, `posts`, `share_visibilities` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `people`.* FROM `people`, `photos`, `posts`, `people` AS `people0` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND 1 = 0 AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `people`.* FROM `people`, `photos`, `posts`, `people` AS `people0` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `people`.* FROM `people`, `photos`, `posts`, `share_visibilities` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND 1 = 0 AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `people`.* FROM `people`, `photos`, `posts`, `share_visibilities` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `share_visibilities` AS `share_visibilities0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `share_visibilities0`.`shareable_id` = `posts0`.`id` AND `share_visibilities0`.`shareable_type` = 'Post' AND `share_visibilities0`.`user_id` = _MY_UID AND `posts0`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0`, `share_visibilities` AS `share_visibilities0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `share_visibilities0`.`shareable_id` = `posts0`.`id` AND `share_visibilities0`.`shareable_type` = 'Post' AND `share_visibilities0`.`user_id` = _MY_UID AND `posts0`.`guid` = '';

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND 1 = 0 AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` = '';

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '';

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND 1 = 0 AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`guid` = '';

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` = '';

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts`, `people` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND 1 = 0 AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts`, `people` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND 1 = 0 AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts`, `share_visibilities` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND 1 = 0 AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts`, `share_visibilities` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND 1 = 0 AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `comments`.* FROM `comments`, `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `comments`.* FROM `comments`, `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `comments`.* FROM `comments`, `posts`, `share_visibilities` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `comments`.* FROM `comments`, `posts`, `share_visibilities` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `likes`.* FROM `likes`, `posts`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `likes`.* FROM `likes`, `posts`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `likes`.* FROM `likes`, `posts`, `share_visibilities` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `likes`.* FROM `likes`, `posts`, `share_visibilities` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `locations`.* FROM `locations`, `posts`, `people` WHERE `locations`.`status_message_id` = `posts`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `locations`.* FROM `locations`, `posts`, `people` WHERE `locations`.`status_message_id` = `posts`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `locations`.* FROM `locations`, `posts`, `share_visibilities` WHERE `locations`.`status_message_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `locations`.* FROM `locations`, `posts`, `share_visibilities` WHERE `locations`.`status_message_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `mentions`.* FROM `mentions` INNER JOIN `comments` ON `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment', `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE;

SELECT `mentions`.* FROM `mentions`, `people`, `posts` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `mentions`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id`;

SELECT `mentions`.* FROM `mentions`, `people`, `posts` WHERE `mentions`.`mentions_container_id` = `posts`.`id` AND `mentions`.`mentions_container_type` = 'Post' AND `mentions`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`public` = TRUE;

SELECT `notifications`.* FROM `notifications`, `posts`, `people` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Post' AND `notifications`.`target_id` = `posts`.`id` AND `notifications`.`unread` = TRUE AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `notifications`.* FROM `notifications`, `posts`, `share_visibilities` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Post' AND `notifications`.`target_id` = `posts`.`id` AND `notifications`.`unread` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts`, `people` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts`, `share_visibilities` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts`, `people` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts`, `share_visibilities` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`guid` <> '';

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`guid` = '';

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`guid` <> '';

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `posts`.`guid` = '';

SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`target_id` = `posts`.`id` AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`guid` <> '' AND `posts`.`public` = TRUE;

SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`guid` = '' AND `posts`.`public` = TRUE;

SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `people`.* FROM `people`, `likes`, `posts` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`guid` <> '' AND `posts`.`public` = TRUE;

SELECT `people`.* FROM `people`, `likes`, `posts` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`guid` = '' AND `posts`.`public` = TRUE;

SELECT `people`.* FROM `people`, `likes`, `posts` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `people`.* FROM `people`, `photos`, `posts` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND 1 = 0 AND `posts`.`guid` = '' AND `posts`.`public` = TRUE;

SELECT `people`.* FROM `people`, `photos`, `posts` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`guid` <> '' AND `posts`.`public` = TRUE;

SELECT `people`.* FROM `people`, `photos`, `posts` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `people`.* FROM `people`, `posts`, `people` AS `people0` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`author_id` = `people0`.`id` AND `people0`.`owner_id` = _MY_UID;

SELECT `people`.* FROM `people`, `posts`, `share_visibilities` WHERE `people`.`id` = `posts`.`author_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `photos`.* FROM `photos`, `posts`, `people` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND 1 = 0 AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `photos`.* FROM `photos`, `posts`, `people` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND 1 = 0 AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `photos`.* FROM `photos`, `posts`, `people` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `photos`.* FROM `photos`, `posts`, `people` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `photos`.* FROM `photos`, `posts`, `share_visibilities` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND 1 = 0 AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `photos`.* FROM `photos`, `posts`, `share_visibilities` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND 1 = 0 AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `photos`.* FROM `photos`, `posts`, `share_visibilities` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `photos`.* FROM `photos`, `posts`, `share_visibilities` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `polls`.* FROM `polls`, `posts`, `people` WHERE `polls`.`status_message_id` = `posts`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `polls`.* FROM `polls`, `posts`, `people` WHERE `polls`.`status_message_id` = `posts`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`guid` = '';

SELECT `polls`.* FROM `polls`, `posts`, `share_visibilities` WHERE `polls`.`status_message_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` <> '';

SELECT `polls`.* FROM `polls`, `posts`, `share_visibilities` WHERE `polls`.`status_message_id` = `posts`.`id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts`.`guid` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post', `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`public` = TRUE AND `posts0`.`guid` <> '';

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND 1 = 0 AND `posts0`.`guid` = '' AND `posts0`.`public` = TRUE;

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND `posts0`.`guid` <> '' AND `posts0`.`public` = TRUE;

SELECT `posts`.* FROM `posts`, `photos`, `posts` AS `posts0` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = `posts0`.`guid` AND `posts0`.`public` = TRUE AND `posts0`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`author_id` = `people`.`id` AND `posts0`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `people` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `posts0`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts0`.`guid` = '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`guid` <> '';

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0`, `share_visibilities` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `share_visibilities`.`shareable_id` = `posts0`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `posts0`.`guid` = '';

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND 1 = 0 AND `posts`.`guid` <> '' AND `posts`.`public` = TRUE;

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND 1 = 0 AND `posts`.`guid` = '' AND `posts`.`public` = TRUE;

SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id`, `posts` WHERE `taggings`.`taggable_id` = `posts`.`id` AND `taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags' AND 1 = 0 AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`guid` <> '' AND `posts`.`public` = TRUE;

SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`guid` = '' AND `posts`.`public` = TRUE;

SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`guid` <> '' AND `posts`.`public` = TRUE;

SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`guid` = '' AND `posts`.`public` = TRUE;

SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `locations`.* FROM `locations`, `posts` WHERE `locations`.`status_message_id` = `posts`.`id` AND `posts`.`guid` <> '' AND `posts`.`public` = TRUE;

SELECT `locations`.* FROM `locations`, `posts` WHERE `locations`.`status_message_id` = `posts`.`id` AND `posts`.`guid` = '' AND `posts`.`public` = TRUE;

SELECT `locations`.* FROM `locations`, `posts` WHERE `locations`.`status_message_id` = `posts`.`id` AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `notifications`.* FROM `notifications`, `posts` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Post' AND `notifications`.`target_id` = `posts`.`id` AND `notifications`.`unread` = TRUE AND `posts`.`public` = TRUE;

SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`public` = TRUE;

SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id
SELECT `participations`.* FROM `participations`, `people` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id AND `people`.`owner_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_id
SELECT `participations`.* FROM `participations`, `people` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = _assoc_root_id AND `people`.`owner_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id
SELECT `people`.* FROM `people`, `likes` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_id
SELECT `people`.* FROM `people`, `likes` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = _assoc_root_id AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_guid
SELECT `people`.* FROM `people`, `photos` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = _assoc_root_guid;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_guid
SELECT `people`.* FROM `people`, `photos` WHERE `people`.`id` = `photos`.`author_id` AND `photos`.`status_message_guid` = _assoc_root_guid AND 1 = 0;

SELECT `people`.* FROM `people`, `posts` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`public` = TRUE;

SELECT `photos`.* FROM `photos`, `posts` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND 1 = 0 AND `posts`.`guid` = '' AND `posts`.`public` = TRUE;

SELECT `photos`.* FROM `photos`, `posts` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND 1 = 0 AND `posts`.`public` = TRUE;

SELECT `photos`.* FROM `photos`, `posts` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`guid` <> '' AND `posts`.`public` = TRUE;

SELECT `photos`.* FROM `photos`, `posts` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`public` = TRUE;

SELECT `photos`.* FROM `photos`, `posts` WHERE `photos`.`status_message_guid` = `posts`.`guid` AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `polls`.* FROM `polls`, `posts` WHERE `polls`.`status_message_id` = `posts`.`id` AND `posts`.`guid` <> '' AND `posts`.`public` = TRUE;

SELECT `polls`.* FROM `polls`, `posts` WHERE `polls`.`status_message_id` = `posts`.`id` AND `posts`.`guid` = '' AND `posts`.`public` = TRUE;

SELECT `polls`.* FROM `polls`, `posts` WHERE `polls`.`status_message_id` = `posts`.`id` AND `posts`.`public` = TRUE AND `posts`.`guid` <> '';

SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' WHERE `share_visibilities`.`user_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `people` WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_guid
SELECT `posts`.* FROM `posts`, `photos` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = _assoc_root_guid;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_guid
SELECT `posts`.* FROM `posts`, `photos` WHERE `posts`.`guid` = `photos`.`status_message_guid` AND `photos`.`status_message_guid` = _assoc_root_guid AND 1 = 0;

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `posts0`.`guid` <> '' AND `posts0`.`public` = TRUE;

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `posts0`.`guid` = '' AND `posts0`.`public` = TRUE;

-- NOTE: join compares columns of different types, as recorded by the runtime (known result-var naming bug)
SELECT `posts`.* FROM `posts`, `posts` AS `posts0` WHERE `posts`.`guid` = `posts0`.`id` AND `posts`.`public` = TRUE AND `posts0`.`public` = TRUE AND `posts0`.`guid` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id
SELECT `likes`.* FROM `likes` WHERE `likes`.`target_id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_id AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_id
SELECT `likes`.* FROM `likes` WHERE `likes`.`target_id` = _assoc_root_id AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_id
SELECT `locations`.* FROM `locations` WHERE `locations`.`status_message_id` = _assoc_root_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Calculations_ids_1_ids
SELECT `notifications`.* FROM `notifications` WHERE `notifications`.`recipient_id` = _MY_UID AND `notifications`.`target_type` = 'Mention' AND `notifications`.`target_id` = _SYM_RESULT_ActiveRecord__Calculations_ids_1_ids AND `notifications`.`unread` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_o_embed_cache_id
SELECT `o_embed_caches`.* FROM `o_embed_caches` WHERE `o_embed_caches`.`id` = _assoc_root_o_embed_cache_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_open_graph_cache_id
SELECT `open_graph_caches`.* FROM `open_graph_caches` WHERE `open_graph_caches`.`id` = _assoc_root_open_graph_cache_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_find_by_3_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _SYM_RESULT_ActiveRecord__FinderMethods_find_by_3_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_find_by_6_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _SYM_RESULT_ActiveRecord__FinderMethods_find_by_6_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_find_by_9_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _SYM_RESULT_ActiveRecord__FinderMethods_find_by_9_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _assoc_root_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_guid
SELECT `photos`.* FROM `photos` WHERE `photos`.`status_message_guid` = _assoc_root_guid;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_guid
SELECT `photos`.* FROM `photos` WHERE `photos`.`status_message_guid` = _assoc_root_guid AND 1 = 0;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_poll_id
SELECT `poll_answers`.* FROM `poll_answers` WHERE `poll_answers`.`poll_id` = _assoc_poll_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_poll_id
SELECT `poll_participations`.* FROM `poll_participations` WHERE `poll_participations`.`poll_id` = _assoc_poll_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_id
SELECT `polls`.* FROM `polls` WHERE `polls`.`status_message_id` = _assoc_root_id;

SELECT `posts`.* FROM `posts`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid
SELECT `posts`.* FROM `posts` WHERE `posts`.`guid` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_row_root_guid;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_poll_status_message_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = _assoc_poll_status_message_id;

SELECT `posts`.* FROM `posts` WHERE `posts`.`public` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_1_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_1_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_2_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_2_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_3_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_3_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_4_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_4_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_5_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_5_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_msg_first_1_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_msg_first_1_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_msg_first_2_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_msg_first_2_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActsAsApi__Collection_as_api_response_1_row_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActsAsApi__Collection_as_api_response_2_row_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActsAsApi__Collection_as_api_response_3_row_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActsAsApi__Collection_as_api_response_4_row_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActsAsApi__Collection_as_api_response_4_row_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_author_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _assoc_author_id;
