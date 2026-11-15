//! Searching Apple Podcasts and Podcast Index directly from the server, and the admin setting for
//! this server's Podcast Index key.

use crate::harness::*;

fn itunes_result() -> String {
    json!({ "resultCount": 1, "results": [{ "collectionName": "Found Show", "feedUrl": "https://feeds.example.invalid/found.xml" }] })
        .to_string()
}

#[tokio::test(flavor = "multi_thread")]
async fn apple_search_needs_no_key_and_returns_apples_answer() {
    let app = TestApp::new().await;
    let user = app.user("searcher").await;
    app.fixtures().serve("itunes/search", Fixture::new("application/json", itunes_result()));

    let body = app.get("/api/data/proxy_search?query=found%20show&index=itunes").key(&user).send().await.ok_json();
    assert_eq!(body["results"][0]["collectionName"], "Found Show", "{body}");
    let hit = app.fixtures().hits("itunes/search").pop().expect("Apple was asked");
    let query = hit.query.unwrap_or_default();
    assert!(query.contains("term=found+show") || query.contains("term=found%20show"), "{query}");
    assert!(query.contains("media=podcast"), "{query}");
}

#[tokio::test(flavor = "multi_thread")]
async fn podcast_index_search_without_a_key_says_how_to_add_one() {
    let app = TestApp::new().await;
    let user = app.user("searcher").await;
    let resp = app.get("/api/data/proxy_search?query=anything&index=podcastindex").key(&user).send().await;
    resp.assert_status(503);
    assert!(resp.text().contains("Settings → Podcast Index"), "{}", resp.text());
    assert!(app.fixtures().hits("podcastindex/api/1.0/search/byterm").is_empty(), "Podcast Index isn't asked");
}

/// The web and phone apps name the index "podcast_index"; both spellings search Podcast Index.
#[tokio::test(flavor = "multi_thread")]
async fn podcast_index_search_accepts_the_name_the_apps_send() {
    let app = TestApp::new().await;
    let user = app.user("searcher").await;
    app.db().set_podcast_index_credentials(Some(("my-key", "my-secret"))).await.unwrap();
    let found = json!({ "feeds": [{ "title": "Found Show", "url": "https://feeds.example.invalid/found.xml" }] });
    app.fixtures().serve("podcastindex/api/1.0/search/byterm", Fixture::new("application/json", found.to_string()));

    for index in ["podcast_index", "podcastindex"] {
        let body = app.get(&format!("/api/data/proxy_search?query=found&index={index}")).key(&user).send().await.ok_json();
        assert_eq!(body["feeds"][0]["title"], "Found Show", "{index}: {body}");
    }
    assert_eq!(app.fixtures().hits("podcastindex/api/1.0/search/byterm").len(), 2);
}

#[tokio::test(flavor = "multi_thread")]
async fn podcast_index_requests_are_signed_with_this_servers_key() {
    let app = TestApp::new().await;
    let user = app.user("searcher").await;
    app.db().set_podcast_index_credentials(Some(("my-key", "my-secret"))).await.unwrap();
    app.fixtures().serve("podcastindex/api/1.0/search/byperson", Fixture::new("application/json", json!({ "items": [] }).to_string()));

    app.get("/api/data/proxy_search?query=Jane%20Doe&index=podcastindex&search_type=person").key(&user).send().await.ok_json();
    let hit = app.fixtures().hits("podcastindex/api/1.0/search/byperson").pop().expect("Podcast Index was asked");
    let date = hit.headers.get("x-auth-date").expect("X-Auth-Date").clone();
    assert_eq!(hit.headers.get("x-auth-key").map(String::as_str), Some("my-key"));
    let expected = {
        use sha1::{Digest, Sha1};
        hex::encode(Sha1::digest(format!("my-keymy-secret{date}").as_bytes()))
    };
    assert_eq!(hit.headers.get("authorization"), Some(&expected));
}

#[tokio::test(flavor = "multi_thread")]
async fn unknown_indexes_are_refused() {
    let app = TestApp::new().await;
    let user = app.user("searcher").await;
    app.get("/api/data/proxy_search?query=x&index=youtube").key(&user).send().await.assert_status(400);
}

#[tokio::test(flavor = "multi_thread")]
async fn an_admin_saves_a_checked_key_and_the_secret_is_never_sent_back() {
    let app = TestApp::new().await;
    let admin = app.admin().await.clone();
    let user = app.user("not-admin").await;
    app.get("/api/data/podcast_index").key(&user).send().await.assert_status(403);

    let status = app.get("/api/data/podcast_index").key(&admin).send().await.ok_json();
    assert_eq!(status["configured"], false);

    // Podcast Index turns the key down: nothing is saved.
    app.fixtures().serve("podcastindex/api/1.0/search/byterm", Fixture::new("application/json", "{}").status(401));
    let resp = app.post("/api/data/podcast_index").key(&admin).json(&json!({ "api_key": "bad", "api_secret": "nope" })).send().await;
    resp.assert_status(400);
    assert!(resp.text().contains("didn't accept"), "{}", resp.text());
    assert_eq!(app.get("/api/data/podcast_index").key(&admin).send().await.ok_json()["configured"], false);

    // Accepted: saved, and only the key comes back.
    app.fixtures().serve("podcastindex/api/1.0/search/byterm", Fixture::new("application/json", json!({ "feeds": [] }).to_string()));
    let saved = app.post("/api/data/podcast_index").key(&admin).json(&json!({ "api_key": "good", "api_secret": "s3cret" })).send().await.ok_json();
    assert_eq!(saved, json!({ "configured": true, "api_key": "good" }));
    assert!(!saved.to_string().contains("s3cret"));
    let stored = text(&app, r#"SELECT podcastindexapisecret FROM "AppSettings""#).await.unwrap();
    assert_ne!(stored, "s3cret", "the secret is stored encrypted");
    assert_eq!(app.db().podcast_index_credentials().await.unwrap(), Some(("good".into(), "s3cret".into())));

    // Removing it.
    let cleared = app.post("/api/data/podcast_index").key(&admin).json(&json!({ "api_key": "", "api_secret": "" })).send().await.ok_json();
    assert_eq!(cleared["configured"], false);
}

#[tokio::test(flavor = "multi_thread")]
async fn trending_and_categories_come_from_podcast_index() {
    let app = TestApp::new().await;
    let user = app.user("browser").await;
    app.db().set_podcast_index_credentials(Some(("k", "s"))).await.unwrap();
    app.fixtures().serve("podcastindex/api/1.0/podcasts/trending", Fixture::new("application/json", json!({ "feeds": [{ "title": "Hot" }] }).to_string()));
    app.fixtures().serve("podcastindex/api/1.0/categories/list", Fixture::new("application/json", json!({ "feeds": [{ "id": 1, "name": "Arts" }] }).to_string()));

    let trending = app.get("/api/data/proxy_trending?cat=Arts&max=5").key(&user).send().await.ok_json();
    assert_eq!(trending["feeds"][0]["title"], "Hot");
    let query = app.fixtures().hits("podcastindex/api/1.0/podcasts/trending").pop().unwrap().query.unwrap_or_default();
    assert!(query.contains("cat=Arts") && query.contains("max=5"), "{query}");
    let cats = app.get("/api/data/proxy_categories").key(&user).send().await.ok_json();
    assert_eq!(cats["feeds"][0]["name"], "Arts");
}

/// One show on Apple's chart, the way Apple's chart and lookup describe it.
fn apple_chart(ids: &[(i64, &str)]) -> String {
    let entries: Vec<_> = ids
        .iter()
        .map(|(id, name)| {
            json!({
                "im:name": { "label": name },
                "im:artist": { "label": "Chart Artist" },
                "summary": { "label": format!("About {name}") },
                "id": { "label": format!("https://podcasts.apple.com/us/podcast/id{id}"), "attributes": { "im:id": id.to_string() } },
            })
        })
        .collect();
    json!({ "feed": { "entry": entries } }).to_string()
}

fn apple_lookup(ids: &[(i64, &str)]) -> String {
    let results: Vec<_> = ids
        .iter()
        .map(|(id, name)| {
            json!({
                "collectionId": id,
                "collectionName": name,
                "artistName": "Show Maker",
                "feedUrl": format!("https://feeds.example.invalid/{id}.xml"),
                "artworkUrl600": format!("https://art.example.invalid/{id}/600x600bb.jpg"),
                "releaseDate": "2026-11-14T02:35:00Z",
                "trackCount": 42,
                "genres": ["Technology", "Podcasts", "Tech News"],
                "genreIds": ["1318", "26", "1528"],
            })
        })
        .collect();
    json!({ "resultCount": results.len(), "results": results }).to_string()
}

/// No Podcast Index key: trending is Apple's chart, in the shape the apps already read.
#[tokio::test(flavor = "multi_thread")]
async fn without_a_key_trending_is_apples_chart() {
    let app = TestApp::new().await;
    let user = app.user("browser").await;
    let shows = [(111, "First Show"), (222, "Second Show")];
    app.fixtures().serve("itunes/charts/limit=24/json", Fixture::new("application/json", apple_chart(&shows)));
    app.fixtures().serve("itunes/lookup", Fixture::new("application/json", apple_lookup(&shows)));

    let body = app.get("/api/data/proxy_trending?max=24").key(&user).send().await.ok_json();
    let feeds = body["feeds"].as_array().expect("feeds");
    assert_eq!(feeds.len(), 2, "{body}");
    assert_eq!(feeds[0]["title"], "First Show", "chart order is kept");
    assert_eq!(feeds[0]["url"], "https://feeds.example.invalid/111.xml");
    assert_eq!(feeds[0]["author"], "Show Maker");
    assert_eq!(feeds[0]["description"], "About First Show");
    assert_eq!(feeds[0]["image"], "https://art.example.invalid/111/600x600bb.jpg");
    assert_eq!(feeds[0]["itunesId"], 111);
    assert_eq!(feeds[0]["newestItemPublishTime"], 1794623700);
    assert_eq!(feeds[0]["categories"], json!({ "1318": "Technology", "1528": "Tech News" }));
    assert!(feeds[0].get("id").is_none(), "an Apple show has no Podcast Index id: {body}");

    let query = app.fixtures().hits("itunes/lookup").pop().expect("lookup").query.unwrap_or_default();
    assert!(query.contains("id=111%2C222") || query.contains("id=111,222"), "{query}");
    assert!(app.fixtures().hits("podcastindex/api/1.0/podcasts/trending").is_empty());
}

/// A category picks Apple's chart for that genre; one Apple doesn't have gives nothing.
#[tokio::test(flavor = "multi_thread")]
async fn without_a_key_a_category_uses_apples_genre_chart() {
    let app = TestApp::new().await;
    let user = app.user("browser").await;
    let shows = [(333, "Culture Show")];
    app.fixtures().serve("itunes/charts/limit=10/genre=1324/json", Fixture::new("application/json", apple_chart(&shows)));
    app.fixtures().serve("itunes/lookup", Fixture::new("application/json", apple_lookup(&shows)));

    let body = app.get("/api/data/proxy_trending?cat=Society%20%26%20Culture").key(&user).send().await.ok_json();
    assert_eq!(body["feeds"][0]["title"], "Culture Show", "{body}");

    let none = app.get("/api/data/proxy_trending?cat=Not%20A%20Genre").key(&user).send().await.ok_json();
    assert_eq!(none["feeds"], json!([]), "{none}");
}

/// Shows Apple gives no feed address for can't be added, so they're left out.
#[tokio::test(flavor = "multi_thread")]
async fn charted_shows_without_a_feed_are_left_out() {
    let app = TestApp::new().await;
    let user = app.user("browser").await;
    app.fixtures().serve("itunes/charts/limit=10/json", Fixture::new("application/json", apple_chart(&[(1, "Has Feed"), (2, "No Feed")])));
    app.fixtures().serve("itunes/lookup", Fixture::new("application/json", apple_lookup(&[(1, "Has Feed")])));

    let body = app.get("/api/data/proxy_trending").key(&user).send().await.ok_json();
    let titles: Vec<_> = body["feeds"].as_array().unwrap().iter().map(|f| f["title"].clone()).collect();
    assert_eq!(titles, vec![json!("Has Feed")]);
}

/// No Podcast Index key: categories are Apple's 19 main genres.
#[tokio::test(flavor = "multi_thread")]
async fn without_a_key_categories_are_apples_genres() {
    let app = TestApp::new().await;
    let user = app.user("browser").await;
    let body = app.get("/api/data/proxy_categories").key(&user).send().await.ok_json();
    let names: Vec<_> = body["feeds"].as_array().unwrap().iter().map(|c| c["name"].as_str().unwrap().to_string()).collect();
    assert_eq!(names.len(), 19, "{names:?}");
    for name in ["Arts", "Society & Culture", "Technology", "True Crime"] {
        assert!(names.contains(&name.to_string()), "{name} in {names:?}");
    }
    assert!(app.fixtures().hits("podcastindex/api/1.0/categories/list").is_empty());
}

/// A key Podcast Index turns down (or Podcast Index being down) falls back to Apple too.
#[tokio::test(flavor = "multi_thread")]
async fn when_podcast_index_fails_trending_and_categories_use_apple() {
    let app = TestApp::new().await;
    let user = app.user("browser").await;
    app.db().set_podcast_index_credentials(Some(("k", "s"))).await.unwrap();
    app.fixtures().serve("podcastindex/api/1.0/podcasts/trending", Fixture::new("application/json", "{}").status(401));
    app.fixtures().serve("podcastindex/api/1.0/categories/list", Fixture::new("application/json", "{}").status(500));
    let shows = [(444, "Apple Show")];
    app.fixtures().serve("itunes/charts/limit=10/json", Fixture::new("application/json", apple_chart(&shows)));
    app.fixtures().serve("itunes/lookup", Fixture::new("application/json", apple_lookup(&shows)));

    let trending = app.get("/api/data/proxy_trending").key(&user).send().await.ok_json();
    assert_eq!(trending["feeds"][0]["title"], "Apple Show", "{trending}");
    assert_eq!(app.fixtures().hits("podcastindex/api/1.0/podcasts/trending").len(), 1, "Podcast Index was tried first");
    let cats = app.get("/api/data/proxy_categories").key(&user).send().await.ok_json();
    assert_eq!(cats["feeds"].as_array().unwrap().len(), 19, "{cats}");
}
