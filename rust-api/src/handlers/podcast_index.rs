//! Admin settings for the Podcast Index API key Castaway searches with. Apple Podcasts search
//! needs no key; Podcast Index search, person search, trending and categories need one.

use axum::{extract::State, http::HeaderMap, Json};
use serde::{Deserialize, Serialize};

use crate::{error::AppError, handlers::require_admin, services::directory, AppState};

#[derive(Serialize, utoipa::ToSchema)]
pub struct PodcastIndexStatus {
    /// Whether a key and secret are saved.
    pub configured: bool,
    /// The saved key (the secret is never sent back).
    pub api_key: Option<String>,
}

async fn status(state: &AppState) -> Result<PodcastIndexStatus, AppError> {
    let api_key = state.db_pool.podcast_index_key().await?;
    Ok(PodcastIndexStatus { configured: directory::podcast_index_configured(&state.db_pool).await?, api_key })
}

#[utoipa::path(
    get,
    path = "/podcast_index",
    tag = "settings",
    summary = "Podcast Index key status",
    description = "Admin only. Whether this server has a Podcast Index API key, and the key itself.",
    security(("api_key" = [])),
    responses(
        (status = 200, description = "Success", body = PodcastIndexStatus),
        (status = 401, description = "Invalid or missing API key"),
        (status = 403, description = "Not an admin"),
    ),
)]
pub async fn get_podcast_index(State(state): State<AppState>, headers: HeaderMap) -> Result<Json<PodcastIndexStatus>, AppError> {
    require_admin(&state, &headers).await?;
    Ok(Json(status(&state).await?))
}

#[derive(Deserialize, utoipa::ToSchema)]
pub struct SetPodcastIndex {
    /// Both empty removes the saved key.
    pub api_key: String,
    pub api_secret: String,
}

#[utoipa::path(
    post,
    path = "/podcast_index",
    tag = "settings",
    summary = "Save the Podcast Index key",
    description = "Admin only. Checks the key and secret with Podcast Index, then saves them (the secret encrypted). Send both empty to remove them.",
    request_body = SetPodcastIndex,
    security(("api_key" = [])),
    responses(
        (status = 200, description = "Saved", body = PodcastIndexStatus),
        (status = 400, description = "Podcast Index didn't accept the key and secret"),
        (status = 401, description = "Invalid or missing API key"),
        (status = 403, description = "Not an admin"),
    ),
)]
pub async fn set_podcast_index(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(request): Json<SetPodcastIndex>,
) -> Result<Json<PodcastIndexStatus>, AppError> {
    require_admin(&state, &headers).await?;
    let (key, secret) = (request.api_key.trim(), request.api_secret.trim());
    if key.is_empty() && secret.is_empty() {
        state.db_pool.set_podcast_index_credentials(None).await?;
        return Ok(Json(status(&state).await?));
    }
    if key.is_empty() || secret.is_empty() {
        return Err(AppError::bad_request("Enter both the API key and the API secret"));
    }
    // A cheap real request, so a mistyped key is caught now rather than on the next search.
    let check = [("q", "podcast".to_string()), ("max", "1".to_string())];
    if let Err(e) = directory::podcast_index_with(&state.config.api, key, secret, "/search/byterm", &check).await {
        return Err(match e {
            AppError::ServiceUnavailable(msg) if msg.contains("didn't accept") => {
                AppError::bad_request("Podcast Index didn't accept that API key and secret")
            }
            other => other,
        });
    }
    state.db_pool.set_podcast_index_credentials(Some((key, secret))).await?;
    Ok(Json(status(&state).await?))
}
