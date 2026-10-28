SELECT `likes`.* FROM `likes`, `people`, `posts`, `people` AS `people0` WHERE `likes`.`author_id` = `people`.`id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE;

SELECT `participations`.* FROM `participations`, `people`, `posts`, `people` AS `people0` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`text` <> '';

SELECT `participations`.* FROM `participations`, `people`, `posts`, `people` AS `people0` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`text` = '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` <> '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` = '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` <> '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` = '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`text` <> '';

SELECT `people`.* FROM `people`, `comments`, `posts`, `people` AS `people0` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people0`.`id` AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`text` = '';

SELECT `people`.* FROM `people`, `likes`, `posts`, `people` AS `people0` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`text` <> '';

SELECT `people`.* FROM `people`, `likes`, `posts`, `people` AS `people0` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE AND `posts`.`text` = '';

SELECT `comments`.* FROM `comments`, `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` <> '';

SELECT `comments`.* FROM `comments`, `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` = '';

SELECT `comments`.* FROM `comments`, `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` <> '';

SELECT `comments`.* FROM `comments`, `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` = '';

SELECT `comments`.* FROM `comments`, `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`text` <> '';

SELECT `comments`.* FROM `comments`, `posts`, `people` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = `people`.`id` AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`comments_count` <> 0 AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `likes`.* FROM `likes`, `people`, `posts` WHERE `likes`.`author_id` = `people`.`id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `likes`.* FROM `likes`, `people`, `posts` WHERE `likes`.`author_id` = `people`.`id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

SELECT `likes`.* FROM `likes`, `posts`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`text` <> '';

SELECT `likes`.* FROM `likes`, `posts`, `people` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE AND `posts`.`text` = '';

SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts`, `people` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE;

SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts`, `people` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `participations`.* FROM `participations`, `people`, `posts` WHERE `participations`.`author_id` = `people`.`id` AND `participations`.`target_id` = `posts`.`id` AND `people`.`owner_id` = _MY_UID AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `people`.* FROM `people`, `likes`, `posts` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `people`.* FROM `people`, `likes`, `posts` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people`, `likes`, `posts` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people`, `likes`, `posts` WHERE `people`.`id` = `likes`.`author_id` AND `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` = '';

SELECT `people`.* FROM `people`, `posts`, `people` AS `people0` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`author_id` = `people0`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people0`.`closed_account` = FALSE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` <> '' AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`guid` = '' AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`comments_count` <> 0 AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` <> '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `likes`.* FROM `likes`, `posts` WHERE `likes`.`target_id` = `posts`.`id` AND `likes`.`target_type` = 'Post' AND `likes`.`positive` = TRUE AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `posts`.`text` = '';

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `o_embed_caches`.* FROM `o_embed_caches`, `posts` WHERE `o_embed_caches`.`id` = `posts`.`o_embed_cache_id` AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `open_graph_caches`.* FROM `open_graph_caches`, `posts` WHERE `open_graph_caches`.`id` = `posts`.`open_graph_cache_id` AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `people`.* FROM `people`, `posts` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `people`.* FROM `people`, `posts` WHERE `people`.`id` = `posts`.`author_id` AND `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

SELECT `posts`.* FROM `posts`, `people` WHERE `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE;

SELECT `people`.* FROM `people`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _SYM_RESULT_ActiveRecord__FinderMethods_find_by_2_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');
