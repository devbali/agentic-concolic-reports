SELECT `posts`.* FROM `posts`, `people` WHERE `posts`.`author_id` = `people`.`id` AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare') AND `people`.`closed_account` = FALSE;

SELECT `people`.* FROM `people`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`author_id` = _SYM_PERSON_via_user_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');

SELECT `posts`.* FROM `posts` WHERE `posts`.`public` = TRUE AND `posts`.`created_at` < _NOW AND `posts`.`type` IN ('StatusMessage', 'Reshare');
