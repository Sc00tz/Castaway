//! A sync app that knows a show under another address (it followed a feed move, or writes the
//! address differently) never makes Castaway subscribe to it twice: the address is remembered
//! as an alias of the podcast, and removing it under that address unsubscribes the podcast.

use crate::harness::gpodder::*;
use crate::harness::*;

async fn scene() -> GpodderScene {
    let app = TestApp::new().await;
    let user = app.user("moved").await;
    let server = app.rust_gpodder_server().await;
    let password = app.enable_gpodder(&server, &user).await;
    GpodderScene { server, app, user, password }
}

async fn feed_urls(s: &GpodderScene) -> Vec<String> {
    s.app.podcasts(&s.user).await.iter().filter_map(|p| p["feedurl"].as_str().map(str::to_string)).collect()
}

async fn aliases(s: &GpodderScene) -> i64 {
    int(&s.app, &format!(r#"SELECT COUNT(*) FROM "PodcastFeedAliases" WHERE UserID = {}"#, s.user.id)).await.unwrap()
}

#[tokio::test(flavor = "multi_thread")]
async fn a_moved_feed_is_not_subscribed_twice_and_unsubscribes_under_its_new_address() {
    let s = scene().await;
    let old = s.app.feed("moved-old.xml", &Feed::with_episodes("Moved Show", 3));
    s.app.subscribe(&s.user, &old, 3).await;
    // The new home has the same episodes and one more.
    let new = s.app.feed("moved-new.xml", &Feed::with_episodes("Moved Show", 4));

    let phone = s.device("phone").await;
    phone.upload_subscription_changes(&[&new], &[]).await.assert_ok();
    eventually("the new address remembered", || async { (aliases(&s).await == 1).then_some(()) }).await;
    assert_eq!(feed_urls(&s).await, vec![old.clone()], "still one podcast, at its own address");

    phone.upload_subscription_changes(&[], &[&new]).await.assert_ok();
    eventually("unsubscribed through the new address", || async { feed_urls(&s).await.is_empty().then_some(()) }).await;
    assert_eq!(aliases(&s).await, 0, "aliases go with the podcast");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_same_address_written_differently_is_not_imported() {
    let s = scene().await;
    let feed = s.app.feed("written.xml", &Feed::with_episodes("Written", 1));
    s.app.subscribe(&s.user, &feed, 1).await;
    let other = s.app.feed("other.xml", &Feed::with_episodes("Other", 1));

    let phone = s.device("phone").await;
    let variant = format!("{}/", feed.replace("http://", "HTTP://"));
    phone.upload_subscription_changes(&[&variant, &other], &[]).await.assert_ok();
    eventually("the other feed imported", || async { feed_urls(&s).await.contains(&other).then_some(()) }).await;
    assert_eq!(feed_urls(&s).await.len(), 2, "the variant isn't a new podcast");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_feed_with_the_same_podcast_guid_is_the_same_show() {
    let s = scene().await;
    let guid = "<podcast:guid>8d2c3a1e-0000-4000-8000-000000000077</podcast:guid>";
    let old = s.app.feed("guid-old.xml", &Feed::with_episodes("Guid Show", 1).extra(guid));
    let pod = s.app.subscribe(&s.user, &old, 1).await;
    eventually("Podcasting 2.0 data stored", || async { s.app.feed_tags_stored(pod).await.then_some(()) }).await;
    // Renamed, and no episodes in common.
    let mut renamed = Feed::new("Guid Show (new home)").extra(guid);
    renamed = renamed.episode(Episode::new(50));
    let new = s.app.feed("guid-new.xml", &renamed);

    let phone = s.device("phone").await;
    phone.upload_subscription_changes(&[&new], &[]).await.assert_ok();
    eventually("the new address remembered", || async { (aliases(&s).await == 1).then_some(()) }).await;
    assert_eq!(feed_urls(&s).await, vec![old]);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_different_show_with_the_same_title_is_still_added() {
    let s = scene().await;
    let first = s.app.feed("same-title-a.xml", &Feed::with_episodes("Daily News", 2));
    s.app.subscribe(&s.user, &first, 2).await;
    let mut other = Feed::new("Daily News");
    for n in 100..103 {
        other = other.episode(Episode::new(n));
    }
    let second = s.app.feed("same-title-b.xml", &other);

    let phone = s.device("phone").await;
    phone.upload_subscription_changes(&[&second], &[]).await.assert_ok();
    eventually("the second show imported", || async { (feed_urls(&s).await.len() == 2).then_some(()) }).await;
    assert_eq!(aliases(&s).await, 0);
}

