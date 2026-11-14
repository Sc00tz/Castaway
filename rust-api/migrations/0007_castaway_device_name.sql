-- A database taken over from the software Castaway was forked from can still hold that
-- software's name in places sync apps and the settings page show: device names ("pinepods",
-- "pinepods-server", "pinepods-<user id>", "pinepods-internal-<user id>"), device captions,
-- and the device name an external sync server knows Castaway by. Give them Castaway's name.

-- The old names, so each user's default-device setting can follow its device.
CREATE TEMP TABLE castaway_device_renames AS
SELECT userid, deviceid, devicename AS old_name FROM "GpodderDevices" WHERE devicename ~* '^pinepods';

-- 1. The old internal device becomes the user's Castaway device, unless they already have one.
UPDATE "GpodderDevices" g
SET systemrole = 'castaway',
    devicecaption = 'Castaway',
    devicename = CASE
        WHEN NOT EXISTS (SELECT 1 FROM "GpodderDevices" d WHERE d.userid = g.userid AND d.devicename = 'castaway') THEN 'castaway'
        WHEN NOT EXISTS (SELECT 1 FROM "GpodderDevices" d WHERE d.userid = g.userid AND d.devicename = 'castaway-server') THEN 'castaway-server'
        ELSE 'castaway-' || g.userid || '-' || g.deviceid
    END
WHERE g.devicename = 'pinepods-internal-' || g.userid
  AND (g.systemrole IS NULL OR g.systemrole = 'castaway')
  AND NOT EXISTS (
      SELECT 1 FROM "GpodderDevices" d
      WHERE d.userid = g.userid AND d.systemrole = 'castaway' AND d.deviceid <> g.deviceid
  );

-- 2. Every other device named after the old software: "pinepods..." becomes "castaway...", or
--    "castaway-<user id>-<device id>" when the user already has a device by that name.
UPDATE "GpodderDevices" g
SET devicename = CASE
        WHEN g.devicename ~* '^pinepods-internal-'
            THEN 'castaway-' || g.userid || '-' || g.deviceid
        WHEN NOT EXISTS (
            SELECT 1 FROM "GpodderDevices" d
            WHERE d.userid = g.userid AND d.devicename = regexp_replace(g.devicename, '^pinepods', 'castaway', 'i')
        ) THEN regexp_replace(g.devicename, '^pinepods', 'castaway', 'i')
        ELSE 'castaway-' || g.userid || '-' || g.deviceid
    END
WHERE g.devicename ~* '^pinepods';

UPDATE "GpodderDevices"
SET devicecaption = regexp_replace(devicecaption, 'pinepods', 'Castaway', 'gi')
WHERE devicecaption ~* 'pinepods';

UPDATE "Users" u
SET defaultgpodderdevice = g.devicename
FROM castaway_device_renames r
JOIN "GpodderDevices" g ON g.deviceid = r.deviceid
WHERE u.userid = r.userid AND u.defaultgpodderdevice = r.old_name;

DROP TABLE castaway_device_renames;

-- 3. An external gpodder or Nextcloud server knows Castaway by the target's device name. A new
--    name is a new device there, so the next sync sends everything again.
UPDATE "SyncTargets"
SET devicename = regexp_replace(devicename, '^pinepods', 'castaway', 'i'),
    needsfullsync = TRUE
WHERE devicename ~* '^pinepods';
