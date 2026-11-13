-- Castaway doesn't use PodPeopleDB (people.pinepods.online): hosts and guests come from each
-- feed's own <podcast:person> tags, and a person's other shows from Podcast Index.
DELETE FROM "PodcastPeople" WHERE source <> 'feed';
DELETE FROM "EpisodePeople" WHERE source <> 'feed';
DELETE FROM "PersonExternalEpisodes" WHERE source <> 'index';
ALTER TABLE "PodcastPeople" DROP COLUMN verified;
ALTER TABLE "EpisodePeople" DROP COLUMN verified;
ALTER TABLE "Persons" DROP COLUMN podpeopleid;
