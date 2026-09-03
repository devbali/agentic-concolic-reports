-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspects`.* FROM `aspects` INNER JOIN `aspect_memberships` ON `aspects`.`id` = `aspect_memberships`.`aspect_id`, `contacts` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id` AND 1 = 0;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `contacts`.* FROM `contacts`;

SELECT `people`.* FROM `people`;
