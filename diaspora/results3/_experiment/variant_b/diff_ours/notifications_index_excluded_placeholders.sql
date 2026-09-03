-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_commentable_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_commentable_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_mentions_container_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_mentions_container_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `people`.* FROM `people`, `mentions` WHERE `people`.`id` = `mentions`.`person_id` AND `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_profile_id
SELECT `tags`.* FROM `tags` INNER JOIN `taggings` ON `tags`.`id` = `taggings`.`tag_id` WHERE `taggings`.`taggable_id` = _assoc_profile_id AND `taggings`.`taggable_type` = 'Profile' AND `taggings`.`context` = 'tags';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_mentions_container_id
SELECT `comments`.* FROM `comments` WHERE `comments`.`id` = _assoc_target_mentions_container_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_commentable_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_commentable_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_mentions_container_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_mentions_container_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Comment';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_id
SELECT `mentions`.* FROM `mentions` WHERE `mentions`.`mentions_container_id` = _assoc_target_id AND `mentions`.`mentions_container_type` = 'Post';

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_author_id
SELECT `people`.* FROM `people` WHERE `people`.`id` = _assoc_target_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_mentions_container_commentable_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = _assoc_mentions_container_commentable_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_target_mentions_container_id
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = _assoc_target_mentions_container_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_author_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _assoc_author_id;

-- NOTE: unresolved symbolic binds kept as placeholders: _assoc_person_id
SELECT `profiles`.* FROM `profiles` WHERE `profiles`.`person_id` = _assoc_person_id;

