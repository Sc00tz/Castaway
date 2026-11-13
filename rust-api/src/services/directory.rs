//! The podcast directories Castaway searches directly: Apple's iTunes Search API (no key needed)
//! and Podcast Index (the admin's own free API key and secret, entered in Settings).
//!
//! Responses are returned as the directory sends them, so clients parse the iTunes and Podcast
//! Index formats they already know.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use sha1::{Digest, Sha1};

use crate::config::ApiConfig;
use crate::database::DatabasePool;
use crate::error::{AppError, AppResult};

pub const DEFAULT_ITUNES_SEARCH_URL: &str = "https://itunes.apple.com/search";
pub const DEFAULT_PODCAST_INDEX_URL: &str = "https://api.podcastindex.org/api/1.0";

const NO_KEY: &str = "Podcast Index search needs an API key. An admin can add one in Settings → Podcast Index \
                      (it's free from api.podcastindex.org). Apple Podcasts search works without one.";

fn client() -> reqwest::Client {
    reqwest::Client::builder()
        .user_agent(concat!("Castaway/", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_secs(20))
        .build()
        .expect("HTTP client")
}

/// Searches Apple Podcasts by title.
pub async fn itunes_search(api: &ApiConfig, term: &str) -> AppResult<serde_json::Value> {
    let response = client()
        .get(&api.itunes_search_url)
        .query(&[("term", term), ("media", "podcast"), ("entity", "podcast")])
        .send()
        .await
        .map_err(|e| unreachable("Apple Podcasts", e))?;
    read_json("Apple Podcasts", response).await
}

/// Calls a Podcast Index endpoint (`path` like "/search/byterm") with this server's key.
pub async fn podcast_index(db: &DatabasePool, api: &ApiConfig, path: &str, params: &[(&str, String)]) -> AppResult<serde_json::Value> {
    let (key, secret) = db.podcast_index_credentials().await?.ok_or_else(|| AppError::service_unavailable(NO_KEY))?;
    podcast_index_with(api, &key, &secret, path, params).await
}

/// Whether this server has a Podcast Index key.
pub async fn podcast_index_configured(db: &DatabasePool) -> AppResult<bool> {
    Ok(db.podcast_index_credentials().await?.is_some())
}

/// Calls Podcast Index with the given key and secret (used to check a key before saving it).
pub async fn podcast_index_with(api: &ApiConfig, key: &str, secret: &str, path: &str, params: &[(&str, String)]) -> AppResult<serde_json::Value> {
    let url = format!("{}{}", api.podcast_index_url.trim_end_matches('/'), path);
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or_default().to_string();
    let response = client()
        .get(&url)
        .query(params)
        .header("X-Auth-Date", &now)
        .header("X-Auth-Key", key)
        .header("Authorization", auth_hash(key, secret, &now))
        .send()
        .await
        .map_err(|e| unreachable("Podcast Index", e))?;
    if matches!(response.status().as_u16(), 401 | 403) {
        return Err(AppError::service_unavailable(
            "Podcast Index didn't accept this server's API key. An admin can check it in Settings → Podcast Index.",
        ));
    }
    read_json("Podcast Index", response).await
}

/// Podcast Index's request signature: SHA-1 of key + secret + the X-Auth-Date value, in hex.
fn auth_hash(key: &str, secret: &str, date: &str) -> String {
    let mut h = Sha1::new();
    h.update(format!("{key}{secret}{date}").as_bytes());
    hex::encode(h.finalize())
}

fn unreachable(name: &str, e: reqwest::Error) -> AppError {
    tracing::warn!("{name} unreachable: {e}");
    AppError::service_unavailable(format!("{name} isn't reachable right now: {}", e.without_url()))
}

async fn read_json(name: &str, response: reqwest::Response) -> AppResult<serde_json::Value> {
    let status = response.status();
    if !status.is_success() {
        tracing::warn!("{name} answered HTTP {status}");
        return Err(AppError::service_unavailable(format!("{name} answered with an error: HTTP {}", status.as_u16())));
    }
    response
        .json()
        .await
        .map_err(|e| AppError::service_unavailable(format!("{name} sent a response Castaway couldn't read: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signs_requests_the_way_podcast_index_documents() {
        // SHA-1 of "keysecret1700000000", computed independently.
        assert_eq!(auth_hash("key", "secret", "1700000000"), "abaf71c02050c31e4d4e6b08c1625173af0445ba");
        assert_eq!(auth_hash("a", "b", "1").len(), 40);
    }
}
