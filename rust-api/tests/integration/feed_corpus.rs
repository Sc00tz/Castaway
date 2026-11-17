//! Not part of the normal suite. Imports a folder of saved real feeds and writes what Castaway
//! stored for each one (podcast details, every episode's fields, people), so two versions of the
//! feed parser can be compared feed by feed:
//!
//!   CASTAWAY_FEED_CORPUS=<folder of .xml> CASTAWAY_FEED_CORPUS_OUT=<output folder> \
//!     scripts/integration-tests.sh -- -- --ignored feed_corpus --nocapture

use crate::harness::*;
use std::time::{Duration, Instant};

#[tokio::test(flavor = "multi_thread")]
#[ignore = "compares feed parsing on a folder of real feeds; see the module comment"]
async fn feed_corpus() {
    let dir = std::env::var("CASTAWAY_FEED_CORPUS").expect("CASTAWAY_FEED_CORPUS: folder of feeds");
    let out = std::env::var("CASTAWAY_FEED_CORPUS_OUT").expect("CASTAWAY_FEED_CORPUS_OUT: output folder");
    std::fs::create_dir_all(&out).unwrap();
    let mut files: Vec<_> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "xml"))
        .collect();
    files.sort();

    let app = TestApp::new().await;
    let user = app.user("corpus").await;
    for file in files {
        let name = file.file_stem().unwrap().to_string_lossy().to_string();
        let url = app
            .fixtures()
            .serve(&format!("corpus/{name}.xml"), Fixture::new("application/rss+xml", std::fs::read(&file).unwrap()));
        let resp = app
            .post("/api/data/add_podcast")
            .key(&user)
            .json(&json!({
                "podcast_values": {
                    "pod_title": "", "pod_artwork": "", "pod_author": "", "categories": {},
                    "pod_description": "", "pod_episode_count": 0, "pod_feed_url": url,
                    "pod_website": "", "pod_explicit": false, "user_id": user.id,
                },
                "podcast_index_id": 0,
            }))
            .send()
            .await;
        let path = format!("{out}/{name}.json");
        if resp.status != 200 {
            std::fs::write(&path, json!({ "error": resp.status.as_u16(), "body": resp.text() }).to_string()).unwrap();
            println!("{name}: add_podcast refused");
            continue;
        }
        let id = resp.ok_json()["podcast_id"].as_i64().unwrap();

        // The import's last write schedules the next refresh.
        let done = format!(r#"SELECT COUNT(*) FROM "Podcasts" WHERE PodcastID = {id} AND RefreshIntervalMinutes IS NOT NULL"#);
        let started = Instant::now();
        while int(&app, &done).await != Some(1) {
            assert!(started.elapsed() < Duration::from_secs(600), "{name}: import didn't finish");
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
        tokio::time::sleep(Duration::from_millis(500)).await; // feed tags land right after

        let dump = text(
            &app,
            &format!(
                r#"SELECT json_build_object(
                  'podcast', (SELECT row_to_json(p) FROM (
                      SELECT podcastname, artworkurl, author, categories, md5(coalesce(description, '')) AS description_md5,
                             websiteurl, explicit, podcastguid
                      FROM "Podcasts" WHERE PodcastID = {id}) p),
                  'episodes', (SELECT coalesce(json_agg(row_to_json(e) ORDER BY e.episodeguid, e.episodetitle, e.episodeurl), '[]') FROM (
                      SELECT episodetitle, md5(coalesce(episodedescription, '')) AS description_md5, episodeurl, episodeartwork,
                             episodepubdate, episodeduration, is_video, episodeguid, chaptersurl, transcriptsjson
                      FROM "Episodes" WHERE PodcastID = {id}) e),
                  'podcast_people', (SELECT coalesce(json_agg(x ORDER BY x), '[]') FROM (
                      SELECT pe.name || '|' || coalesce(pp.role, '') || '|' || coalesce(pe.img, '') AS x
                      FROM "PodcastPeople" pp JOIN "Persons" pe USING (personid) WHERE pp.podcastid = {id}) q),
                  'episode_people', (SELECT coalesce(json_agg(x ORDER BY x), '[]') FROM (
                      SELECT e.episodeguid || '|' || pe.name || '|' || coalesce(ep.role, '') AS x
                      FROM "EpisodePeople" ep JOIN "Persons" pe USING (personid) JOIN "Episodes" e USING (episodeid)
                      WHERE e.podcastid = {id}) q)
                )::text"#
            ),
        )
        .await
        .unwrap();
        std::fs::write(&path, dump).unwrap();
        println!("{name}: done in {:?}", started.elapsed());
    }
}
