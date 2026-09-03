SELECT `photos`.* FROM `photos`, `people` WHERE `photos`.`author_id` = `people`.`id` AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE AND `people`.`closed_account` = FALSE;

SELECT `people`.* FROM `people`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `photos`.* FROM `photos` WHERE `photos`.`author_id` = _SYM_PERSON_via_user_id AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE;
