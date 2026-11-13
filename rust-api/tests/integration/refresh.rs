//! Feed refresh efficiency and integrity: unchanged feeds skip
//! parsing, throttling hosts are backed off, racing refreshes can't duplicate episodes, adding a
//! podcast downloads its feed once, manual refresh revalidates, duration probes are bounded.


use crate::harness::*;

async fn title_of(app: &TestApp, user: &TestUser, podcast_id: i32, guid: &str) -> String {
    let id = int(app, &format!(r#"SELECT EpisodeID FROM "Episodes" WHERE PodcastID = {podcast_id} AND EpisodeGUID = '{guid}'"#))
        .await
        .unwrap();
    let eps = app.episodes(user, podcast_id).await;
    eps.iter().find(|e| e["Episodeid"] == id).unwrap()["Episodetitle"].as_str().unwrap().to_string()
}

async fn tamper_title(app: &TestApp, podcast_id: i32, guid: &str) {
    exec(app, &format!(r#"UPDATE "Episodes" SET EpisodeTitle = 'tampered' WHERE PodcastID = {podcast_id} AND EpisodeGUID = '{guid}'"#)).await;
}

#[tokio::test(flavor = "multi_thread")]
async fn an_unchanged_feed_is_not_reparsed_even_without_an_etag() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let feed = Feed::with_episodes("No ETag Show", 2);
    let url = app.feed("plain.xml", &feed);
    let pod = app.subscribe(&user, &url, 2).await;

    // A local edit survives refreshes of an unchanged body: proof the feed wasn't applied again.
    tamper_title(&app, pod, "guid-1").await;
    app.refresh().await;
    app.refresh().await;
    assert_eq!(app.fixtures().hits("plain.xml").len(), 3, "the feed is still fetched every cycle");
    assert_eq!(title_of(&app, &user, pod, "guid-1").await, "tampered", "unchanged body must skip parse/apply");

    // A changed body is applied in full.
    app.feed("plain.xml", &feed.episode(Episode::new(3)));
    app.refresh().await;
    assert_eq!(app.episodes(&user, pod).await.len(), 3);
    assert_eq!(title_of(&app, &user, pod, "guid-1").await, "Episode 1");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_304_skips_parsing() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let feed = Feed::with_episodes("ETag Show", 2);
    let url = app.fixtures().serve("etag.xml", Fixture::new("application/rss+xml", feed.to_xml()).etag("\"v1\""));
    let pod = app.subscribe(&user, &url, 2).await;
    app.refresh().await; // learns the ETag

    tamper_title(&app, pod, "guid-2").await;
    app.refresh().await;
    let hits = app.fixtures().hits("etag.xml");
    assert_eq!(hits.last().unwrap().headers.get("if-none-match").map(String::as_str), Some("\"v1\""));
    assert_eq!(title_of(&app, &user, pod, "guid-2").await, "tampered", "304 must skip parse/apply");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_throttling_host_is_left_alone_until_its_retry_after() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let feed = Feed::with_episodes("Busy Host", 2);
    let url = app.feed("busy.xml", &feed);
    let pod = app.subscribe(&user, &url, 2).await;

    app.fixtures().serve("busy.xml", Fixture::new("text/plain", "slow down").status(429).header("Retry-After", "3600"));
    app.refresh().await;
    assert_eq!(app.fixtures().hits("busy.xml").len(), 2, "a 429 is not retried within the cycle");
    let held = int(&app, &format!(r#"SELECT COUNT(*) FROM "Podcasts" WHERE PodcastID = {pod} AND RefreshNotBefore IS NOT NULL"#)).await;
    assert_eq!(held, Some(1), "Retry-After is recorded");

    // The host recovers, but we wait out its Retry-After.
    app.feed("busy.xml", &feed.clone().episode(Episode::new(3)));
    app.refresh().await;
    assert_eq!(app.fixtures().hits("busy.xml").len(), 2, "no request before Retry-After");
    assert_eq!(app.episodes(&user, pod).await.len(), 2);

    // Once the hold (and the failure backoff) has passed, the feed refreshes and the hold clears.
    exec(&app, &format!(r#"UPDATE "Podcasts" SET RefreshNotBefore = '2000-01-01 00:00:00', LastRefreshAttempt = '2000-01-01 00:00:00' WHERE PodcastID = {pod}"#)).await;
    app.refresh().await;
    assert_eq!(app.episodes(&user, pod).await.len(), 3);
    let held = int(&app, &format!(r#"SELECT COUNT(*) FROM "Podcasts" WHERE PodcastID = {pod} AND RefreshNotBefore IS NULL AND ConsecutiveFailures = 0"#)).await;
    assert_eq!(held, Some(1), "success clears the hold and the failure count");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_server_error_is_fetched_once_not_retried() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let url = app.feed("down.xml", &Feed::with_episodes("Down", 1));
    app.subscribe(&user, &url, 1).await;

    app.fixtures().serve("down.xml", Fixture::new("text/plain", "oops").status(500));
    app.refresh().await;
    assert_eq!(app.fixtures().hits("down.xml").len(), 2, "one request for the add, one for the refresh");
}

#[tokio::test(flavor = "multi_thread")]
async fn racing_refreshes_never_insert_an_episode_twice() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let mut feed = Feed::with_episodes("Racy", 1);
    let url = app.feed("racy.xml", &feed);
    let pod = app.subscribe(&user, &url, 1).await;

    for n in 2..=40 {
        feed = feed.episode(Episode::new(n));
    }
    let xml = feed.to_xml();
    app.feed("racy.xml", &feed);
    let parsed = app.db().parse_feed_body(&xml, pod, "").await.unwrap();

    // Several appliers see the same 39 episodes as new at the same moment.
    let apply = || app.db().apply_parsed_episodes(pod, &parsed, "", None, false);
    let (a, b, c, d) = tokio::join!(apply(), apply(), apply(), apply());
    let reported: usize = [a, b, c, d].into_iter().map(|r| r.unwrap().len()).sum();
    assert_eq!(reported, 39, "each new episode is reported as new exactly once");
    assert_eq!(app.episodes(&user, pod).await.len(), 40);

    tokio::join!(app.refresh(), app.refresh());
    assert_eq!(app.episodes(&user, pod).await.len(), 40);
    let dups = int(&app, &format!(
        r#"SELECT COUNT(*) FROM (SELECT EpisodeGUID FROM "Episodes" WHERE PodcastID = {pod} GROUP BY EpisodeGUID HAVING COUNT(*) > 1) d"#
    ))
    .await;
    assert_eq!(dups, Some(0));
}

#[tokio::test(flavor = "multi_thread")]
async fn adding_a_podcast_downloads_its_feed_once() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let url = app.feed("once.xml", &Feed::with_episodes("Once", 3));
    app.subscribe(&user, &url, 3).await;
    assert_eq!(app.fixtures().hits("once.xml").len(), 1, "metadata and episodes come from one download");

    let custom = app.feed("custom.xml", &Feed::with_episodes("Custom", 2));
    let body = app
        .post("/api/data/add_custom_podcast")
        .key(&user)
        .json(&json!({ "user_id": user.id, "feed_url": custom }))
        .send()
        .await
        .ok_json();
    let pod = body["data"]["podcastid"].as_i64().unwrap_or_else(|| panic!("{body}")) as i32;
    assert_eq!(app.episodes(&user, pod).await.len(), 2);
    assert_eq!(app.fixtures().hits("custom.xml").len(), 1);
}

async fn manual_refresh(app: &TestApp, user: &TestUser) -> Vec<Value> {
    let (tx, mut rx) = tokio::sync::mpsc::channel(1000);
    castaway_api::handlers::refresh::run_refresh_process(user.id, false, tx, app.state.clone())
        .await
        .expect("manual refresh");
    let mut messages = Vec::new();
    while let Some(m) = rx.recv().await {
        messages.push(serde_json::to_value(&m).unwrap());
    }
    messages
}

#[tokio::test(flavor = "multi_thread")]
async fn manual_refresh_revalidates_and_skips_feeds_just_refreshed() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let feed = Feed::with_episodes("Manual", 2);
    let url = app.fixtures().serve("manual.xml", Fixture::new("application/rss+xml", feed.to_xml()).etag("\"v1\""));
    let pod = app.subscribe(&user, &url, 2).await;
    app.refresh().await;
    let after_scheduled = app.fixtures().hits("manual.xml").len();

    // The scheduled refresh just checked it: nothing to do.
    manual_refresh(&app, &user).await;
    assert_eq!(app.fixtures().hits("manual.xml").len(), after_scheduled, "refreshed under 2 minutes ago");

    let age = format!(r#"UPDATE "Podcasts" SET LastRefreshSuccess = '2000-01-01 00:00:00' WHERE PodcastID = {pod}"#);
    exec(&app, &age).await;
    manual_refresh(&app, &user).await;
    let hits = app.fixtures().hits("manual.xml");
    assert_eq!(hits.len(), after_scheduled + 1);
    assert_eq!(hits.last().unwrap().headers.get("if-none-match").map(String::as_str), Some("\"v1\""), "manual refresh is conditional");

    app.fixtures().serve("manual.xml", Fixture::new("application/rss+xml", feed.episode(Episode::new(3)).to_xml()).etag("\"v2\""));
    exec(&app, &age).await;
    let messages = manual_refresh(&app, &user).await;
    assert!(
        messages.iter().any(|m| m["new_episode"]["episodetitle"] == "Episode 3"),
        "new episodes are streamed: {messages:#?}"
    );
    assert_eq!(app.episodes(&user, pod).await.len(), 3);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_back_catalogue_probes_the_newest_durations_first_and_backfills_the_rest() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    // ~2 MB so the Content-Length estimate kicks in; HEAD responses carry no body.
    let audio = Fixture::new("audio/mpeg", vec![0u8; 2_000_000]);
    let mut feed = Feed::new("Back Catalogue");
    for n in 1..=25 {
        let audio_url = app.fixtures().serve(&format!("audio/{n}.mp3"), audio.clone());
        let mut ep = Episode::new(n).duration(None).enclosure(&audio_url);
        ep.enclosure_len = 0;
        feed = feed.episode(ep);
    }
    let url = app.feed("catalogue.xml", &feed);
    let pod = app.subscribe(&user, &url, 25).await;

    eventually("every duration backfilled", || async {
        let eps = app.episodes(&user, pod).await;
        eps.iter().all(|e| e["Episodeduration"].as_i64().unwrap_or(0) > 0).then_some(())
    })
    .await;

    for n in 1..=25 {
        let hits = app.fixtures().hits(&format!("audio/{n}.mp3"));
        assert_eq!(hits.len(), 1, "episode {n} probed exactly once: {hits:?}");
        assert_eq!(hits[0].method, "HEAD");
    }
    // The ten newest were probed during the import, before any of the backfill.
    let order = app.fixtures().server.request_order(&app.fixtures().namespace, "/audio/");
    let first_ten: Vec<u32> = order[..10].iter().map(|p| p.trim_end_matches(".mp3").parse().unwrap()).collect();
    assert!(first_ten.iter().all(|n| *n >= 16), "newest first: {order:?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_players_duration_fills_in_a_missing_one() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let mut ep = Episode::new(1).duration(None);
    ep.enclosure_len = 0;
    let url = app.feed("nodur.xml", &Feed::new("No Duration").episode(ep));
    let pod = app.subscribe(&user, &url, 1).await;
    let id = app.episode_id(&user, pod, "Episode 1").await;
    let duration = || async { app.episodes(&user, pod).await[0]["Episodeduration"].as_i64().unwrap_or(0) };
    assert_eq!(duration().await, 0, "the enclosure host is unreachable, so nothing could be estimated");

    let report = |d: f64| {
        app.post("/api/data/record_listen_duration")
            .key(&user)
            .json(&json!({ "episode_id": id, "user_id": user.id, "listen_duration": 30.0, "episode_duration": d }))
    };
    report(1234.4).send().await.assert_ok();
    assert_eq!(duration().await, 1234);
    report(999.0).send().await.assert_ok();
    assert_eq!(duration().await, 1234, "a known duration is never overwritten");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_new_episode_posts_an_http_notification() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let mut feed = Feed::with_episodes("Notify Show", 1);
    let url = app.feed("notify.xml", &feed);
    let pod = app.subscribe(&user, &url, 1).await;

    let hook = app.fixtures().serve("hook", Fixture::new("application/json", "{}"));
    let save = |enabled: bool, method: &str, token: &str| {
        let app = &app;
        let user = &user;
        let hook = hook.clone();
        let method = method.to_string();
        let token = token.to_string();
        async move {
            app.put("/api/data/user/notification_settings")
                .key(user)
                .json(&json!({
                    "user_id": user.id,
                    "platform": "http",
                    "enabled": enabled,
                    "http_url": hook,
                    "http_token": token,
                    "http_method": method,
                }))
                .send()
                .await
                .assert_ok();
        }
    };
    save(true, "POST", "hook-secret").await;

    // The channel is on, but this podcast is not: a new episode must not call the webhook.
    feed = feed.episode(Episode::new(2));
    app.feed("notify.xml", &feed);
    app.refresh().await;
    assert!(app.fixtures().hits("hook").is_empty(), "podcast notifications are off");

    app.put("/api/data/podcast/toggle_notifications")
        .key(&user)
        .json(&json!({ "user_id": user.id, "podcast_id": pod, "enabled": true }))
        .send()
        .await
        .assert_ok();

    feed = feed.episode(Episode::new(3));
    app.feed("notify.xml", &feed);
    app.refresh().await;

    let hits = app.fixtures().hits("hook");
    assert_eq!(hits.len(), 1, "{hits:?}");
    let hit = &hits[0];
    assert_eq!(hit.method, "POST");
    assert_eq!(hit.headers.get("authorization").map(String::as_str), Some("Bearer hook-secret"));
    assert_eq!(
        hit.headers.get("content-type").map(String::as_str),
        Some("application/json"),
        "{:?}",
        hit.headers
    );
    let body: Value = serde_json::from_slice(&hit.body).unwrap_or_else(|e| panic!("{e}: {}", String::from_utf8_lossy(&hit.body)));
    let text = "New episode available for Notify Show: Episode 3";
    assert_eq!(
        body,
        json!({ "title": "New Podcast Episode", "message": text, "text": text }),
        "Mattermost reads `text`"
    );

    // The same feed again is not a new episode.
    app.refresh().await;
    assert_eq!(app.fixtures().hits("hook").len(), 1);

    // GET puts the same notice in the query string and sends no bearer token when none is set.
    save(true, "GET", "").await;
    feed = feed.episode(Episode::new(4));
    app.feed("notify.xml", &feed);
    app.refresh().await;
    let hits = app.fixtures().hits("hook");
    assert_eq!(hits.len(), 2, "{hits:?}");
    let get = &hits[1];
    assert_eq!(get.method, "GET");
    assert!(get.headers.get("authorization").is_none(), "{:?}", get.headers);
    let message = "New episode available for Notify Show: Episode 4";
    let expected_query = format!("message={}", urlencoding::encode(&message));
    assert_eq!(get.query.as_deref(), Some(expected_query.as_str()));

    save(false, "GET", "").await;
    feed = feed.episode(Episode::new(5));
    app.feed("notify.xml", &feed);
    app.refresh().await;
    assert_eq!(app.fixtures().hits("hook").len(), 2, "a disabled HTTP channel does not send");
}

#[tokio::test(flavor = "multi_thread")]
async fn an_image_media_content_does_not_lose_the_enclosure() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let audio = "https://example.invalid/audio.mp3";
    let image = r#"<media:content xmlns:media="http://search.yahoo.com/mrss/" url="https://example.invalid/art.jpg" type="image/jpeg"/>"#;
    let feed = Feed::new("Media Show").episode(Episode::new(1).enclosure(audio).extra(image));
    let url = app.feed("media.xml", &feed);
    let pod = app.subscribe(&user, &url, 1).await;

    assert_eq!(app.episodes(&user, pod).await[0]["Episodeurl"], audio);
}

async fn guidless_episodes(app: &TestApp, user: &TestUser, pod: i32) -> Vec<String> {
    let episodes = app.episodes(user, pod).await;
    episodes.iter().map(|e| e["Episodeurl"].as_str().unwrap().to_string()).collect()
}

#[tokio::test(flavor = "multi_thread")]
async fn a_guidless_episode_with_a_reused_title_stays_separate() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let first = Episode::new(1).guid(None).title("Bonus").enclosure("https://example.invalid/one.mp3");
    let feed = Feed::new("Reused Titles").episode(first);
    let url = app.feed("reused.xml", &feed);
    let pod = app.subscribe(&user, &url, 1).await;

    let second = Episode::new(2).guid(None).title("Bonus").enclosure("https://example.invalid/two.mp3");
    app.feed("reused.xml", &feed.episode(second));
    app.refresh().await;

    let mut urls = guidless_episodes(&app, &user, pod).await;
    urls.sort();
    assert_eq!(urls, ["https://example.invalid/one.mp3", "https://example.invalid/two.mp3"]);
}
