-- PaperContactInfo::conflicted
-- 1 of 1 atoms rendered
SELECT `conflictType`, `contactId` FROM `PaperConflict` WHERE `contactId` = _MY_UID AND (`conflictType` > 1);
