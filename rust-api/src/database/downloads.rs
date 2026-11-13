//! Server-side downloads and auto-delete.

use super::*;

impl DatabasePool {
    // Get downloaded episodes - matches Python download_episode_list function
    pub async fn download_episode_list(&self, user_id: i32) -> AppResult<Vec<crate::handlers::podcasts::DownloadedEpisode>> {
        dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(
                    r#"SELECT * FROM (
                        SELECT
                            "Podcasts".podcastid as podcastid,
                            "Podcasts".podcastname as podcastname,
                            "Podcasts".artworkurl as artworkurl,
                            "Episodes".episodeid as episodeid,
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
                            "Podcasts".podcastindexid as podcastindexid,
                            "Podcasts".websiteurl as websiteurl,
                            "DownloadedEpisodes".downloadedlocation as downloadedlocation,
                            "UserEpisodeHistory".listenduration as listenduration,
                            COALESCE((SELECT ues.completed FROM "UserEpisodeState" ues WHERE ues.episodeid = "Episodes".episodeid AND ues.userid = "Podcasts".userid), FALSE) as completed,
                            CASE WHEN "SavedEpisodes".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS saved,
                            CASE WHEN "EpisodeQueue".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS queued,
                            TRUE as downloaded,
                            FALSE as is_youtube,
                            "Episodes".is_video as is_video
                        FROM "DownloadedEpisodes"
                        INNER JOIN "Episodes" ON "DownloadedEpisodes".episodeid = "Episodes".episodeid
                        INNER JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid AND "Podcasts".userid = "DownloadedEpisodes".userid
                        LEFT JOIN "Users" ON "Podcasts".userid = "Users".userid
                        LEFT JOIN "UserEpisodeHistory" ON
                            "DownloadedEpisodes".episodeid = "UserEpisodeHistory".episodeid
                            AND "DownloadedEpisodes".userid = "UserEpisodeHistory".userid
                        LEFT JOIN "SavedEpisodes" ON
                            "DownloadedEpisodes".episodeid = "SavedEpisodes".episodeid
                            AND "SavedEpisodes".userid = $1
                        LEFT JOIN "EpisodeQueue" ON
                            "DownloadedEpisodes".episodeid = "EpisodeQueue".episodeid
                            AND "EpisodeQueue".userid = $2
                            AND "EpisodeQueue".is_youtube = FALSE
                        WHERE "DownloadedEpisodes".userid = $3

                        UNION ALL

                        SELECT
                            "Podcasts".podcastid as podcastid,
                            "Podcasts".podcastname as podcastname,
                            "Podcasts".artworkurl as artworkurl,
                            "YouTubeVideos".videoid as episodeid,
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
                            "Podcasts".podcastindexid as podcastindexid,
                            "Podcasts".websiteurl as websiteurl,
                            "DownloadedVideos".downloadedlocation as downloadedlocation,
                            "YouTubeVideos".listenposition as listenduration,
                            "YouTubeVideos".completed as completed,
                            CASE WHEN "SavedVideos".videoid IS NOT NULL THEN TRUE ELSE FALSE END AS saved,
                            CASE WHEN "EpisodeQueue".episodeid IS NOT NULL AND "EpisodeQueue".is_youtube = TRUE THEN TRUE ELSE FALSE END AS queued,
                            TRUE as downloaded,
                            TRUE as is_youtube,
                            TRUE as is_video
                        FROM "DownloadedVideos"
                        INNER JOIN "YouTubeVideos" ON "DownloadedVideos".videoid = "YouTubeVideos".videoid
                        INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                        LEFT JOIN "Users" ON "Podcasts".userid = "Users".userid
                        LEFT JOIN "SavedVideos" ON
                            "DownloadedVideos".videoid = "SavedVideos".videoid
                            AND "SavedVideos".userid = $4
                        LEFT JOIN "EpisodeQueue" ON
                            "DownloadedVideos".videoid = "EpisodeQueue".episodeid
                            AND "EpisodeQueue".userid = $5
                            AND "EpisodeQueue".is_youtube = TRUE
                        WHERE "DownloadedVideos".userid = $6
                    ) combined
                    ORDER BY episodepubdate DESC"#
                )
                .bind(user_id)
                .bind(user_id)
                .bind(user_id)
                .bind(user_id)
                .bind(user_id)
                .bind(user_id)
                .fetch_all(pool)
                .await?;
                
                let mut episodes = Vec::new();
                for row in rows {
                    episodes.push(crate::handlers::podcasts::DownloadedEpisode {
                        podcastid: row.try_get("podcastid")?,
                        podcastname: row.try_get("podcastname")?,
                        artworkurl: row.try_get("artworkurl").ok(),
                        episodeid: row.try_get("episodeid")?,
                        episodetitle: row.try_get("episodetitle")?,
                        episodepubdate: {
                            let naive = row.try_get::<chrono::NaiveDateTime, _>("episodepubdate")?;
                            naive.format("%Y-%m-%dT%H:%M:%S").to_string()
                        },
                        episodedescription: row.try_get("episodedescription")?,
                        episodeartwork: row.try_get("episodeartwork").ok(),
                        episodeurl: row.try_get("episodeurl")?,
                        episodeduration: row.try_get("episodeduration")?,
                        podcastindexid: row.try_get("podcastindexid").ok(),
                        websiteurl: row.try_get("websiteurl").ok(),
                        downloadedlocation: row.try_get("downloadedlocation")?,
                        listenduration: row.try_get("listenduration").ok(),
                        completed: row.try_get("completed")?,
                        saved: row.try_get("saved")?,
                        queued: row.try_get("queued")?,
                        downloaded: row.try_get("downloaded")?,
                        is_youtube: row.try_get("is_youtube")?,
                        is_video: row.try_get("is_video")?,
                    });
                }
                Ok(episodes)
            },
        })
    }

    pub async fn get_podcast_download_summary(
        &self,
        user_id: i32,
        search: &str,
        filter: &str,
    ) -> AppResult<Vec<crate::handlers::podcasts::PodcastDownloadSummary>> {
        // The summary feeds the downloads page's podcast list. Applying the same search/filter
        // the per-podcast paged query uses keeps the list (and its episode counts) in sync with
        // what actually shows when a podcast is expanded — without this the page can't filter
        // out podcasts whose episodes aren't loaded yet.
        let has_search = !search.is_empty();
        let search_pattern = format!("%{}%", search);
        dialect_match!(self, {
            pg(pool) => {
                // Search matches episode/video title OR the podcast name (a name match surfaces the
                // whole podcast). Bound once as $3 and referenced from both UNION branches.
                let ep_search = if has_search {
                    " AND (e.episodetitle ILIKE $3 OR ep.podcastname ILIKE $3)"
                } else { "" };
                let yt_search = if has_search {
                    " AND (yv.videotitle ILIKE $3 OR yp.podcastname ILIKE $3)"
                } else { "" };
                let ep_filter = match filter {
                    "completed"   => " AND COALESCE((SELECT ues.completed FROM \"UserEpisodeState\" ues WHERE ues.episodeid = e.episodeid AND ues.userid = de.userid), FALSE) = TRUE",
                    "in_progress" => " AND COALESCE((SELECT ues.completed FROM \"UserEpisodeState\" ues WHERE ues.episodeid = e.episodeid AND ues.userid = de.userid), FALSE) = FALSE AND ueh.listenduration IS NOT NULL AND ueh.listenduration > 0",
                    "unplayed"    => " AND COALESCE((SELECT ues.completed FROM \"UserEpisodeState\" ues WHERE ues.episodeid = e.episodeid AND ues.userid = de.userid), FALSE) = FALSE",
                    _             => "",
                };
                let yt_filter = match filter {
                    "completed"   => " AND yv.completed = TRUE",
                    "in_progress" => " AND yv.completed = FALSE AND yv.listenposition IS NOT NULL AND yv.listenposition > 0",
                    "unplayed"    => " AND yv.completed = FALSE",
                    _             => "",
                };
                let sql = format!(
                    r#"SELECT
                        p.podcastid,
                        p.podcastname,
                        p.artworkurl,
                        COUNT(*) AS episode_count
                    FROM (
                        SELECT ep.podcastid
                        FROM "DownloadedEpisodes" de
                        INNER JOIN "Episodes" e ON de.episodeid = e.episodeid
                        INNER JOIN "Podcasts" ep ON e.feedid = ep.feedid AND ep.userid = de.userid
                        LEFT JOIN "UserEpisodeHistory" ueh ON de.episodeid = ueh.episodeid AND de.userid = ueh.userid
                        WHERE de.userid = $1{ep_search}{ep_filter}

                        UNION ALL

                        SELECT yv.podcastid
                        FROM "DownloadedVideos" dv
                        INNER JOIN "YouTubeVideos" yv ON dv.videoid = yv.videoid
                        INNER JOIN "Podcasts" yp ON yv.podcastid = yp.podcastid
                        WHERE dv.userid = $2{yt_search}{yt_filter}
                    ) downloads
                    INNER JOIN "Podcasts" p ON downloads.podcastid = p.podcastid
                    GROUP BY p.podcastid, p.podcastname, p.artworkurl
                    ORDER BY p.podcastname ASC"#,
                    ep_search = ep_search,
                    ep_filter = ep_filter,
                    yt_search = yt_search,
                    yt_filter = yt_filter,
                );

                // SAFETY: sql is built from static literals plus the validated has_search/filter
                // dispatch above. User-supplied search text is bound as $3, never interpolated.
                let mut q = q::query(sqlx::AssertSqlSafe(sql.as_str()))
                    .bind(user_id)
                    .bind(user_id);
                if has_search {
                    q = q.bind(search_pattern.clone());
                }
                let rows = q.fetch_all(pool).await?;

                let mut summaries = Vec::new();
                for row in rows {
                    summaries.push(crate::handlers::podcasts::PodcastDownloadSummary {
                        podcastid: row.try_get("podcastid")?,
                        podcastname: row.try_get("podcastname")?,
                        artworkurl: row.try_get("artworkurl").ok(),
                        episode_count: row.try_get("episode_count")?,
                    });
                }
                Ok(summaries)
            },
        })
    }

    pub async fn get_podcast_downloads_paged(
        &self,
        user_id: i32,
        podcast_id: i32,
        limit: i64,
        offset: i64,
        search: &str,
        filter: &str,
    ) -> AppResult<(Vec<crate::handlers::podcasts::DownloadedEpisode>, i64)> {
        let has_search = !search.is_empty();
        let search_pattern = format!("%{}%", search);
        dialect_match!(self, {
            pg(pool) => {
                // Search ($11, bound after limit/offset) matches title OR podcast name; the
                // completion filter is applied to the merged `combined` set so its `completed`
                // and `listenduration` aliases cover both episodes and youtube videos.
                let ep_search = if has_search {
                    " AND (\"Episodes\".episodetitle ILIKE $11 OR \"Podcasts\".podcastname ILIKE $11)"
                } else { "" };
                let yt_search = if has_search {
                    " AND (\"YouTubeVideos\".videotitle ILIKE $11 OR \"Podcasts\".podcastname ILIKE $11)"
                } else { "" };
                let filter_clause = match filter {
                    "completed"   => " WHERE completed = TRUE",
                    "in_progress" => " WHERE completed = FALSE AND listenduration IS NOT NULL AND listenduration > 0",
                    "unplayed"    => " WHERE completed = FALSE",
                    _             => "",
                };
                let sql = format!(
                    r#"SELECT *, COUNT(*) OVER() AS total_count FROM (
                        SELECT
                            "Podcasts".podcastid as podcastid,
                            "Podcasts".podcastname as podcastname,
                            "Podcasts".artworkurl as artworkurl,
                            "Episodes".episodeid as episodeid,
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
                            "Podcasts".podcastindexid as podcastindexid,
                            "Podcasts".websiteurl as websiteurl,
                            "DownloadedEpisodes".downloadedlocation as downloadedlocation,
                            "UserEpisodeHistory".listenduration as listenduration,
                            COALESCE((SELECT ues.completed FROM "UserEpisodeState" ues WHERE ues.episodeid = "Episodes".episodeid AND ues.userid = "Podcasts".userid), FALSE) as completed,
                            CASE WHEN "SavedEpisodes".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS saved,
                            CASE WHEN "EpisodeQueue".episodeid IS NOT NULL THEN TRUE ELSE FALSE END AS queued,
                            TRUE as downloaded,
                            FALSE as is_youtube,
                            "Episodes".is_video as is_video
                        FROM "DownloadedEpisodes"
                        INNER JOIN "Episodes" ON "DownloadedEpisodes".episodeid = "Episodes".episodeid
                        INNER JOIN "Podcasts" ON "Episodes".feedid = "Podcasts".feedid AND "Podcasts".userid = "DownloadedEpisodes".userid
                        LEFT JOIN "Users" ON "Podcasts".userid = "Users".userid
                        LEFT JOIN "UserEpisodeHistory" ON
                            "DownloadedEpisodes".episodeid = "UserEpisodeHistory".episodeid
                            AND "DownloadedEpisodes".userid = "UserEpisodeHistory".userid
                        LEFT JOIN "SavedEpisodes" ON
                            "DownloadedEpisodes".episodeid = "SavedEpisodes".episodeid
                            AND "SavedEpisodes".userid = $1
                        LEFT JOIN "EpisodeQueue" ON
                            "DownloadedEpisodes".episodeid = "EpisodeQueue".episodeid
                            AND "EpisodeQueue".userid = $2
                            AND "EpisodeQueue".is_youtube = FALSE
                        WHERE "DownloadedEpisodes".userid = $3
                        AND "Podcasts".podcastid = $4{ep_search}

                        UNION ALL

                        SELECT
                            "Podcasts".podcastid as podcastid,
                            "Podcasts".podcastname as podcastname,
                            "Podcasts".artworkurl as artworkurl,
                            "YouTubeVideos".videoid as episodeid,
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
                            "Podcasts".podcastindexid as podcastindexid,
                            "Podcasts".websiteurl as websiteurl,
                            "DownloadedVideos".downloadedlocation as downloadedlocation,
                            "YouTubeVideos".listenposition as listenduration,
                            "YouTubeVideos".completed as completed,
                            CASE WHEN "SavedVideos".videoid IS NOT NULL THEN TRUE ELSE FALSE END AS saved,
                            CASE WHEN "EpisodeQueue".episodeid IS NOT NULL AND "EpisodeQueue".is_youtube = TRUE THEN TRUE ELSE FALSE END AS queued,
                            TRUE as downloaded,
                            TRUE as is_youtube,
                            TRUE as is_video
                        FROM "DownloadedVideos"
                        INNER JOIN "YouTubeVideos" ON "DownloadedVideos".videoid = "YouTubeVideos".videoid
                        INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                        LEFT JOIN "Users" ON "Podcasts".userid = "Users".userid
                        LEFT JOIN "SavedVideos" ON
                            "DownloadedVideos".videoid = "SavedVideos".videoid
                            AND "SavedVideos".userid = $5
                        LEFT JOIN "EpisodeQueue" ON
                            "DownloadedVideos".videoid = "EpisodeQueue".episodeid
                            AND "EpisodeQueue".userid = $6
                            AND "EpisodeQueue".is_youtube = TRUE
                        WHERE "DownloadedVideos".userid = $7
                        AND "Podcasts".podcastid = $8{yt_search}
                    ) combined{filter_clause}
                    ORDER BY episodepubdate DESC
                    LIMIT $9 OFFSET $10"#,
                    ep_search = ep_search,
                    yt_search = yt_search,
                    filter_clause = filter_clause,
                );

                // SAFETY: sql is built from static literals plus the validated has_search/filter
                // dispatch; the search text is bound as $11, never interpolated.
                let mut q = q::query(sqlx::AssertSqlSafe(sql.as_str()))
                    .bind(user_id)    // $1 SavedEpisodes join
                    .bind(user_id)    // $2 EpisodeQueue join
                    .bind(user_id)    // $3 DownloadedEpisodes WHERE
                    .bind(podcast_id) // $4 regular podcast filter
                    .bind(user_id)    // $5 SavedVideos join
                    .bind(user_id)    // $6 EpisodeQueue join
                    .bind(user_id)    // $7 DownloadedVideos WHERE
                    .bind(podcast_id) // $8 youtube podcast filter
                    .bind(limit)      // $9
                    .bind(offset);    // $10
                if has_search {
                    q = q.bind(search_pattern.clone()); // $11
                }
                let rows = q
                    .fetch_all(pool)
                    .await?;

                let total: i64 = rows.first()
                    .and_then(|r| r.try_get::<i64, _>("total_count").ok())
                    .unwrap_or(0);

                let mut episodes = Vec::new();
                for row in rows {
                    episodes.push(crate::handlers::podcasts::DownloadedEpisode {
                        podcastid: row.try_get("podcastid")?,
                        podcastname: row.try_get("podcastname")?,
                        artworkurl: row.try_get("artworkurl").ok(),
                        episodeid: row.try_get("episodeid")?,
                        episodetitle: row.try_get("episodetitle")?,
                        episodepubdate: {
                            let naive = row.try_get::<chrono::NaiveDateTime, _>("episodepubdate")?;
                            naive.format("%Y-%m-%dT%H:%M:%S").to_string()
                        },
                        episodedescription: row.try_get("episodedescription")?,
                        episodeartwork: row.try_get("episodeartwork").ok(),
                        episodeurl: row.try_get("episodeurl")?,
                        episodeduration: row.try_get("episodeduration")?,
                        podcastindexid: row.try_get("podcastindexid").ok(),
                        websiteurl: row.try_get("websiteurl").ok(),
                        downloadedlocation: row.try_get("downloadedlocation")?,
                        listenduration: row.try_get("listenduration").ok(),
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

    // Check if episode is already downloaded
    pub async fn check_downloaded(&self, user_id: i32, episode_id: i32, is_youtube: bool) -> AppResult<bool> {
        dialect_match!(self, {
            pg(pool) => {
                let query = if is_youtube {
                    r#"SELECT COUNT(*) as count FROM "DownloadedVideos" WHERE userid = $1 AND videoid = $2"#
                } else {
                    r#"SELECT COUNT(*) as count FROM "DownloadedEpisodes" WHERE userid = $1 AND episodeid = $2"#
                };
                
                let row = q::query(query)
                    .bind(user_id)
                    .bind(episode_id)
                    .fetch_one(pool)
                    .await?;
                    
                let count: i64 = row.try_get("count")?;
                Ok(count > 0)
            },
        })
    }

    // Fetch the filesystem path stored for a downloaded video before deleting it
    pub async fn get_video_download_location(&self, user_id: i32, video_id: i32) -> AppResult<Option<String>> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"SELECT downloadedlocation FROM "DownloadedVideos" WHERE userid = $1 AND videoid = $2"#)
                    .bind(user_id)
                    .bind(video_id)
                    .fetch_optional(pool)
                    .await?;
                Ok(row.and_then(|r| r.try_get::<Option<String>, _>("downloadedlocation").ok().flatten()))
            },
        })
    }

    // Delete downloaded episode
    // Returns whether a download row was removed.
    pub async fn delete_episode(&self, user_id: i32, episode_id: i32, is_youtube: bool) -> AppResult<bool> {
        dialect_match!(self, {
            pg(pool) => {
                let deleted = if is_youtube {
                    let result = q::query(r#"DELETE FROM "DownloadedVideos" WHERE userid = $1 AND videoid = $2"#)
                        .bind(user_id)
                        .bind(episode_id)
                        .execute(pool)
                        .await?;

                    // Only update UserStats if a row was actually deleted
                    if result.rows_affected() > 0 {
                        q::query(r#"UPDATE "UserStats" SET episodesdownloaded = episodesdownloaded - 1 WHERE userid = $1"#)
                            .bind(user_id)
                            .execute(pool)
                            .await?;
                    }
                    result.rows_affected() > 0
                } else {
                    let result = q::query(r#"DELETE FROM "DownloadedEpisodes" WHERE userid = $1 AND episodeid = $2"#)
                        .bind(user_id)
                        .bind(episode_id)
                        .execute(pool)
                        .await?;

                    // Only update UserStats if a row was actually deleted
                    if result.rows_affected() > 0 {
                        q::query(r#"UPDATE "UserStats" SET episodesdownloaded = episodesdownloaded - 1 WHERE userid = $1"#)
                            .bind(user_id)
                            .execute(pool)
                            .await?;
                    }
                    result.rows_affected() > 0
                };
                Ok(deleted)
            },
        })
    }

    // Get download status for user
    pub async fn get_download_status(&self, user_id: i32) -> AppResult<serde_json::Value> {
        dialect_match!(self, {
            pg(pool) => {
                // Get active download tasks
                let rows = q::query(
                    r#"SELECT taskid, tasktype, progress, status FROM "UserTasks" 
                       WHERE userid = $1 AND tasktype IN ('download_episode', 'download_video', 'download_all_episodes', 'download_all_videos') 
                       AND status IN ('pending', 'running')"#
                )
                .bind(user_id)
                .fetch_all(pool)
                .await?;
                
                let mut tasks = Vec::new();
                for row in rows {
                    tasks.push(serde_json::json!({
                        "task_id": row.try_get::<String, _>("taskid")?,
                        "task_type": row.try_get::<String, _>("tasktype")?,
                        "progress": row.try_get::<Option<i32>, _>("progress")?,
                        "status": row.try_get::<String, _>("status")?
                    }));
                }
                
                Ok(serde_json::json!({ "active_downloads": tasks }))
            },
        })
    }

    // Cleanup old episodes - matches Python cleanup_old_episodes function exactly
    pub async fn cleanup_old_episodes(&self) -> AppResult<()> {
        self.cleanup_expired_shared_episodes().await?;
        Ok(())
    }

    // Auto-delete server downloads older than the resolved retention window (#655).
    //
    // Resolution mirrors the PlaybackSpeed pattern: for each downloaded item, the effective
    // retention is the per-podcast AutoDownloadDeleteDays when AutoDownloadDeleteCustomized is
    // set, otherwise the user's default. A resolved value of 0 means "never delete". Files under
    // /opt/castaway/downloads/ are removed first, then the DB row (reusing delete_episode, which
    // also decrements UserStats.EpisodesDownloaded). local:// feeds are never touched.
    pub async fn auto_delete_old_downloads(&self) -> AppResult<()> {
        let now = chrono::Utc::now().naive_utc();
        let mut deleted: u64 = 0;

        for (user_id, content_id, location, downloaded_date, feed_url, effective_days) in
            self.auto_delete_candidates_episodes().await?
        {
            if Self::should_auto_delete(now, downloaded_date, effective_days, feed_url.as_deref()) {
                Self::remove_download_file(location.as_deref()).await;
                self.delete_episode(user_id, content_id, false).await?;
                deleted += 1;
            }
        }

        for (user_id, content_id, location, downloaded_date, feed_url, effective_days) in
            self.auto_delete_candidates_videos().await?
        {
            if Self::should_auto_delete(now, downloaded_date, effective_days, feed_url.as_deref()) {
                Self::remove_download_file(location.as_deref()).await;
                self.delete_episode(user_id, content_id, true).await?;
                deleted += 1;
            }
        }

        if deleted > 0 {
            tracing::info!("Auto-delete: removed {} server download(s) past their retention window", deleted);
        }
        Ok(())
    }

    // Delete server downloads of episodes the user has finished, when "delete when finished" is
    // on for that podcast (per-podcast AutoDeleteOnComplete, else the user's default). Only
    // downloads made before the episode was finished count, so re-downloading a finished episode
    // to hear it again keeps it, and an hour's grace lets the last minutes play out first.
    pub async fn auto_delete_finished_downloads(&self) -> AppResult<()> {
        let rows: Vec<(i32, i32, Option<String>)> = dialect_match!(self, {
            pg(pool) => q::query(
                r#"SELECT de.userid, de.episodeid, de.downloadedlocation
                   FROM "DownloadedEpisodes" de
                   JOIN "UserEpisodeState" s ON s.userid = de.userid AND s.episodeid = de.episodeid AND s.completed
                   JOIN "Episodes" e ON e.episodeid = de.episodeid
                   JOIN "Podcasts" p ON p.feedid = e.feedid AND p.userid = de.userid
                   JOIN "Users" u ON u.userid = de.userid
                   WHERE COALESCE(p.autodeleteoncomplete, u.autodeleteoncomplete, FALSE)
                     AND p.feedurl NOT LIKE 'local://%'
                     AND (s.completedat IS NULL
                          OR (s.completedat >= de.downloadeddate AND s.completedat < NOW() - INTERVAL '1 hour'))"#,
            )
            .fetch_all(pool)
            .await?
            .iter()
            .map(|r| (
                r.try_get("userid").unwrap_or(0),
                r.try_get("episodeid").unwrap_or(0),
                r.try_get("downloadedlocation").unwrap_or(None),
            ))
            .collect(),
        });

        let mut deleted = 0;
        for (user_id, episode_id, location) in rows {
            Self::remove_download_file(location.as_deref()).await;
            self.delete_episode(user_id, episode_id, false).await?;
            deleted += 1;
        }
        if deleted > 0 {
            tracing::info!("Auto-delete: removed {} server download(s) of finished episodes", deleted);
        }
        Ok(())
    }

    // Decide whether a single downloaded item is due for auto-deletion.
    pub(super) fn should_auto_delete(
        now: chrono::NaiveDateTime,
        downloaded_date: Option<chrono::NaiveDateTime>,
        effective_days: i32,
        feed_url: Option<&str>,
    ) -> bool {
        if effective_days <= 0 {
            return false; // 0 = retention disabled for this item
        }
        if feed_url.map_or(false, |f| f.starts_with("local://")) {
            return false; // never delete user-managed local media
        }
        match downloaded_date {
            Some(dt) => dt < now - chrono::Duration::days(effective_days as i64),
            None => false,
        }
    }

    // Remove a downloaded file from disk if present (mirrors delete_episode handler behavior).
    pub(super) async fn remove_download_file(path: Option<&str>) {
        if let Some(path) = path {
            if tokio::fs::metadata(path).await.is_ok() {
                if let Err(e) = tokio::fs::remove_file(path).await {
                    tracing::error!("Auto-delete: could not remove file {}: {}", path, e);
                }
            }
        }
    }

    // Candidate podcast-episode downloads with their resolved retention window.
    // Returns (user_id, episode_id, location, downloaded_date, feed_url, effective_days).
    pub(super) async fn auto_delete_candidates_episodes(
        &self,
    ) -> AppResult<Vec<(i32, i32, Option<String>, Option<chrono::NaiveDateTime>, Option<String>, i32)>> {
        let mut out = Vec::new();
        dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(
                    r#"SELECT de.userid AS user_id, de.episodeid AS content_id,
                              de.downloadedlocation AS location, de.downloadeddate AS downloaded_date,
                              p.feedurl AS feed_url,
                              CASE WHEN p.autodownloaddeletecustomized THEN p.autodownloaddeletedays
                                   ELSE u.autodownloaddeletedays END AS effective_days
                       FROM "DownloadedEpisodes" de
                       JOIN "Episodes" e ON e.episodeid = de.episodeid
                       JOIN "Podcasts" p ON p.feedid = e.feedid AND p.userid = de.userid
                       JOIN "Users" u ON u.userid = de.userid"#,
                )
                .fetch_all(pool)
                .await?;
                for row in &rows {
                    out.push((
                        row.try_get::<i32, _>("user_id").unwrap_or(0),
                        row.try_get::<i32, _>("content_id").unwrap_or(0),
                        row.try_get::<Option<String>, _>("location").unwrap_or(None),
                        row.try_get::<Option<chrono::NaiveDateTime>, _>("downloaded_date").unwrap_or(None),
                        row.try_get::<Option<String>, _>("feed_url").unwrap_or(None),
                        row.try_get::<i32, _>("effective_days").unwrap_or(0),
                    ));
                }
            },
        });
        Ok(out)
    }

    // Candidate YouTube-video downloads with their resolved retention window.
    // Returns (user_id, video_id, location, downloaded_date, feed_url, effective_days).
    pub(super) async fn auto_delete_candidates_videos(
        &self,
    ) -> AppResult<Vec<(i32, i32, Option<String>, Option<chrono::NaiveDateTime>, Option<String>, i32)>> {
        let mut out = Vec::new();
        dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(
                    r#"SELECT dv.userid AS user_id, dv.videoid AS content_id,
                              dv.downloadedlocation AS location, dv.downloadeddate AS downloaded_date,
                              p.feedurl AS feed_url,
                              CASE WHEN p.autodownloaddeletecustomized THEN p.autodownloaddeletedays
                                   ELSE u.autodownloaddeletedays END AS effective_days
                       FROM "DownloadedVideos" dv
                       JOIN "YouTubeVideos" v ON v.videoid = dv.videoid
                       JOIN "Podcasts" p ON p.podcastid = v.podcastid
                       JOIN "Users" u ON u.userid = dv.userid"#,
                )
                .fetch_all(pool)
                .await?;
                for row in &rows {
                    out.push((
                        row.try_get::<i32, _>("user_id").unwrap_or(0),
                        row.try_get::<i32, _>("content_id").unwrap_or(0),
                        row.try_get::<Option<String>, _>("location").unwrap_or(None),
                        row.try_get::<Option<chrono::NaiveDateTime>, _>("downloaded_date").unwrap_or(None),
                        row.try_get::<Option<String>, _>("feed_url").unwrap_or(None),
                        row.try_get::<i32, _>("effective_days").unwrap_or(0),
                    ));
                }
            },
        });
        Ok(out)
    }

    // Get YouTube video location - matches Python get_youtube_video_location function exactly
    pub async fn get_youtube_video_location(
        &self,
        episode_id: i32,
        user_id: i32,
    ) -> AppResult<Option<String>> {
        info!("Looking up YouTube video location for episode_id: {}, user_id: {}", episode_id, user_id);
        
        let youtube_id = dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    SELECT "YouTubeVideos".youtubevideoid
                    FROM "YouTubeVideos"
                    INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                    WHERE "YouTubeVideos".videoid = $1 AND "Podcasts".userid = $2
                "#)
                .bind(episode_id)
                .bind(user_id)
                .fetch_optional(pool)
                .await?;

                if let Some(row) = row {
                    row.try_get::<String, _>("youtubevideoid")?
                } else {
                    return Ok(None);
                }
            },
        });

        debug!("Found YouTube ID: {}", youtube_id);

        let file_path = format!("{}/{}.mp3", crate::paths::youtube_downloads_dir(), youtube_id);
        let file_path_double = format!("{}/{}.mp3.mp3", crate::paths::youtube_downloads_dir(), youtube_id);

        debug!("Checking paths: {} and {}", file_path, file_path_double);

        if tokio::fs::metadata(&file_path).await.is_ok() {
            debug!("Found file at {}", file_path);
            Ok(Some(file_path))
        } else if tokio::fs::metadata(&file_path_double).await.is_ok() {
            debug!("Found file at {}", file_path_double);
            Ok(Some(file_path_double))
        } else {
            debug!("No file found for YouTube ID: {}", youtube_id);
            Ok(None)
        }
    }

    // Get download location - matches Python get_download_location function exactly
    pub async fn get_download_location(
        &self,
        episode_id: i32,
        user_id: i32,
    ) -> AppResult<Option<String>> {
        info!("Looking up download location for episode_id: {}, user_id: {}", episode_id, user_id);
        
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"SELECT downloadedlocation FROM "DownloadedEpisodes" WHERE episodeid = $1 AND userid = $2"#)
                    .bind(episode_id)
                    .bind(user_id)
                    .fetch_optional(pool)
                    .await?;
                
                if let Some(row) = row {
                    let location: String = row.try_get("downloadedlocation")?;
                    debug!("DownloadedLocation found: {}", location);
                    Ok(Some(location))
                } else {
                    debug!("No DownloadedLocation found for the given EpisodeID and UserID");
                    Ok(None)
                }
            },
        })
    }
}
