-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id`;

SELECT `photos`.* FROM `photos`, `people` WHERE `photos`.`author_id` = `people`.`id` AND `photos`.`created_at` < _NOW AND `photos`.`pending` = FALSE AND `people`.`owner_id` = _MY_UID;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `blocks`.* FROM `blocks`;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `contacts`.* FROM `contacts`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id
SELECT `photos`.* FROM `photos` WHERE `photos`.`author_id` = _SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_id AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE;
