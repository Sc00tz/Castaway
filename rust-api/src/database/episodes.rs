//! Episode lookups, completion state and listen tracking.

use super::*;

// Whether a user finished episodes, kept per user in UserEpisodeState. Only episodes of feeds
// the user subscribes to change; returns how many those were.
dialect_fn!([set_completed_pg]
    pub(super) async fn(conn: &mut q::Conn, user_id: i32, episode_ids: &[i32], completed: bool) -> AppResult<u64> {
    let changed = q::query(
        r#"INSERT INTO "UserEpisodeState" (userid, episodeid, completed, completedat)
           SELECT DISTINCT $1, e.episodeid, $3, CASE WHEN $3 THEN NOW() END
           FROM "Episodes" e JOIN "Podcasts" p ON p.feedid = e.feedid AND p.userid = $1
           WHERE e.episodeid = ANY($2)
           ON CONFLICT (userid, episodeid) DO UPDATE SET completed = EXCLUDED.completed, completedat = EXCLUDED.completedat"#,
    )
    .bind(user_id)
    .bind(episode_ids)
    .bind(completed)
    .execute(&mut *conn)
    .await?;
    Ok(changed.rows_affected())
});

impl DatabasePool {
    // Get episodes for user - paginated with optional since filter
    pub async fn return_episodes(
        &self,
        user_id: i32,
        limit: i64,
        offset: i64,
        since: chrono::NaiveDateTime,
    ) -> AppResult<(Vec<crate::handlers::podcasts::Episode>, i64)> {
        dialect_match!(self, {
            pg(pool) => {
                // COUNT(*) OVER() returns the pre-LIMIT total in every row — no second query needed.
                // Since is always bound; epoch (1970-01-01) makes the clause a no-op when omitted.
                let rows = q::query(
                    r#"SELECT *, COUNT(*) OVER() AS total_count FROM (
                        SELECT
                            "Podcasts".podcastid as podcastid,
                            "Podcasts".podcastname as podcastname,
                            "Episodes".episodetitle as episodetitle,
                            "Episodes".episodepubdate as episodepubdate,
                            "Episodes".episodedescription as episodedescription,
                            CASE
                                WHEN "Podcasts".usepodcastcoverscustomized = TRUE AND "Podcasts".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                                WHEN "Users".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                                ELSE "Episodes".episodeartwork
                            END as episodeartwork,
                            "Episodes".episodeurl as episodeurl,
                            "Episodes".episodeduration as episodeduration,
                            "UserEpisodeHistory".listenduration as listenduration,
                            "Episodes".episodeid as episodeid,
                            COALESCE((SELECT ues.completed FROM "UserEpisodeState" ues WHERE ues.episodeid = "Episodes".episodeid AND ues.userid = "Podcasts".userid), FALSE) as completed,
                            CASE WHEN "SavedEpisodes".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS saved,
                            CASE WHEN "EpisodeQueue".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS queued,
                            CASE WHEN "DownloadedEpisodes".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS downloaded,
                            FALSE as is_youtube,
                            "Episodes".is_video as is_video
                        FROM "Episodes"
                        INNER JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid
                        LEFT JOIN "Users" ON "Podcasts".userid = "Users".userid
                        LEFT JOIN "UserEpisodeHistory" ON
                            "Episodes".episodeid = "UserEpisodeHistory".episodeid
                            AND "UserEpisodeHistory".userid = $1
                        LEFT JOIN "SavedEpisodes" ON
                            "Episodes".episodeid = "SavedEpisodes".episodeid
                            AND "SavedEpisodes".userid = $1
                        LEFT JOIN "EpisodeQueue" ON
                            "Episodes".episodeid = "EpisodeQueue".episodeid
                            AND "EpisodeQueue".userid = $1
                            AND "EpisodeQueue".is_youtube = FALSE
                        LEFT JOIN "DownloadedEpisodes" ON
                            "Episodes".episodeid = "DownloadedEpisodes".episodeid
                            AND "DownloadedEpisodes".userid = $1
                        WHERE "Episodes".episodepubdate >= NOW() - INTERVAL '30 days'
                        AND "Episodes".episodepubdate > $6
                        AND "Podcasts".userid = $1

                        UNION ALL

                        SELECT
                            "YouTubeVideos".podcastid as podcastid,
                            "Podcasts".podcastname as podcastname,
                            "YouTubeVideos".videotitle as episodetitle,
                            "YouTubeVideos".publishedat as episodepubdate,
                            "YouTubeVideos".videodescription as episodedescription,
                            CASE
                                WHEN "Podcasts".usepodcastcoverscustomized = TRUE AND "Podcasts".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                                WHEN "Users".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                                ELSE "YouTubeVideos".thumbnailurl
                            END as episodeartwork,
                            "YouTubeVideos".videourl as episodeurl,
                            "YouTubeVideos".duration as episodeduration,
                            "YouTubeVideos".listenposition as listenduration,
                            "YouTubeVideos".videoid as episodeid,
                            "YouTubeVideos".completed as completed,
                            CASE WHEN "SavedVideos".videoid IS NOT NULL THEN TRUE ELSE FALSE END AS saved,
                            CASE WHEN "EpisodeQueue".episodeid IS NOT NULL AND "EpisodeQueue".is_youtube = TRUE THEN TRUE ELSE FALSE END AS queued,
                            CASE WHEN "DownloadedVideos".videoid IS NOT NULL THEN TRUE ELSE FALSE END AS downloaded,
                            TRUE as is_youtube,
                            TRUE as is_video
                        FROM "YouTubeVideos"
                        INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                        LEFT JOIN "Users" ON "Podcasts".userid = "Users".userid
                        LEFT JOIN "SavedVideos" ON
                            "YouTubeVideos".videoid = "SavedVideos".videoid
                            AND "SavedVideos".userid = $2
                        LEFT JOIN "EpisodeQueue" ON
                            "YouTubeVideos".videoid = "EpisodeQueue".episodeid
                            AND "EpisodeQueue".userid = $3
                            AND "EpisodeQueue".is_youtube = TRUE
                        LEFT JOIN "DownloadedVideos" ON
                            "YouTubeVideos".videoid = "DownloadedVideos".videoid
                            AND "DownloadedVideos".userid = $4
                        WHERE "YouTubeVideos".publishedat >= NOW() - INTERVAL '30 days'
                        AND "YouTubeVideos".publishedat > $7
                        AND "Podcasts".userid = $5
                    ) combined
                    ORDER BY episodepubdate DESC
                    LIMIT $8 OFFSET $9"#
                )
                .bind(user_id)   // $1 — episodes branch user joins
                .bind(user_id)   // $2 — youtube SavedVideos
                .bind(user_id)   // $3 — youtube EpisodeQueue
                .bind(user_id)   // $4 — youtube DownloadedVideos
                .bind(user_id)   // $5 — youtube Podcasts.userid WHERE
                .bind(since)     // $6 — episodes since filter (epoch = no-op)
                .bind(since)     // $7 — youtube since filter
                .bind(limit)     // $8
                .bind(offset)    // $9
                .fetch_all(pool)
                .await?;

                let total: i64 = rows.first()
                    .and_then(|r| r.try_get::<i64, _>("total_count").ok())
                    .unwrap_or(0);

                let mut episodes = Vec::new();
                for row in rows {
                    episodes.push(crate::handlers::podcasts::Episode {
                        podcastid: row.try_get("podcastid")?,
                        podcastname: row.try_get("podcastname")?,
                        episodetitle: row.try_get("episodetitle")?,
                        episodepubdate: {
                            let naive = row.try_get::<chrono::NaiveDateTime, _>("episodepubdate")?;
                            naive.format("%Y-%m-%dT%H:%M:%S").to_string()
                        },
                        episodedescription: row.try_get("episodedescription")?,
                        episodeartwork: row.try_get("episodeartwork")?,
                        episodeurl: row.try_get("episodeurl")?,
                        episodeduration: row.try_get("episodeduration")?,
                        listenduration: row.try_get("listenduration").ok(),
                        episodeid: row.try_get("episodeid")?,
                        completed: row.try_get("completed")?,
                        saved: row.try_get("saved")?,
                        queued: row.try_get("queued")?,
                        downloaded: row.try_get("downloaded")?,
                        is_youtube: row.try_get("is_youtube")?,
                        is_video: row.try_get("is_video")?,
                    });
                }
                Ok((episodes, total))
            },
        })
    }

    /// True if `episode_id` (a `YouTubeVideos.videoid` when `is_youtube`) sits in one of
    /// `user_id`'s podcasts. Every podcast/episode row is per-user, so this is the ownership
    /// test for anything addressed by episode id.
    pub async fn episode_belongs_to_user(&self, episode_id: i32, user_id: i32, is_youtube: bool) -> AppResult<bool> {
        let found = dialect_match!(self, {
            pg(pool) => {
                let sql = if is_youtube {
                    r#"SELECT 1 FROM "YouTubeVideos" v JOIN "Podcasts" p ON p.podcastid = v.podcastid
                       WHERE v.videoid = $1 AND p.userid = $2 LIMIT 1"#
                } else {
                    r#"SELECT 1 FROM "Episodes" e JOIN "Podcasts" p ON p.feedid = e.feedid
                       WHERE e.episodeid = $1 AND p.userid = $2 LIMIT 1"#
                };
                q::query(sql).bind(episode_id).bind(user_id).fetch_optional(pool).await?.is_some()
            },
        });
        Ok(found)
    }

    // Get time info for user - matches Python get_time_info function
    pub async fn get_time_info(&self, user_id: i32) -> AppResult<crate::models::TimeInfoResponse> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(
                    r#"SELECT COALESCE(timezone, 'UTC') as timezone, 
                              COALESCE(timeformat, 12) as hour_pref,
                              dateformat as date_format
                       FROM "Users" WHERE userid = $1"#
                )
                .bind(user_id)
                .fetch_one(pool)
                .await?;
                
                Ok(crate::models::TimeInfoResponse {
                    timezone: row.try_get("timezone")?,
                    hour_pref: row.try_get("hour_pref")?,
                    date_format: row.try_get("date_format").ok(),
                })
            },
        })
    }

    // Check if episode exists in database - matches Python check_episode_exists function
    pub async fn check_episode_exists(&self, user_id: i32, episode_title: &str, episode_url: &str) -> AppResult<bool> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(
                    r#"SELECT EXISTS(
                        SELECT 1 FROM "Episodes"
                        JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid
                        WHERE "Podcasts".userid = $1 
                          AND "Episodes".episodetitle = $2 
                          AND "Episodes".episodeurl = $3
                    ) as episode_exists"#
                )
                .bind(user_id)
                .bind(episode_title)
                .bind(episode_url)
                .fetch_one(pool)
                .await?;
                
                Ok(row.try_get("episode_exists")?)
            },
        })
    }

    pub async fn update_episode_duration(&self, episode_id: i32, new_duration: i32, is_youtube: bool) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                if is_youtube {
                    q::query(r#"UPDATE "YouTubeVideos" SET duration = $1 WHERE videoid = $2"#)
                        .bind(new_duration)
                        .bind(episode_id)
                        .execute(pool)
                        .await?;
                } else {
                    q::query(r#"UPDATE "Episodes" SET episodeduration = $1 WHERE episodeid = $2"#)
                        .bind(new_duration)
                        .bind(episode_id)
                        .execute(pool)
                        .await?;
                }
            },
        });
        Ok(())
    }

    // Mark episode as completed - matches Python mark_episode_completed function
    pub async fn mark_episode_completed(&self, episode_id: i32, user_id: i32, is_youtube: bool, origin: crate::services::sync::SyncOrigin) -> AppResult<()> {
        // Completing an episode also removes it from the queue (if present) so a
        // finished item never lingers in "up next". Runs for both podcast and
        // YouTube completions; no-op when not queued. Doing this here makes queue
        // removal reliable regardless of which client auto-advance path fired.
        self.remove_queued_episode(episode_id, user_id, is_youtube).await?;
        let log = !is_youtube && crate::services::sync::events::should_log(self, user_id, origin).await;

        dialect_match!(self, {
            pg(pool) => {
                if is_youtube {
                    // Get YouTube video duration
                    let duration_row = q::query(
                        r#"SELECT duration FROM "YouTubeVideos" WHERE videoid = $1"#
                    )
                    .bind(episode_id)
                    .fetch_optional(pool)
                    .await?;

                    if let Some(row) = duration_row {
                        let duration: Option<i32> = row.try_get("duration").ok();
                        
                        if let Some(duration) = duration {
                            // Update completion status
                            q::query(
                                r#"UPDATE "YouTubeVideos" SET completed = TRUE WHERE videoid = $1"#
                            )
                            .bind(episode_id)
                            .execute(pool)
                            .await?;

                            // Update history
                            q::query(
                                // The app's UTC clock, like every other position write: the
                                // newest position wins, so all of them must share one clock.
                                r#"INSERT INTO "UserVideoHistory" (userid, videoid, listendate, listenduration)
                                   VALUES ($1, $2, $5, $3)
                                   ON CONFLICT (userid, videoid)
                                   DO UPDATE SET listenduration = $4, listendate = $5"#
                            )
                            .bind(user_id)
                            .bind(episode_id)
                            .bind(duration)
                            .bind(duration)
                            .bind(Self::position_time(None))
                            .execute(pool)
                            .await?;
                        }
                    }
                } else {
                    // Get episode duration
                    let duration_row = q::query(
                        r#"SELECT episodeduration FROM "Episodes" WHERE episodeid = $1"#
                    )
                    .bind(episode_id)
                    .fetch_optional(pool)
                    .await?;

                    if let Some(row) = duration_row {
                        let duration: Option<i32> = row.try_get("episodeduration").ok();
                        
                        if let Some(duration) = duration {
                            let mut tx = q::begin(pool).await?;
                            // Update completion status
                            set_completed_pg(&mut tx, user_id, &[episode_id], true).await?;

                            // Update history
                            q::query(
                                // The app's UTC clock, like every other position write: the
                                // newest position wins, so all of them must share one clock.
                                r#"INSERT INTO "UserEpisodeHistory" (userid, episodeid, listendate, listenduration)
                                   VALUES ($1, $2, $5, $3)
                                   ON CONFLICT (userid, episodeid)
                                   DO UPDATE SET listenduration = $4, listendate = $5"#
                            )
                            .bind(user_id)
                            .bind(episode_id)
                            .bind(duration)
                            .bind(duration)
                            .bind(Self::position_time(None))
                            .execute(&mut *tx)
                            .await?;
                            if log {
                                crate::services::sync::events::episode_pg(self, &mut tx, user_id, episode_id, crate::services::sync::events::EpisodeEvent::Completed).await;
                            }
                            tx.commit().await?;
                        }
                    }
                }
                Ok(())
            },
        })
    }

    // Increment played count - matches Python increment_played function
    pub async fn increment_played(&self, user_id: i32) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                q::query(
                    r#"UPDATE "UserStats" SET podcastsplayed = podcastsplayed + 1 WHERE userid = $1"#
                )
                .bind(user_id)
                .execute(pool)
                .await?;
                Ok(())
            },
        })
    }

    // Get podcast ID from episode ID - matches Python get_podcast_id_from_episode function
    pub async fn get_podcast_id_from_episode(&self, episode_id: i32, user_id: i32, is_youtube: bool) -> AppResult<Option<i32>> {
        dialect_match!(self, {
            pg(pool) => {
                let query = if is_youtube {
                    r#"SELECT "YouTubeVideos".podcastid
                       FROM "YouTubeVideos"
                       INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                       WHERE "YouTubeVideos".videoid = $1 AND "Podcasts".userid = $2"#
                } else {
                    r#"SELECT "Podcasts".podcastid
                       FROM "Episodes" 
                       INNER JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid
                       WHERE "Episodes".episodeid = $1 AND "Podcasts".userid = $2"#
                };

                // First try with provided user_id
                let row = q::query(query)
                    .bind(episode_id)
                    .bind(user_id)
                    .fetch_optional(pool)
                    .await?;

                if let Some(row) = row {
                    return Ok(Some(row.try_get("podcastid")?));
                }

                // If not found, try with system user (1)
                let row = q::query(query)
                    .bind(episode_id)
                    .bind(1)
                    .fetch_optional(pool)
                    .await?;

                if let Some(row) = row {
                    Ok(Some(row.try_get("podcastid")?))
                } else {
                    Ok(None)
                }
            },
        })
    }

    // Get episode ID from episode URL - public version of find_episode_by_url
    pub async fn get_episode_id_from_url(&self, episode_url: &str, user_id: i32) -> AppResult<Option<i32>> {
        self.find_episode_by_url(user_id, episode_url).await
    }

    // Mark episode as uncompleted - matches Python mark_episode_uncompleted function
    pub async fn mark_episode_uncompleted(&self, episode_id: i32, user_id: i32, is_youtube: bool, origin: crate::services::sync::SyncOrigin) -> AppResult<()> {
        let log = !is_youtube && crate::services::sync::events::should_log(self, user_id, origin).await;
        dialect_match!(self, {
            pg(pool) => {
                let mut transaction = q::begin(pool).await?;
                
                if is_youtube {
                    // Handle YouTube video
                    q::query(r#"UPDATE "YouTubeVideos" SET completed = FALSE WHERE videoid = $1"#)
                        .bind(episode_id)
                        .execute(&mut *transaction)
                        .await?;
                    
                    q::query(r#"UPDATE "UserVideoHistory" SET listenduration = 0, listendate = $3 WHERE userid = $1 AND videoid = $2"#)
                        .bind(user_id)
                        .bind(episode_id)
                        .bind(Self::position_time(None))
                        .execute(&mut *transaction)
                        .await?;
                } else {
                    // Handle regular episode
                    set_completed_pg(&mut transaction, user_id, &[episode_id], false).await?;
                    
                    q::query(r#"UPDATE "UserEpisodeHistory" SET listenduration = 0, listendate = $3 WHERE userid = $1 AND episodeid = $2"#)
                        .bind(user_id)
                        .bind(episode_id)
                        .bind(Self::position_time(None))
                        .execute(&mut *transaction)
                        .await?;
                }
                if log {
                    crate::services::sync::events::episode_pg(self, &mut transaction, user_id, episode_id, crate::services::sync::events::EpisodeEvent::New).await;
                }
                
                transaction.commit().await?;
                Ok(())
            },
        })
    }

    // Get first episode ID - matches Python get_first_episode_id function
    pub async fn get_first_episode_id(&self, podcast_id: i32, is_youtube: bool) -> AppResult<Option<i32>> {
        dialect_match!(self, {
            pg(pool) => {
                let query = if is_youtube {
                    r#"SELECT videoid FROM "YouTubeVideos" WHERE podcastid = $1 ORDER BY publishedat ASC LIMIT 1"#
                } else {
                    r#"SELECT episodeid FROM "Episodes" WHERE feedid = (SELECT feedid FROM "Podcasts" WHERE podcastid = $1) ORDER BY episodepubdate ASC LIMIT 1"#
                };
                
                let row = q::query(query)
                    .bind(podcast_id)
                    .fetch_optional(pool)
                    .await?;
                
                if let Some(row) = row {
                    if is_youtube {
                        Ok(Some(row.try_get("videoid")?))
                    } else {
                        Ok(Some(row.try_get("episodeid")?))
                    }
                } else {
                    Ok(None)
                }
            },
        })
    }

    // Get episodes for a specific podcast - matches Python return_podcast_episodes function
    pub async fn return_podcast_episodes(&self, user_id: i32, podcast_id: i32) -> AppResult<Vec<crate::handlers::podcasts::Episode>> {
        dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(
                    r#"SELECT 
                        "Podcasts".podcastid, "Podcasts".podcastname, "Episodes".episodeid,
                        "Episodes".episodetitle, "Episodes".episodepubdate, "Episodes".episodedescription,
                        CASE 
                            WHEN "Podcasts".usepodcastcoverscustomized = TRUE AND "Podcasts".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                            WHEN "Users".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                            ELSE "Episodes".episodeartwork
                        END as episodeartwork,
                        "Episodes".episodeurl, "Episodes".episodeduration,
                        COALESCE((SELECT ues.completed FROM "UserEpisodeState" ues WHERE ues.episodeid = "Episodes".episodeid AND ues.userid = "Podcasts".userid), FALSE) AS completed,
                        "UserEpisodeHistory".listenduration, CAST("Episodes".episodeid AS VARCHAR) AS guid
                       FROM "Episodes"
                       INNER JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid
                       LEFT JOIN "Users" ON "Podcasts".userid = "Users".userid
                       LEFT JOIN "UserEpisodeHistory" ON "Episodes".episodeid = "UserEpisodeHistory".episodeid AND "UserEpisodeHistory".userid = $1
                       WHERE "Podcasts".podcastid = $2 AND "Podcasts".userid = $3
                       ORDER BY "Episodes".episodepubdate DESC"#
                )
                .bind(user_id)
                .bind(podcast_id)
                .bind(user_id)
                .fetch_all(pool)
                .await?;
                
                let mut episodes = Vec::new();
                for row in rows {
                    episodes.push(crate::handlers::podcasts::Episode {
                        podcastid: row.try_get("podcastid")?,
                        podcastname: row.try_get("podcastname")?,
                        episodetitle: row.try_get("episodetitle")?,
                        episodepubdate: {
                            let naive = row.try_get::<chrono::NaiveDateTime, _>("episodepubdate")?;
                            naive.format("%Y-%m-%dT%H:%M:%S").to_string()
                        },
                        episodedescription: row.try_get("episodedescription")?,
                        episodeartwork: row.try_get("episodeartwork")?,
                        episodeurl: row.try_get("episodeurl")?,
                        episodeduration: row.try_get("episodeduration")?,
                        listenduration: row.try_get("listenduration").ok(),
                        episodeid: row.try_get("episodeid")?,
                        completed: row.try_get("completed")?,
                        saved: false, // Not included in this query
                        queued: false, // Not included in this query
                        downloaded: false, // Not included in this query
                        is_youtube: false, // This is for regular episodes
                        is_video: false, // This is for regular episodes
                    });
                }
                Ok(episodes)
            },
        })
    }

    // Get podcast ID from episode name and URL - matches Python get_podcast_id_from_episode_name function
    pub async fn get_podcast_id_from_episode_name(&self, episode_name: &str, episode_url: &str, user_id: i32) -> AppResult<Option<i32>> {
        dialect_match!(self, {
            pg(pool) => {
                // Use UNION query exactly like Python version
                let row = q::query(
                    r#"SELECT podcast_id FROM (
                        SELECT "Podcasts".podcastid as podcast_id
                        FROM "Episodes"
                        INNER JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid
                        WHERE "Episodes".episodetitle = $1
                        AND "Episodes".episodeurl = $2
                        AND "Podcasts".userid = $3

                        UNION

                        SELECT "YouTubeVideos".podcastid as podcast_id
                        FROM "YouTubeVideos"
                        INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                        WHERE "YouTubeVideos".videotitle = $4
                        AND "YouTubeVideos".videourl = $5
                        AND "Podcasts".userid = $6
                    ) combined_results
                    LIMIT 1"#
                )
                .bind(episode_name)
                .bind(episode_url)
                .bind(user_id)
                .bind(episode_name)
                .bind(episode_url)
                .bind(user_id)
                .fetch_optional(pool)
                .await?;
                
                if let Some(row) = row {
                    Ok(Some(row.try_get("podcast_id")?))
                } else {
                    Ok(None)
                }
            },
        })
    }

    // Get episode metadata - matches Python get_episode_metadata function exactly
    pub async fn get_episode_metadata(&self, episode_id: i32, user_id: i32, _person_episode: bool, is_youtube: bool) -> AppResult<serde_json::Value> {
        dialect_match!(self, {
            pg(pool) => {
                if is_youtube {
                    // Query for YouTube videos
                    let row = q::query(
                        r#"SELECT "Podcasts".podcastid, "Podcasts".podcastindexid, "Podcasts".feedurl,
                                "Podcasts".podcastname, "Podcasts".artworkurl,
                                "YouTubeVideos".videotitle as episodetitle,
                                "YouTubeVideos".publishedat as episodepubdate,
                                "YouTubeVideos".videodescription as episodedescription,
                                "YouTubeVideos".thumbnailurl as episodeartwork,
                                "YouTubeVideos".videourl as episodeurl,
                                "YouTubeVideos".duration as episodeduration,
                                "YouTubeVideos".videoid as episodeid,
                                "YouTubeVideos".listenposition as listenduration,
                                "YouTubeVideos".completed,
                                CASE WHEN q.episodeid IS NOT NULL THEN true ELSE false END as is_queued,
                                CASE WHEN s.videoid IS NOT NULL THEN true ELSE false END as is_saved,
                                CASE WHEN d.videoid IS NOT NULL THEN true ELSE false END as is_downloaded,
                                TRUE::boolean as is_youtube
                        FROM "YouTubeVideos"
                        INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                        LEFT JOIN "EpisodeQueue" q ON "YouTubeVideos".videoid = q.episodeid AND q.userid = $1 AND q.is_youtube = TRUE
                        LEFT JOIN "SavedVideos" s ON "YouTubeVideos".videoid = s.videoid AND s.userid = $1
                        LEFT JOIN "DownloadedVideos" d ON "YouTubeVideos".videoid = d.videoid AND d.userid = $1
                        WHERE "YouTubeVideos".videoid = $2 AND "Podcasts".userid = $1"#
                    )
                    .bind(user_id)
                    .bind(episode_id)
                    .fetch_optional(pool)
                    .await?;
                    
                    if let Some(row) = row {
                        let naive_date = row.try_get::<chrono::NaiveDateTime, _>("episodepubdate")?;
                        let episode_pubdate = naive_date.format("%Y-%m-%dT%H:%M:%S").to_string();
                        
                        return Ok(serde_json::json!({
                            "podcastid": row.try_get::<i32, _>("podcastid")?,
                            "podcastindexid": row.try_get::<Option<i32>, _>("podcastindexid")?,
                            "feedurl": row.try_get::<String, _>("feedurl").unwrap_or_default(),
                            "podcastname": row.try_get::<String, _>("podcastname")?,
                            "artworkurl": row.try_get::<Option<String>, _>("artworkurl").unwrap_or_default().unwrap_or_default(),
                            "episodetitle": row.try_get::<String, _>("episodetitle")?,
                            "episodepubdate": episode_pubdate,
                            "episodedescription": row.try_get::<String, _>("episodedescription")?,
                            "episodeartwork": row.try_get::<String, _>("episodeartwork")?,
                            "episodeurl": row.try_get::<String, _>("episodeurl")?,
                            "episodeduration": row.try_get::<i32, _>("episodeduration")?,
                            "episodeid": row.try_get::<i32, _>("episodeid")?,
                            "listenduration": row.try_get::<Option<i32>, _>("listenduration")?,
                            "completed": row.try_get::<bool, _>("completed")?,
                            "is_queued": row.try_get::<bool, _>("is_queued")?,
                            "is_saved": row.try_get::<bool, _>("is_saved")?,
                            "is_downloaded": row.try_get::<bool, _>("is_downloaded")?,
                            "is_youtube": row.try_get::<bool, _>("is_youtube")?,
                        }));
                    }
                }
                
                // Query for regular episodes
                let row = q::query(
                    r#"SELECT "Podcasts".podcastid, "Podcasts".podcastindexid, "Podcasts".feedurl,
                            "Podcasts".podcastname, "Podcasts".artworkurl,
                            "Episodes".episodetitle,
                            "Episodes".episodepubdate,
                            "Episodes".episodedescription,
                            "Episodes".episodeartwork,
                            "Episodes".episodeurl,
                            "Episodes".episodeduration,
                            "Episodes".episodeid,
                            "UserEpisodeHistory".listenduration,
                            COALESCE((SELECT ues.completed FROM "UserEpisodeState" ues WHERE ues.episodeid = "Episodes".episodeid AND ues.userid = "Podcasts".userid), FALSE) AS completed,
                            CASE WHEN q.episodeid IS NOT NULL THEN true ELSE false END as is_queued,
                            CASE WHEN s.episodeid IS NOT NULL THEN true ELSE false END as is_saved,
                            CASE WHEN d.episodeid IS NOT NULL THEN true ELSE false END as is_downloaded,
                            FALSE::boolean as is_youtube
                    FROM "Episodes"
                    INNER JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid
                    LEFT JOIN "UserEpisodeHistory" ON "Episodes".episodeid = "UserEpisodeHistory".episodeid AND "UserEpisodeHistory".userid = $1
                    LEFT JOIN "EpisodeQueue" q ON "Episodes".episodeid = q.episodeid AND q.userid = $1
                    LEFT JOIN "SavedEpisodes" s ON "Episodes".episodeid = s.episodeid AND s.userid = $1
                    LEFT JOIN "DownloadedEpisodes" d ON "Episodes".episodeid = d.episodeid AND d.userid = $1
                    WHERE "Episodes".episodeid = $2 AND "Podcasts".userid = $1"#
                )
                .bind(user_id)
                .bind(episode_id)
                .fetch_optional(pool)
                .await?;

                if let Some(row) = row {
                    let naive_date = row.try_get::<chrono::NaiveDateTime, _>("episodepubdate")?;
                    let episode_pubdate = naive_date.format("%Y-%m-%dT%H:%M:%S").to_string();
                    
                    Ok(serde_json::json!({
                        "podcastid": row.try_get::<i32, _>("podcastid")?,
                        "podcastindexid": row.try_get::<Option<i32>, _>("podcastindexid")?,
                        "feedurl": row.try_get::<String, _>("feedurl").unwrap_or_default(),
                        "podcastname": row.try_get::<String, _>("podcastname")?,
                        "artworkurl": row.try_get::<Option<String>, _>("artworkurl").unwrap_or_default().unwrap_or_default(),
                        "episodetitle": row.try_get::<String, _>("episodetitle")?,
                        "episodepubdate": episode_pubdate,
                        "episodedescription": row.try_get::<String, _>("episodedescription")?,
                        "episodeartwork": row.try_get::<String, _>("episodeartwork")?,
                        "episodeurl": row.try_get::<String, _>("episodeurl")?,
                        "episodeduration": row.try_get::<i32, _>("episodeduration")?,
                        "episodeid": row.try_get::<i32, _>("episodeid")?,
                        "listenduration": row.try_get::<Option<i32>, _>("listenduration")?,
                        "completed": row.try_get::<bool, _>("completed")?,
                        "is_queued": row.try_get::<bool, _>("is_queued")?,
                        "is_saved": row.try_get::<bool, _>("is_saved")?,
                        "is_downloaded": row.try_get::<bool, _>("is_downloaded")?,
                        "is_youtube": row.try_get::<bool, _>("is_youtube")?,
                    }))
                } else {
                    Err(AppError::not_found("Episode not found"))
                }
            },
        })
    }

    // Fetch podcasting 2.0 data for episode
    /// Podcasting 2.0 data for an episode, all stored at refresh time: people (the episode's own
    /// credits plus the show's regulars), transcripts, and chapters (fetched from the stored
    /// chapters URL, the one thing not kept in the database).
    pub async fn fetch_podcasting_2_data(&self, episode_id: i32, user_id: i32) -> AppResult<serde_json::Value> {
        use crate::services::people::store;
        let people = store::episode_credits(self, episode_id, user_id).await?;
        let (chapters_url, transcripts) = store::episode_extras(self, episode_id).await?;

        let mut chapters = serde_json::Value::Array(vec![]);
        if let Some(url) = chapters_url {
            let (feed_url, username, password) = self.episode_feed_credentials(episode_id).await?;
            match self.fetch_chapters_data(&url, &feed_url, username.as_deref(), password.as_deref()).await {
                Ok(c) => chapters = c,
                Err(e) => debug!("Couldn't load chapters for episode {}: {}", episode_id, e),
            }
        }

        Ok(serde_json::json!({
            "chapters": chapters,
            "transcripts": transcripts,
            "people": people,
        }))
    }

    /// Feed URL and credentials of an episode's podcast (chapters on the feed's host get the
    /// same auth).
    pub(super) async fn episode_feed_credentials(&self, episode_id: i32) -> AppResult<(String, Option<String>, Option<String>)> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(
                    r#"SELECT p.feedurl, p.username, p.password FROM "Episodes" e JOIN "Podcasts" p ON p.feedid = e.feedid WHERE e.episodeid = $1 LIMIT 1"#,
                )
                .bind(episode_id)
                .fetch_optional(pool)
                .await?
                .ok_or_else(|| AppError::not_found("Episode not found"))?;
                Ok((row.try_get("feedurl")?, row.try_get("username")?, row.try_get("password")?))
            },
        })
    }

    // Fetch chapters data from external JSON URL - matches Python chapter fetching logic
    pub(super) async fn fetch_chapters_data(&self, chapters_url: &str, feed_url: &str, username: Option<&str>, password: Option<&str>) -> AppResult<serde_json::Value> {
        // SSRF guard: the chapters URL comes straight out of a (user-added) feed.
        if let Err(reason) = crate::services::url_guard::ensure_safe_public_url_async(chapters_url).await {
            warn!("Refusing to fetch chapters from unsafe URL {}: {}", chapters_url, reason);
            return Err(AppError::bad_request(format!("Refused to fetch chapters URL: {}", reason)));
        }
        let client = crate::services::url_guard::guarded_client_builder()
            .timeout(std::time::Duration::from_secs(5))
            .build()?;
        
        let mut request = client.get(chapters_url)
            .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
            .header("Accept", "application/json, text/javascript, */*; q=0.01")
            .header("Accept-Language", "en-US,en;q=0.9")
            .header("Referer", feed_url);
        
        // Use same auth for chapters if it's from the same domain
        if chapters_url.starts_with(feed_url) {
            if let (Some(user), Some(pass)) = (username, password) {
                request = request.basic_auth(user, Some(pass));
            }
        }
        
        let response = request.send().await?;
        let json_data: serde_json::Value = response.json().await?;
        
        Ok(json_data.get("chapters").unwrap_or(&serde_json::Value::Array(vec![])).clone())
    }

    /// Podcasting 2.0 data for a podcast, stored at refresh time: its people (regulars in
    /// `people`, episode-only credits in `guests`), podroll, funding and value.
    pub async fn fetch_podcasting_2_pod_data(&self, podcast_id: i32, user_id: i32) -> AppResult<serde_json::Value> {
        use crate::services::people::store;
        let credits = store::podcast_credits(self, podcast_id, user_id).await?;
        let extras = store::channel_extras(self, podcast_id).await?;
        Ok(serde_json::json!({
            "people": credits.people,
            "guests": credits.guests,
            "podroll": extras.podroll,
            "funding": extras.funding,
            "value": extras.value,
        }))
    }

    // Get the next episode in a podcast (chronologically after the given episode)
    // The episode after `episode_id` in its podcast, skipping ones the user already finished.
    pub async fn get_next_podcast_episode(&self, episode_id: i32, user_id: i32) -> AppResult<Option<crate::models::QueuedEpisode>> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(
                    r#"SELECT
                        e.episodetitle,
                        p.podcastname,
                        p.podcastid,
                        e.episodepubdate,
                        e.episodedescription,
                        CASE
                            WHEN p.usepodcastcoverscustomized = TRUE AND p.usepodcastcovers = TRUE THEN p.artworkurl
                            WHEN u.usepodcastcovers = TRUE THEN p.artworkurl
                            ELSE e.episodeartwork
                        END as episodeartwork,
                        e.episodeurl,
                        e.episodeduration,
                        COALESCE(ueh.listenduration, 0) as listenduration,
                        e.episodeid,
                        COALESCE((SELECT ues.completed FROM "UserEpisodeState" ues WHERE ues.episodeid = e.episodeid AND ues.userid = p.userid), FALSE) AS completed,
                        CASE WHEN se.episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS saved,
                        CASE WHEN eq.episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS queued,
                        CASE WHEN de.episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS downloaded,
                        FALSE as is_youtube,
                        COALESCE(e.is_video, FALSE) as is_video
                    FROM "Episodes" e
                    INNER JOIN "Podcasts" p ON e.feedid = p.feedid
                    LEFT JOIN "Users" u ON p.userid = u.userid
                    LEFT JOIN "UserEpisodeHistory" ueh ON e.episodeid = ueh.episodeid AND ueh.userid = $2
                    LEFT JOIN "SavedEpisodes" se ON e.episodeid = se.episodeid AND se.userid = $2
                    LEFT JOIN "EpisodeQueue" eq ON e.episodeid = eq.episodeid AND eq.userid = $2 AND eq.is_youtube = FALSE
                    LEFT JOIN "DownloadedEpisodes" de ON e.episodeid = de.episodeid AND de.userid = $2
                    WHERE e.feedid = (SELECT feedid FROM "Episodes" WHERE episodeid = $1)
                      AND e.episodepubdate > (SELECT episodepubdate FROM "Episodes" WHERE episodeid = $1)
                      AND p.userid = $2
                      AND COALESCE((SELECT ues.completed FROM "UserEpisodeState" ues WHERE ues.episodeid = e.episodeid AND ues.userid = p.userid), FALSE) = FALSE
                    ORDER BY e.episodepubdate ASC
                    LIMIT 1"#
                )
                .bind(episode_id)
                .bind(user_id)
                .fetch_optional(pool)
                .await?;

                if let Some(row) = row {
                    Ok(Some(crate::models::QueuedEpisode {
                        episodetitle: row.try_get("episodetitle")?,
                        podcastname: row.try_get("podcastname")?,
                        podcastid: row.try_get("podcastid")?,
                        episodepubdate: {
                            let naive = row.try_get::<chrono::NaiveDateTime, _>("episodepubdate")?;
                            naive.format("%Y-%m-%dT%H:%M:%S").to_string()
                        },
                        episodedescription: row.try_get("episodedescription")?,
                        episodeartwork: row.try_get("episodeartwork")?,
                        episodeurl: row.try_get("episodeurl")?,
                        queueposition: None,
                        episodeduration: row.try_get("episodeduration")?,
                        queuedate: String::new(),
                        listenduration: row.try_get("listenduration").ok(),
                        episodeid: row.try_get("episodeid")?,
                        completed: row.try_get("completed")?,
                        saved: row.try_get("saved")?,
                        queued: row.try_get("queued")?,
                        downloaded: row.try_get("downloaded")?,
                        is_youtube: row.try_get("is_youtube")?,
                        is_video: row.try_get("is_video")?,
                    }))
                } else {
                    Ok(None)
                }
            },
        })
    }

    // Resolve account defaults and podcast overrides in one database round trip.
    pub async fn get_play_episode_details(&self, user_id: i32, podcast_id: i32, _is_youtube: bool) -> AppResult<(f64, i32, i32, bool)> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    SELECT COALESCE(
                        CASE WHEN p.playbackspeedcustomized THEN p.playbackspeed END,
                        u.playbackspeed, 1.0
                    ) AS playback_speed,
                    COALESCE(p.startskip, 0) AS start_skip,
                    COALESCE(p.endskip, 0) AS end_skip,
                    COALESCE(p.playbackspeedcustomized, FALSE) AS customized
                    FROM "Users" u
                    LEFT JOIN "Podcasts" p ON p.userid = u.userid AND p.podcastid = $2
                    WHERE u.userid = $1
                "#)
                    .bind(user_id)
                    .bind(podcast_id)
                    .fetch_optional(pool)
                    .await?;
                match row {
                    Some(row) => Ok((
                        q::decimal(&row, "playback_speed")?.unwrap_or(1.0),
                        row.try_get("start_skip")?,
                        row.try_get("end_skip")?,
                        row.try_get("customized")?,
                    )),
                    None => Ok((1.0, 0, 0, false)),
                }
            },
        })
    }

    // Get podcast episodes with capitalized field names for frontend compatibility.
    //
    // Pagination strategy: each UNION branch carries 5-6 LEFT JOINs, so the cost is dominated
    // by how many rows the joins fire on. We resolve merged podcast IDs in a tiny up-front
    // query, then push LIMIT (offset + limit) INSIDE each branch so the joins only run on the
    // rows that can possibly contribute to the final page. The outer ORDER BY...LIMIT/OFFSET
    // produces the correctly-merged page from the two pre-sorted streams. Total count is a
    // separate cheap query (two COUNT(*) on the indexed PodcastID column, no joins).
    pub async fn return_podcast_episodes_capitalized(
        &self,
        user_id: i32,
        podcast_id: i32,
        limit: Option<i64>,
        offset: Option<i64>,
        sort_by: &str,
        sort_order: &str,
        search: &str,
        filter: &str,
    ) -> AppResult<(Vec<crate::handlers::podcasts::PodcastEpisode>, i64)> {
        // Validate sort column/direction to prevent SQL injection (only fixed string literals
        // are ever spliced into the query — the actual user input is bound as a parameter).
        let pg_order_col = match sort_by {
            "duration" => "\"Episodeduration\"",
            "title"    => "\"Episodetitle\"",
            _          => "\"Episodepubdate\"", // "date" or unknown
        };
        let order_dir = if sort_order == "asc" { "ASC" } else { "DESC" };
        let has_search = !search.is_empty();
        // Each branch keeps only the rows that can reach the requested page, sorted the same way
        // as the outer query. The completed/in-progress filter runs on the combined rows, so a
        // filtered page needs every row.
        let filter_is_all = !matches!(filter, "completed" | "in_progress" | "incomplete");
        dialect_match!(self, {
            pg(pool) => {
                let lim: i64 = limit.unwrap_or(i64::MAX);
                let off: i64 = offset.unwrap_or(0);
                // Per-branch cap: each branch must keep at least (offset + limit) rows so the
                // outer ORDER BY can correctly interleave them. saturating_add avoids overflow
                // when limit is i64::MAX (the "give me everything" caller path).
                let per_branch_limit: i64 = if filter_is_all { lim.saturating_add(off) } else { i64::MAX };

                // Resolve the full set of podcast IDs (primary + merged) up front so the main
                // query is just `podcastid = ANY($2)` instead of the per-row JSON unpacking the
                // original query did.
                let mut podcast_ids: Vec<i32> = vec![podcast_id];
                let merged_row = q::query(
                    r#"SELECT mergedpodcastids FROM "Podcasts" WHERE podcastid = $1 AND userid = $2"#
                )
                .bind(podcast_id)
                .bind(user_id)
                .fetch_optional(pool)
                .await?;
                if let Some(row) = merged_row {
                    if let Ok(Some(merged_json)) = row.try_get::<Option<String>, _>("mergedpodcastids") {
                        if let Ok(parsed) = serde_json::from_str::<Vec<i32>>(&merged_json) {
                            for id in parsed {
                                if !podcast_ids.contains(&id) {
                                    podcast_ids.push(id);
                                }
                            }
                        }
                    }
                }

                let filter_clause = match filter {
                    "completed"   => " WHERE \"Completed\" = TRUE",
                    "in_progress" => " WHERE \"Completed\" = FALSE AND \"Listenduration\" IS NOT NULL AND \"Listenduration\" > 0",
                    "incomplete"  => " WHERE \"Completed\" = FALSE",
                    _             => "",
                };
                let ep_search_clause = if has_search {
                    " AND (\"Episodes\".episodetitle ILIKE $3 OR \"Episodes\".episodedescription ILIKE $3)"
                } else { "" };
                let yt_search_clause = if has_search {
                    " AND (\"YouTubeVideos\".videotitle ILIKE $3 OR \"YouTubeVideos\".videodescription ILIKE $3)"
                } else { "" };
                let search_pattern = if has_search {
                    format!("%{}%", search)
                } else { String::new() };

                // Bind positions shift when a search pattern is present (it takes $3).
                let (pb_lim_pos, outer_lim_pos, outer_off_pos) = if has_search {
                    ("$4", "$5", "$6")
                } else {
                    ("$3", "$4", "$5")
                };

                let rows_sql = format!(
                    r#"SELECT * FROM (
                        (SELECT
                            "Podcasts".podcastname as podcastname,
                            "Episodes".episodetitle as "Episodetitle",
                            "Episodes".episodepubdate as "Episodepubdate",
                            "Episodes".episodedescription as "Episodedescription",
                            CASE
                                WHEN "Podcasts".usepodcastcoverscustomized = TRUE AND "Podcasts".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                                WHEN "Users".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                                ELSE "Episodes".episodeartwork
                            END as "Episodeartwork",
                            "Episodes".episodeurl as "Episodeurl",
                            "Episodes".episodeduration as "Episodeduration",
                            "UserEpisodeHistory".listenduration as "Listenduration",
                            "Episodes".episodeid as "Episodeid",
                            COALESCE((SELECT ues.completed FROM "UserEpisodeState" ues WHERE ues.episodeid = "Episodes".episodeid AND ues.userid = "Podcasts".userid), FALSE) as "Completed",
                            CASE WHEN "SavedEpisodes".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS saved,
                            CASE WHEN "EpisodeQueue".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS queued,
                            CASE WHEN "DownloadedEpisodes".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS downloaded,
                            FALSE as is_youtube,
                            "Episodes".is_video as is_video
                        FROM "Episodes"
                        INNER JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid
                        LEFT JOIN "Users" ON "Podcasts".userid = "Users".userid
                        LEFT JOIN "UserEpisodeHistory" ON
                            "Episodes".episodeid = "UserEpisodeHistory".episodeid
                            AND "UserEpisodeHistory".userid = $1
                        LEFT JOIN "SavedEpisodes" ON
                            "Episodes".episodeid = "SavedEpisodes".episodeid
                            AND "SavedEpisodes".userid = $1
                        LEFT JOIN "EpisodeQueue" ON
                            "Episodes".episodeid = "EpisodeQueue".episodeid
                            AND "EpisodeQueue".userid = $1
                            AND "EpisodeQueue".is_youtube = FALSE
                        LEFT JOIN "DownloadedEpisodes" ON
                            "Episodes".episodeid = "DownloadedEpisodes".episodeid
                            AND "DownloadedEpisodes".userid = $1
                        WHERE "Podcasts".userid = $1 AND "Podcasts".podcastid = ANY($2){ep_search_clause}
                        ORDER BY {pg_order_col} {order_dir} NULLS LAST, "Episodeid"
                        LIMIT {pb_lim_pos})

                        UNION ALL

                        (SELECT
                            "Podcasts".podcastname as podcastname,
                            "YouTubeVideos".videotitle as "Episodetitle",
                            "YouTubeVideos".publishedat as "Episodepubdate",
                            "YouTubeVideos".videodescription as "Episodedescription",
                            CASE
                                WHEN "Podcasts".usepodcastcoverscustomized = TRUE AND "Podcasts".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                                WHEN "Users".usepodcastcovers = TRUE THEN "Podcasts".artworkurl
                                ELSE "YouTubeVideos".thumbnailurl
                            END as "Episodeartwork",
                            "YouTubeVideos".videourl as "Episodeurl",
                            "YouTubeVideos".duration as "Episodeduration",
                            "YouTubeVideos".listenposition as "Listenduration",
                            "YouTubeVideos".videoid as "Episodeid",
                            "YouTubeVideos".completed as "Completed",
                            CASE WHEN "SavedVideos".videoid IS NOT NULL THEN TRUE ELSE FALSE END AS saved,
                            CASE WHEN "EpisodeQueue".episodeid IS NOT NULL AND "EpisodeQueue".is_youtube = TRUE THEN TRUE ELSE FALSE END AS queued,
                            CASE WHEN "DownloadedVideos".videoid IS NOT NULL THEN TRUE ELSE FALSE END AS downloaded,
                            TRUE as is_youtube,
                            TRUE as is_video
                        FROM "YouTubeVideos"
                        INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                        LEFT JOIN "Users" ON "Podcasts".userid = "Users".userid
                        LEFT JOIN "SavedVideos" ON
                            "YouTubeVideos".videoid = "SavedVideos".videoid
                            AND "SavedVideos".userid = $1
                        LEFT JOIN "EpisodeQueue" ON
                            "YouTubeVideos".videoid = "EpisodeQueue".episodeid
                            AND "EpisodeQueue".userid = $1
                            AND "EpisodeQueue".is_youtube = TRUE
                        LEFT JOIN "DownloadedVideos" ON
                            "YouTubeVideos".videoid = "DownloadedVideos".videoid
                            AND "DownloadedVideos".userid = $1
                        WHERE "Podcasts".userid = $1 AND "Podcasts".podcastid = ANY($2){yt_search_clause}
                        ORDER BY {pg_order_col} {order_dir} NULLS LAST, "Episodeid"
                        LIMIT {pb_lim_pos})
                    ) combined{filter_clause}
                    ORDER BY {pg_order_col} {order_dir} NULLS LAST, is_youtube, "Episodeid"
                    LIMIT {outer_lim_pos} OFFSET {outer_off_pos}"#,
                    ep_search_clause = ep_search_clause,
                    yt_search_clause = yt_search_clause,
                    pb_lim_pos = pb_lim_pos,
                    pg_order_col = pg_order_col,
                    order_dir = order_dir,
                    filter_clause = filter_clause,
                    outer_lim_pos = outer_lim_pos,
                    outer_off_pos = outer_off_pos,
                );

                // SAFETY: rows_sql is built from static literals plus the validated
                // sort_by/sort_order/filter/has_search dispatch above. User-supplied search text
                // is bound as $3, never interpolated.
                let mut q = q::query(sqlx::AssertSqlSafe(rows_sql.as_str()))
                    .bind(user_id)
                    .bind(&podcast_ids);
                if has_search {
                    q = q.bind(search_pattern.clone());
                }
                let rows = q
                    .bind(per_branch_limit)
                    .bind(lim)
                    .bind(off)
                    .fetch_all(pool)
                    .await?;

                // Total comes from a separate count query. The rows query LIMITs each branch to
                // `per_branch_limit` for efficiency (so the joins only fire on rows that can
                // possibly contribute to the requested page), which means a `COUNT(*) OVER()` on
                // it would cap at the page size and break pagination on long podcast feeds. The
                // count query mirrors the rows query's filters but selects only the minimum
                // columns needed for `filter_clause`.
                let count_sql = format!(
                    r#"SELECT COUNT(*) AS total FROM (
                        (SELECT
                            "UserEpisodeHistory".listenduration as "Listenduration",
                            COALESCE((SELECT ues.completed FROM "UserEpisodeState" ues WHERE ues.episodeid = "Episodes".episodeid AND ues.userid = "Podcasts".userid), FALSE) as "Completed"
                        FROM "Episodes"
                        INNER JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid
                        LEFT JOIN "UserEpisodeHistory" ON
                            "Episodes".episodeid = "UserEpisodeHistory".episodeid
                            AND "UserEpisodeHistory".userid = $1
                        WHERE "Podcasts".userid = $1 AND "Podcasts".podcastid = ANY($2){ep_search_clause})

                        UNION ALL

                        (SELECT
                            "YouTubeVideos".listenposition as "Listenduration",
                            "YouTubeVideos".completed as "Completed"
                        FROM "YouTubeVideos"
                        INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                        WHERE "Podcasts".userid = $1 AND "Podcasts".podcastid = ANY($2){yt_search_clause})
                    ) combined{filter_clause}"#,
                    ep_search_clause = ep_search_clause,
                    yt_search_clause = yt_search_clause,
                    filter_clause = filter_clause,
                );
                let mut count_q = q::query(sqlx::AssertSqlSafe(count_sql.as_str()))
                    .bind(user_id)
                    .bind(&podcast_ids);
                if has_search {
                    count_q = count_q.bind(search_pattern.clone());
                }
                let total: i64 = count_q.fetch_one(pool).await?.try_get("total")?;

                let mut episodes = Vec::new();
                for row in rows {
                    let naive_date = row.try_get::<chrono::NaiveDateTime, _>("Episodepubdate")?;
                    let episodepubdate = naive_date.format("%Y-%m-%dT%H:%M:%S").to_string();

                    episodes.push(crate::handlers::podcasts::PodcastEpisode {
                        podcastname: row.try_get("podcastname")?,
                        episodetitle: row.try_get("Episodetitle")?,
                        episodepubdate,
                        episodedescription: row.try_get("Episodedescription")?,
                        episodeartwork: row.try_get("Episodeartwork")?,
                        episodeurl: row.try_get("Episodeurl")?,
                        episodeduration: row.try_get("Episodeduration")?,
                        listenduration: row.try_get("Listenduration")?,
                        episodeid: row.try_get("Episodeid")?,
                        completed: row.try_get("Completed")?,
                        saved: row.try_get("saved")?,
                        queued: row.try_get("queued")?,
                        downloaded: row.try_get("downloaded")?,
                        is_youtube: row.try_get("is_youtube")?,
                        is_video: row.try_get("is_video")?,
                    });
                }

                Ok((episodes, total))
            },
        })
    }

    /// When a reported position was taken: the client's `recorded_at`, never later than now
    /// (a fast clock mustn't let one device win every future comparison), or now if the client
    /// didn't say.
    pub fn position_time(recorded_at: Option<DateTime<Utc>>) -> chrono::NaiveDateTime {
        let now = Utc::now();
        recorded_at.map_or(now, |at| at.min(now)).naive_utc()
    }

    /// Save where the user is in an episode.
    ///
    /// The most recently *recorded* position wins, so rewinding, skipping back and restarting
    /// all stick, while a stale report (an offline device catching up, or an upload retried
    /// late) can't overwrite a newer one. `recorded_at` is when the player took the position;
    /// `UserEpisodeHistory.ListenDate` holds that time for the stored position, the same rule
    /// gpodder sync applies (see `services::sync::db::set_listen_position`).
    pub async fn record_listen_duration(
        &self,
        episode_id: i32,
        user_id: i32,
        listen_duration: f64,
        recorded_at: Option<DateTime<Utc>>,
        origin: crate::services::sync::SyncOrigin,
    ) -> AppResult<()> {
        use crate::services::sync::events::{self, EpisodeEvent};
        if !listen_duration.is_finite() || listen_duration < 0.0 {
            warn!("Skipped updating listen duration for user {} and episode {} due to invalid duration: {}", user_id, episode_id, listen_duration);
            return Ok(());
        }
        let position = listen_duration as i32;
        let at = Self::position_time(recorded_at);
        let log = events::should_log(self, user_id, origin).await;

        dialect_match!(self, {
            pg(pool) => {
                let mut tx = q::begin(pool).await?;
                let changed = q::query(
                    r#"INSERT INTO "UserEpisodeHistory" (userid, episodeid, listendate, listenduration)
                       VALUES ($1, $2, $3, $4)
                       ON CONFLICT (userid, episodeid) DO UPDATE
                       SET listenduration = EXCLUDED.listenduration, listendate = EXCLUDED.listendate
                       WHERE "UserEpisodeHistory".listendate IS NULL
                          OR "UserEpisodeHistory".listendate <= EXCLUDED.listendate"#,
                )
                .bind(user_id)
                .bind(episode_id)
                .bind(at)
                .bind(position)
                .execute(&mut *tx)
                .await?
                .rows_affected()
                    > 0;
                if changed && log {
                    events::episode_pg(self, &mut tx, user_id, episode_id, EpisodeEvent::Progress(position)).await;
                }
                tx.commit().await?;
                if !changed {
                    debug!("Ignored a stale position for user {} episode {}: a newer one is stored", user_id, episode_id);
                }
            },
        });
        Ok(())
    }

    /// [`record_listen_duration`](Self::record_listen_duration) for YouTube videos: the most
    /// recently recorded position wins.
    pub async fn record_youtube_listen_duration(
        &self,
        video_id: i32,
        user_id: i32,
        listen_duration: f64,
        recorded_at: Option<DateTime<Utc>>,
    ) -> AppResult<()> {
        if !listen_duration.is_finite() || listen_duration < 0.0 {
            warn!("Skipped updating listen duration for user {} and video {} due to invalid duration: {}", user_id, video_id, listen_duration);
            return Ok(());
        }
        let position = listen_duration as i32;
        let at = Self::position_time(recorded_at);

        dialect_match!(self, {
            pg(pool) => {
                q::query(
                    r#"INSERT INTO "UserVideoHistory" (userid, videoid, listendate, listenduration)
                       VALUES ($1, $2, $3, $4)
                       ON CONFLICT (userid, videoid) DO UPDATE
                       SET listenduration = EXCLUDED.listenduration, listendate = EXCLUDED.listendate
                       WHERE "UserVideoHistory".listendate IS NULL
                          OR "UserVideoHistory".listendate <= EXCLUDED.listendate"#,
                )
                .bind(user_id)
                .bind(video_id)
                .bind(at)
                .bind(position)
                .execute(pool)
                .await?;
            },
        });
        Ok(())
    }

    // Get episode duration in seconds
    pub async fn get_episode_duration(&self, episode_id: i32) -> AppResult<i32> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"SELECT episodeduration FROM "Episodes" WHERE episodeid = $1"#)
                    .bind(episode_id)
                    .fetch_optional(pool)
                    .await?;
                
                if let Some(row) = row {
                    Ok(row.try_get::<Option<i32>, _>("episodeduration")?.unwrap_or(0))
                } else {
                    Ok(0)
                }
            },
        })
    }

    // Get YouTube episode duration in seconds
    pub async fn get_youtube_episode_duration(&self, episode_id: i32) -> AppResult<i32> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"SELECT duration FROM "YouTubeVideos" WHERE videoid = $1"#)
                    .bind(episode_id)
                    .fetch_optional(pool)
                    .await?;
                
                if let Some(row) = row {
                    Ok(row.try_get::<Option<i32>, _>("duration")?.unwrap_or(0))
                } else {
                    Ok(0)
                }
            },
        })
    }

    // Get users who have auto-complete enabled (auto_complete_seconds > 0)
    pub async fn get_users_with_auto_complete_enabled(&self) -> AppResult<Vec<UserAutoComplete>> {
        dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(r#"
                    SELECT us.userid, us.autocompleteseconds 
                    FROM "UserSettings" us 
                    WHERE us.autocompleteseconds > 0
                "#)
                .fetch_all(pool)
                .await?;

                let mut users = Vec::new();
                for row in rows {
                    users.push(UserAutoComplete {
                        user_id: row.try_get("userid")?,
                        auto_complete_seconds: row.try_get("autocompleteseconds")?,
                    });
                }
                Ok(users)
            },
        })
    }

    // Auto-complete episodes listened to in the last 7 days (the nightly sweep; progress saves
    // and sync already complete at write time).
    pub async fn auto_complete_user_episodes(&self, user_id: i32, auto_complete_seconds: i32) -> AppResult<i32> {
        if auto_complete_seconds <= 0 {
            return Ok(0);
        }

        let mut completed_count = 0;

        dialect_match!(self, {
            pg(pool) => {
                // Handle regular episodes
                let episode_rows = q::query(r#"
                    SELECT e.episodeid, e.episodeduration, COALESCE(h.listenduration, 0) as listenduration
                    FROM "Episodes" e
                    LEFT JOIN "UserEpisodeHistory" h ON e.episodeid = h.episodeid AND h.userid = $1
                    WHERE NOT EXISTS (SELECT 1 FROM "UserEpisodeState" ues WHERE ues.episodeid = e.episodeid AND ues.userid = h.userid AND ues.completed)
                      AND e.episodeduration > 0 
                      AND h.listenduration > 0
                      AND h.listendate >= NOW() - INTERVAL '7 days'
                      AND (e.episodeduration - h.listenduration) <= $2
                "#)
                .bind(user_id)
                .bind(auto_complete_seconds)
                .fetch_all(pool)
                .await?;

                for row in episode_rows {
                    let episode_id: i32 = row.try_get("episodeid")?;
                    let _ = self.mark_episode_completed(episode_id, user_id, false, crate::services::sync::SyncOrigin::Pinepods).await;
                    completed_count += 1;
                }

                // Handle YouTube episodes
                let youtube_rows = q::query(r#"
                    SELECT v.videoid, v.duration, COALESCE(h.listenduration, 0) as listenduration
                    FROM "YouTubeVideos" v
                    LEFT JOIN "UserVideoHistory" h ON v.videoid = h.videoid AND h.userid = $1
                    WHERE v.completed = false 
                      AND v.duration > 0 
                      AND h.listenduration > 0
                      AND h.listendate >= NOW() - INTERVAL '7 days'
                      AND (v.duration - h.listenduration) <= $2
                "#)
                .bind(user_id)
                .bind(auto_complete_seconds)
                .fetch_all(pool)
                .await?;

                for row in youtube_rows {
                    let video_id: i32 = row.try_get("videoid")?;
                    let _ = self.mark_episode_completed(video_id, user_id, true, crate::services::sync::SyncOrigin::Pinepods).await;
                    completed_count += 1;
                }
            },
        });

        Ok(completed_count)
    }

    // Increment listen time - matches Python increment_listen_time function exactly
    pub async fn increment_listen_time(&self, user_id: i32) -> AppResult<()> {
        dialect_match!(self, {
            pg(pool) => {
                q::query(r#"UPDATE "UserStats" SET TimeListened = TimeListened + 1 WHERE UserID = $1"#)
                    .bind(user_id)
                    .execute(pool)
                    .await?;
                Ok(())
            },
        })
    }

    // Get an episode's URL (verifying the user owns the podcast). Used by the stream
    // endpoint to fall back to local-media episodes that are not in DownloadedEpisodes.
    pub async fn get_episode_url_for_stream(
        &self,
        episode_id: i32,
        user_id: i32,
    ) -> AppResult<Option<String>> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    SELECT e.episodeurl AS episodeurl
                    FROM "Episodes" e
                    JOIN "Podcasts" p ON e.feedid = p.feedid
                    WHERE e.episodeid = $1 AND p.userid = $2
                "#)
                    .bind(episode_id)
                    .bind(user_id)
                    .fetch_optional(pool)
                    .await?;
                Ok(row.map(|r| r.try_get::<String, _>("episodeurl")).transpose()?)
            },
        })
    }

    // Bulk episode operations for efficient batch processing
    pub async fn bulk_mark_episodes_completed(&self, episode_ids: Vec<i32>, user_id: i32, is_youtube: bool) -> AppResult<(i32, i32)> {
        if episode_ids.is_empty() {
            return Ok((0, 0));
        }

        let mut processed = 0;
        let mut failed = 0;

        dialect_match!(self, {
            pg(pool) => {
                let mut tx = q::begin(pool).await?;
                
                if is_youtube {
                    for episode_id in episode_ids {
                        match self.mark_episode_completed(episode_id, user_id, is_youtube, crate::services::sync::SyncOrigin::Pinepods).await {
                            Ok(_) => processed += 1,
                            Err(_) => failed += 1,
                        }
                    }
                } else {
                    processed = set_completed_pg(&mut tx, user_id, &episode_ids, true).await? as i32;
                }
                
                tx.commit().await?;
            },
        });

        Ok((processed, failed))
    }
}
