-- Castaway's own themes (2026-11-19): "Castaway Dark" (navy) is the default for new
-- accounts, and accounts still on the untouched default inherited from the software
-- Castaway was forked from ("Nordic") move to it. Accounts that chose any other theme keep it.
ALTER TABLE "UserSettings" ALTER COLUMN theme SET DEFAULT 'Castaway Dark';
UPDATE "UserSettings" SET theme = 'Castaway Dark' WHERE theme = 'Nordic' OR theme IS NULL;
