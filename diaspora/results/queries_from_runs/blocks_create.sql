-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id`;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `contacts`.* FROM `contacts`;
