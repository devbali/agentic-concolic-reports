SELECT `photos`.* FROM `photos`, `people` WHERE `photos`.`author_id` = `people`.`id` AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE AND `people`.`closed_account` = FALSE;

SELECT `profiles`.* FROM `profiles`, `people` WHERE `profiles`.`person_id` = `people`.`id` AND `people`.`closed_account` = FALSE;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_profile_id
SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id` WHERE `taggings`.`taggable_id` = _assoc_profile_id AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags' AND 1 = 0;

SELECT `people`.* FROM `people`;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `photos`.* FROM `photos` WHERE `photos`.`author_id` = _SYM_PERSON_via_user_id AND `photos`.`public` = TRUE AND `photos`.`pending` = FALSE;

-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_PERSON_via_user_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _SYM_PERSON_via_user_id;
