-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts`, `aspects` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id` AND `aspect_memberships`.`aspect_id` = `aspects`.`id` AND `contacts`.`receiving` = FALSE;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `aspect_memberships`.* FROM `aspect_memberships`, `contacts`, `aspects` WHERE `aspect_memberships`.`contact_id` = `contacts`.`id` AND `aspect_memberships`.`aspect_id` = `aspects`.`id` AND `contacts`.`receiving` = TRUE;

SELECT `aspects`.* FROM `aspects`;

-- NOTE: finder mock rendered without its WHERE conditions; query is broader than the app's real query
SELECT `contacts`.* FROM `contacts`;
