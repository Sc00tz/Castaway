//! Whether a user finished an episode is kept per user: subscribers of a feed share its
//! episodes but not their progress, marking only touches episodes of the caller's feeds, and the
//! upgrade carries existing completions over.

use castaway_api::services::sync::SyncOrigin;

use crate::harness::*;

async fn completed(app: &TestApp, user: &TestUser, episode: i32) -> Option<i64> {
    int(app, &format!(r#"SELECT Completed FROM "UserEpisodeState" WHERE UserID = {} AND EpisodeID = {episode}"#, user.id)).await
}

#[tokio::test(flavor = "multi_thread")]
async fn completion_is_recorded_per_user() {
    let app = TestApp::new().await;
    let (alice, bob) = (app.user("alice").await, app.user("bob").await);
    let url = app.feed("show.xml", &Feed::with_episodes("Show", 2));
    let a = app.subscribe(&alice, &url, 2).await;
    let b = app.subscribe(&bob, &url, 2).await;
    let e1 = app.episode_id(&alice, a, "Episode 1").await;
    let e2 = app.episode_id(&alice, a, "Episode 2").await;
    assert_eq!(app.episode_id(&bob, b, "Episode 1").await, e1, "one shared episode");
    let only_bob = app.subscribe(&bob, &app.feed("bob.xml", &Feed::with_episodes("Bob's", 1)), 1).await;
    let mine = app.episode_id(&bob, only_bob, "Episode 1").await;

    app.db().mark_episode_completed(e1, alice.id, false, SyncOrigin::Unlogged).await.unwrap();
    assert_eq!(completed(&app, &alice, e1).await, Some(1));
    assert_eq!(completed(&app, &bob, e1).await, None, "bob hasn't finished it");
    let bobs = app.episodes(&bob, b).await;
    assert!(bobs.iter().all(|e| e["Completed"] == false), "{bobs:#?}");

    app.db().mark_episode_uncompleted(e1, alice.id, false, SyncOrigin::Unlogged).await.unwrap();
    assert_eq!(completed(&app, &alice, e1).await, Some(0));

    // An episode of a feed Alice doesn't follow is left alone.
    let (done, _) = app.db().bulk_mark_episodes_completed(vec![e1, e2, mine], alice.id, false).await.unwrap();
    assert_eq!(done, 2);
    assert_eq!(completed(&app, &alice, e2).await, Some(1));
    assert_eq!(completed(&app, &alice, mine).await, None);
    assert_eq!(completed(&app, &bob, mine).await, None);
}

