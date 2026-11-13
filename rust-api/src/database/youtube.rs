//! YouTube channels and videos.

use super::*;

impl DatabasePool {
    // ===================================================================================
    // Unified host feed
    //
    // A host's episodes come from the Podcast Index person index,
    // and must be viewable whether or not the user is subscribed to the host or to the
    // underlying podcasts. `build_host_feed_shared` produces the non-user-specific feed (podcasts
    // a host appears in + a merged, artwork-resolved episode list) — this is what the handler
    // caches. `overlay_host_feed_user_state` then layers the requesting user's interaction state
    // (real episode id, saved/downloaded/listen progress) for podcasts they're subscribed to.
    // ===================================================================================

    // Check existing YouTube channel subscription - matches Python check_existing_channel_subscription function exactly
    pub async fn check_existing_channel_subscription(&self, channel_id: &str, user_id: i32) -> AppResult<Option<i32>> {
        debug!("Checking existing channel subscription for {} and user {}", channel_id, user_id);
        
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"SELECT podcastid FROM "Podcasts" WHERE feedurl = $1 AND userid = $2"#)
                    .bind(format!("https://www.youtube.com/channel/{}", channel_id))
                    .bind(user_id)
                    .fetch_optional(pool)
                    .await?;
                
                if let Some(row) = row {
                    let podcast_id: i32 = row.try_get("podcastid")?;
                    debug!("Found existing subscription with ID: {}", podcast_id);
                    Ok(Some(podcast_id))
                } else {
                    info!("No existing subscription found");
                    Ok(None)
                }
            },
        })
    }

    // Add YouTube channel - matches Python add_youtube_channel function exactly
    pub async fn add_youtube_channel(&self, channel_info: &std::collections::HashMap<String, String>, user_id: i32, feed_cutoff: i32) -> AppResult<i32> {
        debug!("Adding YouTube channel to database for user {}", user_id);
        
        let channel_id = channel_info.get("channel_id").ok_or_else(|| AppError::bad_request("Channel ID is required"))?;
        let empty_string = String::new();
        let name = channel_info.get("name").unwrap_or(&empty_string);
        let description = &crate::services::html::sanitize_feed_html(channel_info.get("description").unwrap_or(&empty_string));
        let thumbnail_url = channel_info.get("thumbnail_url").unwrap_or(&empty_string);
        let feed_url = format!("https://www.youtube.com/channel/{}", channel_id);
        
        // Insert new YouTube channel as podcast
        let podcast_id = dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    INSERT INTO "Podcasts" (
                        userid, podcastname, artworkurl, description, episodecount,
                        websiteurl, feedurl, author, categories, explicit, podcastindexid, feedcutoffdays, isyoutubechannel
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
                    RETURNING podcastid
                "#)
                    .bind(user_id)
                    .bind(name)
                    .bind(thumbnail_url)
                    .bind(description)
                    .bind(0) // Initial episode count
                    .bind(&feed_url)
                    .bind(&feed_url)
                    .bind(name) // Use channel name as author
                    .bind("{}") // Empty categories for YouTube
                    .bind(false) // Not explicit by default
                    .bind(0) // No podcast index ID for YouTube
                    .bind(feed_cutoff)
                    .bind(true) // Is YouTube channel
                    .fetch_one(pool)
                    .await?;
                
                row.try_get("podcastid")?
            },
        });
        
        // Update UserStats PodcastsAdded counter
        dialect_match!(self, {
            pg(pool) => {
                let _ = q::query(r#"
                    UPDATE "UserStats" 
                    SET podcastsadded = podcastsadded + 1 
                    WHERE userid = $1
                "#)
                    .bind(user_id)
                    .execute(pool)
                    .await;
            },
        });
        
        self.link_feed_or_warn(podcast_id).await;
        debug!("Successfully added YouTube channel with ID: {}", podcast_id);
        Ok(podcast_id)
    }

    // Check if YouTube channel already exists - matches Python check_youtube_channel function exactly
    pub async fn check_youtube_channel(&self, user_id: i32, channel_name: &str, channel_url: &str) -> AppResult<bool> {
        dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    SELECT podcastid FROM "Podcasts"
                    WHERE userid = $1 AND podcastname = $2 AND feedurl = $3 AND isyoutubechannel = TRUE
                "#)
                    .bind(user_id)
                    .bind(channel_name)
                    .bind(channel_url)
                    .fetch_optional(pool)
                    .await?;
                
                Ok(row.is_some())
            },
        })
    }

    // Remove a channel's videos published before the cutoff, except those a user still has in
    // their history, queue, saved list, downloads, playlists or collections.
    pub async fn remove_old_youtube_videos(&self, podcast_id: i32, cutoff_date: chrono::DateTime<chrono::Utc>) -> AppResult<()> {
        let cutoff_naive = cutoff_date.naive_utc();
        let rows_affected = dialect_match!(self, {
            pg(pool) => {
                q::query(r#"
                    DELETE FROM "YouTubeVideos" AS v
                    WHERE v.podcastid = $1 AND v.publishedat < $2
                      AND NOT EXISTS (SELECT 1 FROM "UserVideoHistory" h WHERE h.videoid = v.videoid)
                      AND NOT EXISTS (SELECT 1 FROM "SavedVideos" s WHERE s.videoid = v.videoid)
                      AND NOT EXISTS (SELECT 1 FROM "DownloadedVideos" d WHERE d.videoid = v.videoid)
                      AND NOT EXISTS (SELECT 1 FROM "PlaylistContents" p WHERE p.videoid = v.videoid)
                      AND NOT EXISTS (SELECT 1 FROM "CollectionEpisodes" c WHERE c.videoid = v.videoid)
                      AND NOT EXISTS (SELECT 1 FROM "EpisodeQueue" q WHERE q.episodeid = v.videoid AND q.is_youtube = TRUE)
                "#)
                .bind(podcast_id)
                .bind(cutoff_naive)
                .execute(pool)
                .await?
                .rows_affected()
            },
        });
        if rows_affected > 0 {
            debug!("Removed {} old YouTube videos of podcast {}", rows_affected, podcast_id);
        }
        Ok(())
    }

    // YouTube IDs of a channel podcast's stored videos.
    pub async fn youtube_video_ids(&self, podcast_id: i32) -> AppResult<std::collections::HashSet<String>> {
        let ids: Vec<Option<String>> = dialect_match!(self, {
            pg(pool) => {
                q::query_scalar(r#"SELECT youtubevideoid FROM "YouTubeVideos" WHERE podcastid = $1"#)
                    .bind(podcast_id)
                    .fetch_all(pool)
                    .await?
            },
        });
        Ok(ids.into_iter().flatten().collect())
    }

    // Video filters of these channel podcasts; podcasts without any are left out.
    pub async fn youtube_video_filters(
        &self,
        podcast_ids: &[i32],
    ) -> AppResult<HashMap<i32, crate::handlers::youtube::YouTubeVideoFilter>> {
        type Row = (i32, Option<i32>, Option<i32>, Option<String>);
        if podcast_ids.is_empty() {
            return Ok(HashMap::new());
        }
        let rows: Vec<Row> = dialect_match!(self, {
            pg(pool) => {
                q::query_as(r#"
                    SELECT podcastid, videominminutes, videomaxminutes, videotitlefilter FROM "Podcasts"
                    WHERE podcastid = ANY($1)
                      AND (videominminutes IS NOT NULL OR videomaxminutes IS NOT NULL OR videotitlefilter IS NOT NULL)
                "#)
                .bind(podcast_ids)
                .fetch_all(pool)
                .await?
            },
        });
        Ok(rows
            .into_iter()
            .map(|(id, min_minutes, max_minutes, title_contains)| {
                (id, crate::handlers::youtube::YouTubeVideoFilter { min_minutes, max_minutes, title_contains })
            })
            .collect())
    }

    // Set the video filter of a user's channel podcast. The stored feed hash is dropped so the next
    // refresh looks at the channel's listed videos again (a looser filter may take some of them).
    // False when the user has no such channel.
    pub async fn set_youtube_video_filter(
        &self,
        podcast_id: i32,
        user_id: i32,
        filter: &crate::handlers::youtube::YouTubeVideoFilter,
    ) -> AppResult<bool> {
        let updated = dialect_match!(self, {
            pg(pool) => {
                q::query(r#"
                    UPDATE "Podcasts" SET videominminutes = $1, videomaxminutes = $2, videotitlefilter = $3, feedcontenthash = NULL
                    WHERE podcastid = $4 AND userid = $5 AND isyoutubechannel = TRUE
                "#)
                .bind(filter.min_minutes)
                .bind(filter.max_minutes)
                .bind(&filter.title_contains)
                .bind(podcast_id)
                .bind(user_id)
                .execute(pool)
                .await?
                .rows_affected()
            },
        });
        Ok(updated > 0 || self.owns_youtube_channel(podcast_id, user_id).await?)
    }

    // Whether this channel podcast is the user's.
    pub async fn owns_youtube_channel(&self, podcast_id: i32, user_id: i32) -> AppResult<bool> {
        let found: Option<i32> = dialect_match!(self, {
            pg(pool) => {
                q::query_scalar(r#"SELECT podcastid FROM "Podcasts" WHERE podcastid = $1 AND userid = $2 AND isyoutubechannel = TRUE"#)
                    .bind(podcast_id)
                    .bind(user_id)
                    .fetch_optional(pool)
                    .await?
            },
        });
        Ok(found.is_some())
    }

    // Insert videos into a channel podcast; returns the inserted rows.
    pub async fn add_youtube_videos(
        &self,
        podcast_id: i32,
        videos: &[&crate::handlers::youtube::VideoDetails],
    ) -> AppResult<Vec<crate::handlers::podcasts::Episode>> {
        let mut inserted = Vec::with_capacity(videos.len());
        for video in videos {
            let title = self.clean_and_normalize_title(&video.title);
            // Sanitize after decoding: decoding turns escaped text like "&lt;img onerror…&gt;" back
            // into real markup, and the channel owner writes these descriptions.
            let description = crate::services::html::sanitize_feed_html(&self.decode_html_entities(&video.description));
            let url = format!("https://www.youtube.com/watch?v={}", video.id);
            let published = video.published.naive_utc();
            let video_id: i32 = dialect_match!(self, {
                pg(pool) => {
                    q::query_scalar(r#"
                        INSERT INTO "YouTubeVideos" (
                            podcastid, youtubevideoid, videotitle, videodescription, videourl,
                            thumbnailurl, publishedat, duration, completed, listenposition
                        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, FALSE, 0)
                        RETURNING videoid
                    "#)
                    .bind(podcast_id)
                    .bind(&video.id)
                    .bind(&title)
                    .bind(&description)
                    .bind(&url)
                    .bind(&video.thumbnail)
                    .bind(published)
                    .bind(video.duration)
                    .fetch_one(pool)
                    .await?
                },
            });
            inserted.push(crate::handlers::podcasts::Episode {
                podcastid: podcast_id,
                podcastname: String::new(),
                episodetitle: title,
                episodepubdate: video.published.format("%Y-%m-%dT%H:%M:%S").to_string(),
                episodedescription: description,
                episodeartwork: video.thumbnail.clone(),
                episodeurl: url,
                episodeduration: video.duration,
                listenduration: None,
                episodeid: video_id,
                completed: false,
                saved: false,
                queued: false,
                downloaded: false,
                is_youtube: true,
                is_video: true,
            });
        }
        Ok(inserted)
    }

    // Get video date using web scraping - matches Python get_video_date function exactly
    pub async fn get_video_date(&self, video_id: &str) -> AppResult<chrono::DateTime<chrono::Utc>> {
        let client = reqwest::Client::new();
        let url = format!("https://www.youtube.com/watch?v={}", video_id);
        
        let response = client.get(&url)
            .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            .send()
            .await
            .map_err(|e| AppError::external_error(&format!("Failed to fetch video page: {}", e)))?;

        let html = response.text().await
            .map_err(|e| AppError::external_error(&format!("Failed to read response: {}", e)))?;

        // Parse HTML to find upload date (simplified version of Python's BeautifulSoup approach)
        if let Some(start) = html.find("\"uploadDate\":\"") {
            let date_start = start + "\"uploadDate\":\"".len();
            if let Some(end) = html[date_start..].find("\"") {
                let date_str = &html[date_start..date_start + end];
                if let Ok(parsed_date) = chrono::DateTime::parse_from_rfc3339(date_str) {
                    return Ok(parsed_date.with_timezone(&chrono::Utc));
                }
            }
        }

        // Fallback to current time minus some hours if date not found
        Ok(chrono::Utc::now() - chrono::Duration::hours(1))
    }

    // Update YouTube video duration after download - updates duration from MP3 file
    pub async fn update_youtube_video_duration(&self, video_id: &str, duration_seconds: i32) -> AppResult<()> {
        debug!("Updating duration for YouTube video {} to {} seconds", video_id, duration_seconds);
        
        dialect_match!(self, {
            pg(pool) => {
                q::query(r#"UPDATE "YouTubeVideos" SET duration = $1 WHERE youtubevideoid = $2"#)
                    .bind(duration_seconds)
                    .bind(video_id)
                    .execute(pool)
                    .await?;
            },
        });
        
        debug!("Successfully updated duration for YouTube video {}", video_id);
        Ok(())
    }

    // Return YouTube episodes - matches Python return_youtube_episodes function exactly
    pub async fn return_youtube_episodes(
        &self,
        user_id: i32,
        podcast_id: i32,
    ) -> AppResult<Option<Vec<serde_json::Value>>> {
        dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(r#"
                    SELECT "Podcasts".podcastid, "Podcasts".podcastname, "YouTubeVideos".videoid AS episodeid,
                    "YouTubeVideos".videotitle AS episodetitle, "YouTubeVideos".publishedat AS episodepubdate,
                    "YouTubeVideos".videodescription AS episodedescription,
                    "YouTubeVideos".thumbnailurl AS episodeartwork, "YouTubeVideos".videourl AS episodeurl,
                    "YouTubeVideos".duration AS episodeduration,
                    "YouTubeVideos".listenposition AS listenduration,
                    "YouTubeVideos".youtubevideoid AS guid
                    FROM "YouTubeVideos"
                    INNER JOIN "Podcasts" ON "YouTubeVideos".podcastid = "Podcasts".podcastid
                    WHERE "Podcasts".podcastid = $1 AND "Podcasts".userid = $2
                    ORDER BY "YouTubeVideos".publishedat DESC
                "#)
                .bind(podcast_id)
                .bind(user_id)
                .fetch_all(pool)
                .await?;

                if rows.is_empty() {
                    return Ok(None);
                }

                let mut episodes = Vec::new();
                for row in rows {
                    let episode = serde_json::json!({
                        "Podcastid": row.try_get::<i32, _>("podcastid").unwrap_or(0),
                        "Podcastname": row.try_get::<String, _>("podcastname").unwrap_or_default(),
                        "Episodeid": row.try_get::<i32, _>("episodeid").unwrap_or(0),
                        "Episodetitle": row.try_get::<String, _>("episodetitle").unwrap_or_default(),
                        "Episodepubdate": row.try_get::<chrono::NaiveDateTime, _>("episodepubdate")
                            .map(|dt| dt.and_utc().to_rfc3339())
                            .unwrap_or_default(),
                        "Episodedescription": row.try_get::<String, _>("episodedescription").unwrap_or_default(),
                        "Episodeartwork": row.try_get::<String, _>("episodeartwork").unwrap_or_default(),
                        "Episodeurl": row.try_get::<String, _>("episodeurl").unwrap_or_default(),
                        "Episodeduration": row.try_get::<i32, _>("episodeduration").unwrap_or(0),
                        "Listenduration": row.try_get::<i32, _>("listenduration").unwrap_or(0),
                        "Guid": row.try_get::<String, _>("guid").unwrap_or_default()
                    });
                    episodes.push(episode);
                }

                Ok(Some(episodes))
            },
        })
    }

    // Remove YouTube channel by URL - matches Python remove_youtube_channel_by_url function exactly
    pub async fn remove_youtube_channel_by_url(
        &self,
        channel_name: &str,
        channel_url: &str,
        user_id: i32,
    ) -> AppResult<()> {
        info!("got to remove youtube channel");
        
        // Get the PodcastID first
        let podcast_id = dialect_match!(self, {
            pg(pool) => {
                let row = q::query(r#"
                    SELECT podcastid
                    FROM "Podcasts"
                    WHERE podcastname = $1
                    AND feedurl = $2
                    AND userid = $3
                    AND isyoutubechannel = TRUE
                "#)
                .bind(channel_name)
                .bind(channel_url)
                .bind(user_id)
                .fetch_optional(pool)
                .await?;

                if let Some(row) = row {
                    row.try_get::<i32, _>("podcastid")?
                } else {
                    return Err(AppError::external_error(&format!("No YouTube channel found with name {}", channel_name)));
                }
            },
        });

        // Remove the channel by ID
        self.remove_youtube_channel_by_id(podcast_id, user_id).await
    }

    // Remove YouTube channel by ID - matches Python remove_youtube_channel function exactly
    pub async fn remove_youtube_channel_by_id(
        &self,
        podcast_id: i32,
        user_id: i32,
    ) -> AppResult<()> {
        // First, get all video IDs for the podcast so we can delete the files
        let video_ids: Vec<String> = dialect_match!(self, {
            pg(pool) => {
                let rows = q::query(r#"SELECT youtubevideoid FROM "YouTubeVideos" WHERE podcastid = $1"#)
                    .bind(podcast_id)
                    .fetch_all(pool)
                    .await?;

                rows.into_iter()
                    .map(|row| row.try_get::<String, _>("youtubevideoid").unwrap_or_default())
                    .collect()
            },
        });

        // Delete the MP3 files for each video
        for video_id in &video_ids {
            let file_paths = vec![
                format!("{}/{}.mp3", crate::paths::youtube_downloads_dir(), video_id),
                format!("{}/{}.mp3.mp3", crate::paths::youtube_downloads_dir(), video_id), // In case of double extension
            ];

            for file_path in file_paths {
                if tokio::fs::metadata(&file_path).await.is_ok() {
                    match tokio::fs::remove_file(&file_path).await {
                        Ok(_) => info!("Deleted file: {}", file_path),
                        Err(e) => warn!("Failed to delete file {}: {}", file_path, e),
                    }
                }
            }
        }

        // Delete from the related tables in the correct order
        dialect_match!(self, {
            pg(pool) => {
                let delete_queries = vec![
                    r#"DELETE FROM "PlaylistContents" WHERE episodeid IN (SELECT videoid FROM "YouTubeVideos" WHERE podcastid = $1)"#,
                    r#"DELETE FROM "UserEpisodeHistory" WHERE episodeid IN (SELECT videoid FROM "YouTubeVideos" WHERE podcastid = $1)"#,
                    r#"DELETE FROM "UserVideoHistory" WHERE videoid IN (SELECT videoid FROM "YouTubeVideos" WHERE podcastid = $1)"#,
                    r#"DELETE FROM "DownloadedEpisodes" WHERE episodeid IN (SELECT videoid FROM "YouTubeVideos" WHERE podcastid = $1)"#,
                    r#"DELETE FROM "DownloadedVideos" WHERE videoid IN (SELECT videoid FROM "YouTubeVideos" WHERE podcastid = $1)"#,
                    r#"DELETE FROM "SavedVideos" WHERE videoid IN (SELECT videoid FROM "YouTubeVideos" WHERE podcastid = $1)"#,
                    r#"DELETE FROM "SavedEpisodes" WHERE episodeid IN (SELECT videoid FROM "YouTubeVideos" WHERE podcastid = $1)"#,
                    r#"DELETE FROM "EpisodeQueue" WHERE episodeid IN (SELECT videoid FROM "YouTubeVideos" WHERE podcastid = $1)"#,
                    r#"DELETE FROM "YouTubeVideos" WHERE podcastid = $1"#,
                    r#"DELETE FROM "Podcasts" WHERE podcastid = $1 AND isyoutubechannel = TRUE"#,
                ];

                for query in delete_queries {
                    q::query(query)
                        .bind(podcast_id)
                        .execute(pool)
                        .await?;
                }

                // Update user stats
                q::query(r#"UPDATE "UserStats" SET podcastsadded = podcastsadded - 1 WHERE userid = $1"#)
                    .bind(user_id)
                    .execute(pool)
                    .await?;
            },
        });

        Ok(())
    }
}
