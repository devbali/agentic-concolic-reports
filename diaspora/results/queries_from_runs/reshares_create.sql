-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_Anonymous_diaspora_initialize_1_id
SELECT `participations`.* FROM `participations`, `people` WHERE `participations`.`target_id` = _SYM_RESULT_Anonymous_diaspora_initialize_1_id AND `participations`.`target_type` = 'Post' AND `participations`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

SELECT `posts`.* FROM `posts` INNER JOIN `share_visibilities` ON `share_visibilities`.`shareable_id` = `posts`.`id` AND `share_visibilities`.`shareable_type` = 'Post' WHERE `share_visibilities`.`user_id` = _MY_UID;

SELECT `posts`.* FROM `posts`, `people` WHERE `posts`.`author_id` = `people`.`id` AND `people`.`owner_id` = _MY_UID;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_Anonymous_diaspora_initialize_1_id
SELECT `comments`.* FROM `comments` WHERE `comments`.`commentable_id` = _SYM_RESULT_Anonymous_diaspora_initialize_1_id AND `comments`.`commentable_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_row_id
SELECT `likes`.* FROM `likes` WHERE `likes`.`target_id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_row_id AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_Anonymous_diaspora_initialize_1_id
SELECT `likes`.* FROM `likes` WHERE `likes`.`target_id` = _SYM_RESULT_Anonymous_diaspora_initialize_1_id AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_id
SELECT `likes`.* FROM `likes` WHERE `likes`.`target_id` = _assoc_root_id AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `participations`.* FROM `participations`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_row_id
SELECT `participations`.* FROM `participations` WHERE `participations`.`target_id` = _SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_row_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_Anonymous_diaspora_initialize_1_id
SELECT `participations`.* FROM `participations` WHERE `participations`.`target_id` = _SYM_RESULT_Anonymous_diaspora_initialize_1_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_root_id
SELECT `participations`.* FROM `participations` WHERE `participations`.`target_id` = _assoc_root_id;

SELECT `posts`.* FROM `posts` WHERE `posts`.`public` = TRUE;
