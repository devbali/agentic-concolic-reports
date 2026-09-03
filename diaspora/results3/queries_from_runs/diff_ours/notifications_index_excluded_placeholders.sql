
-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id
SELECT `conversation_visibilities`.* FROM `conversation_visibilities` WHERE `conversation_visibilities`.`person_id` = _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id;


-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id
SELECT `roles`.* FROM `roles` WHERE `roles`.`name` IN ('moderator', 'admin') AND `roles`.`person_id` = _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id;


-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id
SELECT `roles`.* FROM `roles` WHERE `roles`.`person_id` = _SYM_RESULT_ActiveRecord__FinderMethods_first_1_person_id AND `roles`.`name` = `admin`;
