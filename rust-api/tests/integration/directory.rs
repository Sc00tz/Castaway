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
