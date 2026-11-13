//! Local (file-based) podcasts.

use super::*;

impl DatabasePool {
    // =========================================================
    // Local Podcast Functions
    // =========================================================

    pub async fn local_podcast_exists(&self, feed_url: &str, user_id: i32) -> AppResult<bool> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"SELECT 1 FROM "Podcasts" WHERE feedurl = $1 AND userid = $2"#)
                    .bind(feed_url)
                    .bind(user_id)
                    .fetch_optional(pool)
                    .await?;
                Ok(row.is_some())
            },
        })
    }

    pub async fn add_local_podcast(
        &self,
        podcast_name: &str,
        feed_url: &str,
        description: &str,
        author: &str,
        artwork_url: &str,
        explicit: bool,
        user_id: i32,
    ) -> AppResult<i32> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(
                    r#"INSERT INTO "Podcasts"
                       (podcastname, artworkurl, author, categories, description, episodecount,
                        feedurl, websiteurl, explicit, userid, feedcutoffdays, podcastindexid)
                       VALUES ($1, $2, $3, $4, $5, 0, $6, '', $7, $8, 0, 0)
                       RETURNING podcastid"#,
                )
                .bind(podcast_name)
                .bind(artwork_url)
                .bind(author)
                .bind("{}") // empty categories JSON
                .bind(description)
                .bind(feed_url)
                .bind(explicit)
                .bind(user_id)
                .fetch_one(pool)
                .await?;

                let podcast_id: i32 = row.try_get("podcastid")?;

                q::query(r#"UPDATE "UserStats" SET podcastsadded = podcastsadded + 1 WHERE userid = $1"#)
                    .bind(user_id)
                    .execute(pool)
                    .await?;

                self.link_feed_or_warn(podcast_id).await;
                Ok(podcast_id)
            },
        })
    }

    pub async fn add_local_episodes(
        &self,
        podcast_id: i32,
        user_id: i32,
        candidates: &[crate::handlers::local_podcast::LocalEpisodeCandidate],
    ) -> AppResult<Vec<(usize, i32)>> {
        let feed_id = self.feed_of_podcast(podcast_id).await?;
        // (index into `candidates`, episode id) of the episodes this call inserted.
        let mut inserted = Vec::new();
        for (index, candidate) in candidates.iter().enumerate() {
            let episode_url = format!("local://{}", candidate.file_path);
            let artwork = candidate.artwork_url.as_deref().unwrap_or("");

            let episode_id = dialect_match!(self, {
                pg(pool) => {
                    // Skip if already exists
                    let existing = q::query(r#"SELECT episodeid FROM "Episodes" WHERE feedid = $1 AND episodeurl = $2"#)
                        .bind(feed_id)
                        .bind(&episode_url)
                        .fetch_optional(pool)
                        .await?;
                    if let Some(row) = existing {
                        row.try_get::<i32, _>("episodeid")?
                    } else {
                        let row = q::query(
                            r#"INSERT INTO "Episodes"
                               (podcastid, feedid, episodetitle, episodedescription, episodeurl, episodeartwork, episodepubdate, episodeduration)
                               VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                               RETURNING episodeid"#,
                        )
                        .bind(podcast_id)
                        .bind(feed_id)
                        .bind(&candidate.title)
                        .bind(&candidate.description)
                        .bind(&episode_url)
                        .bind(artwork)
                        .bind(candidate.pub_date)
                        .bind(candidate.duration)
                        .fetch_one(pool)
                        .await?;
                        let id = row.try_get::<i32, _>("episodeid")?;
                        inserted.push((index, id));
                        id
                    }
                },
            });

            // Get file size for DownloadedEpisodes
            let file_size = std::fs::metadata(&candidate.file_path)
                .map(|m| m.len() as i64)
                .unwrap_or(0);

            // Insert into DownloadedEpisodes so stream_episode() can serve the file
            dialect_match!(self, {
                pg(pool) => {
                    // Only insert if not already there
                    let existing = q::query(r#"SELECT 1 FROM "DownloadedEpisodes" WHERE userid = $1 AND episodeid = $2"#)
                        .bind(user_id)
                        .bind(episode_id)
                        .fetch_optional(pool)
                        .await?;
                    if existing.is_none() {
                        q::query(r#"INSERT INTO "DownloadedEpisodes" (userid, episodeid, downloadedsize, downloadedlocation) VALUES ($1, $2, $3, $4)"#)
                            .bind(user_id)
                            .bind(episode_id)
                            .bind(file_size)
                            .bind(&candidate.file_path)
                            .execute(pool)
                            .await?;
                    }
                },
            })
        }

        self.update_episode_count(podcast_id).await?;
        Ok(inserted)
    }

    pub async fn get_feed_url_for_podcast(
        &self,
        podcast_id: i32,
        user_id: i32,
    ) -> AppResult<Option<String>> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"SELECT feedurl FROM "Podcasts" WHERE podcastid = $1 AND userid = $2"#)
                    .bind(podcast_id)
                    .bind(user_id)
                    .fetch_optional(pool)
                    .await?;
                Ok(row.and_then(|r| r.try_get::<String, _>("feedurl").ok()))
            },
        })
    }

    pub async fn get_feed_url_for_episode(
        &self,
        episode_id: i32,
    ) -> AppResult<Option<String>> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(
                    r#"SELECT p.feedurl FROM "Episodes" e
                       JOIN "Podcasts" p ON e.feedid = p.feedid
                       WHERE e.episodeid = $1 LIMIT 1"#,
                )
                .bind(episode_id)
                .fetch_optional(pool)
                .await?;
                Ok(row.and_then(|r| r.try_get::<String, _>("feedurl").ok()))
            },
        })
    }

    pub async fn get_local_episode_paths(
        &self,
        podcast_id: i32,
    ) -> AppResult<Vec<String>> {
        dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(
                    r#"SELECT de.downloadedlocation FROM "DownloadedEpisodes" de
                       JOIN "Episodes" e ON de.episodeid = e.episodeid
                       WHERE e.feedid = (SELECT feedid FROM "Podcasts" WHERE podcastid = $1)"#,
                )
                .bind(podcast_id)
                .fetch_all(pool)
                .await?;
                Ok(rows
                    .iter()
                    .filter_map(|r| r.try_get::<String, _>("downloadedlocation").ok())
                    .collect())
            },
        })
    }

    pub async fn update_podcast_artwork(
        &self,
        podcast_id: i32,
        user_id: i32,
        artwork_url: &str,
    ) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                q::query(r#"UPDATE "Podcasts" SET artworkurl = $1 WHERE podcastid = $2 AND userid = $3"#)
                    .bind(artwork_url)
                    .bind(podcast_id)
                    .bind(user_id)
                    .execute(pool)
                    .await?;
            },
        });
        Ok(())
    }
}
