SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE;

SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `posts`.`public` = TRUE;

SELECT `posts`.* FROM `posts`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_1_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_first_1_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_retry_1_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_json_retry_1_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_msg_first_1_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_mention_lookup_msg_first_1_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_author_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _assoc_author_id;
