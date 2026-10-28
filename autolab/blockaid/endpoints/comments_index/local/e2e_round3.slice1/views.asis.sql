SELECT `people`.* FROM `people`, `mentions`, `comments`, `posts` WHERE `people`.`id` = `mentions`.`person_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment';
SELECT `profiles`.* FROM `profiles`, `mentions`, `comments`, `posts` WHERE `profiles`.`person_id` = `mentions`.`person_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post' AND `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment';
SELECT `mentions`.* FROM `mentions`, `comments`, `posts` WHERE `mentions`.`mentions_container_id` = `comments`.`id` AND `mentions`.`mentions_container_type` = 'Comment' AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post';
SELECT `people`.* FROM `people`, `comments`, `posts` WHERE `people`.`id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post';
SELECT `profiles`.* FROM `profiles`, `comments`, `posts` WHERE `profiles`.`person_id` = `comments`.`author_id` AND `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post';
SELECT `comments`.* FROM `comments`, `posts` WHERE `comments`.`commentable_id` = `posts`.`id` AND `comments`.`commentable_type` = 'Post';
SELECT 1 AS one FROM `posts`;
SELECT `posts`.* FROM `posts`;
