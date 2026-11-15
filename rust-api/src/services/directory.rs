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
/// Apple's top-podcasts chart (US store), overall or for one genre.
pub const DEFAULT_APPLE_CHARTS_URL: &str = "https://itunes.apple.com/us/rss/toppodcasts";
/// Apple's lookup by ID, which gives each charted show's feed address.
pub const DEFAULT_ITUNES_LOOKUP_URL: &str = "https://itunes.apple.com/lookup";

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

/// Trending podcasts for the Discover page and recommendations. Podcast Index's trending list
/// when this server has a key; otherwise (or when Podcast Index fails) Apple's top chart, in the
/// same shape. `params` are Podcast Index's: `cat` (category names or ids, comma separated) and
/// `max` are honoured for Apple too.
pub async fn trending(db: &DatabasePool, api: &ApiConfig, params: &[(&str, String)]) -> AppResult<serde_json::Value> {
    if podcast_index_configured(db).await? {
        match podcast_index(db, api, "/podcasts/trending", params).await {
            Ok(body) => return Ok(body),
            Err(e) => tracing::warn!("Podcast Index trending failed, using Apple's chart: {e:?}"),
        }
    }
    let param = |name: &str| params.iter().find(|(k, _)| *k == name).map(|(_, v)| v.as_str());
    let max = param("max").and_then(|v| v.parse::<u32>().ok()).unwrap_or(10).clamp(1, 100);
    let genre = match param("cat").filter(|c| !c.trim().is_empty()) {
        None => None,
        Some(cats) => match cats.split(',').find_map(apple_genre_id) {
            Some(id) => Some(id),
            // A category Apple doesn't have: nothing, rather than the overall chart.
            None => return Ok(feed_list(Vec::new())),
        },
    };
    apple_chart(api, genre, max).await
}

/// The category list for "Browse by category": Podcast Index's when this server has a key,
/// otherwise (or when Podcast Index fails) Apple's main podcast genres, in the same shape.
pub async fn categories(db: &DatabasePool, api: &ApiConfig) -> AppResult<serde_json::Value> {
    if podcast_index_configured(db).await? {
        match podcast_index(db, api, "/categories/list", &[]).await {
            Ok(body) => return Ok(body),
            Err(e) => tracing::warn!("Podcast Index categories failed, using Apple's genres: {e:?}"),
        }
    }
    let genres = APPLE_GENRES
        .iter()
        .filter(|(_, _, parent)| *parent == 0)
        .map(|(id, name, _)| serde_json::json!({ "id": id, "name": name }))
        .collect();
    Ok(feed_list(genres))
}

fn feed_list(feeds: Vec<serde_json::Value>) -> serde_json::Value {
    serde_json::json!({ "status": "true", "count": feeds.len(), "feeds": feeds })
}

/// Apple's podcast genres: (id, name, parent genre id or 0 for a main genre).
const APPLE_GENRES: &[(u32, &str, u32)] = &[
    (1301, "Arts", 0),
    (1482, "Books", 1301),
    (1402, "Design", 1301),
    (1459, "Fashion & Beauty", 1301),
    (1306, "Food", 1301),
    (1405, "Performing Arts", 1301),
    (1406, "Visual Arts", 1301),
    (1321, "Business", 0),
    (1410, "Careers", 1321),
    (1493, "Entrepreneurship", 1321),
    (1412, "Investing", 1321),
    (1491, "Management", 1321),
    (1492, "Marketing", 1321),
    (1494, "Non-Profit", 1321),
    (1303, "Comedy", 0),
    (1496, "Comedy Interviews", 1303),
    (1495, "Improv", 1303),
    (1497, "Stand-Up", 1303),
    (1304, "Education", 0),
    (1501, "Courses", 1304),
    (1499, "How To", 1304),
    (1498, "Language Learning", 1304),
    (1500, "Self-Improvement", 1304),
    (1483, "Fiction", 0),
    (1486, "Comedy Fiction", 1483),
    (1484, "Drama", 1483),
    (1485, "Science Fiction", 1483),
    (1511, "Government", 0),
    (1512, "Health & Fitness", 0),
    (1513, "Alternative Health", 1512),
    (1514, "Fitness", 1512),
    (1518, "Medicine", 1512),
    (1517, "Mental Health", 1512),
    (1515, "Nutrition", 1512),
    (1516, "Sexuality", 1512),
    (1487, "History", 0),
    (1305, "Kids & Family", 0),
    (1519, "Education for Kids", 1305),
    (1521, "Parenting", 1305),
    (1522, "Pets & Animals", 1305),
    (1520, "Stories for Kids", 1305),
    (1502, "Leisure", 0),
    (1510, "Animation & Manga", 1502),
    (1503, "Automotive", 1502),
    (1504, "Aviation", 1502),
    (1506, "Crafts", 1502),
    (1507, "Games", 1502),
    (1505, "Hobbies", 1502),
    (1508, "Home & Garden", 1502),
    (1509, "Video Games", 1502),
    (1310, "Music", 0),
    (1523, "Music Commentary", 1310),
    (1524, "Music History", 1310),
    (1525, "Music Interviews", 1310),
    (1489, "News", 0),
    (1490, "Business News", 1489),
    (1526, "Daily News", 1489),
    (1531, "Entertainment News", 1489),
    (1530, "News Commentary", 1489),
    (1527, "Politics", 1489),
    (1529, "Sports News", 1489),
    (1528, "Tech News", 1489),
    (1314, "Religion & Spirituality", 0),
    (1438, "Buddhism", 1314),
    (1439, "Christianity", 1314),
    (1463, "Hinduism", 1314),
    (1440, "Islam", 1314),
    (1441, "Judaism", 1314),
    (1532, "Religion", 1314),
    (1444, "Spirituality", 1314),
    (1533, "Science", 0),
    (1538, "Astronomy", 1533),
    (1539, "Chemistry", 1533),
    (1540, "Earth Sciences", 1533),
    (1541, "Life Sciences", 1533),
    (1536, "Mathematics", 1533),
    (1534, "Natural Sciences", 1533),
    (1537, "Nature", 1533),
    (1542, "Physics", 1533),
    (1535, "Social Sciences", 1533),
    (1324, "Society & Culture", 0),
    (1543, "Documentary", 1324),
    (1302, "Personal Journals", 1324),
    (1443, "Philosophy", 1324),
    (1320, "Places & Travel", 1324),
    (1544, "Relationships", 1324),
    (1545, "Sports", 0),
    (1549, "Baseball", 1545),
    (1548, "Basketball", 1545),
    (1554, "Cricket", 1545),
    (1560, "Fantasy Sports", 1545),
    (1547, "Football", 1545),
    (1553, "Golf", 1545),
    (1550, "Hockey", 1545),
    (1552, "Rugby", 1545),
    (1551, "Running", 1545),
    (1546, "Soccer", 1545),
    (1558, "Swimming", 1545),
    (1556, "Tennis", 1545),
    (1557, "Volleyball", 1545),
    (1559, "Wilderness", 1545),
    (1555, "Wrestling", 1545),
    (1309, "TV & Film", 0),
    (1562, "After Shows", 1309),
    (1564, "Film History", 1309),
    (1565, "Film Interviews", 1309),
    (1563, "Film Reviews", 1309),
    (1561, "TV Reviews", 1309),
    (1318, "Technology", 0),
    (1488, "True Crime", 0),
];

/// Compares category names loosely: "Society &amp; Culture", "society-and-culture" and
/// "Society & Culture" are the same category.
fn category_key(name: &str) -> String {
    name.to_lowercase()
        .replace("&amp;", "&")
        .replace('&', " and ")
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

/// Apple's genre id for a category name (or an Apple genre id).
fn apple_genre_id(cat: &str) -> Option<u32> {
    let cat = cat.trim();
    if let Ok(id) = cat.parse::<u32>() {
        return APPLE_GENRES.iter().find(|(g, _, _)| *g == id).map(|(g, _, _)| *g);
    }
    let key = category_key(cat);
    APPLE_GENRES.iter().find(|(_, name, _)| category_key(name) == key).map(|(id, _, _)| *id)
}

/// Apple's top chart (overall or one genre), as Podcast Index trending feeds. The chart has no
/// feed addresses, so one lookup fetches them; shows Apple gives no feed for are left out.
async fn apple_chart(api: &ApiConfig, genre: Option<u32>, max: u32) -> AppResult<serde_json::Value> {
    let base = api.apple_charts_url.trim_end_matches('/');
    let url = match genre {
        Some(id) => format!("{base}/limit={max}/genre={id}/json"),
        None => format!("{base}/limit={max}/json"),
    };
    let response = client().get(&url).send().await.map_err(|e| unreachable("Apple Podcasts", e))?;
    let chart = read_json("Apple Podcasts", response).await?;
    // One charted show comes back as an object instead of a list.
    let entries: Vec<serde_json::Value> = match chart.pointer("/feed/entry") {
        Some(serde_json::Value::Array(list)) => list.clone(),
        Some(one @ serde_json::Value::Object(_)) => vec![one.clone()],
        _ => Vec::new(),
    };
    let charted: Vec<(i64, &serde_json::Value)> = entries
        .iter()
        .filter_map(|e| {
            let id = e.pointer("/id/attributes/im:id")?.as_str()?.parse::<i64>().ok()?;
            Some((id, e))
        })
        .collect();
    if charted.is_empty() {
        return Ok(feed_list(Vec::new()));
    }

    let ids = charted.iter().map(|(id, _)| id.to_string()).collect::<Vec<_>>().join(",");
    let response = client()
        .get(&api.itunes_lookup_url)
        .query(&[("id", ids.as_str()), ("entity", "podcast")])
        .send()
        .await
        .map_err(|e| unreachable("Apple Podcasts", e))?;
    let lookup = read_json("Apple Podcasts", response).await?;
    let shows: std::collections::HashMap<i64, &serde_json::Value> = lookup
        .get("results")
        .and_then(|r| r.as_array())
        .map(|list| {
            list.iter()
                .filter_map(|s| Some((s.get("collectionId")?.as_i64()?, s)))
                .collect()
        })
        .unwrap_or_default();

    let feeds = charted
        .into_iter()
        .filter_map(|(id, entry)| apple_feed(id, entry, shows.get(&id).copied()?))
        .collect();
    Ok(feed_list(feeds))
}

/// One charted show as a Podcast Index trending feed. No "id": it isn't in Podcast Index's
/// numbering, so clients add it by its feed address.
fn apple_feed(itunes_id: i64, entry: &serde_json::Value, show: &serde_json::Value) -> Option<serde_json::Value> {
    let text = |v: Option<&serde_json::Value>| v.and_then(|v| v.as_str()).unwrap_or_default().to_string();
    let url = text(show.get("feedUrl"));
    if url.is_empty() {
        return None;
    }
    let title = Some(text(show.get("collectionName")))
        .filter(|t| !t.is_empty())
        .unwrap_or_else(|| text(entry.pointer("/im:name/label")));
    let author = Some(text(show.get("artistName")))
        .filter(|a| !a.is_empty())
        .unwrap_or_else(|| text(entry.pointer("/im:artist/label")));
    let image = ["artworkUrl600", "artworkUrl100"]
        .iter()
        .map(|k| text(show.get(*k)))
        .find(|i| !i.is_empty())
        .unwrap_or_default();
    let names = show.get("genres").and_then(|g| g.as_array()).cloned().unwrap_or_default();
    let ids = show.get("genreIds").and_then(|g| g.as_array()).cloned().unwrap_or_default();
    let categories: serde_json::Map<String, serde_json::Value> = ids
        .iter()
        .zip(names.iter())
        .filter_map(|(id, name)| Some((id.as_str()?.to_string(), name.clone())))
        .filter(|(id, _)| id != "26") // "Podcasts", Apple's top level
        .collect();
    let newest = show
        .get("releaseDate")
        .and_then(|d| d.as_str())
        .and_then(|d| chrono::DateTime::parse_from_rfc3339(d).ok())
        .map(|d| d.timestamp())
        .unwrap_or(0);
    Some(serde_json::json!({
        "title": title,
        "url": url,
        "description": text(entry.pointer("/summary/label")),
        "author": author,
        "image": image,
        "artwork": image,
        "newestItemPublishTime": newest,
        "itunesId": itunes_id,
        "episodeCount": show.get("trackCount").and_then(|c| c.as_i64()).unwrap_or(0),
        "categories": categories,
    }))
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

    #[test]
    fn category_names_match_apples_genres_loosely() {
        assert_eq!(apple_genre_id("Society & Culture"), Some(1324));
        assert_eq!(apple_genre_id("society &amp; culture"), Some(1324));
        assert_eq!(apple_genre_id("Health and Fitness"), Some(1512));
        assert_eq!(apple_genre_id("tv-&-film"), Some(1309));
        assert_eq!(apple_genre_id("Tech News"), Some(1528));
        assert_eq!(apple_genre_id(" Technology "), Some(1318));
        assert_eq!(apple_genre_id("1301"), Some(1301));
        assert_eq!(apple_genre_id("9999"), None);
        assert_eq!(apple_genre_id("Not A Genre"), None);
    }

    #[test]
    fn the_genre_table_has_apples_nineteen_main_genres() {
        assert_eq!(APPLE_GENRES.iter().filter(|g| g.2 == 0).count(), 19);
        for (_, _, parent) in APPLE_GENRES.iter().filter(|g| g.2 != 0) {
            assert!(APPLE_GENRES.iter().any(|g| g.0 == *parent && g.2 == 0), "{parent}");
        }
    }
}
