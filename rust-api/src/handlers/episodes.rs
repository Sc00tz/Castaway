use axum::{extract::State, http::HeaderMap, response::Json};
use axum::response::{Response, IntoResponse};
use axum::http::{StatusCode, header};
use sqlx::Row;
use crate::{
    error::{AppError, AppResult},
    handlers::{extract_api_key, require_episode_owner, require_episodes_owner, require_valid_api_key},
    models::{BulkEpisodeActionRequest, BulkEpisodeActionResponse},
    AppState,
};
use crate::database::dialect::dialect_match;

// Bulk episode action handlers for efficient mass operations

// Bulk mark episodes as completed
#[utoipa::path(
    post,
    path = "/bulk_mark_episodes_completed",
    tag = "episodes",
    summary = "Bulk mark episodes completed",
    request_body = BulkEpisodeActionRequest,
    security(("api_key" = [])),
    responses(
        (status = 200, description = "Success", body = BulkEpisodeActionResponse),
        (status = 401, description = "Invalid or missing API key"),
    ),
)]
pub async fn bulk_mark_episodes_completed(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<BulkEpisodeActionRequest>,
) -> AppResult<Json<BulkEpisodeActionResponse>> {
    let api_key = extract_api_key(&headers)?;
    require_valid_api_key(&state, &api_key).await?;
    
    let calling_user_id = state.db_pool.get_user_id_from_api_key(&api_key).await?;
    if calling_user_id != request.user_id {
        return Err(AppError::forbidden("You can only mark episodes as completed for yourself!"));
    }

    let is_youtube = request.is_youtube.unwrap_or(false);
    require_episodes_owner(&state, request.user_id, &request.episode_ids, is_youtube).await?;
    let (processed_count, failed_count) = state.db_pool
        .bulk_mark_episodes_completed(request.episode_ids, request.user_id, is_youtube)
        .await?;

    let message = if failed_count > 0 {
        format!("Marked {} episodes as completed, {} failed", processed_count, failed_count)
    } else {
        format!("Successfully marked {} episodes as completed", processed_count)
    };

    Ok(Json(BulkEpisodeActionResponse {
        message,
        processed_count,
        failed_count: if failed_count > 0 { Some(failed_count) } else { None },
    }))
}

// Bulk save episodes
#[utoipa::path(
    post,
    path = "/bulk_save_episodes",
    tag = "episodes",
    summary = "Bulk save episodes",
    request_body = BulkEpisodeActionRequest,
    security(("api_key" = [])),
    responses(
        (status = 200, description = "Success", body = BulkEpisodeActionResponse),
        (status = 401, description = "Invalid or missing API key"),
    ),
)]
pub async fn bulk_save_episodes(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<BulkEpisodeActionRequest>,
) -> AppResult<Json<BulkEpisodeActionResponse>> {
    let api_key = extract_api_key(&headers)?;
    require_valid_api_key(&state, &api_key).await?;
    
    let calling_user_id = state.db_pool.get_user_id_from_api_key(&api_key).await?;
    if calling_user_id != request.user_id {
        return Err(AppError::forbidden("You can only save episodes for yourself!"));
    }

    let is_youtube = request.is_youtube.unwrap_or(false);
    require_episodes_owner(&state, request.user_id, &request.episode_ids, is_youtube).await?;
    let (processed_count, failed_count) = state.db_pool
        .bulk_save_episodes(request.episode_ids, request.user_id, is_youtube)
        .await?;

    let message = if failed_count > 0 {
        format!("Saved {} episodes, {} failed or already saved", processed_count, failed_count)
    } else {
        format!("Successfully saved {} episodes", processed_count)
    };

    Ok(Json(BulkEpisodeActionResponse {
        message,
        processed_count,
        failed_count: if failed_count > 0 { Some(failed_count) } else { None },
    }))
}

// Bulk queue episodes
#[utoipa::path(
    post,
    path = "/bulk_queue_episodes",
    tag = "episodes",
    summary = "Bulk queue episodes",
    request_body = BulkEpisodeActionRequest,
    security(("api_key" = [])),
    responses(
        (status = 200, description = "Success", body = BulkEpisodeActionResponse),
        (status = 401, description = "Invalid or missing API key"),
    ),
)]
pub async fn bulk_queue_episodes(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<BulkEpisodeActionRequest>,
) -> AppResult<Json<BulkEpisodeActionResponse>> {
    let api_key = extract_api_key(&headers)?;
    require_valid_api_key(&state, &api_key).await?;
    
    let calling_user_id = state.db_pool.get_user_id_from_api_key(&api_key).await?;
    if calling_user_id != request.user_id {
        return Err(AppError::forbidden("You can only queue episodes for yourself!"));
    }

    let is_youtube = request.is_youtube.unwrap_or(false);
    require_episodes_owner(&state, request.user_id, &request.episode_ids, is_youtube).await?;
    // The batch keeps its order, placed like a single add.
    let placement = crate::handlers::podcasts::resolve_queue_placement(&state, request.user_id, request.position, None).await?;
    let (processed_count, failed_count) = state.db_pool
        .bulk_queue_episodes(request.episode_ids, request.user_id, is_youtube, placement)
        .await?;

    let message = if failed_count > 0 {
        format!("Queued {} episodes, {} failed or already queued", processed_count, failed_count)
    } else {
        format!("Successfully queued {} episodes", processed_count)
    };

    Ok(Json(BulkEpisodeActionResponse {
        message,
        processed_count,
        failed_count: if failed_count > 0 { Some(failed_count) } else { None },
    }))
}

// Bulk download episodes - triggers download tasks
#[utoipa::path(
    post,
    path = "/bulk_download_episodes",
    tag = "episodes",
    summary = "Bulk download episodes",
    request_body = BulkEpisodeActionRequest,
    security(("api_key" = [])),
    responses(
        (status = 200, description = "Success", body = BulkEpisodeActionResponse),
        (status = 401, description = "Invalid or missing API key"),
    ),
)]
pub async fn bulk_download_episodes(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<BulkEpisodeActionRequest>,
) -> AppResult<Json<BulkEpisodeActionResponse>> {
    let api_key = extract_api_key(&headers)?;
    require_valid_api_key(&state, &api_key).await?;
    
    let calling_user_id = state.db_pool.get_user_id_from_api_key(&api_key).await?;
    if calling_user_id != request.user_id {
        return Err(AppError::forbidden("You can only download episodes for yourself!"));
    }

    // Check if server downloads are enabled
    let downloads_enabled = state.db_pool.download_status().await?;
    if !downloads_enabled {
        return Err(AppError::forbidden("Server downloads are disabled by the administrator."));
    }

    let is_youtube = request.is_youtube.unwrap_or(false);
    require_episodes_owner(&state, request.user_id, &request.episode_ids, is_youtube).await?;
    let mut processed_count = 0;
    let mut failed_count = 0;

    // Check if episodes are already downloaded and queue download tasks
    for episode_id in request.episode_ids {
        let is_downloaded = state.db_pool
            .check_downloaded(request.user_id, episode_id, is_youtube)
            .await?;

        if !is_downloaded {
            let result = if is_youtube {
                state.task_spawner.spawn_download_youtube_video(episode_id, request.user_id).await
            } else {
                state.task_spawner.spawn_download_podcast_episode(episode_id, request.user_id).await
            };

            match result {
                Ok(_) => processed_count += 1,
                Err(_) => failed_count += 1,
            }
        }
    }

    let message = if failed_count > 0 {
        format!("Queued {} episodes for download, {} failed or already downloaded", processed_count, failed_count)
    } else {
        format!("Successfully queued {} episodes for download", processed_count)
    };

    Ok(Json(BulkEpisodeActionResponse {
        message,
        processed_count,
        failed_count: if failed_count > 0 { Some(failed_count) } else { None },
    }))
}

// Bulk delete downloaded episodes - removes multiple downloaded episodes at once
#[utoipa::path(
    post,
    path = "/bulk_delete_downloaded_episodes",
    tag = "episodes",
    summary = "Bulk delete downloaded episodes",
    request_body = BulkEpisodeActionRequest,
    security(("api_key" = [])),
    responses(
        (status = 200, description = "Success", body = BulkEpisodeActionResponse),
        (status = 401, description = "Invalid or missing API key"),
    ),
)]
pub async fn bulk_delete_downloaded_episodes(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<BulkEpisodeActionRequest>,
) -> AppResult<Json<BulkEpisodeActionResponse>> {
    let api_key = extract_api_key(&headers)?;
    require_valid_api_key(&state, &api_key).await?;
    
    let calling_user_id = state.db_pool.get_user_id_from_api_key(&api_key).await?;
    if calling_user_id != request.user_id {
        return Err(AppError::forbidden("You can only delete your own downloaded episodes!"));
    }

    let is_youtube = request.is_youtube.unwrap_or(false);
    require_episodes_owner(&state, request.user_id, &request.episode_ids, is_youtube).await?;
    let (mut processed_count, mut failed_count) = (0, 0);
    for episode_id in request.episode_ids {
        match crate::handlers::podcasts::delete_download(&state, request.user_id, episode_id, is_youtube).await {
            Ok(true) => processed_count += 1,
            _ => failed_count += 1,
        }
    }

    let message = if failed_count > 0 {
        format!("Deleted {} downloaded episodes, {} failed or were not found", processed_count, failed_count)
    } else {
        format!("Successfully deleted {} downloaded episodes", processed_count)
    };

    Ok(Json(BulkEpisodeActionResponse {
        message,
        processed_count,
        failed_count: if failed_count > 0 { Some(failed_count) } else { None },
    }))
}

// Share episode - creates a shareable URL that expires in 60 days
#[utoipa::path(
    post,
    path = "/share_episode/{episode_id}",
    tag = "episodes",
    summary = "Share episode",
    params(("episode_id" = i32, Path)),
    security(("api_key" = [])),
    responses(
        (status = 200, description = "Success", body = serde_json::Value),
        (status = 401, description = "Invalid or missing API key"),
    ),
)]
pub async fn share_episode(
    State(state): State<AppState>,
    axum::extract::Path(episode_id): axum::extract::Path<i32>,
    headers: HeaderMap,
) -> AppResult<Json<serde_json::Value>> {
    let api_key = extract_api_key(&headers)?;
    require_valid_api_key(&state, &api_key).await?;
    
    // Get the user ID from the API key
    let user_id = state.db_pool.get_user_id_from_api_key(&api_key).await?;
    require_episode_owner(&state, user_id, episode_id, false).await?;
    
    // Generate unique share code and expiration date
    let share_code = uuid::Uuid::new_v4().to_string();
    let expiration_date = chrono::Utc::now() + chrono::Duration::days(60);
    
    // Insert the shared episode entry
    let result = state.db_pool
        .add_shared_episode(episode_id, user_id, &share_code, expiration_date)
        .await?;
    
    if result {
        Ok(Json(serde_json::json!({ "url_key": share_code })))
    } else {
        Err(AppError::internal("Failed to share episode"))
    }
}

// Get episode by URL key - for accessing shared episodes
#[utoipa::path(
    get,
    path = "/episode_by_url/{url_key}",
    tag = "episodes",
    summary = "Get episode by url key",
    params(("url_key" = String, Path)),
    responses(
        (status = 200, description = "Success", body = serde_json::Value),
    ),
)]
pub async fn get_episode_by_url_key(
    State(state): State<AppState>,
    axum::extract::Path(url_key): axum::extract::Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    // Find the episode ID associated with the URL key
    let episode_id = match state.db_pool.get_episode_id_by_share_code(&url_key).await? {
        Some(id) => id,
        None => return Err(AppError::not_found("Invalid or expired URL key")),
    };
    
    // Now retrieve the episode metadata using the special shared episode method
    // This bypasses user restrictions for public shared access
    let episode_data = state.db_pool
        .get_shared_episode_metadata(episode_id)
        .await?;
    
    Ok(Json(serde_json::json!({ "episode": episode_data })))
}

// Download episode file with metadata
#[utoipa::path(
    get,
    path = "/{episode_id}/download",
    tag = "episodes",
    summary = "Download an episode media file",
    params(
        ("episode_id" = i32, Path, description = "Episode ID to download"),
        ("api_key" = Option<String>, Query, description = "API key (alternative to the Api-Key header)"),
    ),
    security(("api_key" = [])),
    responses(
        (status = 200, description = "Episode media file stream", content_type = "application/octet-stream"),
        (status = 401, description = "API key is required or invalid"),
    ),
)]
pub async fn download_episode_file(
    State(state): State<AppState>,
    axum::extract::Path(episode_id): axum::extract::Path<i32>,
    headers: HeaderMap,
    axum::extract::Query(params): axum::extract::Query<std::collections::HashMap<String, String>>,
) -> AppResult<impl IntoResponse> {
    // Try to get API key from header first, then from query parameter
    let api_key = if let Ok(key) = extract_api_key(&headers) {
        key
    } else if let Some(key) = params.get("api_key") {
        key.clone()
    } else {
        return Err(AppError::unauthorized("API key is required"));
    };
    
    require_valid_api_key(&state, &api_key).await?;
    
    let user_id = state.db_pool.get_user_id_from_api_key(&api_key).await?;
    // The download uses the owning podcast's stored feed credentials: owner only.
    require_episode_owner(&state, user_id, episode_id, false).await?;
    
    // Get episode metadata
    let episode_info = dialect_match!(&state.db_pool, {
        pg(pool) => {
            let row = q::query(r#"
                SELECT e."episodeurl", e."episodetitle", p."podcastname",
                       e."episodepubdate", p."author", e."episodeartwork", p."artworkurl",
                       e."episodedescription", p."username", p."password",
                       p."feedurl", e."episodeguid", e."episodeduration"
                FROM "Episodes" e
                JOIN "Podcasts" p ON e."feedid" = p."feedid" AND p."userid" = $2
                WHERE e."episodeid" = $1
            "#)
            .bind(episode_id)
            .bind(user_id)
            .fetch_one(pool)
            .await?;

            (
                row.try_get::<String, _>("episodeurl")?,
                row.try_get::<String, _>("episodetitle")?,
                row.try_get::<String, _>("podcastname")?,
                row.try_get::<Option<chrono::NaiveDateTime>, _>("episodepubdate")?,
                row.try_get::<Option<String>, _>("author")?,
                row.try_get::<Option<String>, _>("episodeartwork")?,
                row.try_get::<Option<String>, _>("artworkurl")?,
                row.try_get::<Option<String>, _>("episodedescription")?,
                row.try_get::<Option<String>, _>("username")?,
                row.try_get::<Option<String>, _>("password")?,
                row.try_get::<Option<String>, _>("feedurl")?,
                row.try_get::<Option<String>, _>("episodeguid")?,
                row.try_get::<Option<i32>, _>("episodeduration")?
            )
        },
        mysql(pool) => {
            let row = sqlx::query("
                SELECT e.EpisodeURL, e.EpisodeTitle, p.PodcastName,
                       e.EpisodePubDate, p.Author, e.EpisodeArtwork, p.ArtworkURL,
                       e.EpisodeDescription, p.Username, p.Password,
                       p.FeedURL, e.EpisodeGUID, e.EpisodeDuration
                FROM Episodes e
                JOIN Podcasts p ON e.FeedID = p.FeedID AND p.UserID = ?
                WHERE e.EpisodeID = ?
            ")
            .bind(user_id)
            .bind(episode_id)
            .fetch_one(pool)
            .await?;

            (
                row.try_get::<String, _>("EpisodeURL")?,
                row.try_get::<String, _>("EpisodeTitle")?,
                row.try_get::<String, _>("PodcastName")?,
                row.try_get::<Option<chrono::NaiveDateTime>, _>("EpisodePubDate")?,
                row.try_get::<Option<String>, _>("Author")?,
                row.try_get::<Option<String>, _>("EpisodeArtwork")?,
                row.try_get::<Option<String>, _>("ArtworkURL")?,
                row.try_get::<Option<String>, _>("EpisodeDescription")?,
                row.try_get::<Option<String>, _>("Username")?,
                row.try_get::<Option<String>, _>("Password")?,
                row.try_get::<Option<String>, _>("FeedURL")?,
                row.try_get::<Option<String>, _>("EpisodeGUID")?,
                row.try_get::<Option<i32>, _>("EpisodeDuration")?
            )
        },
    });

    let (episode_url, episode_title, podcast_name, pub_date, author, episode_artwork, artwork_url, description, feed_username, feed_password, feed_url, episode_guid, episode_duration) = episode_info;

    // SSRF guard: episode_url is the feed's <enclosure url>, which the feed's author controls,
    // and this handler returns whatever it fetches. Refuse internal destinations up front; the
    // guarded client also checks every redirect and DNS answer.
    crate::services::url_guard::ensure_safe_public_url_async(&episode_url)
        .await
        .map_err(|reason| AppError::bad_request(format!("Refusing to download episode URL: {}", reason)))?;

    // Download the episode file. Send a podcast-client User-Agent first; some hosts
    // (e.g. Buzzsprout) reject requests without one with 403 Forbidden.
    let client = crate::services::http::download_client();
    let build_request = |user_agent: &str| {
        let mut request = client
            .get(&episode_url)
            .header("User-Agent", user_agent)
            .header("Accept", "*/*");
        if let (Some(ref username), Some(ref password)) = (&feed_username, &feed_password) {
            if !username.is_empty() {
                request = request.basic_auth(username, Some(password));
            }
        }
        request
    };

    let mut response = build_request("PinePods/1.0")
        .send()
        .await
        .map_err(|e| AppError::internal(&format!("Failed to download episode: {}", crate::services::http::describe_error(&e))))?;

    // If we get a 403, retry with a browser User-Agent as a fallback.
    if response.status() == reqwest::StatusCode::FORBIDDEN {
        let browser_response = build_request("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
            .send()
            .await
            .map_err(|e| AppError::internal(&format!("Failed to download episode: {}", crate::services::http::describe_error(&e))))?;
        if browser_response.status().is_success() {
            response = browser_response;
        }
    }

    if !response.status().is_success() {
        return Err(AppError::internal(&format!("Server returned error: {}", response.status())));
    }

    let (content_type, extension) = media_type_for(
        response.headers().get(header::CONTENT_TYPE).and_then(|v| v.to_str().ok()),
        &episode_url,
    );

    // Stream the download into a temp file chunk by chunk, so even a multi-gigabyte video never
    // sits in memory. The name is random so concurrent downloads can't collide or be predicted.
    use tokio::io::AsyncWriteExt;
    let temp_path = std::env::temp_dir().join(format!("episode_{}.{}", uuid::Uuid::new_v4(), extension));
    let write_result: Result<(), AppError> = async {
        let mut file = tokio::fs::File::create(&temp_path)
            .await
            .map_err(|e| AppError::internal(&format!("Failed to create temp file: {}", e)))?;
        while let Some(chunk) = response.chunk()
            .await
            .map_err(|e| AppError::internal(&format!("Failed to download audio content: {}", e)))?
        {
            file.write_all(&chunk)
                .await
                .map_err(|e| AppError::internal(&format!("Failed to write temp file: {}", e)))?;
        }
        file.flush()
            .await
            .map_err(|e| AppError::internal(&format!("Failed to write temp file: {}", e)))
    }
    .await;
    if let Err(e) = write_result {
        let _ = tokio::fs::remove_file(&temp_path).await;
        return Err(e);
    }

    // Add metadata using the same shared tagging as server downloads. ID3 tags only belong on
    // MP3s (writing them into an M4A or video file can corrupt it), and the client download is a
    // single file with no folder, so sidecars do not apply here.
    let episode_meta = crate::services::download_metadata::EpisodeMetadata {
        title: episode_title.clone(),
        artist: author.clone().unwrap_or_else(|| "Unknown".to_string()),
        album: podcast_name.clone(),
        date: pub_date,
        description: description.clone(),
        feed_url: feed_url.clone(),
        episode_url: Some(episode_url.clone()),
        guid: episode_guid.clone(),
        duration: episode_duration,
        episode_artwork: episode_artwork.clone(),
        podcast_artwork: artwork_url.clone(),
    };
    if extension == "mp3" {
        if let Err(e) = crate::services::download_metadata::add_podcast_metadata(
            &temp_path,
            &episode_meta,
        ).await {
            tracing::warn!("Failed to add metadata to downloaded episode: {}", e);
        }
    }

    // Open the finished file, then unlink it right away: the open handle keeps the data readable
    // while it streams, and the temp file disappears even if the client disconnects midway.
    let file = tokio::fs::File::open(&temp_path).await;
    let _ = tokio::fs::remove_file(&temp_path).await;
    let file = file.map_err(|e| AppError::internal(&format!("Failed to read processed file: {}", e)))?;
    let file_len = file
        .metadata()
        .await
        .map_err(|e| AppError::internal(&format!("Failed to read processed file: {}", e)))?
        .len();

    // Create safe filename for download
    let safe_episode_title = episode_title.chars()
        .map(|c| if c.is_alphanumeric() || c == ' ' || c == '-' || c == '_' { c } else { '_' })
        .collect::<String>()
        .trim()
        .to_string();
    
    let safe_podcast_name = podcast_name.chars()
        .map(|c| if c.is_alphanumeric() || c == ' ' || c == '-' || c == '_' { c } else { '_' })
        .collect::<String>()
        .trim()
        .to_string();
    
    let pub_date_str = if let Some(date) = pub_date {
        date.format("%Y-%m-%d").to_string()
    } else {
        chrono::Utc::now().format("%Y-%m-%d").to_string()
    };
    
    let filename = format!("{}_{}_-_{}.{}", pub_date_str, safe_podcast_name, safe_episode_title, extension);

    // Stream the file back rather than loading it into memory.
    let response = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CONTENT_DISPOSITION, format!("attachment; filename=\"{}\"", filename))
        .header(header::CONTENT_LENGTH, file_len)
        .body(axum::body::Body::from_stream(tokio_util::io::ReaderStream::new(file)))
        .map_err(|e| AppError::internal(&format!("Failed to create response: {}", e)))?;

    Ok(response)
}

/// Content type and file extension for a downloaded episode, from the host's Content-Type, or
/// the URL's extension when the host sends a generic type. Falls back to MP3.
fn media_type_for(content_type: Option<&str>, url: &str) -> (&'static str, &'static str) {
    const KNOWN: &[(&str, &str, &str)] = &[
        // (content type, extension, other content types that mean the same)
        ("audio/mpeg", "mp3", "audio/mp3"),
        ("audio/mp4", "m4a", "audio/x-m4a audio/aac-mp4"),
        ("audio/aac", "aac", "audio/x-aac"),
        ("audio/ogg", "ogg", "application/ogg"),
        ("audio/opus", "opus", ""),
        ("audio/flac", "flac", "audio/x-flac"),
        ("audio/wav", "wav", "audio/x-wav audio/wave"),
        ("video/mp4", "mp4", "video/x-m4v"),
        ("video/webm", "webm", "audio/webm"),
    ];
    let declared = content_type
        .map(|ct| ct.split(';').next().unwrap_or("").trim().to_ascii_lowercase())
        .unwrap_or_default();
    for &(ct, ext, aliases) in KNOWN {
        if declared == ct || aliases.split_whitespace().any(|a| a == declared) {
            return (ct, ext);
        }
    }
    let url_ext = url::Url::parse(url)
        .ok()
        .and_then(|u| u.path().rsplit_once('.').map(|(_, ext)| ext.to_ascii_lowercase()));
    if let Some(url_ext) = url_ext {
        if let Some(&(ct, ext, _)) = KNOWN.iter().find(|(_, ext, _)| *ext == url_ext) {
            return (ct, ext);
        }
    }
    ("audio/mpeg", "mp3")
}

#[cfg(test)]
mod media_type_tests {
    use super::media_type_for;

    #[test]
    fn picks_type_from_header_then_url_then_mp3() {
        assert_eq!(media_type_for(Some("audio/mpeg"), "https://x/a"), ("audio/mpeg", "mp3"));
        assert_eq!(media_type_for(Some("audio/x-m4a; charset=binary"), "https://x/a"), ("audio/mp4", "m4a"));
        assert_eq!(media_type_for(Some("video/mp4"), "https://x/a.mp3"), ("video/mp4", "mp4"));
        assert_eq!(media_type_for(Some("application/octet-stream"), "https://x/ep.M4A?t=1"), ("audio/mp4", "m4a"));
        assert_eq!(media_type_for(None, "https://x/ep"), ("audio/mpeg", "mp3"));
    }
}

