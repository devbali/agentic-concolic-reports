SELECT `taggings`.* FROM `taggings` INNER JOIN `tags` ON `tags`.`id` = `taggings`.`tag_id` GROUP BY `tag`;

SELECT `aspect_memberships`.* FROM `aspect_memberships` WHERE `aspect_memberships`.`created_at` BETWEEN _NOW AND _NOW;

SELECT `comments`.* FROM `comments` WHERE `comments`.`created_at` BETWEEN _NOW AND _NOW;

SELECT `posts`.* FROM `posts` WHERE (`posts`.`created_at` >= '2026-07-25') GROUP BY DATE(`created_at`);

SELECT `posts`.* FROM `posts` WHERE `posts`.`created_at` BETWEEN _NOW AND _NOW;

SELECT `roles`.* FROM `roles`;

SELECT `users`.* FROM `users`;

SELECT `users`.* FROM `users` WHERE `users`.`created_at` BETWEEN _NOW AND _NOW;
