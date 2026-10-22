-- Contact::can_set_decision
-- 1 of 1 atoms rendered
SELECT `ContactInfo`.`contactId`, `ContactInfo`.`roles`, `PaperConflict`.`conflictType` FROM `ContactInfo` JOIN `PaperConflict` ON `ContactInfo`.`contactId` = `PaperConflict`.`contactId` WHERE `ContactInfo`.`contactId` = _MY_UID AND (`PaperConflict`.`conflictType` <= 1 AND (`ContactInfo`.`roles` & 15) <> 0 AND (`ContactInfo`.`roles` & 4) <> 0);
