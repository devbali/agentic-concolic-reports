-- reference queries NOT answerable from our generated query set
-- 43 queries

SELECT `poll_answers`.`id` AS `id2`, `poll_answers`.`answer`, `poll_answers`.`poll_id`, `poll_answers`.`guid` AS `guid1`, `poll_answers`.`vote_count`, `polls`.`status_message_id` FROM `posts`,     `share_visibilities`,     `polls`,     `poll_answers` WHERE `poll_answers`.`poll_id` = `polls`.`id` AND (`posts`.`type` = 'StatusMessage' AND `share_visibilities`.`shareable_id` = `posts`.`id`) AND (`share_visibilities`.`shareable_type` = 'Post' AND (`share_visibilities`.`user_id` = _MY_UID AND `polls`.`status_message_id` = `posts`.`id`));

SELECT `profiles`.`id`, `profiles`.`diaspora_handle`, `profiles`.`first_name`, `profiles`.`last_name`, `profiles`.`image_url`, `profiles`.`image_url_small`, `profiles`.`image_url_medium`, `profiles`.`searchable`, `profiles`.`person_id`, `profiles`.`created_at`, `profiles`.`updated_at`, `profiles`.`full_name`, `profiles`.`nsfw`, `profiles`.`public_details`, `posts`.`id` FROM `posts`,     `share_visibilities`,     `people`,     `profiles` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `profiles`.`id`, `profiles`.`diaspora_handle`, `profiles`.`first_name`, `profiles`.`last_name`, `profiles`.`image_url`, `profiles`.`image_url_small`, `profiles`.`image_url_medium`, `profiles`.`searchable`, `profiles`.`person_id`, `profiles`.`created_at`, `profiles`.`updated_at`, `profiles`.`full_name`, `profiles`.`nsfw`, `profiles`.`public_details`, `mentions`.`mentions_container_id` FROM `people`,     `posts`,     `mentions`,     `profiles` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND (`posts`.`type` = 'StatusMessage' AND `mentions`.`mentions_container_type` = 'Post') AND (`posts`.`author_id` = `people`.`id` AND (`people`.`owner_id` = _MY_UID AND `mentions`.`mentions_container_id` = `posts`.`id`));

SELECT `profiles`.`id`, `profiles`.`diaspora_handle`, `profiles`.`first_name`, `profiles`.`last_name`, `profiles`.`image_url`, `profiles`.`image_url_small`, `profiles`.`image_url_medium`, `profiles`.`searchable`, `profiles`.`person_id`, `profiles`.`created_at`, `profiles`.`updated_at`, `profiles`.`full_name`, `profiles`.`nsfw`, `profiles`.`public_details`, `likes`.`target_id` FROM `people`,     `posts`,     `likes`,     `profiles` WHERE `profiles`.`person_id` = `likes`.`author_id` AND (`likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE) AND (`posts`.`author_id` = `people`.`id` AND (`people`.`owner_id` = _MY_UID AND `posts`.`id` = `likes`.`target_id`));

SELECT 1 AS `one`, `posts`.`id` FROM `posts`,     `share_visibilities`,     `people`,     `roles` WHERE `roles`.`person_id` = `people`.`id` AND (`roles`.`name` = 'admin' AND `people`.`owner_id` = _MY_UID) AND (`share_visibilities`.`shareable_id` = `posts`.`id` AND (`share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID));

SELECT 1 AS `one`, `posts`.`id` FROM `posts`,     `share_visibilities`,     `people`,     `roles` WHERE `roles`.`name` IN ('admin', 'moderator') AND (`roles`.`person_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID) AND (`share_visibilities`.`shareable_id` = `posts`.`id` AND (`share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID));

SELECT `tags`.`id`, `tags`.`name`, `tags`.`taggings_count`, `taggings`.`taggable_id` FROM `people`,     `posts`,     `tags`,     `taggings` WHERE `tags`.`id` = `taggings`.`tag_id` AND (`taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags') AND (`posts`.`type` = 'StatusMessage' AND `posts`.`author_id` = `people`.`id` AND (`people`.`owner_id` = _MY_UID AND `posts`.`id` = `taggings`.`taggable_id`));

SELECT `aspects`.`id` AS `id1`, `aspects`.`name`, `aspects`.`user_id`, `aspects`.`created_at` AS `created_at1`, `aspects`.`updated_at` AS `updated_at1`, `aspects`.`order_id`, `aspects`.`chat_enabled`, `aspects`.`post_default`, `posts`.`id` AS `id0` FROM `people`,     `posts`,     `aspects` WHERE `aspects`.`user_id` = _MY_UID AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT 1 AS `one`, `posts`.`id` AS `id0` FROM `people`,     `posts`,     `roles` WHERE `roles`.`person_id` = `people`.`id` AND `roles`.`name` = 'admin' AND `posts`.`public` = TRUE AND `people`.`owner_id` = _MY_UID;

SELECT `poll_answers`.`id` AS `id1`, `poll_answers`.`answer`, `poll_answers`.`poll_id`, `poll_answers`.`guid` AS `guid1`, `poll_answers`.`vote_count`, `polls`.`status_message_id` FROM `posts`,     `polls`,     `poll_answers` WHERE `poll_answers`.`poll_id` = `polls`.`id` AND `posts`.`type` = 'StatusMessage' AND `posts`.`public` = TRUE AND `polls`.`status_message_id` = `posts`.`id`;

SELECT 1 AS `one`, `participations`.`target_id` FROM `people`,     `posts`,     `participations` WHERE `participations`.`author_id` = `people`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`id` = `participations`.`target_id`;

SELECT 1 AS `one`, `posts`.`id` AS `id0` FROM `people`,     `posts`,     `roles` WHERE `roles`.`person_id` = `people`.`id` AND `roles`.`name` = 'admin' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `locations`.`id` AS `id1`, `locations`.`address`, `locations`.`lat`, `locations`.`lng`, `locations`.`status_message_id`, `locations`.`created_at` AS `created_at1`, `locations`.`updated_at` AS `updated_at1` FROM `people`,     `posts`,     `locations` WHERE `posts`.`type` = 'StatusMessage' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`id` = `locations`.`status_message_id`;

SELECT `people`.`id` AS `id1`, `people`.`guid` AS `guid0`, `people`.`diaspora_handle`, `people`.`serialized_public_key`, `people`.`owner_id`, `people`.`created_at` AS `created_at0`, `people`.`updated_at` AS `updated_at0`, `people`.`closed_account`, `people`.`fetch_status`, `people`.`pod_id`, `posts`.`id` FROM `posts`,     `share_visibilities`,     `people` WHERE `people`.`id` = `posts`.`author_id` AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `o_embed_caches`.`id` AS `id1`, `o_embed_caches`.`url`, `o_embed_caches`.`data`, `posts`.`id` AS `id0` FROM `people`,     `posts`,     `o_embed_caches` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`type` = 'StatusMessage' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `mentions`.`id` AS `id1`, `mentions`.`mentions_container_id`, `mentions`.`person_id`, `mentions`.`mentions_container_type` FROM `people`,     `posts`,     `mentions` WHERE `mentions`.`mentions_container_type` = 'Post' AND `posts`.`type` = 'StatusMessage' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `mentions`.`mentions_container_id` = `posts`.`id`;

SELECT `people`.`id` AS `id1`, `people`.`guid` AS `guid1`, `people`.`diaspora_handle`, `people`.`serialized_public_key`, `people`.`owner_id`, `people`.`created_at` AS `created_at1`, `people`.`updated_at` AS `updated_at1`, `people`.`closed_account`, `people`.`fetch_status`, `people`.`pod_id`, `likes`.`target_id` FROM `posts`,     `likes`,     `people` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`public` = TRUE AND `posts`.`id` = `likes`.`target_id`;

SELECT `contacts`.`id` AS `id1`, `contacts`.`user_id` AS `user_id0`, `contacts`.`person_id`, `contacts`.`created_at` AS `created_at0`, `contacts`.`updated_at` AS `updated_at0`, `contacts`.`sharing`, `contacts`.`receiving`, `posts`.`id` FROM `posts`,     `share_visibilities`,     `contacts` WHERE `contacts`.`user_id` = _MY_UID AND `contacts`.`receiving` = TRUE AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `people`.`id` AS `id1`, `people`.`guid` AS `guid0`, `people`.`diaspora_handle`, `people`.`serialized_public_key`, `people`.`owner_id`, `people`.`created_at` AS `created_at0`, `people`.`updated_at` AS `updated_at0`, `people`.`closed_account`, `people`.`fetch_status`, `people`.`pod_id`, `mentions`.`mentions_container_id` FROM `posts`,     `mentions`,     `people` WHERE `people`.`id` = `mentions`.`person_id` AND `posts`.`type` = 'StatusMessage' AND `mentions`.`mentions_container_type` = 'Post' AND `posts`.`public` = TRUE AND `mentions`.`mentions_container_id` = `posts`.`id`;

SELECT `polls`.`id` AS `id1`, `polls`.`question`, `polls`.`status_message_id`, `polls`.`status`, `polls`.`guid` AS `guid1`, `polls`.`created_at` AS `created_at1`, `polls`.`updated_at` AS `updated_at1` FROM `people`,     `posts`,     `polls` WHERE `posts`.`type` = 'StatusMessage' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `polls`.`status_message_id` = `posts`.`id`;

SELECT `o_embed_caches`.`id` AS `id1`, `o_embed_caches`.`url`, `o_embed_caches`.`data`, `posts`.`id` FROM `posts`,     `share_visibilities`,     `o_embed_caches` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`type` = 'StatusMessage' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `open_graph_caches`.`id` AS `id1`, `open_graph_caches`.`title`, `open_graph_caches`.`ob_type`, `open_graph_caches`.`image`, `open_graph_caches`.`url`, `open_graph_caches`.`description`, `open_graph_caches`.`video_url`, `posts`.`id` AS `id0` FROM `people`,     `posts`,     `open_graph_caches` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`type` = 'StatusMessage' AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `open_graph_caches`.`id` AS `id1`, `open_graph_caches`.`title`, `open_graph_caches`.`ob_type`, `open_graph_caches`.`image`, `open_graph_caches`.`url`, `open_graph_caches`.`description`, `open_graph_caches`.`video_url`, `posts`.`id` FROM `posts`,     `share_visibilities`,     `open_graph_caches` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`type` = 'StatusMessage' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `likes`.`id` AS `id1`, `likes`.`positive`, `likes`.`target_id`, `likes`.`author_id` AS `author_id0`, `likes`.`guid` AS `guid1`, `likes`.`created_at` AS `created_at1`, `likes`.`updated_at` AS `updated_at1`, `likes`.`target_type` FROM `people`,     `posts`,     `likes` WHERE `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`id` = `likes`.`target_id`;

SELECT `profiles`.`id`, `profiles`.`diaspora_handle`, `profiles`.`first_name`, `profiles`.`last_name`, `profiles`.`image_url`, `profiles`.`image_url_small`, `profiles`.`image_url_medium`, `profiles`.`searchable`, `profiles`.`person_id`, `profiles`.`created_at`, `profiles`.`updated_at`, `profiles`.`full_name`, `profiles`.`nsfw`, `profiles`.`public_details`, `posts`.`id` AS `id0` FROM `people`,     `posts`,     `profiles` WHERE `profiles`.`person_id` = `people`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `tags`.`id`, `tags`.`name`, `tags`.`taggings_count`, `taggings`.`taggable_id` FROM `posts`,     `tags`,     `taggings` WHERE `tags`.`id` = `taggings`.`tag_id` AND (`taggings`.`taggable_type` = 'Post' AND `taggings`.`context` = 'tags') AND (`posts`.`type` = 'StatusMessage' AND (`posts`.`public` = TRUE AND `posts`.`id` = `taggings`.`taggable_id`));

SELECT 1 AS `one`, `posts`.`id` AS `id0` FROM `people`,     `posts`,     `roles` WHERE `roles`.`name` IN ('admin', 'moderator') AND `roles`.`person_id` = `people`.`id` AND `posts`.`public` = TRUE AND `people`.`owner_id` = _MY_UID;

SELECT 1 AS `one`, `participations`.`target_id` FROM `people`,     `posts`,     `participations` WHERE `participations`.`author_id` = `people`.`id` AND `posts`.`public` = TRUE AND `people`.`owner_id` = _MY_UID AND `posts`.`id` = `participations`.`target_id`;

SELECT `mentions`.`id` AS `id1`, `mentions`.`mentions_container_id`, `mentions`.`person_id`, `mentions`.`mentions_container_type` FROM `posts`,     `share_visibilities`,     `mentions` WHERE `mentions`.`mentions_container_type` = 'Post' AND (`posts`.`type` = 'StatusMessage' AND `share_visibilities`.`shareable_id` = `posts`.`id`) AND (`share_visibilities`.`shareable_type` = 'Post' AND (`share_visibilities`.`user_id` = _MY_UID AND `mentions`.`mentions_container_id` = `posts`.`id`));

SELECT `mentions`.`id`, `mentions`.`mentions_container_id` FROM `people`,     `posts`,     `mentions` WHERE `mentions`.`mentions_container_type` = 'Post' AND `mentions`.`person_id` = `people`.`id` AND `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID AND `mentions`.`mentions_container_id` = `posts`.`id`;

SELECT `polls`.`id` AS `id1`, `polls`.`question`, `polls`.`status_message_id`, `polls`.`status`, `polls`.`guid` AS `guid0`, `polls`.`created_at` AS `created_at0`, `polls`.`updated_at` AS `updated_at0` FROM `posts`,     `share_visibilities`,     `polls` WHERE `posts`.`type` = 'StatusMessage' AND `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID AND `polls`.`status_message_id` = `posts`.`id`;

SELECT `polls`.`id` AS `id0`, `polls`.`question`, `polls`.`status_message_id`, `polls`.`status`, `polls`.`guid` AS `guid0`, `polls`.`created_at` AS `created_at0`, `polls`.`updated_at` AS `updated_at0` FROM `posts`,     `polls` WHERE `posts`.`type` = 'StatusMessage' AND `posts`.`public` = TRUE AND `polls`.`status_message_id` = `posts`.`id`;

SELECT `aspects`.`id` AS `id0`, `aspects`.`name`, `aspects`.`user_id`, `aspects`.`created_at` AS `created_at0`, `aspects`.`updated_at` AS `updated_at0`, `aspects`.`order_id`, `aspects`.`chat_enabled`, `aspects`.`post_default`, `posts`.`id` FROM `posts`,     `aspects` WHERE `aspects`.`user_id` = _MY_UID AND `posts`.`public` = TRUE;

SELECT `profiles`.`id`, `profiles`.`diaspora_handle`, `profiles`.`first_name`, `profiles`.`last_name`, `profiles`.`image_url`, `profiles`.`image_url_small`, `profiles`.`image_url_medium`, `profiles`.`searchable`, `profiles`.`person_id`, `profiles`.`created_at`, `profiles`.`updated_at`, `profiles`.`full_name`, `profiles`.`nsfw`, `profiles`.`public_details`, `posts`.`id` FROM `posts`,     `profiles` WHERE `profiles`.`person_id` = `posts`.`author_id` AND `posts`.`public` = TRUE;

SELECT `posts`.`id`, `posts`.`author_id`, `posts`.`public`, `posts`.`guid`, `posts`.`type`, `posts`.`text`, `posts`.`created_at`, `posts`.`updated_at`, `posts`.`provider_display_name`, `posts`.`root_guid`, `posts`.`likes_count`, `posts`.`comments_count`, `posts`.`o_embed_cache_id`, `posts`.`reshares_count`, `posts`.`interacted_at`, `posts`.`tweet_id`, `posts`.`open_graph_cache_id`, `posts`.`tumblr_ids` FROM `posts`,     `share_visibilities` WHERE `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' AND `share_visibilities`.`user_id` = _MY_UID;

SELECT `people`.`id` AS `id0`, `people`.`guid` AS `guid0`, `people`.`diaspora_handle`, `people`.`serialized_public_key`, `people`.`owner_id`, `people`.`created_at` AS `created_at0`, `people`.`updated_at` AS `updated_at0`, `people`.`closed_account`, `people`.`fetch_status`, `people`.`pod_id`, `posts`.`id` FROM `posts`,     `people` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`public` = TRUE;

SELECT `open_graph_caches`.`id` AS `id0`, `open_graph_caches`.`title`, `open_graph_caches`.`ob_type`, `open_graph_caches`.`image`, `open_graph_caches`.`url`, `open_graph_caches`.`description`, `open_graph_caches`.`video_url`, `posts`.`id` FROM `posts`,     `open_graph_caches` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`type` = 'StatusMessage' AND `posts`.`public` = TRUE;

SELECT `locations`.`id` AS `id0`, `locations`.`address`, `locations`.`lat`, `locations`.`lng`, `locations`.`status_message_id`, `locations`.`created_at` AS `created_at0`, `locations`.`updated_at` AS `updated_at0` FROM `posts`,     `locations` WHERE `posts`.`type` = 'StatusMessage' AND `posts`.`public` = TRUE AND `posts`.`id` = `locations`.`status_message_id`;

SELECT `o_embed_caches`.`id` AS `id0`, `o_embed_caches`.`url`, `o_embed_caches`.`data`, `posts`.`id` FROM `posts`,     `o_embed_caches` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`type` = 'StatusMessage' AND `posts`.`public` = TRUE;

SELECT `posts`.`id` AS `id0`, `posts`.`author_id`, `posts`.`public`, `posts`.`guid` AS `guid0`, `posts`.`type`, `posts`.`text`, `posts`.`created_at` AS `created_at0`, `posts`.`updated_at` AS `updated_at0`, `posts`.`provider_display_name`, `posts`.`root_guid`, `posts`.`likes_count`, `posts`.`comments_count`, `posts`.`o_embed_cache_id`, `posts`.`reshares_count`, `posts`.`interacted_at`, `posts`.`tweet_id`, `posts`.`open_graph_cache_id`, `posts`.`tumblr_ids` FROM `people`,     `posts` WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT * FROM `posts` WHERE `public` = TRUE;

SELECT * FROM `users` WHERE `id` = _MY_UID;

SELECT * FROM `people` WHERE `owner_id` = _MY_UID;
