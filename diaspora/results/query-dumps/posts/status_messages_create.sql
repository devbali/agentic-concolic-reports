-- NOTE: query had no symbolic binds in the recorded run (all literals); verify against app code whether these should be symbolic vars
SELECT `aspects`.* FROM `aspects` WHERE `aspects`.`id` = 1;
SELECT `posts`.* FROM `posts` WHERE `posts`.`guid` = 'SYM_RESULT_Anonymous_diaspora_initialize_1_guid_v';
SELECT `posts`.* FROM `posts` WHERE `posts`.`id` = 1;
