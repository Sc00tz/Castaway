-- Castaway searches Podcast Index directly with the admin's own API key (the secret is stored
-- encrypted with AppSettings.EncryptionKey). Podping, which came through PinePods' relay, is gone.
ALTER TABLE "AppSettings"
    ADD COLUMN podcastindexapikey TEXT,
    ADD COLUMN podcastindexapisecret TEXT,
    DROP COLUMN IF EXISTS podpingenabled;
