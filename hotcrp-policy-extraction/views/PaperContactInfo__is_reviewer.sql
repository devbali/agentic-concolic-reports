-- PaperContactInfo::is_reviewer
-- 1 of 1 atoms rendered
SELECT `contactId`, `reviewType` FROM `PaperReview` WHERE `contactId` = _MY_UID AND (`reviewType` > 0);
