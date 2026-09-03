-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_profile_id
SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id` WHERE `taggings`.`taggable_id` = _assoc_profile_id AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags';
