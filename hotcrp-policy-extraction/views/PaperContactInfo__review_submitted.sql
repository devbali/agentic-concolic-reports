-- PaperContactInfo::review_submitted
-- 1 of 1 atoms rendered
SELECT `contactId`, `rflags` FROM `PaperReview` WHERE `contactId` = _MY_UID AND ((`rflags` & 4096) <> 0);
