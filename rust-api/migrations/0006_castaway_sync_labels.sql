-- The server's own sync device and the changes it records were labelled 'pinepods'; they're
-- 'castaway' now.
UPDATE "GpodderDevices" SET systemrole = 'castaway' WHERE systemrole = 'pinepods';
UPDATE "GpodderSyncEpisodeActions" SET origin = 'castaway' WHERE origin = 'pinepods';
UPDATE "GpodderSyncSubscriptions" SET origin = 'castaway' WHERE origin = 'pinepods';
UPDATE "SyncImportFailures" SET origin = 'castaway' WHERE origin = 'pinepods';
