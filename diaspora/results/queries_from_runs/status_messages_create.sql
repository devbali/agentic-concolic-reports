-- NOTE: unresolved symbolic binds kept as placeholders: _SYM_RESULT_Anonymous_diaspora_initialize_1_id
SELECT DISTINCT `contacts`.* FROM `contacts` INNER JOIN `aspect_memberships` ON `aspect_memberships`.`contact_id` = `contacts`.`id` WHERE `aspect_memberships`.`aspect_id` IN (SELECT `aspects`.`id` FROM `aspects` INNER JOIN `aspect_visibilities` ON `aspects`.`id` = `aspect_visibilities`.`aspect_id` WHERE `aspect_visibilities`.`shareable_id` = _SYM_RESULT_Anonymous_diaspora_initialize_1_id AND `aspect_visibilities`.`shareable_type` = 'Post' AND (1 = 0));

SELECT `aspects`.* FROM `aspects`;
