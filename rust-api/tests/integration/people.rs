//! People: credits stored at refresh, one identity across shows, follows, and episodes from
//! shows outside the library (from Podcast Index's person search).

use crate::harness::*;
use pinepods_api::services::people::{external, Endpoints};

fn person_tag(role: &str, name: &str) -> String {
    format!("    <podcast:person role=\"{role}\">{name}</podcast:person>\n")
}

fn endpoints(app: &TestApp) -> Endpoints {
    Endpoints::from_config(&app.state.config)
}

async fn podcast_people(app: &TestApp, u: &TestUser, podcast_id: i32) -> Value {
    app.get(&format!("/api/data/people/podcast/{podcast_id}")).key(u).send().await.ok_json()
}

async fn episode_people(app: &TestApp, u: &TestUser, episode_id: i32) -> Value {
    app.get(&format!("/api/data/people/episode/{episode_id}")).key(u).send().await.ok_json()
}

fn names(list: &Value) -> Vec<String> {
    let mut v: Vec<String> = list.as_array().unwrap().iter().map(|p| p["name"].as_str().unwrap().to_string()).collect();
    v.sort();
    v
}

fn find<'a>(list: &'a Value, name: &str) -> &'a Value {
    list.as_array()
        .unwrap()
        .iter()
        .find(|p| p["name"] == name)
        .unwrap_or_else(|| panic!("{name} not in {list:#}"))
}

/// A show with a channel host, a recurring guest, and an episode-level co-host.
fn show(title: &str) -> Feed {
    Feed::new(title)
        .extra(&person_tag("host", "Alice Host"))
        .episode(Episode::new(1).extra(&person_tag("guest", "Bob Guest")))
        .episode(Episode::new(2).extra(&format!("{}{}", person_tag("guest", "Bob Guest"), person_tag("co-host", "Carol Cohost"))))
        .episode(Episode::new(3))
}

#[tokio::test(flavor = "multi_thread")]
async fn credits_are_stored_at_refresh_and_pages_never_fetch_the_feed() {
    let app = TestApp::new().await;
    let user = app.user("listener").await;
    let feed_url = app.fixtures().serve_feed("show.xml", show("Stored Show").to_xml());
    let pod = app.subscribe(&user, &feed_url, 3).await;
    let fetches = app.fixtures().hits("show.xml").len();

    let credits = podcast_people(&app, &user, pod).await;
    assert_eq!(names(&credits["people"]), ["Alice Host"], "{credits:#}");
    let alice = find(&credits["people"], "Alice Host");
    assert_eq!(alice["scope"], "podcast");
    assert_eq!(alice["sources"], json!(["feed"]));
    assert_eq!(names(&credits["guests"]), ["Bob Guest", "Carol Cohost"]);
    assert_eq!(find(&credits["guests"], "Bob Guest")["episode_count"], 2);

    // The legacy podcast endpoint reads the same stored data.
    let legacy = app
        .get("/api/data/fetch_podcasting_2_pod_data")
        .key(&user)
        .query("podcast_id", pod)
        .query("user_id", user.id)
        .send()
        .await
        .ok_json();
    assert_eq!(names(&legacy["people"]), ["Alice Host"]);

    // Episode 2 names its own co-host, so the show's host isn't added; episode 3 has no tags
    // and gets the show's regulars.
    let two = app.episode_id(&user, pod, "Episode 2").await;
    let three = app.episode_id(&user, pod, "Episode 3").await;
    let ep2 = episode_people(&app, &user, two).await;
    assert_eq!(names(&ep2), ["Bob Guest", "Carol Cohost"], "{ep2:#}");
    assert_eq!(find(&ep2, "Bob Guest")["scope"], "episode");
    assert_eq!(names(&episode_people(&app, &user, three).await), ["Alice Host"]);

    assert_eq!(app.fixtures().hits("show.xml").len(), fetches, "page loads must not fetch the feed");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_feed_without_people_has_no_placeholder_host() {
    let app = TestApp::new().await;
    let user = app.user("plain").await;
    let feed_url = app.fixtures().serve_feed("plain.xml", Feed::with_episodes("No Tags", 2).to_xml());
    let pod = app.subscribe(&user, &feed_url, 2).await;
    let credits = podcast_people(&app, &user, pod).await;
    assert_eq!(credits["people"], json!([]), "{credits:#}");
    assert_eq!(credits["guests"], json!([]));
}

#[tokio::test(flavor = "multi_thread")]
async fn changed_feed_tags_replace_stored_credits() {
    let app = TestApp::new().await;
    let user = app.user("refresher").await;
    let feed_url = app.fixtures().serve_feed("changing.xml", show("Changing").to_xml());
    let pod = app.subscribe(&user, &feed_url, 3).await;

    let updated = Feed::new("Changing")
        .extra(&person_tag("host", "New Host"))
        .episode(Episode::new(1))
        .episode(Episode::new(2))
        .episode(Episode::new(3));
    app.fixtures().serve_feed("changing.xml", updated.to_xml());
    app.refresh().await;
    let credits = eventually("new host stored", || async {
        let c = podcast_people(&app, &user, pod).await;
        (names(&c["people"]) == ["New Host"]).then_some(c)
    })
    .await;
    assert_eq!(credits["guests"], json!([]), "{credits:#}");
}

#[tokio::test(flavor = "multi_thread")]
async fn one_person_across_shows_and_follows_follow_them_everywhere() {
    let app = TestApp::new().await;
    let user = app.user("fan").await;
    let a = app.fixtures().serve_feed(
        "a.xml",
        Feed::new("Show A").extra(&person_tag("host", "Dana Smith")).episode(Episode::new(1)).episode(Episode::new(2)).to_xml(),
    );
    // Same person, written differently.
    let b = app.fixtures().serve_feed(
        "b.xml",
        Feed::new("Show B").extra(&person_tag("host", "dana  SMITH")).episode(Episode::new(11)).to_xml(),
    );
    let pod_a = app.subscribe(&user, &a, 2).await;
    let pod_b = app.subscribe(&user, &b, 1).await;
    let id_a = podcast_people(&app, &user, pod_a).await["people"][0]["id"].as_i64().unwrap();
    let id_b = podcast_people(&app, &user, pod_b).await["people"][0]["id"].as_i64().unwrap();
    assert_eq!(id_a, id_b, "one person, not one per show");

    app.post(&format!("/api/data/people/{id_a}/follow")).key(&user).send().await.assert_ok();
    let followed = app.get("/api/data/people/followed").key(&user).send().await.ok_json();
    assert_eq!(names(&followed), ["Dana Smith"]);
    assert_eq!(podcast_people(&app, &user, pod_b).await["people"][0]["followed"], true);

    let profile = app.get(&format!("/api/data/people/{id_a}")).key(&user).send().await.ok_json();
    assert_eq!(profile["person"]["followed"], true);
    let mut shows: Vec<&str> = profile["podcasts"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|p| !p["podcastid"].is_null())
        .map(|p| p["podcastname"].as_str().unwrap())
        .collect();
    shows.sort();
    assert_eq!(shows, ["Show A", "Show B"], "{profile:#}");
    assert_eq!(profile["episodes"].as_array().unwrap().len(), 3, "every episode of shows they host");

    app.delete(&format!("/api/data/people/{id_a}/follow")).key(&user).send().await.assert_ok();
    assert_eq!(app.get("/api/data/people/followed").key(&user).send().await.ok_json(), json!([]));
}

#[tokio::test(flavor = "multi_thread")]
async fn people_endpoints_only_show_your_own_library() {
    let app = TestApp::new().await;
    let owner = app.user("owner").await;
    let other = app.user("other").await;
    let feed_url = app.fixtures().serve_feed("mine.xml", show("Mine").to_xml());
    let pod = app.subscribe(&owner, &feed_url, 3).await;
    let ep = app.episode_id(&owner, pod, "Episode 1").await;

    app.get(&format!("/api/data/people/podcast/{pod}")).key(&other).send().await.assert_status(404);
    app.get(&format!("/api/data/people/episode/{ep}")).key(&other).send().await.assert_status(404);
    app.get("/api/data/fetch_podcasting_2_pod_data")
        .key(&other)
        .query("podcast_id", pod)
        .query("user_id", owner.id)
        .send()
        .await
        .assert_status(403);

    // A person's page lists only the viewer's own shows.
    let id = podcast_people(&app, &owner, pod).await["people"][0]["id"].as_i64().unwrap();
    let profile = app.get(&format!("/api/data/people/{id}")).key(&other).send().await.ok_json();
    assert_eq!(profile["episodes"], json!([]), "{profile:#}");
    assert!(profile["podcasts"].as_array().unwrap().iter().all(|p| p["podcastid"].is_null()));
}

#[tokio::test(flavor = "multi_thread")]
async fn external_episodes_come_from_shows_outside_the_library() {
    let app = TestApp::new().await;
    let user = app.user("explorer").await;
    let feed_url = app.fixtures().serve_feed("home.xml", show("Home Show").to_xml());
    let pod = app.subscribe(&user, &feed_url, 3).await;
    let id = podcast_people(&app, &user, pod).await["people"][0]["id"].as_i64().unwrap() as i32;

    let item = |title: &str, feed: &str, t: i64| {
        json!({ "title": title, "enclosureUrl": format!("https://cdn.example.invalid/{title}.mp3"),
                "datePublished": t, "duration": 600, "feedTitle": format!("Feed of {title}"),
                "feedUrl": feed, "feedId": 42, "guid": title, "description": "d", "image": "", "feedImage": "https://img.example.invalid/f.jpg" })
    };
    app.db().set_podcast_index_credentials(Some(("test-key", "test-secret"))).await.unwrap();
    app.fixtures().serve(
        "podcastindex/api/1.0/search/byperson",
        Fixture::new(
            "application/json",
            json!({ "items": [
                item("Elsewhere", "https://other.example.invalid/feed.xml", 1_700_000_000),
                // A show the user already has: shown with their library, not as external.
                item("AtHome", &feed_url, 1_700_000_100),
            ]})
            .to_string(),
        ),
    );
    external::refresh(app.db(), &endpoints(&app), id).await.unwrap();

    let profile = app.get(&format!("/api/data/people/{id}")).key(&user).send().await.ok_json();
    let titles: Vec<&str> = profile["external_episodes"].as_array().unwrap().iter().map(|e| e["episodetitle"].as_str().unwrap()).collect();
    assert_eq!(titles, ["Elsewhere"], "{profile:#}");
    assert_eq!(profile["external_episodes"][0]["episodeid"], -1);
    assert_eq!(profile["refreshing"], false, "fresh list, no background refresh");
    let elsewhere = profile["podcasts"].as_array().unwrap().iter().find(|p| p["podcastid"].is_null()).unwrap();
    assert_eq!(elsewhere["feedurl"], "https://other.example.invalid/feed.xml");
    assert_eq!(elsewhere["artworkurl"], "https://img.example.invalid/f.jpg");
}
