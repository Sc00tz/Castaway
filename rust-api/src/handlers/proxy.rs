use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use crate::AppState;

#[derive(Deserialize, utoipa::IntoParams)]
pub struct ImageProxyQuery {
    pub url: String,
}

// Server-side image cache: 1-day TTL, skip caching anything larger than this so a few huge images
// can't blow out Redis. Cached entries are stored as two keys: bytes + content-type.
const IMAGE_CACHE_TTL_SECS: u64 = 86_400;
const IMAGE_CACHE_MAX_BYTES: usize = 5 * 1024 * 1024;

fn image_cache_keys(url: &str) -> (String, String) {
    let mut hasher = DefaultHasher::new();
    url.hash(&mut hasher);
    let h = hasher.finish();
    (format!("imgproxy:{:x}:data", h), format!("imgproxy:{:x}:ct", h))
}

fn image_response(content_type: &str, bytes: axum::body::Bytes) -> Response {
    let mut headers = HeaderMap::new();
    if let Ok(ct) = content_type.parse() {
        headers.insert("content-type", ct);
    }
    headers.insert("cache-control", "public, max-age=86400".parse().unwrap());
    headers.insert("access-control-allow-origin", "*".parse().unwrap());
    headers.insert("x-content-type-options", "nosniff".parse().unwrap());
    (headers, bytes).into_response()
}

// Image proxy endpoint - matches Python proxy_image endpoint
#[utoipa::path(
    get,
    path = "/image",
    tag = "proxy",
    summary = "Proxy image",
    params(ImageProxyQuery),
    responses(
        (status = 200, description = "Proxied image bytes", content_type = "application/octet-stream"),
    ),
)]
pub async fn proxy_image(
    State(state): State<AppState>,
    Query(query): Query<ImageProxyQuery>,
) -> Result<Response, StatusCode> {
    tracing::debug!("Image proxy request received for URL: {}", query.url);

    if !is_valid_image_url(&query.url) {
        tracing::error!("Invalid image URL: {}", query.url);
        return Err(StatusCode::BAD_REQUEST);
    }

    // Serve from the server-side cache when present (avoids re-fetching upstream for every cold
    // client). Best-effort: any Redis hiccup just falls through to a live fetch.
    let (data_key, ct_key) = image_cache_keys(&query.url);
    if let Ok(Some(cached)) = state.redis_client.get::<Vec<u8>>(&data_key).await {
        if !cached.is_empty() {
            let ct = state
                .redis_client
                .get::<String>(&ct_key)
                .await
                .ok()
                .flatten()
                .unwrap_or_else(|| "application/octet-stream".to_string());
            tracing::debug!("Image proxy cache hit for {}", query.url);
            return Ok(image_response(&ct, axum::body::Bytes::from(cached)));
        }
    }

    // The same guard as every other fetch of an outside address: the URL, every address its
    // host resolves to, and every redirect must be public (or allowed by ALLOWED_PRIVATE_NETWORKS).
    if let Err(reason) = crate::services::url_guard::ensure_safe_public_url_async(&query.url).await {
        tracing::warn!("Blocked image proxy request: {reason}");
        return Err(StatusCode::FORBIDDEN);
    }

    let client = crate::services::url_guard::guarded_client_builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    tracing::info!("Fetching image from: {}", query.url);
    
    let response = client
        .get(&query.url)
        .send()
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;

    tracing::info!("Image fetch response status: {}", response.status());

    if !response.status().is_success() {
        return Err(StatusCode::BAD_GATEWAY);
    }

    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|ct| ct.to_str().ok())
        .unwrap_or("")
        .to_string();

    tracing::debug!("Content type: {}", content_type);

    if !content_type.starts_with("image/") && content_type != "application/octet-stream" {
        tracing::error!("Invalid content type: {}", content_type);
        return Err(StatusCode::BAD_REQUEST);
    }

    let bytes = response.bytes().await.map_err(|_| StatusCode::BAD_GATEWAY)?;

    // Populate the cache (best-effort) for reasonably sized images.
    if !bytes.is_empty() && bytes.len() <= IMAGE_CACHE_MAX_BYTES {
        let _ = state
            .redis_client
            .set_ex(&data_key, bytes.to_vec(), IMAGE_CACHE_TTL_SECS)
            .await;
        let _ = state
            .redis_client
            .set_ex(&ct_key, content_type.clone(), IMAGE_CACHE_TTL_SECS)
            .await;
    }

    tracing::debug!("Returning freshly fetched image response");
    Ok(image_response(&content_type, bytes))
}

fn is_valid_image_url(url: &str) -> bool {
    // Basic URL validation - check if it's a valid URL and uses http/https
    if let Ok(parsed_url) = url::Url::parse(url) {
        matches!(parsed_url.scheme(), "http" | "https")
    } else {
        false
    }
}

// Returns a simple SVG placeholder image at the requested dimensions
pub async fn placeholder_image(
    Path((width, height)): Path<(u32, u32)>,
) -> impl IntoResponse {
    let svg = format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><rect width="{w}" height="{h}" fill="#1a1a2e"/><text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle" font-family="sans-serif" font-size="14" fill="#4a4a6a">{w}x{h}</text></svg>"##,
        w = width,
        h = height
    );

    let mut headers = HeaderMap::new();
    headers.insert("content-type", "image/svg+xml".parse().unwrap());
    headers.insert("cache-control", "public, max-age=86400".parse().unwrap());
    (headers, svg)
}