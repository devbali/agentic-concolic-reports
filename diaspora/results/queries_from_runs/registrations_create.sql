-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `blocks`.* FROM `blocks` WHERE `blocks`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_id
SELECT `blocks`.* FROM `blocks` WHERE `blocks`.`person_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_id;

SELECT `people`.* FROM `people`;

SELECT `users`.* FROM `users`;

SELECT `users`.* FROM `users` WHERE `users`.`email` = 'new@example.com';

SELECT `users`.* FROM `users` WHERE `users`.`username` = 'newuser';
