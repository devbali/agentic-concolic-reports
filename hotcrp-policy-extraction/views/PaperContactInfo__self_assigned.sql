-- PaperContactInfo::self_assigned
-- 1 of 1 atoms rendered
SELECT `contactId`, `rflags` FROM `PaperReview` WHERE `contactId` = _MY_UID AND ((`rflags` & 131072) <> 0);
