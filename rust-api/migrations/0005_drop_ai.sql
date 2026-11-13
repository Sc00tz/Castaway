-- Castaway has no AI features: no generated transcripts, ad detection or AI settings.
-- Feed transcripts and silence trimming stay.
DROP TABLE "EpisodeAdSkipReview";
DROP TABLE "AISettings";
DELETE FROM "EpisodeSkipSegments" WHERE kind = 'ad';
DELETE FROM "EpisodeTranscripts" WHERE source <> 'feed';
ALTER TABLE "EpisodeTranscripts" ALTER COLUMN source SET DEFAULT 'feed';
ALTER TABLE "EpisodeTranscripts" DROP COLUMN model, DROP COLUMN audiofingerprint, DROP COLUMN audioduration, DROP COLUMN audiosource;
ALTER TABLE "Episodes" DROP COLUMN adsdetected;
ALTER TABLE "Podcasts" DROP COLUMN autotranscribe, DROP COLUMN autoaddetect, DROP COLUMN adskipautoactivate;
ALTER TABLE "DownloadedEpisodes" DROP COLUMN audiofingerprint;
